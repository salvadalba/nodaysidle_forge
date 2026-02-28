import SwiftUI
import AppKit
import Metal
import QuartzCore
import ForgeShared
import ForgeEditorEngine

// MARK: - MetalEditorView

/// NSViewRepresentable wrapping a CAMetalLayer for GPU-accelerated text rendering.
/// Falls back to CoreTextFallbackView when Metal is unavailable.
public struct MetalEditorView: View {
    @Bindable var buffer: EditorBuffer
    let highlighter: SyntaxHighlighter
    let language: ForgeShared.Language

    @State private var tokens: [SyntaxToken] = []
    @State private var renderingEngine: MetalRenderingEngine?
    @State private var useMetalRendering = true

    public init(buffer: EditorBuffer, highlighter: SyntaxHighlighter, language: ForgeShared.Language) {
        self.buffer = buffer
        self.highlighter = highlighter
        self.language = language
    }

    public var body: some View {
        Group {
            if useMetalRendering, renderingEngine != nil {
                TimelineView(.animation) { timeline in
                    MetalLayerView(
                        renderingEngine: renderingEngine!,
                        buffer: buffer,
                        tokens: tokens,
                        date: timeline.date
                    )
                }
            } else {
                CoreTextFallbackView(buffer: buffer, tokens: tokens)
            }
        }
        .focusable()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .task {
            // Initialize Metal engine
            if let engine = MetalRenderingEngine() {
                renderingEngine = engine
                useMetalRendering = true
            } else {
                useMetalRendering = false
            }
            await updateHighlighting()
        }
        .onChange(of: buffer.text) {
            Task { await updateHighlighting() }
        }
    }

    private func updateHighlighting() async {
        tokens = await highlighter.highlight(buffer.text, language: language)
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let char = keyPress.characters

        if keyPress.key == .return {
            try? buffer.insertAtCursor("\n")
            return .handled
        }
        if keyPress.key == .tab {
            try? buffer.insertAtCursor("    ")
            return .handled
        }
        if keyPress.key == .delete {
            buffer.deleteBackward()
            return .handled
        }

        if keyPress.modifiers.contains(.command) {
            if char == "z" {
                if keyPress.modifiers.contains(.shift) {
                    buffer.redo()
                } else {
                    buffer.undo()
                }
                return .handled
            }
            return .ignored
        }

        if !char.isEmpty && !keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.control) {
            try? buffer.insertAtCursor(char)
            return .handled
        }

        return .ignored
    }
}

// MARK: - MetalLayerView (NSViewRepresentable)

struct MetalLayerView: NSViewRepresentable {
    let renderingEngine: MetalRenderingEngine
    @Bindable var buffer: EditorBuffer
    let tokens: [SyntaxToken]
    let date: Date

    func makeNSView(context: Context) -> MetalNSView {
        let view = MetalNSView()
        view.wantsLayer = true
        view.layer = CAMetalLayer()
        if let metalLayer = view.layer as? CAMetalLayer {
            renderingEngine.configure(layer: metalLayer)
        }
        return view
    }

    func updateNSView(_ nsView: MetalNSView, context: Context) {
        guard let metalLayer = nsView.layer as? CAMetalLayer else { return }

        let size = nsView.bounds.size
        let scale = nsView.window?.backingScaleFactor ?? 2.0
        metalLayer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        metalLayer.contentsScale = scale

        let lineCount = buffer.lineCount
        let lineHeight: CGFloat = 20
        let firstVisibleLine = max(0, Int(0 / lineHeight)) // TODO: wire scroll offset
        let lastVisibleLine = min(lineCount, firstVisibleLine + Int(size.height / lineHeight) + 2)

        let viewport = EditorViewport(
            visibleLineRange: firstVisibleLine..<lastVisibleLine,
            viewportSize: CGSize(width: size.width * scale, height: size.height * scale),
            scrollOffset: .zero,
            lineHeight: lineHeight * scale,
            gutterWidth: 50 * scale
        )

        renderingEngine.render(
            viewport: viewport,
            buffer: buffer,
            tokens: tokens,
            cursorPosition: buffer.cursorPosition,
            selections: buffer.selections
        )
    }
}

/// Simple NSView subclass for hosting a CAMetalLayer.
class MetalNSView: NSView {
    override var isFlipped: Bool { true }

    override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }
}
