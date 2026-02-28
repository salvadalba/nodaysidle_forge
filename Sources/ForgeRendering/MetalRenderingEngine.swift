import Foundation
import Metal
import MetalKit
import CoreText
import QuartzCore
import os.log
import ForgeShared
import ForgeEditorEngine

private let logger = Logger(subsystem: "com.forge.editor", category: "rendering")

/// Rendering mode indicator.
public enum RenderingMode: Sendable {
    case metal
    case coreTextFallback
}

// MARK: - Vertex Types (Swift side, mirrors Shaders.metal)

public struct TextVertexData {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
    var color: SIMD4<Float>
}

public struct RectVertexData {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

public struct UniformData {
    var viewportSize: SIMD2<Float>
    var cursorBlinkOpacity: Float
    var time: Float
}

// MARK: - Editor Viewport

/// Describes the visible region of the editor for rendering.
public struct EditorViewport: Sendable {
    public var visibleLineRange: Range<Int>
    public var viewportSize: CGSize
    public var scrollOffset: CGPoint
    public var lineHeight: CGFloat
    public var gutterWidth: CGFloat

    public init(
        visibleLineRange: Range<Int>,
        viewportSize: CGSize,
        scrollOffset: CGPoint = .zero,
        lineHeight: CGFloat = 20,
        gutterWidth: CGFloat = 50
    ) {
        self.visibleLineRange = visibleLineRange
        self.viewportSize = viewportSize
        self.scrollOffset = scrollOffset
        self.lineHeight = lineHeight
        self.gutterWidth = gutterWidth
    }
}

// MARK: - MetalRenderingEngine

/// GPU-accelerated text rendering engine using Metal.
///
/// Manages the Metal pipeline state, glyph atlas, and per-frame
/// rendering of text, selections, and cursor layers.
@MainActor
public final class MetalRenderingEngine {
    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    public let glyphAtlas: GlyphAtlas

    private var textPipelineState: MTLRenderPipelineState?
    private var selectionPipelineState: MTLRenderPipelineState?
    private var cursorPipelineState: MTLRenderPipelineState?

    private var sampler: MTLSamplerState?
    private var metalLayer: CAMetalLayer?

    private var currentFont: CTFont
    private var time: Float = 0
    private var cursorBlinkPhase: Float = 0

    /// Whether the Metal engine is actively rendering.
    public private(set) var isActive: Bool = false

    // MARK: - Init

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("Failed to create Metal device — GPU unavailable")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            logger.error("Failed to create Metal command queue")
            return nil
        }

        self.device = device
        self.commandQueue = queue

        // Default font: SF Mono 13pt
        self.currentFont = CTFontCreateWithName("SFMono-Regular" as CFString, 13, nil)

        do {
            self.glyphAtlas = try GlyphAtlas(device: device)
        } catch {
            logger.error("Failed to create glyph atlas: \(error.localizedDescription)")
            return nil
        }

        setupPipelineStates()
        setupSampler()
        glyphAtlas.prewarmASCII(font: currentFont)
        isActive = true

