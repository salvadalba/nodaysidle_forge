import SwiftUI
import ForgeShared

// MARK: - EditorView

/// The primary text editor view, wired to an EditorBuffer.
/// Uses standard SwiftUI Text rendering initially; replaced by Metal in Task 2.
public struct EditorView: View {
    @Bindable var buffer: EditorBuffer
    let highlighter: SyntaxHighlighter
    let language: Language

    @State private var tokens: [SyntaxToken] = []
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var isFocused: Bool

    public init(buffer: EditorBuffer, highlighter: SyntaxHighlighter, language: Language) {
        self.buffer = buffer
        self.highlighter = highlighter
        self.language = language
    }

    public var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<buffer.lineCount, id: \.self) { lineIndex in
                    HStack(spacing: 0) {
                        // Line number gutter
                        Text("\(lineIndex + 1)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                            .padding(.trailing, 8)

                        // Line content with syntax highlighting
                        highlightedLineView(lineIndex)
                    }
                    .frame(height: 20)
                }
            }
            .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .focusable()
        .focused($isFocused)
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .task {
            await updateHighlighting()
        }
        .onChange(of: buffer.text) {
            Task { await updateHighlighting() }
        }
    }

    // MARK: - Highlighted Line

    @ViewBuilder
    private func highlightedLineView(_ lineIndex: Int) -> some View {
        let lineText = buffer.lineText(lineIndex)
        if lineText.isEmpty {
            Text(" ")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
        } else {
            let attributed = applyTokenColors(to: lineText, lineIndex: lineIndex)
            Text(attributed)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Token Coloring

    private func applyTokenColors(to lineText: String, lineIndex: Int) -> AttributedString {
        var attributedString = AttributedString(lineText)
        attributedString.foregroundColor = .primary
        attributedString.font = .system(.body, design: .monospaced)

        let lineTokens = tokens.filter { $0.range.start.line == lineIndex }

        for token in lineTokens {
            let startCol = max(0, token.range.start.column)
            let endCol = min(lineText.count, token.range.end.column)
            guard startCol < endCol, startCol < lineText.count else { continue }

            let startIdx = lineText.index(lineText.startIndex, offsetBy: startCol)
            let endIdx = lineText.index(lineText.startIndex, offsetBy: endCol)
            guard let attrStart = AttributedString.Index(startIdx, within: attributedString),
                  let attrEnd = AttributedString.Index(endIdx, within: attributedString) else {
                continue
            }

            attributedString[attrStart..<attrEnd].foregroundColor = colorForTokenKind(token.kind)
        }

        return attributedString
    }

    private func colorForTokenKind(_ kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .keyword: return .pink
        case .string: return .red
        case .number: return .purple
        case .comment: return .gray
        case .type, .builtinType: return .cyan
        case .function: return .blue
        case .variable: return .primary
        case .property: return .teal
        case .operator: return .primary
        case .punctuation: return .secondary
        case .attribute: return .orange
        case .parameter: return .primary
        case .label: return .yellow
        case .plain: return .primary
        }
    }

    // MARK: - Highlighting

    private func updateHighlighting() async {
        let text = buffer.text
        tokens = await highlighter.highlight(text, language: language)
    }

    // MARK: - Key Handling

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let char = keyPress.characters

        // Handle special keys
        if keyPress.key == .return {
            try? buffer.insertAtCursor("\n")
            return .handled
        }
        if keyPress.key == .tab {
            try? buffer.insertAtCursor("    ")
            return .handled
        }
        if keyPress.key == .delete {
            buffer.deleteBackward()
            return .handled
        }

        // Handle Cmd+Z (undo) and Cmd+Shift+Z (redo)
        if keyPress.modifiers.contains(.command) {
            if char == "z" {
                if keyPress.modifiers.contains(.shift) {
                    buffer.redo()
                } else {
                    buffer.undo()
                }
                return .handled
            }
            return .ignored
        }

        // Regular character input
        if !char.isEmpty && !keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.control) {
            try? buffer.insertAtCursor(char)
            return .handled
        }

        return .ignored
    }
}

// MARK: - File Open/Save Helpers

/// Open a file using NSOpenPanel with security-scoped bookmark.
@MainActor
public func openFileWithPanel() async throws -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.sourceCode, .plainText, .json, .yaml, .xml, .html]

    let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
    guard response == .OK, let url = panel.url else { return nil }

    // Create security-scoped bookmark
    do {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: "bookmark_\(url.path)")
    } catch {
        throw EditorError.bookmarkCreationFailed(url)
    }

    return url
}

/// Open a workspace directory using NSOpenPanel with security-scoped bookmark.
@MainActor
public func openWorkspaceWithPanel() async throws -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false

    let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
    guard response == .OK, let url = panel.url else { return nil }

    // Create security-scoped bookmark
    do {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: "workspace_bookmark_\(url.path)")
    } catch {
        throw EditorError.bookmarkCreationFailed(url)
    }

    return url
}
