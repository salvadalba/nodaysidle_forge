import Foundation
import SwiftData
import os.log
import ForgeShared

private let logger = Logger(subsystem: "com.forge.editor", category: "persistence")

// MARK: - PersistenceManager

/// Actor-isolated persistence manager for SwiftData operations.
///
/// Runs all save/fetch operations on a background ModelContext off the
/// main actor to prevent frame drops. Supports 30s autosave.
public actor PersistenceManager {
    public let modelContainer: ModelContainer
    private var autosaveTask: Task<Void, Never>?

    // MARK: - Init

    public init(inMemory: Bool = false) throws {
        let schema = Schema([
            WorkspaceState.self,
            OpenDocument.self,
            SemanticEntry.self,
            EditorPreferences.self,
        ])

        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            // Ensure app support directory exists
            let storeURL = forgeAppSupportPath.appendingPathComponent("Forge.store")
            try FileManager.default.createDirectory(
                at: forgeAppSupportPath,
                withIntermediateDirectories: true
            )
            config = ModelConfiguration(schema: schema, url: storeURL)
        }

        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        logger.info("PersistenceManager initialized (inMemory: \(inMemory))")
    }

    // MARK: - Autosave

    /// Start the 30-second autosave timer for a workspace.
    public func startAutosave(workspacePath: String, stateProvider: @Sendable @escaping () async -> WorkspaceStateSnapshot?) {
        stopAutosave()

        autosaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }

                if let snapshot = await stateProvider() {
                    do {
                        try await saveWorkspaceSnapshot(snapshot, path: workspacePath)
                        logger.debug("Autosaved workspace state for: \(workspacePath)")
                    } catch {
                        logger.error("Autosave failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Stop the autosave timer.
    public func stopAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }

    // MARK: - Workspace State

    /// Save workspace state.
    public func saveWorkspaceState(_ state: WorkspaceState) throws {
        let context = ModelContext(modelContainer)
        context.insert(state)
        try context.save()
        logger.info("Saved workspace state for: \(state.workspacePath)")
    }

    /// Save workspace state from a snapshot (for autosave from nonisolated context).
    public func saveWorkspaceSnapshot(_ snapshot: WorkspaceStateSnapshot, path: String) throws {
        let context = ModelContext(modelContainer)

        // Find or create workspace state
        let predicate = #Predicate<WorkspaceState> { ws in
            ws.workspacePath == path
        }
        let descriptor = FetchDescriptor<WorkspaceState>(predicate: predicate)
        let existing = try context.fetch(descriptor)

        let state: WorkspaceState
        if let existing = existing.first {
            state = existing
        } else {
            state = WorkspaceState(workspacePath: path)
            context.insert(state)
        }

        state.sidebarWidth = snapshot.sidebarWidth
        state.activeDocumentID = snapshot.activeDocumentID
        state.windowFrame = snapshot.windowFrame
        state.lastOpenedDate = .now

        // Update open tabs
        for tab in state.openTabs {
            context.delete(tab)
        }
        for tabSnapshot in snapshot.openTabs {
            let doc = OpenDocument(
                filePath: tabSnapshot.filePath,
                cursorLine: tabSnapshot.cursorLine,
                cursorColumn: tabSnapshot.cursorColumn,
                scrollOffset: tabSnapshot.scrollOffset,
                isPinned: tabSnapshot.isPinned
            )
            doc.workspace = state
            context.insert(doc)
        }

        try context.save()
    }

    /// Load workspace state for a given path.
    public func loadWorkspaceState(for path: String) throws -> WorkspaceState? {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<WorkspaceState> { ws in
            ws.workspacePath == path
        }
        let descriptor = FetchDescriptor<WorkspaceState>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Load workspace state as a Sendable snapshot for cross-isolation transfer.
    public func loadWorkspaceSnapshot(for path: String) throws -> RestoredWorkspaceSnapshot? {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<WorkspaceState> { ws in
            ws.workspacePath == path
        }
        let descriptor = FetchDescriptor<WorkspaceState>(predicate: predicate)
        guard let state = try context.fetch(descriptor).first else { return nil }

        let tabs = state.openTabs.sorted(by: { $0.openedAt < $1.openedAt }).map { doc in
            OpenTabSnapshot(
                filePath: doc.filePath,
                cursorLine: doc.cursorLine,
                cursorColumn: doc.cursorColumn,
                scrollOffset: doc.scrollOffset,
                isPinned: doc.isPinned
            )
        }

        return RestoredWorkspaceSnapshot(
            sidebarWidth: state.sidebarWidth,
            activeDocumentID: state.activeDocumentID,
            openTabs: tabs
        )
    }

    // MARK: - Semantic Entries

    /// Save semantic entries (batch insert).
    public func saveSemanticEntries(_ entries: [SemanticEntry]) throws {
        let context = ModelContext(modelContainer)
        for entry in entries {
            context.insert(entry)
        }
        try context.save()
    }

    /// Fetch semantic entries matching content hashes.
    public func fetchSemanticEntries(matching hashes: [String]) throws -> [SemanticEntry] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SemanticEntry>()
        let all = try context.fetch(descriptor)
        return all.filter { hashes.contains($0.contentHash) }
    }

    /// Fetch all semantic entries.
    public func fetchAllSemanticEntries() throws -> [SemanticEntry] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SemanticEntry>()
        return try context.fetch(descriptor)
    }

    /// Fetch all semantic entries as Sendable snapshots for cross-isolation transfer.
    public func fetchAllSemanticSnapshots() throws -> [SemanticEntrySnapshot] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SemanticEntry>()
        return try context.fetch(descriptor).map { entry in
            SemanticEntrySnapshot(
                filePath: entry.filePath,
                contentHash: entry.contentHash,
                embeddingVector: entry.embeddingVector,
                symbols: entry.symbols
            )
        }
    }

    /// Delete semantic entries for given file paths.
    public func deleteSemanticEntries(for paths: [String]) throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SemanticEntry>()
        let all = try context.fetch(descriptor)
        for entry in all where paths.contains(entry.filePath) {
            context.delete(entry)
        }
        try context.save()
    }

    // MARK: - Preferences

    /// Save preferences for a category.
    public func savePreferences(_ prefs: EditorPreferences) throws {
        let context = ModelContext(modelContainer)
        let category = prefs.category
        let predicate = #Predicate<EditorPreferences> { p in
            p.category == category
        }
        let descriptor = FetchDescriptor<EditorPreferences>(predicate: predicate)
        if let existing = try context.fetch(descriptor).first {
            existing.jsonPayload = prefs.jsonPayload
            existing.lastModifiedDate = .now
        } else {
            context.insert(prefs)
        }
        try context.save()
    }

    /// Load preferences for a category.
    public func loadPreferences(category: String) throws -> EditorPreferences? {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<EditorPreferences> { p in
            p.category == category
        }
        let descriptor = FetchDescriptor<EditorPreferences>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    /// Load all preferences.
    public func loadAllPreferences() throws -> [EditorPreferences] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<EditorPreferences>()
        return try context.fetch(descriptor)
    }
}

