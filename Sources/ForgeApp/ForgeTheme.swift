import SwiftUI

// MARK: - Molten Craft Design System

enum ForgeTheme {

    // MARK: - Colors

    enum Colors {
        static let base = Color(red: 0.051, green: 0.051, blue: 0.059)           // #0D0D0F
        static let surface = Color(red: 0.102, green: 0.102, blue: 0.118)        // #1A1A1E
        static let surfaceHover = Color(red: 0.145, green: 0.145, blue: 0.157)   // #252528
        static let border = Color(red: 0.165, green: 0.165, blue: 0.180)         // #2A2A2E

        static let textPrimary = Color(red: 0.941, green: 0.929, blue: 0.918)    // #F0EDEA
        static let textSecondary = Color(red: 0.541, green: 0.525, blue: 0.502)  // #8A8680
        static let textTertiary = Color(red: 0.353, green: 0.341, blue: 0.329)   // #5A5754

        static let accent = Color(red: 0.961, green: 0.651, blue: 0.137)         // #F5A623
        static let accentOrange = Color(red: 1.0, green: 0.420, blue: 0.173)     // #FF6B2C
        static let accentMuted = Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.15)

        static let success = Color(red: 0.290, green: 0.871, blue: 0.502)        // #4ADE80
        static let warning = Color(red: 0.984, green: 0.749, blue: 0.141)        // #FBBF24
        static let error = Color(red: 0.937, green: 0.267, blue: 0.267)          // #EF4444
        static let info = Color(red: 0.376, green: 0.647, blue: 0.980)           // #60A5FA

        static let accentGradient = LinearGradient(
            colors: [accent, accentOrange],
            startPoint: .leading,
            endPoint: .trailing
        )

        // NSColor equivalents for AppKit interop
        static let nsBase = NSColor(red: 0.051, green: 0.051, blue: 0.059, alpha: 1)
        static let nsSurface = NSColor(red: 0.102, green: 0.102, blue: 0.118, alpha: 1)
    }

    // MARK: - Fonts

    enum Fonts {
        static func ui(size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func code(size: CGFloat = 13) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }

        static func label(size: CGFloat = 11) -> Font {
            .system(size: size, weight: .light, design: .default)
        }
    }

    // MARK: - Spacing (8px grid)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Animation

    enum Anim {
        static let spring = Animation.spring(duration: 0.25, bounce: 0.12)
        static let hover = Animation.easeOut(duration: 0.15)
    }

    // MARK: - Corner Radii

    enum Corner {
        static let panel: CGFloat = 8
        static let button: CGFloat = 6
        static let inline: CGFloat = 4
    }
}

// MARK: - View Modifiers

struct ForgePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ForgeTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.panel))
            .overlay(
                RoundedRectangle(cornerRadius: ForgeTheme.Corner.panel)
                    .strokeBorder(ForgeTheme.Colors.border, lineWidth: 0.5)
            )
    }
}

struct ForgeSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ForgeTheme.Colors.surface)
    }
}

struct ForgeButtonModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(ForgeTheme.Colors.textPrimary)
            .padding(.horizontal, ForgeTheme.Spacing.xs)
            .padding(.vertical, ForgeTheme.Spacing.xxs)
            .background(isHovering ? ForgeTheme.Colors.surfaceHover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: ForgeTheme.Corner.button))
            .onHover { hovering in
                withAnimation(ForgeTheme.Anim.hover) {
                    isHovering = hovering
                }
            }
    }
}

extension View {
    func forgePanel() -> some View {
        modifier(ForgePanelModifier())
    }

    func forgeSurface() -> some View {
        modifier(ForgeSurfaceModifier())
    }

    func forgeButton() -> some View {
        modifier(ForgeButtonModifier())
    }
}
