import Foundation
import Observation
import ForgeShared
import ForgeEditorEngine
import ForgePersistence
import os.log

private let logger = Logger(subsystem: "com.forge.editor", category: "workspace")

// MARK: - Tab Item

/// Represents a single open tab in the editor.
@Observable
@MainActor
public final class TabItem: Identifiable {
    public let id: UUID
    public var fileURL: URL
    public var buffer: EditorBuffer
    public var isPinned: Bool
    public var openedAt: Date

    public init(fileURL: URL, buffer: EditorBuffer, isPinned: Bool = false) {
        self.id = UUID()
        self.fileURL = fileURL
        self.buffer = buffer
        self.isPinned = isPinned
        self.openedAt = .now
    }

    public var title: String {
        fileURL.lastPathComponent
    }
}

// MARK: - WorkspaceManager

/// Central coordinator for workspace state: file tree, tabs, active document,
/// and file watcher integration. Persists state via PersistenceManager.
@Observable
@MainActor
public final class WorkspaceManager {
    // MARK: - Properties

    /// The root directory of the workspace.
    public var workspaceURL: URL?

    /// File tree model built from the workspace directory.
    public var fileTree: FileTreeNode?

    /// Currently open tabs.
    public var openTabs: [TabItem] = []

    /// The currently active (focused) tab.
    public var activeTab: TabItem?

    /// Recently closed tabs for undo-close (max 20).
    public var recentlyClosed: [TabItem] = []

    /// Sidebar width for state restoration.
    public var sidebarWidth: Double = 250

    /// Whether the sidebar is visible.
    public var isSidebarVisible: Bool = true

    // MARK: - Dependencies

    private let fileWatcher = FileWatcher()
    private let persistenceManager: PersistenceManager?
    private let highlighter = SyntaxHighlighter()

    private var fileWatcherTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?

    private static let maxRecentlyClosed = 20

    // MARK: - Init

    public init(persistenceManager: PersistenceManager? = nil) {
        self.persistenceManager = persistenceManager
    }

    // MARK: - Workspace Lifecycle

    /// Open a workspace directory: enumerate files, start watching, restore state.
    public func openWorkspace(at url: URL) async {
        workspaceURL = url
        logger.info("Opening workspace: \(url.path)")

        // Enumerate file tree
        do {
            fileTree = try await fileWatcher.enumerateDirectory(url)
        } catch {
            logger.error("Failed to enumerate directory: \(error.localizedDescription)")
        }

        // Start file watching
        do {
            try await fileWatcher.watch(directory: url)
            startFileWatcherSubscription()
        } catch {
            logger.error("Failed to start file watcher: \(error.localizedDescription)")
        }

        // Restore persisted state
        await restoreWorkspaceState(for: url.path)

        // Start autosave timer
        startAutosave()
    }

    /// Close the workspace: stop watching, save state, close all tabs.
    public func closeWorkspace() async {
        await saveWorkspaceState()
        stopAutosave()
        fileWatcherTask?.cancel()
        fileWatcherTask = nil
        await fileWatcher.stop()
        openTabs.removeAll()
        activeTab = nil
        fileTree = nil
        workspaceURL = nil
    }

    // MARK: - Tab Management

    /// Open a file in a new tab (or focus existing tab).
    public func openFile(at url: URL) {
        // Check if already open
        if let existing = openTabs.first(where: { $0.fileURL == url }) {
            activeTab = existing
            return
        }

        let buffer = EditorBuffer()
        let tab = TabItem(fileURL: url, buffer: buffer)

        // Load file content
        Task {
            do {
                try buffer.load(from: url)
            } catch {
                logger.error("Failed to load file: \(error.localizedDescription)")
            }
        }

        // Insert after pinned tabs
        let insertIndex = openTabs.lastIndex(where: { $0.isPinned }).map { $0 + 1 } ?? openTabs.count
        if insertIndex <= openTabs.count {
            openTabs.insert(tab, at: insertIndex)
        } else {
            openTabs.append(tab)
        }
        activeTab = tab
    }

    /// Close a tab by ID.
    public func closeTab(_ tab: TabItem) {
        guard let index = openTabs.firstIndex(where: { $0.id == tab.id }) else { return }

        // Save to recently closed for undo
        recentlyClosed.insert(tab, at: 0)
        if recentlyClosed.count > Self.maxRecentlyClosed {
            recentlyClosed.removeLast()
        }

        openTabs.remove(at: index)

        // Update active tab if we closed the active one
        if activeTab?.id == tab.id {
            if openTabs.isEmpty {
                activeTab = nil
            } else {
                let newIndex = min(index, openTabs.count - 1)
                activeTab = openTabs[newIndex]
            }
        }
    }