        logger.info("MetalRenderingEngine initialized with device: \(device.name)")
    }

    // MARK: - Setup

    private func setupPipelineStates() {
        // Load shader source from bundled resource and compile at runtime
        // (SwiftPM doesn't compile .metal files — we compile from source)
        guard let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL) else {
            logger.error("Failed to load Metal shader source from bundle")
            return
        }

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            logger.error("Failed to compile Metal shader library")
            return
        }

        // Text pipeline
        if let vertexFn = library.makeFunction(name: "textVertexShader"),
           let fragmentFn = library.makeFunction(name: "textFragmentShader") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            textPipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        // Selection pipeline
        if let vertexFn = library.makeFunction(name: "selectionVertexShader"),
           let fragmentFn = library.makeFunction(name: "selectionFragmentShader") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            selectionPipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        // Cursor pipeline
        if let vertexFn = library.makeFunction(name: "cursorVertexShader"),
           let fragmentFn = library.makeFunction(name: "cursorFragmentShader") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            cursorPipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        }
    }

    private func setupSampler() {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: descriptor)
    }

    // MARK: - Configure Layer

    /// Configure a CAMetalLayer for rendering.
    public func configure(layer: CAMetalLayer) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.displaySyncEnabled = true
        self.metalLayer = layer
    }

    // MARK: - Render Frame

    /// Render a single frame with text, selections, and cursor.
    public func render(
        viewport: EditorViewport,
        buffer: EditorBuffer,
        tokens: [SyntaxToken],
        cursorPosition: ForgeShared.TextPosition,
        selections: [ForgeShared.TextRange]
    ) {
        guard let metalLayer = metalLayer,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let viewportSize = SIMD2<Float>(Float(viewport.viewportSize.width), Float(viewport.viewportSize.height))

        // Update timing
        time += 1.0 / 120.0
        cursorBlinkPhase += 1.0 / 120.0
        let blinkOpacity = (sin(cursorBlinkPhase * 3.0) + 1.0) / 2.0

        var uniforms = UniformData(
            viewportSize: viewportSize,
            cursorBlinkOpacity: blinkOpacity,
            time: time
        )

        // 1. Render selection highlights
        renderSelections(encoder: encoder, uniforms: &uniforms, viewport: viewport, selections: selections)

        // 2. Render text
        renderText(encoder: encoder, uniforms: &uniforms, viewport: viewport, buffer: buffer, tokens: tokens)

        // 3. Render cursor
        renderCursor(encoder: encoder, uniforms: &uniforms, viewport: viewport, cursorPosition: cursorPosition)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Layer Renderers

    private func renderText(
        encoder: MTLRenderCommandEncoder,
        uniforms: inout UniformData,
        viewport: EditorViewport,
        buffer: EditorBuffer,
        tokens: [SyntaxToken]
    ) {
        guard let pipelineState = textPipelineState,
              let atlas = glyphAtlas.texture,
              let sampler = sampler else { return }

        var vertices: [TextVertexData] = []

        for lineIdx in viewport.visibleLineRange {
            let lineText = buffer.lineText(lineIdx)
            let y = Float(lineIdx) * Float(viewport.lineHeight) - Float(viewport.scrollOffset.y)
            var x = Float(viewport.gutterWidth)

            for (charIdx, char) in lineText.unicodeScalars.enumerated() {
                var glyphs = [CGGlyph(0)]
                var chars = [UniChar(char.value)]
                CTFontGetGlyphsForCharacters(currentFont, &chars, &glyphs, 1)

                guard let info = glyphAtlas.glyphInfo(for: glyphs[0], font: currentFont) else {
                    x += Float(CTFontGetSize(currentFont) * 0.6) // fallback advance
                    continue
                }

                let color = tokenColor(at: ForgeShared.TextPosition(line: lineIdx, column: charIdx), tokens: tokens)

                // Two triangles (quad) for this glyph
                let x0 = x + info.bearingX
                let y0 = y - info.bearingY
                let x1 = x0 + Float(info.pixelWidth)
                let y1 = y0 + Float(info.pixelHeight)

                let u0 = info.uvX
                let v0 = info.uvY
                let u1 = info.uvX + info.uvWidth
                let v1 = info.uvY + info.uvHeight

                vertices.append(contentsOf: [
                    TextVertexData(position: SIMD2(x0, y0), texCoord: SIMD2(u0, v0), color: color),
                    TextVertexData(position: SIMD2(x1, y0), texCoord: SIMD2(u1, v0), color: color),
                    TextVertexData(position: SIMD2(x0, y1), texCoord: SIMD2(u0, v1), color: color),

                    TextVertexData(position: SIMD2(x1, y0), texCoord: SIMD2(u1, v0), color: color),
                    TextVertexData(position: SIMD2(x1, y1), texCoord: SIMD2(u1, v1), color: color),
                    TextVertexData(position: SIMD2(x0, y1), texCoord: SIMD2(u0, v1), color: color),
                ])

                x += info.advance
            }
        }

        guard !vertices.isEmpty else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(vertices, length: MemoryLayout<TextVertexData>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformData>.size, index: 1)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func renderSelections(
        encoder: MTLRenderCommandEncoder,
        uniforms: inout UniformData,
        viewport: EditorViewport,
        selections: [ForgeShared.TextRange]
    ) {
        guard let pipelineState = selectionPipelineState, !selections.isEmpty else { return }

        var vertices: [RectVertexData] = []
        let selColor = SIMD4<Float>(0.2, 0.4, 0.8, 0.3) // Blue highlight

        for selection in selections {
            for line in selection.start.line...selection.end.line {
                guard viewport.visibleLineRange.contains(line) else { continue }

                let y = Float(line) * Float(viewport.lineHeight) - Float(viewport.scrollOffset.y)
                let startCol = line == selection.start.line ? selection.start.column : 0
                let endCol = line == selection.end.line ? selection.end.column : 200 // approximate line length

                let x0 = Float(viewport.gutterWidth) + Float(startCol) * Float(CTFontGetSize(currentFont) * 0.6)
                let x1 = Float(viewport.gutterWidth) + Float(endCol) * Float(CTFontGetSize(currentFont) * 0.6)
                let y0 = y
                let y1 = y + Float(viewport.lineHeight)

                vertices.append(contentsOf: [
                    RectVertexData(position: SIMD2(x0, y0), color: selColor),
                    RectVertexData(position: SIMD2(x1, y0), color: selColor),
                    RectVertexData(position: SIMD2(x0, y1), color: selColor),
                    RectVertexData(position: SIMD2(x1, y0), color: selColor),
                    RectVertexData(position: SIMD2(x1, y1), color: selColor),
                    RectVertexData(position: SIMD2(x0, y1), color: selColor),
                ])
            }
        }

        guard !vertices.isEmpty else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(vertices, length: MemoryLayout<RectVertexData>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformData>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func renderCursor(
        encoder: MTLRenderCommandEncoder,
        uniforms: inout UniformData,
        viewport: EditorViewport,
        cursorPosition: ForgeShared.TextPosition
    ) {
        guard let pipelineState = cursorPipelineState,
              viewport.visibleLineRange.contains(cursorPosition.line) else { return }

        let charWidth = Float(CTFontGetSize(currentFont) * 0.6)
        let x = Float(viewport.gutterWidth) + Float(cursorPosition.column) * charWidth
        let y = Float(cursorPosition.line) * Float(viewport.lineHeight) - Float(viewport.scrollOffset.y)
        let cursorWidth: Float = 2.0
        let cursorHeight = Float(viewport.lineHeight)

        let cursorColor = SIMD4<Float>(0.9, 0.9, 0.9, 1.0)

        let vertices: [RectVertexData] = [
            RectVertexData(position: SIMD2(x, y), color: cursorColor),
            RectVertexData(position: SIMD2(x + cursorWidth, y), color: cursorColor),
            RectVertexData(position: SIMD2(x, y + cursorHeight), color: cursorColor),
            RectVertexData(position: SIMD2(x + cursorWidth, y), color: cursorColor),
            RectVertexData(position: SIMD2(x + cursorWidth, y + cursorHeight), color: cursorColor),
            RectVertexData(position: SIMD2(x, y + cursorHeight), color: cursorColor),
        ]

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(vertices, length: MemoryLayout<RectVertexData>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformData>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    // MARK: - Token Colors

    private func tokenColor(at position: ForgeShared.TextPosition, tokens: [SyntaxToken]) -> SIMD4<Float> {
        for token in tokens {
            if token.range.start.line == position.line &&
               token.range.start.column <= position.column &&
               token.range.end.column > position.column {
                return simdColor(for: token.kind)
            }
        }
        return SIMD4<Float>(0.85, 0.85, 0.85, 1.0) // Default text color
    }

    private func simdColor(for kind: SyntaxTokenKind) -> SIMD4<Float> {
        switch kind {
        case .keyword:     return SIMD4(0.98, 0.37, 0.60, 1.0) // Pink
        case .string:      return SIMD4(0.90, 0.38, 0.34, 1.0) // Red
        case .number:      return SIMD4(0.68, 0.51, 0.87, 1.0) // Purple
        case .comment:     return SIMD4(0.50, 0.50, 0.50, 1.0) // Gray
        case .type:        return SIMD4(0.40, 0.82, 0.92, 1.0) // Cyan
        case .builtinType: return SIMD4(0.40, 0.82, 0.92, 1.0) // Cyan
        case .function:    return SIMD4(0.40, 0.55, 0.95, 1.0) // Blue
        case .variable:    return SIMD4(0.85, 0.85, 0.85, 1.0) // Light gray
        case .property:    return SIMD4(0.55, 0.82, 0.78, 1.0) // Teal
        case .operator:    return SIMD4(0.85, 0.85, 0.85, 1.0) // Light gray
        case .punctuation: return SIMD4(0.65, 0.65, 0.65, 1.0) // Medium gray
        case .attribute:   return SIMD4(0.95, 0.68, 0.28, 1.0) // Orange
        case .parameter:   return SIMD4(0.85, 0.85, 0.85, 1.0) // Light gray
        case .label:       return SIMD4(0.95, 0.85, 0.30, 1.0) // Yellow
        case .plain:       return SIMD4(0.85, 0.85, 0.85, 1.0) // Light gray
        }
    }

    // MARK: - Resize

    /// Update the rendering surface size.
    public func resize(to size: CGSize) {
        metalLayer?.drawableSize = size
    }

    // MARK: - Font

    /// Change the rendering font and invalidate glyph cache.
    public func setFont(name: String, size: CGFloat) {
        let oldFontName = CTFontCopyPostScriptName(currentFont) as String
        currentFont = CTFontCreateWithName(name as CFString, size, nil)
        glyphAtlas.invalidateCache(for: oldFontName)
        glyphAtlas.prewarmASCII(font: currentFont)
    }
}
