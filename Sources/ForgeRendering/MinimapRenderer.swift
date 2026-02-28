import Foundation
import Metal
import ForgeShared
import ForgeEditorEngine

// MARK: - MinimapRenderer

/// Renders a downscaled minimap overview of the document using colored blocks
/// to represent syntax-highlighted code structure.
@MainActor
public final class MinimapRenderer {
    // MARK: - Configuration

    /// Width of the minimap in pixels.
    public var minimapWidth: Float = 80

    /// Scale factor for minimap lines (how tall each line appears).
    public var lineScale: Float = 2.0

    /// Horizontal pixel width of each character block in the minimap.
    public var charBlockWidth: Float = 1.5

    // MARK: - Properties

    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState?

    // MARK: - Init

    public init?(device: MTLDevice, library: MTLLibrary?) {
        self.device = device

        guard let library = library,
              let vertexFn = library.makeFunction(name: "minimapVertexShader"),
              let fragmentFn = library.makeFunction(name: "minimapFragmentShader") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        self.pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Render

    /// Render the minimap for the given buffer state.
    public func render(
        encoder: MTLRenderCommandEncoder,
        buffer: EditorBuffer,
        tokens: [SyntaxToken],
        viewport: EditorViewport,
        uniforms: inout UniformData
    ) {
        guard let pipelineState = pipelineState else { return }

        let viewportWidth = Float(viewport.viewportSize.width)
        let minimapX = viewportWidth - minimapWidth - 10 // 10px margin from right edge
        let totalLines = buffer.lineCount

        var vertices: [TextVertexData] = []

        // Background for minimap
        let bgColor = SIMD4<Float>(0.08, 0.08, 0.10, 0.8)
        vertices.append(contentsOf: makeQuad(
            x: minimapX - 5, y: 0,
            width: minimapWidth + 10, height: Float(viewport.viewportSize.height),
            color: bgColor
        ))

        // Visible area indicator
        let scrollRatio = Float(viewport.scrollOffset.y) / max(1, Float(totalLines) * Float(viewport.lineHeight))
        let visibleRatio = Float(viewport.viewportSize.height) / max(1, Float(totalLines) * Float(viewport.lineHeight))
        let indicatorY = scrollRatio * Float(viewport.viewportSize.height)
        let indicatorHeight = max(20, visibleRatio * Float(viewport.viewportSize.height))

        let indicatorColor = SIMD4<Float>(0.3, 0.5, 0.8, 0.2)
        vertices.append(contentsOf: makeQuad(
            x: minimapX, y: indicatorY,
            width: minimapWidth, height: indicatorHeight,
            color: indicatorColor
        ))

        // Render line blocks
        for lineIdx in 0..<totalLines {
            let y = Float(lineIdx) * lineScale
            guard y < Float(viewport.viewportSize.height) else { break }

            let lineText = buffer.lineText(lineIdx)
            guard !lineText.isEmpty else { continue }

            // Get token color for approximate line representation
            let lineTokens = tokens.filter { $0.range.start.line == lineIdx }

            if lineTokens.isEmpty {
                // Plain text block
                let blockWidth = min(Float(lineText.count) * charBlockWidth, minimapWidth)
                let color = SIMD4<Float>(0.5, 0.5, 0.5, 0.4)
                vertices.append(contentsOf: makeQuad(
                    x: minimapX, y: y,
                    width: blockWidth, height: lineScale,
                    color: color
                ))
            } else {
                // Colored blocks per token
                for token in lineTokens {
                    let startX = minimapX + Float(token.range.start.column) * charBlockWidth
                    let blockWidth = Float(token.range.end.column - token.range.start.column) * charBlockWidth
                    let color = minimapColor(for: token.kind)
                    vertices.append(contentsOf: makeQuad(
                        x: startX, y: y,
                        width: min(blockWidth, minimapWidth), height: lineScale,
                        color: color
                    ))
                }
            }
        }

        guard !vertices.isEmpty else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(vertices, length: MemoryLayout<TextVertexData>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<UniformData>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    // MARK: - Hit Testing

    /// Convert a click position on the minimap to a document line number.
    public func lineAtPoint(_ point: CGPoint, totalLines: Int, viewportHeight: CGFloat) -> Int? {
        let viewportWidth = Float(viewportHeight) // approximate from context
        let minimapX = viewportWidth - minimapWidth - 10
        guard Float(point.x) >= minimapX else { return nil }

        let line = Int(Float(point.y) / lineScale)
        guard line >= 0 && line < totalLines else { return nil }
        return line
    }

    // MARK: - Helpers

    private func makeQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) -> [TextVertexData] {
        let emptyUV = SIMD2<Float>(0, 0) // no texture sampling for minimap
        return [
            TextVertexData(position: SIMD2(x, y), texCoord: emptyUV, color: color),
            TextVertexData(position: SIMD2(x + width, y), texCoord: emptyUV, color: color),
            TextVertexData(position: SIMD2(x, y + height), texCoord: emptyUV, color: color),
            TextVertexData(position: SIMD2(x + width, y), texCoord: emptyUV, color: color),
            TextVertexData(position: SIMD2(x + width, y + height), texCoord: emptyUV, color: color),
            TextVertexData(position: SIMD2(x, y + height), texCoord: emptyUV, color: color),
        ]
    }

    private func minimapColor(for kind: SyntaxTokenKind) -> SIMD4<Float> {
        switch kind {
        case .keyword:     return SIMD4(0.98, 0.37, 0.60, 0.6)
        case .string:      return SIMD4(0.90, 0.38, 0.34, 0.6)
        case .number:      return SIMD4(0.68, 0.51, 0.87, 0.6)
        case .comment:     return SIMD4(0.40, 0.40, 0.40, 0.4)
        case .type, .builtinType: return SIMD4(0.40, 0.82, 0.92, 0.6)
        case .function:    return SIMD4(0.40, 0.55, 0.95, 0.6)
        case .attribute:   return SIMD4(0.95, 0.68, 0.28, 0.6)
        default:           return SIMD4(0.55, 0.55, 0.55, 0.4)
        }
    }
}
