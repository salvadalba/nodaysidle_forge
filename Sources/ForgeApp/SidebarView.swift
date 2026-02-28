import SwiftUI
import ForgeShared

// MARK: - SidebarView

/// File tree sidebar using recursive DisclosureGroups for directories.
struct SidebarView: View {
    @Bindable var workspace: WorkspaceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(workspace.workspaceURL?.lastPathComponent ?? "No Workspace")
                    .font(ForgeTheme.Fonts.ui(size: 13, weight: .semibold))
                    .foregroundStyle(ForgeTheme.Colors.textPrimary)
                Spacer()
                Button {
                    openWorkspaceFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(ForgeTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Open Workspace Folder")
            }
            .padding(.horizontal, ForgeTheme.Spacing.sm)
            .padding(.vertical, ForgeTheme.Spacing.xs)
            .background(ForgeTheme.Colors.surface)

            Rectangle()
                .fill(ForgeTheme.Colors.border)
                .frame(height: 0.5)

            // File Tree
            if let root = workspace.fileTree {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(root.children) { node in
                            FileTreeNodeView(node: node, workspace: workspace, depth: 0)
                        }
                    }
                    .padding(.vertical, ForgeTheme.Spacing.xxs)
                }
            } else {
                ContentUnavailableView {
                    Label("No Workspace Open", systemImage: "folder")
                        .foregroundStyle(ForgeTheme.Colors.textSecondary)
                } description: {
                    Text("Open a folder to browse its files.")
                        .foregroundStyle(ForgeTheme.Colors.textTertiary)
                } actions: {
                    Button("Open Folder...") {
                        openWorkspaceFolder()
                    }
                    .forgeButton()
                }
            }
        }
        .frame(minWidth: 200)
        .background(ForgeTheme.Colors.base)
    }

    private func openWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await workspace.openWorkspace(at: url)
        }
    }
}

// MARK: - FileTreeNodeView

/// A recursive view for a single node in the file tree.
struct FileTreeNodeView: View {
    let node: FileTreeNode
    @Bindable var workspace: WorkspaceManager
    let depth: Int

    @State private var isExpanded = false

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    FileTreeNodeView(node: child, workspace: workspace, depth: depth + 1)
                }
            } label: {
                directoryLabel
            }
            .padding(.leading, CGFloat(depth) * 8)
        } else {
            fileLabel
                .padding(.leading, CGFloat(depth) * 8 + 20)
                .onTapGesture {
                    workspace.openFile(at: node.url)
                }
        }
    }

    @State private var isFileHovering = false

    private var directoryLabel: some View {
        HStack(spacing: ForgeTheme.Spacing.xxs) {
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 12))
                .foregroundStyle(ForgeTheme.Colors.textSecondary)
            Text(node.name)
                .font(ForgeTheme.Fonts.ui(size: 13))
                .foregroundStyle(ForgeTheme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    private var fileLabel: some View {
        let isActive = workspace.activeTab?.fileURL == node.url

        return HStack(spacing: ForgeTheme.Spacing.xxs) {
            Image(systemName: iconForFile(node.name))
                .font(.system(size: 12))
                .foregroundStyle(colorForFile(node.name))
            Text(node.name)
                .font(ForgeTheme.Fonts.ui(size: 13))
                .foregroundStyle(isActive ? ForgeTheme.Colors.textPrimary : ForgeTheme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Modified indicator for open files
            if let tab = workspace.openTabs.first(where: { $0.fileURL == node.url }),
               tab.buffer.isModified {
                Circle()
                    .fill(ForgeTheme.Colors.accent)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 2)
        .padding(.trailing, ForgeTheme.Spacing.xs)
        .contentShape(Rectangle())
        .background(
            isActive
                ? ForgeTheme.Colors.accentMuted
                : (isFileHovering ? ForgeTheme.Colors.surfaceHover : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.button))
        .onHover { hovering in
            withAnimation(ForgeTheme.Anim.hover) {
                isFileHovering = hovering
            }
        }
    }

    // MARK: - File Icons

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md", "markdown": return "doc.richtext"
        case "html", "htm": return "globe"
        case "css": return "paintbrush"
        case "rs": return "gearshape.2"
        case "c", "h", "cpp", "hpp": return "c.square"
        case "go": return "chevron.left.forwardslash.chevron.right"
        case "yaml", "yml": return "list.bullet.indent"
        case "sh", "bash", "zsh", "fish": return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }

    private func colorForFile(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return ForgeTheme.Colors.accent
        case "py": return ForgeTheme.Colors.success
        case "js", "jsx": return ForgeTheme.Colors.warning
        case "ts", "tsx": return ForgeTheme.Colors.info
        case "rs": return Color(red: 0.8, green: 0.5, blue: 0.3)   // warm rust
        case "go": return Color(red: 0.4, green: 0.8, blue: 0.8)   // warm cyan
        case "md", "markdown": return Color(red: 0.7, green: 0.6, blue: 0.9) // warm lavender
        case "json", "yaml", "yml": return Color(red: 0.5, green: 0.8, blue: 0.7) // warm mint
        default: return ForgeTheme.Colors.textSecondary
        }
    }
}
