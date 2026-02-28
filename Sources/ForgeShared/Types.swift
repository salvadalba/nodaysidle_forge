import Foundation

// MARK: - Text Positions & Ranges

/// A position in a text document (zero-indexed line and column).
public struct TextPosition: Codable, Sendable, Hashable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

extension TextPosition: Comparable {
    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.column < rhs.column
    }
}

/// A range in a text document defined by start and end positions.
public struct TextRange: Codable, Sendable, Hashable {
    public var start: TextPosition
    public var end: TextPosition

    public init(start: TextPosition, end: TextPosition) {
        self.start = start
        self.end = end
    }

    public var isEmpty: Bool { start == end }
}

// MARK: - Syntax

/// A single syntax token with a range and a kind identifier (e.g. "keyword", "string").
public struct SyntaxToken: Codable, Sendable, Hashable {
    public var range: TextRange
    public var kind: SyntaxTokenKind

    public init(range: TextRange, kind: SyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// Categories of syntax tokens for theme mapping.
public enum SyntaxTokenKind: String, Codable, Sendable, Hashable {
    case keyword
    case string
    case number
    case comment
    case type
    case function
    case variable
    case property
    case `operator`
    case punctuation
    case attribute
    case builtinType
    case parameter
    case label
    case plain
}

// MARK: - File System Events

/// A file system change event emitted by the FileWatcher.
public struct FileChangeEvent: Codable, Sendable, Hashable {
    public var path: URL
    public var kind: ChangeKind
    public var timestamp: Date

    public init(path: URL, kind: ChangeKind, timestamp: Date = .now) {
        self.path = path
        self.kind = kind
        self.timestamp = timestamp
    }
}

/// The type of file system change.
public enum ChangeKind: String, Codable, Sendable, Hashable {
    case created
    case modified
    case deleted
    case renamed
    case permissionError
}

// MARK: - Semantic Search

/// A result from semantic code search.
public struct SemanticMatch: Codable, Sendable, Hashable {
    public var filePath: String
    public var symbolName: String
    public var lineRange: Range<Int>
    public var score: Float
    public var snippet: String

    public init(filePath: String, symbolName: String, lineRange: Range<Int>, score: Float, snippet: String) {
        self.filePath = filePath
        self.symbolName = symbolName
        self.lineRange = lineRange
        self.score = score
        self.snippet = snippet
    }
}

// MARK: - Commands

/// A registered command for the command palette.
public struct ForgeCommand: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var category: String
    public var keyboardShortcut: String?

    public init(id: String, title: String, category: String, keyboardShortcut: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.keyboardShortcut = keyboardShortcut
    }
}

// MARK: - Index Status

/// The current state of the semantic indexer.
public enum IndexStatus: Codable, Sendable, Hashable {
    case idle
    case building(filesProcessed: Int, totalFiles: Int)
    case completed(totalFiles: Int)
    case error(String)
}

// MARK: - Language Detection

/// Supported programming languages for syntax highlighting and LSP.
public enum Language: String, Codable, Sendable, Hashable, CaseIterable {
    case swift
    case python
    case typescript
    case javascript
    case rust
    case c
    case cpp
    case go
    case java
    case json
    case yaml
    case markdown
    case html
    case css
    case unknown

    /// Detect language from file URL extension.
    public static func detect(from url: URL) -> Language {
        switch url.pathExtension.lowercased() {
        case "swift": return .swift
        case "py": return .python
        case "ts", "tsx": return .typescript
        case "js", "jsx": return .javascript
        case "rs": return .rust
        case "c", "h": return .c
        case "cpp", "cxx", "cc", "hpp": return .cpp
        case "go": return .go
        case "java": return .java
        case "json": return .json
        case "yml", "yaml": return .yaml
        case "md", "markdown": return .markdown
        case "html", "htm": return .html
        case "css": return .css
        default: return .unknown
        }
    }
}

// MARK: - Geometry Helpers

/// A Codable wrapper for window frame rectangles used in SwiftData persistence.
/// CGRect conversions are provided via extension in modules that import CoreGraphics.
public struct CodableRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Text Edit

/// Describes a text edit operation for LSP and undo/redo.
public struct TextEdit: Codable, Sendable, Hashable {
    public var range: TextRange
    public var newText: String

    public init(range: TextRange, newText: String) {
        self.range = range
        self.newText = newText
    }
}

// MARK: - LSP Types

/// A completion item from the language server.
public struct CompletionItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var detail: String?
    public var insertText: String
    public var kind: CompletionKind

    public init(id: String, label: String, detail: String? = nil, insertText: String, kind: CompletionKind) {
        self.id = id
        self.label = label
        self.detail = detail
        self.insertText = insertText
        self.kind = kind
    }
}

public enum CompletionKind: String, Codable, Sendable, Hashable {
    case function
    case variable
    case type
    case keyword
    case property
    case snippet
    case other
}

/// A source code location (file + position).
public struct SourceLocation: Codable, Sendable, Hashable {
    public var uri: URL
    public var position: TextPosition

    public init(uri: URL, position: TextPosition) {
        self.uri = uri
        self.position = position
    }
}

/// Hover information from the language server.
public struct HoverInfo: Codable, Sendable, Hashable {
    public var contents: String
    public var range: TextRange?

    public init(contents: String, range: TextRange? = nil) {
        self.contents = contents
        self.range = range
    }
}

// MARK: - LSP Status

/// The current state of the language server.
public enum LSPStatus: Codable, Sendable, Hashable {
    case stopped
    case starting
    case running
    case restarting(attempt: Int)
    case unavailable
}

// MARK: - File Tree

/// A node in the workspace file tree.
public struct FileTreeNode: Sendable, Identifiable, Hashable {
    public var id: URL
    public var name: String
    public var url: URL
    public var isDirectory: Bool
    public var children: [FileTreeNode]

    public init(name: String, url: URL, isDirectory: Bool, children: [FileTreeNode] = []) {
        self.id = url
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }
}
