import SwiftUI
import ForgeShared

// MARK: - CompletionPopup

/// Floating popup showing ranked code completions from the language server.
struct CompletionPopup: View {
    let items: [CompletionItem]
    let onSelect: (CompletionItem) -> Void
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            completionRow(item: item, isSelected: index == selectedIndex)
                                .id(index)
                                .onTapGesture {
                                    onSelect(item)
                                }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
        .frame(width: 320)
        .background(ForgeTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.panel))
        .overlay(
            RoundedRectangle(cornerRadius: ForgeTheme.Corner.panel)
                .strokeBorder(ForgeTheme.Colors.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < items.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            if items.indices.contains(selectedIndex) {
                onSelect(items[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func completionRow(item: CompletionItem, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            // Kind icon
            kindIcon(item.kind)
                .font(.system(size: 12))
                .foregroundStyle(kindColor(item.kind))
                .frame(width: 18)

            // Label
            Text(item.label)
                .font(ForgeTheme.Fonts.code(size: 13))
                .foregroundStyle(ForgeTheme.Colors.textPrimary)

            Spacer()

            // Detail
            if let detail = item.detail {
                Text(detail)
                    .font(ForgeTheme.Fonts.label(size: 11))
                    .foregroundStyle(ForgeTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, ForgeTheme.Spacing.xs)
        .padding(.vertical, ForgeTheme.Spacing.xxs)
        .background(isSelected ? ForgeTheme.Colors.accentMuted : Color.clear)
    }

    private func kindIcon(_ kind: CompletionKind) -> some View {
        switch kind {
        case .function: return Image(systemName: "f.square")
        case .variable: return Image(systemName: "v.square")
        case .type: return Image(systemName: "t.square")
        case .keyword: return Image(systemName: "k.square")
        case .property: return Image(systemName: "p.square")
        case .snippet: return Image(systemName: "text.badge.plus")
        case .other: return Image(systemName: "questionmark.square")
        }
    }

    private func kindColor(_ kind: CompletionKind) -> Color {
        switch kind {
        case .function: return Color(red: 0.7, green: 0.6, blue: 0.9)   // warm lavender
        case .variable: return ForgeTheme.Colors.info                     // sky blue
        case .type: return Color(red: 0.4, green: 0.8, blue: 0.8)       // warm cyan
        case .keyword: return Color(red: 0.9, green: 0.5, blue: 0.6)    // warm rose
        case .property: return ForgeTheme.Colors.success                  // warm green
        case .snippet: return ForgeTheme.Colors.accent                    // amber
        case .other: return ForgeTheme.Colors.textSecondary
        }
    }
}