    /// Reopen the most recently closed tab.
    public func reopenClosedTab() {
        guard let tab = recentlyClosed.first else { return }
        recentlyClosed.removeFirst()

        openTabs.append(tab)
        activeTab = tab

        // Reload file content if needed
        Task {
            do {
                try tab.buffer.load(from: tab.fileURL)
            } catch {
                logger.error("Failed to reload file: \(error.localizedDescription)")
            }
        }
    }

    /// Toggle pin state on a tab.
    public func togglePin(_ tab: TabItem) {
        tab.isPinned.toggle()

        // Reorder: pinned tabs come first
        openTabs.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.openedAt < rhs.openedAt
        }
    }

    /// Reorder tabs via drag-and-drop.
    public func moveTab(from source: IndexSet, to destination: Int) {
        openTabs.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - File Watcher Subscription

    private func startFileWatcherSubscription() {
        fileWatcherTask?.cancel()
        let eventStream = fileWatcher.events
        fileWatcherTask = Task { [weak self] in
            for await batch in eventStream {
                guard !Task.isCancelled else { break }
                await self?.handleFileChanges(batch)
            }
        }
    }

    private func handleFileChanges(_ events: [FileChangeEvent]) async {
        guard let workspaceURL else { return }

        // Re-enumerate the file tree on any change for simplicity
        // (Incremental updates could be done for perf later)
        do {
            fileTree = try await fileWatcher.enumerateDirectory(workspaceURL)
        } catch {
            logger.error("Failed to re-enumerate directory: \(error.localizedDescription)")
        }

        // Mark modified buffers for externally changed files
        for event in events {
            if event.kind == .deleted {
                // If a file was deleted, log it (keep tab open for save-as)
                if openTabs.contains(where: { $0.fileURL == event.path }) {
                    logger.info("Open file deleted externally: \(event.path.lastPathComponent)")
                }
            }
        }
    }

    // MARK: - Persistence

    private func restoreWorkspaceState(for path: String) async {
        guard let persistence = persistenceManager else { return }

        do {
            guard let snapshot = try await persistence.loadWorkspaceSnapshot(for: path) else { return }

            sidebarWidth = snapshot.sidebarWidth

            // Restore open tabs
            for tabSnapshot in snapshot.openTabs {
                let url = URL(fileURLWithPath: tabSnapshot.filePath)
                guard FileManager.default.fileExists(atPath: tabSnapshot.filePath) else { continue }
                openFile(at: url)

                // Restore cursor position and pin state
                if let tab = openTabs.last {
                    tab.isPinned = tabSnapshot.isPinned
                    tab.buffer.cursorPosition = TextPosition(line: tabSnapshot.cursorLine, column: tabSnapshot.cursorColumn)
                }
            }

            // Restore active document
            if let activeID = snapshot.activeDocumentID,
               let tab = openTabs.first(where: { $0.id == activeID }) {
                activeTab = tab
            } else {
                activeTab = openTabs.first
            }

            logger.info("Restored workspace state: \(snapshot.openTabs.count) tabs")
        } catch {
            logger.error("Failed to restore workspace state: \(error.localizedDescription)")
        }
    }

    /// Save current workspace state to persistence.
    public func saveWorkspaceState() async {
        guard let persistence = persistenceManager,
              let workspaceURL else { return }

        let tabSnapshots = openTabs.map { tab in
            OpenTabSnapshot(
                filePath: tab.fileURL.path,
                cursorLine: tab.buffer.cursorPosition.line,
                cursorColumn: tab.buffer.cursorPosition.column,
                scrollOffset: 0,
                isPinned: tab.isPinned
            )
        }

        let snapshot = WorkspaceStateSnapshot(
            sidebarWidth: sidebarWidth,
            activeDocumentID: activeTab?.id,
            windowFrame: CodableRect(),
            openTabs: tabSnapshots
        )

        do {
            try await persistence.saveWorkspaceSnapshot(snapshot, path: workspaceURL.path)
            logger.debug("Saved workspace state")
        } catch {
            logger.error("Failed to save workspace state: \(error.localizedDescription)")
        }
    }

    // MARK: - Autosave

    private func startAutosave() {
        stopAutosave()
        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await self?.saveWorkspaceState()
            }
        }
    }

    private func stopAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }
}
