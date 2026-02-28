import SwiftUI
import ForgeShared
import ForgeLSP

// MARK: - DiagnosticsOverlay

/// Renders inline diagnostic markers (errors, warnings, info, hints)
/// over the editor content area.
struct DiagnosticsOverlay: View {
    let diagnostics: [DiagnosticItem]
    let lineHeight: CGFloat
    let scrollOffset: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(diagnostics) { diagnostic in
                diagnosticMarker(diagnostic)
            }
        }
    }

    private func diagnosticMarker(_ item: DiagnosticItem) -> some View {
        let y = CGFloat(item.range.start.line) * lineHeight - scrollOffset

        return HStack(spacing: ForgeTheme.Spacing.xxs) {
            // Severity icon
            severityIcon(item.severity)
                .font(.system(size: 10))
                .foregroundStyle(severityColor(item.severity))

            // Message
            Text(item.message)
                .font(ForgeTheme.Fonts.label(size: 11))
                .foregroundStyle(severityColor(item.severity))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(severityColor(item.severity).opacity(0.1))
        .background(ForgeTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.inline))
        .offset(y: y)
        .opacity(y >= 0 ? 1 : 0) // Hide if scrolled above viewport
    }

    private func severityIcon(_ severity: DiagnosticSeverity) -> some View {
        switch severity {
        case .error: return Image(systemName: "xmark.circle.fill")
        case .warning: return Image(systemName: "exclamationmark.triangle.fill")
        case .information: return Image(systemName: "info.circle.fill")
        case .hint: return Image(systemName: "lightbulb.fill")
        }
    }

    private func severityColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .error: return ForgeTheme.Colors.error
        case .warning: return ForgeTheme.Colors.warning
        case .information: return ForgeTheme.Colors.info
        case .hint: return ForgeTheme.Colors.success
        }
    }
}

// MARK: - DiagnosticsGutterView

/// Renders severity indicators in the line number gutter.
struct DiagnosticsGutterView: View {
    let diagnostics: [DiagnosticItem]
    let lineHeight: CGFloat
    let visibleRange: Range<Int>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(diagnosticsInRange, id: \.id) { diagnostic in
                let y = CGFloat(diagnostic.range.start.line - visibleRange.lowerBound) * lineHeight

                Circle()
                    .fill(gutterColor(diagnostic.severity))
                    .frame(width: 8, height: 8)
                    .offset(y: y + (lineHeight - 8) / 2)
            }
        }
        .frame(width: 12)
    }

    private var diagnosticsInRange: [DiagnosticItem] {
        diagnostics.filter { visibleRange.contains($0.range.start.line) }
    }

    private func gutterColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .error: return ForgeTheme.Colors.error
        case .warning: return ForgeTheme.Colors.warning
        case .information: return ForgeTheme.Colors.info
        case .hint: return ForgeTheme.Colors.success
        }
    }
}
