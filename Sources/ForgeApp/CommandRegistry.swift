import Foundation
import Observation
import ForgeShared

// MARK: - CommandRegistry

/// Singleton registry collecting ForgeCommand entries from all modules.
/// Supports fuzzy matching with prefix > substring ranking.
@Observable
@MainActor
public final class CommandRegistry {
    /// All registered commands.
    public var commands: [ForgeCommand] = []

    // MARK: - Singleton

    public static let shared = CommandRegistry()

    private init() {
        registerBuiltinCommands()
    }

    // MARK: - Registration

    /// Register a new command.
    public func register(_ command: ForgeCommand) {
        if !commands.contains(where: { $0.id == command.id }) {
            commands.append(command)
        }
    }

    /// Register multiple commands at once.
    public func register(_ newCommands: [ForgeCommand]) {
        for command in newCommands {
            register(command)
        }
    }

    // MARK: - Search

    /// Fuzzy-match commands against a query string.
    /// Ranking: exact prefix match > word boundary match > substring match.
    public func search(query: String) -> [ForgeCommand] {
        guard !query.isEmpty else {
            return commands.sorted { $0.title < $1.title }
        }

        let lowered = query.lowercased()
        var ranked: [(command: ForgeCommand, score: Int)] = []

        for command in commands {
            let title = command.title.lowercased()
            let category = command.category.lowercased()
            let combined = "\(category): \(title)"

            if title.hasPrefix(lowered) {
                ranked.append((command, 100))
            } else if combined.hasPrefix(lowered) {
                ranked.append((command, 90))
            } else if title.contains(lowered) {
                ranked.append((command, 70))
            } else if category.contains(lowered) {
                ranked.append((command, 50))
            } else if fuzzyMatch(query: lowered, target: title) {
                ranked.append((command, 30))
            }
        }

        return ranked.sorted { $0.score > $1.score }.map(\.command)
    }

    // MARK: - Fuzzy Match

    /// Returns true if all characters in query appear in-order in target.
    private func fuzzyMatch(query: String, target: String) -> Bool {
        var queryIdx = query.startIndex
        var targetIdx = target.startIndex

        while queryIdx < query.endIndex && targetIdx < target.endIndex {
            if query[queryIdx] == target[targetIdx] {
                queryIdx = query.index(after: queryIdx)
            }
            targetIdx = target.index(after: targetIdx)
        }

        return queryIdx == query.endIndex
    }

    // MARK: - Built-in Commands

    private func registerBuiltinCommands() {
        register([
            ForgeCommand(id: "file.open", title: "Open File", category: "File", keyboardShortcut: "⌘O"),
            ForgeCommand(id: "file.openFolder", title: "Open Folder", category: "File", keyboardShortcut: "⇧⌘O"),
            ForgeCommand(id: "file.save", title: "Save", category: "File", keyboardShortcut: "⌘S"),
            ForgeCommand(id: "file.saveAs", title: "Save As...", category: "File", keyboardShortcut: "⇧⌘S"),
            ForgeCommand(id: "file.close", title: "Close Tab", category: "File", keyboardShortcut: "⌘W"),

            ForgeCommand(id: "edit.undo", title: "Undo", category: "Edit", keyboardShortcut: "⌘Z"),
            ForgeCommand(id: "edit.redo", title: "Redo", category: "Edit", keyboardShortcut: "⇧⌘Z"),
            ForgeCommand(id: "edit.find", title: "Find", category: "Edit", keyboardShortcut: "⌘F"),
            ForgeCommand(id: "edit.replace", title: "Find and Replace", category: "Edit", keyboardShortcut: "⌥⌘F"),

            ForgeCommand(id: "view.toggleSidebar", title: "Toggle Sidebar", category: "View", keyboardShortcut: "⌘\\"),
            ForgeCommand(id: "view.commandPalette", title: "Command Palette", category: "View", keyboardShortcut: "⇧⌘P"),
            ForgeCommand(id: "view.settings", title: "Settings", category: "View", keyboardShortcut: "⌘,"),

            ForgeCommand(id: "tab.reopenClosed", title: "Reopen Closed Tab", category: "Tab", keyboardShortcut: "⇧⌘T"),
            ForgeCommand(id: "tab.nextTab", title: "Next Tab", category: "Tab", keyboardShortcut: "⌃⇥"),
            ForgeCommand(id: "tab.previousTab", title: "Previous Tab", category: "Tab", keyboardShortcut: "⌃⇧⇥"),

            ForgeCommand(id: "go.definition", title: "Go to Definition", category: "Go", keyboardShortcut: "⌘⌥D"),
            ForgeCommand(id: "go.line", title: "Go to Line", category: "Go", keyboardShortcut: "⌘G"),
        ])
    }
}
