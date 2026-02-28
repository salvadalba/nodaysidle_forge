import Foundation
import SwiftData
import ForgeShared

// MARK: - Schema Version

enum ForgeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [WorkspaceState.self, OpenDocument.self, SemanticEntry.self, EditorPreferences.self]
    }
}

// MARK: - Migration Plan

enum ForgeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ForgeSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

// MARK: - WorkspaceState

@Model
public final class WorkspaceState {
    @Attribute(.unique)
    public var workspacePath: String

    public var sidebarWidth: Double
    public var activeDocumentID: UUID?
    public var windowFrameX: Double
    public var windowFrameY: Double
    public var windowFrameWidth: Double
    public var windowFrameHeight: Double
    public var lastOpenedDate: Date

    @Relationship(deleteRule: .cascade, inverse: \OpenDocument.workspace)
    public var openTabs: [OpenDocument]

    public init(
        workspacePath: String,
        sidebarWidth: Double = 250,
        activeDocumentID: UUID? = nil,
        windowFrame: CodableRect = CodableRect(),
        lastOpenedDate: Date = .now
    ) {
        self.workspacePath = workspacePath
        self.sidebarWidth = sidebarWidth
        self.activeDocumentID = activeDocumentID
        self.windowFrameX = windowFrame.x
        self.windowFrameY = windowFrame.y
        self.windowFrameWidth = windowFrame.width
        self.windowFrameHeight = windowFrame.height
        self.lastOpenedDate = lastOpenedDate
        self.openTabs = []
    }

    public var windowFrame: CodableRect {
        get {
            CodableRect(x: windowFrameX, y: windowFrameY, width: windowFrameWidth, height: windowFrameHeight)
        }
        set {
            windowFrameX = newValue.x
            windowFrameY = newValue.y
            windowFrameWidth = newValue.width
            windowFrameHeight = newValue.height
        }
    }
}

// MARK: - OpenDocument

@Model
public final class OpenDocument: Identifiable {
    public var id: UUID
    public var filePath: String
    public var cursorLine: Int
    public var cursorColumn: Int
    public var scrollOffset: Double
    public var isPinned: Bool
    public var openedAt: Date

    public var workspace: WorkspaceState?

    public init(
        filePath: String,
        cursorLine: Int = 0,
        cursorColumn: Int = 0,
        scrollOffset: Double = 0,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.filePath = filePath
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
        self.scrollOffset = scrollOffset
        self.isPinned = isPinned
        self.openedAt = .now
    }
}

// MARK: - SemanticEntry

@Model
public final class SemanticEntry {
    @Attribute(.unique)
    public var filePath: String

    public var contentHash: String
    public var embedding: Data
    public var symbolsJSON: Data
    public var lastIndexedDate: Date

    public init(
        filePath: String,
        contentHash: String,
        embedding: [Float],
        symbols: [String]
    ) {
        self.filePath = filePath
        self.contentHash = contentHash
        self.embedding = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)
        self.symbolsJSON = (try? JSONEncoder().encode(symbols)) ?? Data()
        self.lastIndexedDate = .now
    }

    public var embeddingVector: [Float] {
        embedding.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    public var symbols: [String] {
        (try? JSONDecoder().decode([String].self, from: symbolsJSON)) ?? []
    }
}

// MARK: - EditorPreferences

@Model
public final class EditorPreferences {
    @Attribute(.unique)
    public var category: String

    public var jsonPayload: Data
    public var lastModifiedDate: Date

    public init(category: String, payload: Data = Data()) {
        self.category = category
        self.jsonPayload = payload
        self.lastModifiedDate = .now
    }

    public func decode<T: Codable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: jsonPayload)
    }

    public func encode<T: Codable>(_ value: T) {
        jsonPayload = (try? JSONEncoder().encode(value)) ?? Data()
        lastModifiedDate = .now
    }
}

// MARK: - Application Support Path

public let forgeAppSupportPath: URL = {
    let fm = FileManager.default
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Forge", isDirectory: true)
}()
