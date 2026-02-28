import SwiftUI
import SwiftData
import ForgeShared
import ForgeEditorEngine
import ForgePersistence

// MARK: - App Entry Point

@main
struct ForgeApp: App {
    @NSApplicationDelegateAdaptor(ForgeAppDelegate.self) var appDelegate

    @State private var workspace: WorkspaceManager

    init() {
        let persistence: PersistenceManager?
        do {
            persistence = try PersistenceManager()
        } catch {
            persistence = nil
        }
        _workspace = State(initialValue: WorkspaceManager(persistenceManager: persistence))
    }

    var body: some Scene {
        WindowGroup {
            MainEditorView(workspace: workspace)
                .frame(minWidth: 800, minHeight: 600)
                .preferredColorScheme(.dark)
                .tint(ForgeTheme.Colors.accent)
                .onDisappear {
                    Task {
                        await workspace.saveWorkspaceState()
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            ForgeMenuCommands(workspace: workspace)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Menu Commands

struct ForgeMenuCommands: Commands {
    @Bindable var workspace: WorkspaceManager

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open File...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = true

                guard panel.runModal() == .OK else { return }
                for url in panel.urls {
                    workspace.openFile(at: url)
                }
            }
            .keyboardShortcut("o")

            Button("Open Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.prompt = "Open Workspace"

                guard panel.runModal() == .OK, let url = panel.url else { return }
                Task {
                    await workspace.openWorkspace(at: url)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Save") {
                guard let tab = workspace.activeTab else { return }
                Task {
                    try? await tab.buffer.save()
                }
            }
            .keyboardShortcut("s")
            .disabled(workspace.activeTab == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                workspace.activeTab?.buffer.undo()
            }
            .keyboardShortcut("z")
            .disabled(workspace.activeTab?.buffer.canUndo != true)

            Button("Redo") {
                workspace.activeTab?.buffer.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(workspace.activeTab?.buffer.canRedo != true)
        }

        CommandGroup(after: .undoRedo) {
            Divider()

            Button("Reopen Closed Tab") {
                workspace.reopenClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(workspace.recentlyClosed.isEmpty)

            Button("Close Tab") {
                guard let tab = workspace.activeTab else { return }
                workspace.closeTab(tab)
            }
            .keyboardShortcut("w")
            .disabled(workspace.activeTab == nil)
        }
    }
}

// Settings scene uses SettingsView from SettingsView.swift
