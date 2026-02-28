import Foundation
import Metal
import CoreText
import os.log
import ForgeShared

private let logger = Logger(subsystem: "com.forge.editor", category: "rendering")

// MARK: - GlyphAtlas

/// Manages a Metal texture atlas for rasterized glyphs.
///
/// Rasterizes glyphs via Core Text CTFont/CTLine, packs them into
/// a 2048x2048 RGBA8 texture (growing to 4096x4096 on demand),
/// and provides UV coordinates for each cached glyph.
public final class GlyphAtlas: @unchecked Sendable {
    // MARK: - Types

    /// UV coordinates and metrics for a cached glyph.
    public struct GlyphInfo {
        public let uvX: Float
        public let uvY: Float
        public let uvWidth: Float
        public let uvHeight: Float
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let bearingX: Float
        public let bearingY: Float
        public let advance: Float
    }

    /// Key for glyph cache lookup.
    private struct GlyphKey: Hashable {
        let glyph: CGGlyph
        let fontName: String
        let fontSize: CGFloat
    }

    // MARK: - Properties

    private let device: MTLDevice
    private(set) public var texture: MTLTexture?
    private var textureWidth: Int
    private var textureHeight: Int
    private let maxTextureSize = 4096

    /// Glyph cache: key → (info, lastAccessTime)
    private var cache: [GlyphKey: (info: GlyphInfo, accessOrder: UInt64)] = [:]
    private var accessCounter: UInt64 = 0

    /// Packing state: simple row-based packer
    private var currentRowX: Int = 0
    private var currentRowY: Int = 0
    private var currentRowHeight: Int = 0

    // MARK: - Init

    public init(device: MTLDevice, initialSize: Int = 2048) throws {
        self.device = device
        self.textureWidth = initialSize
        self.textureHeight = initialSize

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: initialSize,
            height: initialSize,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .managed

        guard let tex = device.makeTexture(descriptor: descriptor) else {
            throw RenderingError.pipelineCreationFailed("Failed to create glyph atlas texture")
        }
        self.texture = tex

        logger.info("GlyphAtlas created: \(initialSize)x\(initialSize)")
    }

    // MARK: - Pre-warm

    /// Pre-warm the atlas with printable ASCII glyphs for the given font.
    public func prewarmASCII(font: CTFont) {
        var glyphs = [CGGlyph](repeating: 0, count: 95) // ASCII 32-126
        var chars = [UniChar](repeating: 0, count: 95)
        for i in 0..<95 {
            chars[i] = UniChar(32 + i)
        }
        CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 95)

        let fontName = CTFontCopyPostScriptName(font) as String
        let fontSize = CTFontGetSize(font)

        for (i, glyph) in glyphs.enumerated() where glyph != 0 {
            let key = GlyphKey(glyph: glyph, fontName: fontName, fontSize: fontSize)
            if cache[key] == nil {
                _ = rasterizeAndCache(glyph: glyph, font: font, key: key)
            }
        }

