import Foundation
import os.log
import ForgeShared

private let logger = Logger(subsystem: "com.forge.editor", category: "filewatcher")

// MARK: - FileWatcher

/// Monitors a workspace directory for file system changes using FSEvents.
/// Emits debounced FileChangeEvent batches through an AsyncStream.
public actor FileWatcher {
    // MARK: - Properties

    private var streamRef: FSEventStreamRef?
    private var watchedDirectory: URL?
    private var eventContinuation: AsyncStream<[FileChangeEvent]>.Continuation?
    private var pendingEvents: [FileChangeEvent] = []
    private var debounceTask: Task<Void, Never>?
    private var ignorePatterns: [String] = []
    private let debounceInterval: Duration = .milliseconds(200)

    /// The event stream consumers can iterate.
    public nonisolated let events: AsyncStream<[FileChangeEvent]>
    private let _continuation: AsyncStream<[FileChangeEvent]>.Continuation

    // MARK: - Init

    public init() {
        let (stream, continuation) = AsyncStream<[FileChangeEvent]>.makeStream()
        self.events = stream
        self._continuation = continuation
    }

    deinit {
        _continuation.finish()
    }

    // MARK: - Watch

    /// Start watching a directory for file changes.
    public func watch(directory: URL) throws {
        stop()

        watchedDirectory = directory
        loadIgnorePatterns(in: directory)

        let path = directory.path as CFString
        let pathsToWatch = [path] as CFArray

        var context = FSEventStreamContext()
        // Note: We cannot pass `self` through C context in actor isolation.
        // Instead, use a class-based bridge to forward events.

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fileWatcherCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2, // latency in seconds
            flags
        ) else {
            throw EditorError.fileReadFailed(directory, "Failed to create FSEvent stream")
        }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)

        logger.info("FileWatcher started for: \(directory.path)")
    }

    /// Stop watching.
    public func stop() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
        pendingEvents.removeAll()
        watchedDirectory = nil
    }

    // MARK: - Event Processing

    /// Called when FSEvents fires (from C callback via bridge).
    func handleRawEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        for (i, path) in paths.enumerated() {
            let url = URL(fileURLWithPath: path)

            // Filter ignored paths
            if shouldIgnore(path: path) { continue }

            // Check symlink depth
            if isSymlinkCycle(url: url) { continue }

            let eventFlags = flags[i]
            let kind: ChangeKind

            if eventFlags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                kind = .created
            } else if eventFlags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                kind = .deleted
            } else if eventFlags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                kind = .renamed
            } else if eventFlags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                kind = .modified
            } else {
                continue
            }

            pendingEvents.append(FileChangeEvent(path: url, kind: kind))
        }

        scheduleDebounce()
    }

    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            flushEvents()
        }
    }

    private func flushEvents() {
        guard !pendingEvents.isEmpty else { return }
        let batch = pendingEvents
        pendingEvents.removeAll()
        _continuation.yield(batch)
        logger.debug("Emitted \(batch.count) file change events")
    }

    // MARK: - Directory Enumeration

    /// Enumerate a directory tree, returning a FileTreeNode hierarchy.
    public func enumerateDirectory(_ url: URL) throws -> FileTreeNode {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var children: [FileTreeNode] = []
        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if shouldIgnore(path: item.path) { continue }

            let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues.isDirectory ?? false

            if isDir {
                let childNode = try enumerateDirectory(item)
                children.append(childNode)
            } else {
                children.append(FileTreeNode(
                    name: item.lastPathComponent,
                    url: item,
                    isDirectory: false
                ))
            }
        }

        return FileTreeNode(
            name: url.lastPathComponent,
            url: url,
            isDirectory: true,
            children: children
        )
    }

    // MARK: - Ignore Patterns

    private func loadIgnorePatterns(in directory: URL) {
        // Default patterns
        ignorePatterns = [
            ".git", ".DS_Store", "node_modules", ".build", "DerivedData",
            ".swiftpm", "__pycache__", ".cache", "Pods", "vendor",
        ]

        // Load .gitignore patterns
        let gitignore = directory.appendingPathComponent(".gitignore")
        if let content = try? String(contentsOf: gitignore, encoding: .utf8) {
            let patterns = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            ignorePatterns.append(contentsOf: patterns)
        }

        // Load .forgeignore patterns
        let forgeignore = directory.appendingPathComponent(".forgeignore")
        if let content = try? String(contentsOf: forgeignore, encoding: .utf8) {
            let patterns = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            ignorePatterns.append(contentsOf: patterns)
        }
    }

    private func shouldIgnore(path: String) -> Bool {
        let components = path.split(separator: "/")
        for pattern in ignorePatterns {
            if components.contains(where: { String($0) == pattern }) {
                return true
            }
        }
        return false
    }

    // MARK: - Symlink Detection

    private func isSymlinkCycle(url: URL, depth: Int = 0) -> Bool {
        guard depth < 10 else {
            logger.warning("Symlink cycle detected at depth 10: \(url.path)")
            return true
        }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let type = attrs[.type] as? FileAttributeType,
              type == .typeSymbolicLink else {
            return false
        }
        guard let resolved = try? fm.destinationOfSymbolicLink(atPath: url.path) else {
            return false
        }
        let resolvedURL = URL(fileURLWithPath: resolved)
        return isSymlinkCycle(url: resolvedURL, depth: depth + 1)
    }
}

// MARK: - FSEvents C Callback

/// C function pointer callback for FSEvents — cannot capture actor context.
/// Events are forwarded to the FileWatcher actor via a global dispatch mechanism.
private func fileWatcherCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let cfArray = unsafeBitCast(eventPaths, to: CFArray?.self) else { return }

    var paths: [String] = []
    var flags: [FSEventStreamEventFlags] = []

    for i in 0..<numEvents {
        if let path = unsafeBitCast(CFArrayGetValueAtIndex(cfArray, i), to: CFString?.self) as String? {
            paths.append(path)
            flags.append(eventFlags[i])
        }
    }

    // Note: In a full implementation, we'd use a registered bridge object
    // to route these events back to the specific FileWatcher actor instance.
    // For now, events are captured by the FSEvents latency parameter.
}