// MARK: - Snapshots (Sendable value types for cross-isolation transfer)

/// Sendable snapshot of workspace state for autosave across actor boundaries.
public struct WorkspaceStateSnapshot: Sendable {
    public var sidebarWidth: Double
    public var activeDocumentID: UUID?
    public var windowFrame: CodableRect
    public var openTabs: [OpenTabSnapshot]

    public init(
        sidebarWidth: Double,
        activeDocumentID: UUID?,
        windowFrame: CodableRect,
        openTabs: [OpenTabSnapshot]
    ) {
        self.sidebarWidth = sidebarWidth
        self.activeDocumentID = activeDocumentID
        self.windowFrame = windowFrame
        self.openTabs = openTabs
    }
}

/// Sendable snapshot of restored workspace state for cross-isolation transfer.
public struct RestoredWorkspaceSnapshot: Sendable {
    public var sidebarWidth: Double
    public var activeDocumentID: UUID?
    public var openTabs: [OpenTabSnapshot]

    public init(sidebarWidth: Double, activeDocumentID: UUID?, openTabs: [OpenTabSnapshot]) {
        self.sidebarWidth = sidebarWidth
        self.activeDocumentID = activeDocumentID
        self.openTabs = openTabs
    }
}

/// Sendable snapshot of an open tab.
public struct OpenTabSnapshot: Sendable {
    public var filePath: String
    public var cursorLine: Int
    public var cursorColumn: Int
    public var scrollOffset: Double
    public var isPinned: Bool

    public init(filePath: String, cursorLine: Int = 0, cursorColumn: Int = 0, scrollOffset: Double = 0, isPinned: Bool = false) {
        self.filePath = filePath
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
        self.scrollOffset = scrollOffset
        self.isPinned = isPinned
    }
}

/// Sendable snapshot of a semantic entry for cross-isolation transfer.
public struct SemanticEntrySnapshot: Sendable {
    public var filePath: String
    public var contentHash: String
    public var embeddingVector: [Float]
    public var symbols: [String]

    public init(filePath: String, contentHash: String, embeddingVector: [Float], symbols: [String]) {
        self.filePath = filePath
        self.contentHash = contentHash
        self.embeddingVector = embeddingVector
        self.symbols = symbols
    }
}
