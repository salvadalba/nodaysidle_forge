import AppKit
import os.log

private let logger = Logger(subsystem: "com.forge.editor", category: "appdelegate")

// MARK: - AppDelegate

/// Customizes NSWindow appearance: dark Molten Craft chrome,
/// full-size content view, and window frame state restoration.
final class ForgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        customizeMainWindow()
        logger.info("Forge application launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Forge application terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Window Customization

    private func customizeMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }

            // Dark Molten Craft chrome
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)

            window.isMovableByWindowBackground = true
            window.backgroundColor = ForgeTheme.Colors.nsBase

            // Minimum size
            window.minSize = NSSize(width: 800, height: 600)

            logger.info("Window customized with Molten Craft theme")
        }
    }
}
