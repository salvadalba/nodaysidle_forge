import SwiftUI
import ForgeShared

// MARK: - StatusBarView

/// Bottom status bar showing current file, cursor position, LSP status,
/// indexing progress, and rendering mode.
struct StatusBarView: View {
    let activeTab: TabItem?
    let lspStatus: LSPStatus
    let indexStatus: IndexStatus
    let isMetalActive: Bool

    var body: some View {
        HStack(spacing: ForgeTheme.Spacing.sm) {
            // File name
            if let tab = activeTab {
                Text(tab.title)
                    .font(ForgeTheme.Fonts.label(size: 11))
                    .foregroundStyle(ForgeTheme.Colors.textSecondary)
                    .lineLimit(1)

                statusDivider

                // Cursor position
                Text("Ln \(tab.buffer.cursorPosition.line + 1), Col \(tab.buffer.cursorPosition.column + 1)")
                    .font(ForgeTheme.Fonts.code(size: 11))
                    .foregroundStyle(ForgeTheme.Colors.textPrimary)
            } else {
                Text("No file open")
                    .font(ForgeTheme.Fonts.label(size: 11))
                    .foregroundStyle(ForgeTheme.Colors.textTertiary)
            }

            Spacer()

            // Index status
            indexStatusView

            statusDivider

            // LSP status
            lspStatusView

            statusDivider

            // Rendering mode
            HStack(spacing: ForgeTheme.Spacing.xxs) {
                Circle()
                    .fill(isMetalActive ? ForgeTheme.Colors.accent : ForgeTheme.Colors.textTertiary)
                    .frame(width: 6, height: 6)
                Text(isMetalActive ? "Metal" : "CoreText")
                    .font(ForgeTheme.Fonts.label(size: 10))
                    .foregroundStyle(isMetalActive ? ForgeTheme.Colors.accent : ForgeTheme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, ForgeTheme.Spacing.sm)
        .frame(height: 24)
        .background(ForgeTheme.Colors.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ForgeTheme.Colors.border)
                .frame(height: 0.5)
        }
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(ForgeTheme.Colors.border)
            .frame(width: 0.5, height: 12)
    }

    // MARK: - LSP Status

    private var lspStatusView: some View {
        HStack(spacing: ForgeTheme.Spacing.xxs) {
            Circle()
                .fill(lspStatusColor)
                .frame(width: 6, height: 6)
            Text(lspStatusText)
                .font(ForgeTheme.Fonts.label(size: 10))
                .foregroundStyle(ForgeTheme.Colors.textSecondary)
        }
    }

    private var lspStatusColor: Color {
        switch lspStatus {
        case .running: return ForgeTheme.Colors.success
        case .starting: return ForgeTheme.Colors.warning
        case .restarting: return ForgeTheme.Colors.accent
        case .stopped: return ForgeTheme.Colors.textTertiary
        case .unavailable: return ForgeTheme.Colors.error
        }
    }

    private var lspStatusText: String {
        switch lspStatus {
        case .running: return "LSP"
        case .starting: return "LSP Starting"
        case .restarting(let attempt): return "LSP Restart (\(attempt))"
        case .stopped: return "LSP Off"
        case .unavailable: return "LSP Error"
        }
    }

    // MARK: - Index Status

    private var indexStatusView: some View {
        Group {
            switch indexStatus {
            case .idle:
                Text("Index: Ready")
                    .font(ForgeTheme.Fonts.label(size: 10))
                    .foregroundStyle(ForgeTheme.Colors.textSecondary)
            case .building(let processed, let total):
                HStack(spacing: ForgeTheme.Spacing.xxs) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(ForgeTheme.Colors.accent)
                    Text("Indexing \(processed)/\(total)")
                        .font(ForgeTheme.Fonts.label(size: 10))
                        .foregroundStyle(ForgeTheme.Colors.accent)
                }
            case .completed(let total):
                Text("Indexed: \(total) files")
                    .font(ForgeTheme.Fonts.label(size: 10))
                    .foregroundStyle(ForgeTheme.Colors.textSecondary)
            case .error(let msg):
                HStack(spacing: ForgeTheme.Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundStyle(ForgeTheme.Colors.warning)
                    Text("Index: \(msg)")
                        .font(ForgeTheme.Fonts.label(size: 10))
                        .foregroundStyle(ForgeTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