        logger.debug("Pre-warmed \(self.cache.count) ASCII glyphs")
    }

    // MARK: - Lookup / Rasterize

    /// Get glyph info, rasterizing and caching if needed.
    public func glyphInfo(for glyph: CGGlyph, font: CTFont) -> GlyphInfo? {
        let fontName = CTFontCopyPostScriptName(font) as String
        let fontSize = CTFontGetSize(font)
        let key = GlyphKey(glyph: glyph, fontName: fontName, fontSize: fontSize)

        if var entry = cache[key] {
            accessCounter += 1
            entry.accessOrder = accessCounter
            cache[key] = entry
            return entry.info
        }

        return rasterizeAndCache(glyph: glyph, font: font, key: key)
    }

    // MARK: - Rasterize

    private func rasterizeAndCache(glyph: CGGlyph, font: CTFont, key: GlyphKey) -> GlyphInfo? {
        // Get glyph bounding rect
        var boundingRect = CGRect.zero
        var glyphArray = [glyph]
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphArray, &boundingRect, 1)

        var advances = [CGSize.zero]
        CTFontGetAdvancesForGlyphs(font, .default, &glyphArray, &advances, 1)

        let padding = 2
        let pixelWidth = Int(ceil(boundingRect.width)) + padding * 2
        let pixelHeight = Int(ceil(boundingRect.height)) + padding * 2

        guard pixelWidth > 0 && pixelHeight > 0 else { return nil }

        // Check if we need to advance to next row or grow atlas
        if currentRowX + pixelWidth > textureWidth {
            currentRowY += currentRowHeight + 1
            currentRowX = 0
            currentRowHeight = 0
        }

        if currentRowY + pixelHeight > textureHeight {
            if textureWidth < maxTextureSize {
                growAtlas()
            } else {
                evictLRU(count: cache.count / 4)
            }
        }

        // Rasterize glyph to pixel buffer
        let bytesPerRow = pixelWidth * 4
        var pixelData = [UInt8](repeating: 0, count: pixelHeight * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsAntialiasing(true)

        let drawPoint = CGPoint(
            x: CGFloat(padding) - boundingRect.origin.x,
            y: CGFloat(padding) - boundingRect.origin.y
        )

        var position = drawPoint
        CTFontDrawGlyphs(font, &glyphArray, &position, 1, context)

        // Upload to atlas texture
        let region = MTLRegion(
            origin: MTLOrigin(x: currentRowX, y: currentRowY, z: 0),
            size: MTLSize(width: pixelWidth, height: pixelHeight, depth: 1)
        )

        texture?.replace(region: region, mipmapLevel: 0, withBytes: pixelData, bytesPerRow: bytesPerRow)

        let info = GlyphInfo(
            uvX: Float(currentRowX) / Float(textureWidth),
            uvY: Float(currentRowY) / Float(textureHeight),
            uvWidth: Float(pixelWidth) / Float(textureWidth),
            uvHeight: Float(pixelHeight) / Float(textureHeight),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            bearingX: Float(boundingRect.origin.x) - Float(padding),
            bearingY: Float(boundingRect.origin.y) - Float(padding),
            advance: Float(advances[0].width)
        )

        accessCounter += 1
        cache[key] = (info: info, accessOrder: accessCounter)

        currentRowX += pixelWidth + 1
        currentRowHeight = max(currentRowHeight, pixelHeight)

        return info
    }

    // MARK: - Atlas Growth

    private func growAtlas() {
        let newSize = min(textureWidth * 2, maxTextureSize)
        logger.info("Growing glyph atlas from \(self.textureWidth)x\(self.textureHeight) to \(newSize)x\(newSize)")

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: newSize,
            height: newSize,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .managed

        guard let newTexture = device.makeTexture(descriptor: descriptor) else {
            logger.error("Failed to create larger atlas texture")
            return
        }

        // Copy old texture content
        if let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer(),
           let blitEncoder = commandBuffer.makeBlitCommandEncoder(),
           let oldTexture = texture {
            blitEncoder.copy(
                from: oldTexture,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: textureWidth, height: textureHeight, depth: 1),
                to: newTexture,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        // Update UVs for all cached glyphs
        let scaleX = Float(textureWidth) / Float(newSize)
        let scaleY = Float(textureHeight) / Float(newSize)
        for (key, var entry) in cache {
            let old = entry.info
            entry.info = GlyphInfo(
                uvX: old.uvX * scaleX,
                uvY: old.uvY * scaleY,
                uvWidth: old.uvWidth * scaleX,
                uvHeight: old.uvHeight * scaleY,
                pixelWidth: old.pixelWidth,
                pixelHeight: old.pixelHeight,
                bearingX: old.bearingX,
                bearingY: old.bearingY,
                advance: old.advance
            )
            cache[key] = entry
        }

        textureWidth = newSize
        textureHeight = newSize
        texture = newTexture
    }

    // MARK: - LRU Eviction

    private func evictLRU(count: Int) {
        let sorted = cache.sorted { $0.value.accessOrder < $1.value.accessOrder }
        let toEvict = sorted.prefix(count)
        for (key, _) in toEvict {
            cache.removeValue(forKey: key)
        }
        logger.debug("Evicted \(count) LRU glyph entries")

        // Reset packing state — requires full rebuild
        rebuildAtlas()
    }

    private func rebuildAtlas() {
        // Clear texture and re-pack all remaining glyphs
        currentRowX = 0
        currentRowY = 0
        currentRowHeight = 0

        // For simplicity, clear the atlas and let glyphs be re-rasterized on demand
        let clearData = [UInt8](repeating: 0, count: textureWidth * textureHeight * 4)
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: textureWidth, height: textureHeight, depth: 1)
        )
        texture?.replace(region: region, mipmapLevel: 0, withBytes: clearData, bytesPerRow: textureWidth * 4)
        cache.removeAll()
    }

    // MARK: - Invalidation

    /// Invalidate all cached glyphs for a specific font (e.g., on font change).
    public func invalidateCache(for fontName: String) {
        cache = cache.filter { $0.key.fontName != fontName }
        rebuildAtlas()
        logger.info("Invalidated glyph cache for font: \(fontName)")
    }

    /// The number of cached glyphs.
    public var cachedGlyphCount: Int { cache.count }
}
