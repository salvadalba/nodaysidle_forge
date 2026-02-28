import SwiftUI
import ForgeShared

// MARK: - CommandPalette

/// Animated command palette overlay with fuzzy search and keyboard navigation.
/// Triggered via ⌘⇧P. Uses matchedGeometryEffect for open/close transitions.
struct CommandPalette: View {
    @Binding var isPresented: Bool
    let onExecute: (ForgeCommand) -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private let registry = CommandRegistry.shared

    private var filteredCommands: [ForgeCommand] {
        registry.search(query: query)
    }

    var body: some View {
        if isPresented {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                // Palette
                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: ForgeTheme.Spacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(ForgeTheme.Colors.textTertiary)

                        TextField("Type a command...", text: $query)
                            .textFieldStyle(.plain)
                            .font(ForgeTheme.Fonts.ui(size: 16, weight: .regular))
                            .foregroundStyle(ForgeTheme.Colors.textPrimary)
                            .focused($isSearchFocused)
                            .onSubmit {
                                executeSelected()
                            }
                    }
                    .padding(.horizontal, ForgeTheme.Spacing.md)
                    .padding(.vertical, ForgeTheme.Spacing.sm)

                    Rectangle()
                        .fill(ForgeTheme.Colors.border)
                        .frame(height: 0.5)

                    // Results list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                    commandRow(command: command, isSelected: index == selectedIndex)
                                        .id(index)
                                        .onTapGesture {
                                            execute(command)
                                        }
                                }

                                if filteredCommands.isEmpty && !query.isEmpty {
                                    HStack {
                                        Spacer()
                                        Text("No matching commands")
                                            .foregroundStyle(ForgeTheme.Colors.textTertiary)
                                            .padding(.vertical, 20)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.vertical, ForgeTheme.Spacing.xxs)
                        }
                        .onChange(of: selectedIndex) { _, newValue in
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                    .frame(maxHeight: 320)
                }
                .frame(width: 520)
                .background(ForgeTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.panel))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                .padding(.top, 100)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
            }
            .animation(.spring(duration: 0.25, bounce: 0.15), value: isPresented)
            .onAppear {
                query = ""
                selectedIndex = 0
                isSearchFocused = true
            }
        }
    }

    // MARK: - Command Row

    private func commandRow(command: ForgeCommand, isSelected: Bool) -> some View {
        HStack(spacing: 0) {
            // Amber left edge indicator for selected row
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? ForgeTheme.Colors.accent : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(ForgeTheme.Fonts.ui(size: 14))
                        .foregroundStyle(ForgeTheme.Colors.textPrimary)

                    Text(command.category)
                        .font(ForgeTheme.Fonts.label(size: 11))
                        .foregroundStyle(ForgeTheme.Colors.textTertiary)
                }

                Spacer()

                if let shortcut = command.keyboardShortcut {
                    Text(shortcut)
                        .font(ForgeTheme.Fonts.code(size: 12))
                        .foregroundStyle(ForgeTheme.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ForgeTheme.Colors.border)
                        .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.inline))
                }
            }
            .padding(.leading, ForgeTheme.Spacing.sm)
            .padding(.trailing, ForgeTheme.Spacing.md)
        }
        .padding(.vertical, 6)
        .background(isSelected ? ForgeTheme.Colors.accentMuted : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < filteredCommands.count {
            selectedIndex = newIndex
        }
    }

    private func executeSelected() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        execute(filteredCommands[selectedIndex])
    }

    private func execute(_ command: ForgeCommand) {
        onExecute(command)
        dismiss()
    }

    private func dismiss() {
        withAnimation(.spring(duration: 0.2)) {
            isPresented = false
        }
    }
}
