import SwiftUI
import ForgeShared
import ForgeEditorEngine
import ForgeRendering

// MARK: - MainEditorView

/// The main editor layout using NavigationSplitView with sidebar, tab bar,
/// command palette overlay, and status bar.
struct MainEditorView: View {
    @Bindable var workspace: WorkspaceManager
    private let highlighter = SyntaxHighlighter()

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isCommandPaletteVisible = false
    @State private var lspStatus: LSPStatus = .stopped
    @State private var indexStatus: IndexStatus = .idle

    var body: some View {
        ZStack {
            // Main layout
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(workspace: workspace)
                    .navigationSplitViewColumnWidth(
                        min: 180,
                        ideal: workspace.sidebarWidth,
                        max: 400
                    )
            } detail: {
                VStack(spacing: 0) {
                    // Tab bar
                    if !workspace.openTabs.isEmpty {
                        TabBarView(workspace: workspace)
                    }

                    // Editor content
                    editorContent

                    // Status bar
                    StatusBarView(
                        activeTab: workspace.activeTab,
                        lspStatus: lspStatus,
                        indexStatus: indexStatus,
                        isMetalActive: true
                    )
                }
            }

            // Command palette overlay
            CommandPalette(isPresented: $isCommandPaletteVisible) { command in
                executeCommand(command)
            }
        }
        .environment(workspace)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        workspace.isSidebarVisible.toggle()
                        columnVisibility = workspace.isSidebarVisible ? .automatic : .detailOnly
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    workspace.reopenClosedTab()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(workspace.recentlyClosed.isEmpty)
                .help("Reopen Closed Tab")

                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                        isCommandPaletteVisible.toggle()
                    }
                } label: {
                    Image(systemName: "command")
                }
                .help("Command Palette (⇧⌘P)")
            }
        }
        .onKeyPress(phases: .down) { press in
            // ⌘⇧P for command palette
            if press.modifiers.contains([.command, .shift]) && press.characters == "p" {
                withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                    isCommandPaletteVisible.toggle()
                }
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Editor Content

    @ViewBuilder
    private var editorContent: some View {
        if let tab = workspace.activeTab {
            MetalEditorView(
                buffer: tab.buffer,
                highlighter: highlighter,
                language: Language.detect(from: tab.fileURL)
            )
            .id(tab.id)
        } else {
            welcomeView
        }
    }

    private var welcomeView: some View {
        VStack(spacing: ForgeTheme.Spacing.md) {
            // Forge anvil motif: hammer + flame composition
            ZStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(ForgeTheme.Colors.accentGradient)
                    .opacity(0.3)
                    .offset(y: -4)

                Image(systemName: "hammer.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(ForgeTheme.Colors.accentGradient)
            }

            Text("Forge")
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundStyle(ForgeTheme.Colors.accentGradient)

            Text("Open a file or folder to get started")
                .font(ForgeTheme.Fonts.ui(size: 14))
                .foregroundStyle(ForgeTheme.Colors.textTertiary)

            HStack(spacing: ForgeTheme.Spacing.sm) {
                Button("Open File...") {
                    openFile()
                }
                .forgeButton()

                Button("Open Folder...") {
                    openFolder()
                }
                .forgeButton()
            }
            .padding(.top, ForgeTheme.Spacing.xs)

            Text("⌘O to open a file  |  ⇧⌘O to open a folder  |  ⇧⌘P for command palette")
                .font(ForgeTheme.Fonts.label(size: 11))
                .foregroundStyle(ForgeTheme.Colors.textTertiary)
                .padding(.top, ForgeTheme.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ForgeTheme.Colors.base)
    }

    // MARK: - Command Execution

    private func executeCommand(_ command: ForgeCommand) {
        switch command.id {
        case "file.open":
            openFile()
        case "file.openFolder":
            openFolder()
        case "file.save":
            if let tab = workspace.activeTab {
                Task { try? await tab.buffer.save() }
            }
        case "file.close":
            if let tab = workspace.activeTab {
                workspace.closeTab(tab)
            }
        case "edit.undo":
            workspace.activeTab?.buffer.undo()
        case "edit.redo":
            workspace.activeTab?.buffer.redo()
        case "view.toggleSidebar":
            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                workspace.isSidebarVisible.toggle()
                columnVisibility = workspace.isSidebarVisible ? .automatic : .detailOnly
            }
        case "view.commandPalette":
            withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
                isCommandPaletteVisible.toggle()
            }
        case "tab.reopenClosed":
            workspace.reopenClosedTab()
        default:
            break
        }
    }

    // MARK: - File Actions

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            workspace.openFile(at: url)
        }
    }

    private func openFolder() {
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
}
