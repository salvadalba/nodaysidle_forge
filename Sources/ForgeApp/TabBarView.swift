import SwiftUI

// MARK: - TabBarView

/// Horizontal scrollable tab bar showing open documents.
/// Supports close, pin, and drag-to-reorder.
struct TabBarView: View {
    @Bindable var workspace: WorkspaceManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspace.openTabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: workspace.activeTab?.id == tab.id,
                        onSelect: {
                            workspace.activeTab = tab
                        },
                        onClose: {
                            workspace.closeTab(tab)
                        },
                        onTogglePin: {
                            workspace.togglePin(tab)
                        }
                    )
                }
            }
        }
        .frame(height: 32)
        .background(ForgeTheme.Colors.surface)
    }
}

// MARK: - TabItemView

/// A single tab in the tab bar.
struct TabItemView: View {
    let tab: TabItem
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.xxs) {
            // Pin indicator
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(ForgeTheme.Colors.textTertiary)
            }

            // Modified indicator
            if tab.buffer.isModified {
                Circle()
                    .fill(ForgeTheme.Colors.accent)
                    .frame(width: 6, height: 6)
            }

            // File name
            Text(tab.title)
                .font(ForgeTheme.Fonts.ui(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? ForgeTheme.Colors.textPrimary : ForgeTheme.Colors.textSecondary)

            // Close button (visible on hover or when active)
            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isHovering ? ForgeTheme.Colors.accent : ForgeTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isActive
                ? ForgeTheme.Colors.base
                : (isHovering ? ForgeTheme.Colors.surfaceHover : Color.clear)
        )
        .animation(ForgeTheme.Anim.spring, value: isHovering)
        .overlay(alignment: .bottom) {
            if isActive {
                ForgeTheme.Colors.accentGradient
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ForgeTheme.Colors.border)
                .frame(width: 0.5, height: 16)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Close") { onClose() }
            Button("Close Others") { closeOthers() }
            Divider()
            Button(tab.isPinned ? "Unpin" : "Pin") { onTogglePin() }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.fileURL.path, forType: .string)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([tab.fileURL])
            }
        }
    }

    private func closeOthers() {
        let tabsToClose = workspace.openTabs.filter { $0.id != tab.id && !$0.isPinned }
        for t in tabsToClose {
            workspace.closeTab(t)
        }
    }

    // Access workspace from parent context
    @Environment(WorkspaceManager.self) private var workspace
}
