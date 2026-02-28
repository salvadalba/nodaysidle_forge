import Foundation
import ForgeShared
import SwiftTreeSitter

// Language and TextRange aliases defined in ModuleAliases.swift

// MARK: - SyntaxHighlighter

/// Actor-isolated syntax highlighter using tree-sitter for incremental parsing.
///
/// Falls back to a regex-based highlighter when tree-sitter grammars
/// are not available for a given language.
public actor SyntaxHighlighter {
    private var parser: Parser?
    private var currentTree: Tree?
    private var currentLanguage: Language = .unknown

    public init() {
        self.parser = Parser()
    }

    // MARK: - Language Detection

    /// Detect the language of a file from its URL extension or shebang.
    nonisolated public func detectLanguage(for url: URL) -> Language {
        // Check extension first
        let lang = Language.detect(from: url)
        if lang != .unknown { return lang }

        // Try shebang detection
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let firstLine = String(data: data.prefix(256), encoding: .utf8)?
                .components(separatedBy: .newlines).first,
              firstLine.hasPrefix("#!") else {
            return .unknown
        }

        let shebang = firstLine.lowercased()
        if shebang.contains("python") { return .python }
        if shebang.contains("node") { return .javascript }
        if shebang.contains("ruby") { return .python } // approximate
        if shebang.contains("bash") || shebang.contains("sh") { return .unknown }

        return .unknown
    }

    // MARK: - Full Highlight

    /// Parse and highlight the full text for a given language.
    /// Returns syntax tokens for the entire document.
    public func highlight(_ text: String, language: Language) -> [SyntaxToken] {
        // Use regex-based fallback highlighting for now.
        // Tree-sitter grammar integration requires bundled language-specific parsers,
        // which will be added as SPM binary targets per language.
        return regexHighlight(text, language: language)
    }

    // MARK: - Incremental Update

    /// Apply an edit and return updated syntax tokens.
    /// Leverages tree-sitter's incremental parsing when available.
    public func applyEdit(_ edit: TextEdit, to text: String, language: Language) -> [SyntaxToken] {
        // Full re-highlight for now; tree-sitter incremental reparse will
        // be wired once grammars are bundled as binary targets.
        return highlight(text, language: language)
    }

    // MARK: - Regex-Based Fallback

    /// Simple regex-based syntax highlighting as a fallback.
    private func regexHighlight(_ text: String, language: Language) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        let patterns = highlightPatterns(for: language)

        for (lineIdx, line) in lines.enumerated() {
            let lineStr = String(line)
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: pattern.options) else {
                    continue
                }
                let range = NSRange(lineStr.startIndex..., in: lineStr)
                let matches = regex.matches(in: lineStr, range: range)

                for match in matches {
                    guard let swiftRange = Range(match.range, in: lineStr) else { continue }
                    let startCol = lineStr.distance(from: lineStr.startIndex, to: swiftRange.lowerBound)
                    let endCol = lineStr.distance(from: lineStr.startIndex, to: swiftRange.upperBound)

                    tokens.append(SyntaxToken(
                        range: TextRange(
                            start: TextPosition(line: lineIdx, column: startCol),
                            end: TextPosition(line: lineIdx, column: endCol)
                        ),
                        kind: pattern.kind
                    ))
                }
            }
        }

        return tokens
    }

    private struct HighlightPattern {
        let pattern: String
        let kind: SyntaxTokenKind
        let options: NSRegularExpression.Options
    }

    private func highlightPatterns(for language: Language) -> [HighlightPattern] {
        switch language {
        case .swift:
            return swiftPatterns
        case .python:
            return pythonPatterns
        case .javascript, .typescript:
            return jsPatterns
        default:
            return genericPatterns
        }
    }

    // MARK: - Language Patterns

    private var swiftPatterns: [HighlightPattern] {
        [
            HighlightPattern(
                pattern: #"//.*$"#,
                kind: .comment,
                options: .anchorsMatchLines
            ),
            HighlightPattern(
                pattern: #""(?:[^"\\]|\\.)*""#,
                kind: .string,
                options: []
            ),
            HighlightPattern(
                pattern: #"\b(import|func|var|let|class|struct|enum|protocol|extension|if|else|guard|return|switch|case|for|while|repeat|break|continue|throw|throws|try|catch|do|async|await|actor|public|private|internal|fileprivate|open|static|final|override|mutating|nonmutating|init|deinit|subscript|typealias|associatedtype|where|in|as|is|self|Self|super|nil|true|false|some|any)\b"#,
                kind: .keyword,
                options: []
            ),
            HighlightPattern(
                pattern: #"\b\d+(\.\d+)?\b"#,
                kind: .number,
                options: []
            ),
            HighlightPattern(
                pattern: #"@\w+"#,
                kind: .attribute,
                options: []
            ),
            HighlightPattern(
                pattern: #"\b(Int|String|Bool|Double|Float|Array|Dictionary|Set|Optional|Any|AnyObject|Void|Never|URL|Data|Date|UUID)\b"#,
                kind: .builtinType,
                options: []
            ),
            HighlightPattern(
                pattern: #"\b(func)\s+(\w+)"#,
                kind: .function,
                options: []
            ),
        ]
    }

    private var pythonPatterns: [HighlightPattern] {
        [
            HighlightPattern(pattern: #"#.*$"#, kind: .comment, options: .anchorsMatchLines),
            HighlightPattern(pattern: #"(?:\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?''')"#, kind: .string, options: .dotMatchesLineSeparators),
            HighlightPattern(pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#, kind: .string, options: []),
            HighlightPattern(
                pattern: #"\b(def|class|if|elif|else|for|while|return|import|from|as|try|except|finally|raise|with|yield|lambda|and|or|not|in|is|pass|break|continue|True|False|None|async|await|global|nonlocal)\b"#,
                kind: .keyword,
                options: []
            ),
            HighlightPattern(pattern: #"\b\d+(\.\d+)?\b"#, kind: .number, options: []),
            HighlightPattern(pattern: #"@\w+"#, kind: .attribute, options: []),
        ]
    }

    private var jsPatterns: [HighlightPattern] {
        [
            HighlightPattern(pattern: #"//.*$"#, kind: .comment, options: .anchorsMatchLines),
            HighlightPattern(pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`"#, kind: .string, options: []),
            HighlightPattern(
                pattern: #"\b(const|let|var|function|class|if|else|for|while|return|import|export|from|default|try|catch|finally|throw|new|this|super|typeof|instanceof|void|delete|in|of|async|await|yield|switch|case|break|continue|true|false|null|undefined)\b"#,
                kind: .keyword,
                options: []
            ),
            HighlightPattern(pattern: #"\b\d+(\.\d+)?\b"#, kind: .number, options: []),
        ]
    }

    private var genericPatterns: [HighlightPattern] {
        [
            HighlightPattern(pattern: #"//.*$|#.*$"#, kind: .comment, options: .anchorsMatchLines),
            HighlightPattern(pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#, kind: .string, options: []),
            HighlightPattern(pattern: #"\b\d+(\.\d+)?\b"#, kind: .number, options: []),
        ]
    }
}
