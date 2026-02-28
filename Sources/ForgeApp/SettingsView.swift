import SwiftUI
import ForgeShared

// MARK: - Settings Data Models

/// User-facing editor settings persisted via EditorPreferences.
struct EditorSettings: Codable {
    var tabWidth: Int = 4
    var insertSpaces: Bool = true
    var wordWrap: Bool = false
    var showLineNumbers: Bool = true
    var showMinimap: Bool = true
    var highlightCurrentLine: Bool = true
}

/// User-facing theme settings.
struct ThemeSettings: Codable {
    var appearance: AppearanceMode = .auto
    var editorFontFamily: String = "SF Mono"
    var editorFontSize: Double = 13
    var enableLigatures: Bool = true
}

/// Appearance mode options.
enum AppearanceMode: String, Codable, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case auto = "System"
}

// MARK: - SettingsView

/// The main settings interface with tabbed sections.
struct SettingsView: View {
    @State private var editorSettings = EditorSettings()
    @State private var themeSettings = ThemeSettings()

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            editorTab
                .tabItem {
                    Label("Editor", systemImage: "pencil")
                }

            themeTab
                .tabItem {
                    Label("Themes", systemImage: "paintpalette")
                }

            keybindingsTab
                .tabItem {
                    Label("Keybindings", systemImage: "keyboard")
                }
        }
        .frame(width: 500, height: 380)
        .preferredColorScheme(.dark)
        .tint(ForgeTheme.Colors.accent)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themeSettings.appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
            }

            Section("Startup") {
                Toggle("Restore previous workspace on launch", isOn: .constant(true))
                Toggle("Show welcome screen for empty windows", isOn: .constant(true))
            }
        }
        .padding(20)
    }

    // MARK: - Editor Tab

    private var editorTab: some View {
        Form {
            Section("Indentation") {
                Stepper("Tab Width: \(editorSettings.tabWidth)", value: $editorSettings.tabWidth, in: 1...8)
                Toggle("Insert Spaces", isOn: $editorSettings.insertSpaces)
            }

            Section("Display") {
                Toggle("Show Line Numbers", isOn: $editorSettings.showLineNumbers)
                Toggle("Show Minimap", isOn: $editorSettings.showMinimap)
                Toggle("Highlight Current Line", isOn: $editorSettings.highlightCurrentLine)
                Toggle("Word Wrap", isOn: $editorSettings.wordWrap)
            }
        }
        .padding(20)
    }

    // MARK: - Theme Tab

    private var themeTab: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Family")
                    Spacer()
                    Picker("", selection: $themeSettings.editorFontFamily) {
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("Courier New").tag("Courier New")
                        Text("JetBrains Mono").tag("JetBrains Mono")
                        Text("Fira Code").tag("Fira Code")
                    }
                    .frame(width: 180)
                }

                HStack {
                    Text("Size")
                    Spacer()
                    Slider(value: $themeSettings.editorFontSize, in: 8...32, step: 1)
                        .frame(width: 180)
                    Text("\(Int(themeSettings.editorFontSize)) pt")
                        .frame(width: 40)
                        .foregroundStyle(.secondary)
                }

                Toggle("Enable Font Ligatures", isOn: $themeSettings.enableLigatures)
            }

            Section("Preview") {
                Text("func hello() -> String {\n    return \"Hello, Forge!\"\n}")
                    .font(.system(size: CGFloat(themeSettings.editorFontSize), design: .monospaced))
                    .foregroundStyle(ForgeTheme.Colors.textPrimary)
                    .padding(ForgeTheme.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ForgeTheme.Colors.base)
                    .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.button))
            }
        }
        .padding(20)
    }

    // MARK: - Keybindings Tab

    private var keybindingsTab: some View {
        Form {
            Section("Keybindings") {
                Text("Custom keybindings will be available in a future update.")
                    .foregroundStyle(.secondary)

                // Show current defaults
                ForEach(CommandRegistry.shared.commands.prefix(10)) { command in
                    HStack {
                        Text(command.title)
                            .foregroundStyle(ForgeTheme.Colors.textPrimary)
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
                }
            }
        }
        .padding(20)
    }
}
