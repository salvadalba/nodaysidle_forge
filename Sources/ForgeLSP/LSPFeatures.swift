import Foundation
import ForgeShared

// MARK: - LSPFeatures

/// High-level LSP feature methods wrapping the raw JSON-RPC protocol.
/// Each method maps to an LSP spec method and returns typed ForgeShared models.
public struct LSPFeatures: Sendable {
    private let coordinator: LSPCoordinator

    public init(coordinator: LSPCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Document Sync

    /// Notify the server that a document was opened.
    public func didOpenDocument(uri: URL, language: Language, text: String) async throws {
        let params = JSONValue.object([
            "textDocument": .object([
                "uri": .string(uri.absoluteString),
                "languageId": .string(language.rawValue),
                "version": .int(1),
                "text": .string(text),
            ])
        ])
        try await coordinator.sendNotification(method: "textDocument/didOpen", params: params)
    }

    /// Notify the server that a document changed.
    public func didChangeDocument(uri: URL, version: Int, text: String) async throws {
        let params = JSONValue.object([
            "textDocument": .object([
                "uri": .string(uri.absoluteString),
                "version": .int(version),
            ]),
            "contentChanges": .array([
                .object(["text": .string(text)])
            ])
        ])
        try await coordinator.sendNotification(method: "textDocument/didChange", params: params)
    }

    /// Notify the server that a document was closed.
    public func didCloseDocument(uri: URL) async throws {
        let params = JSONValue.object([
            "textDocument": .object([
                "uri": .string(uri.absoluteString),
            ])
        ])
        try await coordinator.sendNotification(method: "textDocument/didClose", params: params)
    }

    // MARK: - Completions

    /// Request completions at a position in a document.
    public func requestCompletion(uri: URL, position: TextPosition) async throws -> [CompletionItem] {
        let params = JSONValue.object([
            "textDocument": .object([
                "uri": .string(uri.absoluteString),
            ]),
            "position": .object([
                "line": .int(position.line),
                "character": .int(position.column),
            ])
        ])

        let response = try await coordinator.sendRequest(method: "textDocument/completion", params: params)

        guard let result = response.result else { return [] }

        return parseCompletions(from: result)
    }

    // MARK: - Go to Definition

    /// Request the definition location for a symbol at a position.
    public func gotoDefinition(uri: URL, position: TextPosition) async throws -> SourceLocation? {
        let params = JSONValue.object([
            "textDocument": .object([
                "uri": .string(uri.absoluteString),
            ]),
            "position": .object([
                "line": .int(position.line),
                "character": .int(position.column),
            ])
        ])

        let response = try await coordinator.sendRequest(method: "textDocument/definition", params: params)

        guard let result = response.result else { return nil }

        return parseLocation(from: result)
    }

    // MARK: - Hover

    /// Request hover information at a position.
    public func hover(uri: URL, position: TextPosition) async throws -> HoverInfo? {
        let params = JSONValue.object([
            "textDocument": .object([
                "uri": .string(uri.absoluteString),
            ]),
            "position": .object([
                "line": .int(position.line),
                "character": .int(position.column),
            ])
        ])

        let response = try await coordinator.sendRequest(method: "textDocument/hover", params: params)

        guard let result = response.result else { return nil }

        return parseHover(from: result)
    }

    // MARK: - Diagnostics

    /// Register a handler for published diagnostics.
    public func onDiagnostics(handler: @Sendable @escaping (URL, [DiagnosticItem]) -> Void) async {
        await coordinator.onNotification("textDocument/publishDiagnostics") { params in
            guard let obj = params.objectValue,
                  let uriStr = obj["uri"]?.stringValue,
                  let uri = URL(string: uriStr),
                  let diagnosticsArr = obj["diagnostics"]?.arrayValue else { return }

            let items = diagnosticsArr.compactMap { Self.parseDiagnostic(from: $0) }
            handler(uri, items)
        }
    }

    // MARK: - Parsing Helpers

    private func parseCompletions(from value: JSONValue) -> [CompletionItem] {
        let items: [JSONValue]
        if let arr = value.arrayValue {
            items = arr
        } else if let obj = value.objectValue, let arr = obj["items"]?.arrayValue {
            items = arr
        } else {
            return []
        }

        return items.compactMap { item -> CompletionItem? in
            guard let obj = item.objectValue,
                  let label = obj["label"]?.stringValue else { return nil }

            let detail = obj["detail"]?.stringValue
            let insertText = obj["insertText"]?.stringValue ?? label
            let kindInt: Int
            if case .int(let k) = obj["kind"] { kindInt = k } else { kindInt = 0 }

            return CompletionItem(
                id: UUID().uuidString,
                label: label,
                detail: detail,
                insertText: insertText,
                kind: mapCompletionKind(kindInt)
            )
        }
    }

    private func mapCompletionKind(_ lspKind: Int) -> CompletionKind {
        switch lspKind {
        case 3: return .function
        case 6: return .variable
        case 7, 22: return .type
        case 14: return .keyword
        case 10: return .property
        case 15: return .snippet
        default: return .other
        }
    }

    private func parseLocation(from value: JSONValue) -> SourceLocation? {
        // Can be a single Location or an array
        let locationObj: [String: JSONValue]?
        if let obj = value.objectValue {
            locationObj = obj
        } else if let arr = value.arrayValue, let first = arr.first?.objectValue {
            locationObj = first
        } else {
            return nil
        }

        guard let obj = locationObj,
              let uriStr = obj["uri"]?.stringValue,
              let uri = URL(string: uriStr),
              let range = obj["range"]?.objectValue,
              let start = range["start"]?.objectValue,
              case .int(let line) = start["line"],
              case .int(let character) = start["character"] else {
            return nil
        }

        return SourceLocation(uri: uri, position: TextPosition(line: line, column: character))
    }

    private func parseHover(from value: JSONValue) -> HoverInfo? {
        guard let obj = value.objectValue else { return nil }

        let contents: String
        if let contentsStr = obj["contents"]?.stringValue {
            contents = contentsStr
        } else if let contentsObj = obj["contents"]?.objectValue,
                  let value = contentsObj["value"]?.stringValue {
            contents = value
        } else {
            return nil
        }

        return HoverInfo(contents: contents)
    }

    private static func parseDiagnostic(from value: JSONValue) -> DiagnosticItem? {
        guard let obj = value.objectValue,
              let message = obj["message"]?.stringValue,
              let range = obj["range"]?.objectValue,
              let start = range["start"]?.objectValue,
              case .int(let startLine) = start["line"],
              case .int(let startChar) = start["character"] else {
            return nil
        }

        let severityInt: Int
        if case .int(let s) = obj["severity"] { severityInt = s } else { severityInt = 1 }

        let endLine: Int
        let endChar: Int
        if let end = range["end"]?.objectValue,
           case .int(let el) = end["line"],
           case .int(let ec) = end["character"] {
            endLine = el
            endChar = ec
        } else {
            endLine = startLine
            endChar = startChar
        }

        return DiagnosticItem(
            message: message,
            severity: DiagnosticSeverity(lspValue: severityInt),
            range: TextRange(
                start: TextPosition(line: startLine, column: startChar),
                end: TextPosition(line: endLine, column: endChar)
            )
        )
    }
}

// MARK: - Diagnostic Types

/// A diagnostic item from the language server.
public struct DiagnosticItem: Sendable, Identifiable {
    public let id = UUID()
    public var message: String
    public var severity: DiagnosticSeverity
    public var range: TextRange
}

/// Diagnostic severity levels matching LSP spec.
public enum DiagnosticSeverity: Int, Sendable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4

    init(lspValue: Int) {
        self = DiagnosticSeverity(rawValue: lspValue) ?? .error
    }
}
