#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let iconRect = CGRect(x: 0, y: 0, width: size, height: size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fprint("Failed to create CGContext")
    exit(1)
}

func fprint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

// --- Background: rounded superellipse with dark base ---
let cornerRadius: CGFloat = 224 // macOS icon radius ratio
let bgPath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

// Dark gradient background: slightly lighter at top for depth
let bgColors = [
    CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1),  // top
    CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1),  // bottom
]
let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])

// --- Radial glow behind the hammer (warm amber bloom) ---
let glowColors = [
    CGColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.35),  // center amber
    CGColor(red: 1.0, green: 0.42, blue: 0.17, alpha: 0.15),   // mid orange
    CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.0),   // fade to transparent
]
let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0, 0.4, 1.0])!
ctx.drawRadialGradient(
    glowGrad,
    startCenter: CGPoint(x: 512, y: 540),
    startRadius: 0,
    endCenter: CGPoint(x: 512, y: 540),
    endRadius: 380,
    options: []
)

// --- Helper: draw text centered ---
func drawText(_ text: String, font: NSFont, color: NSColor, at point: CGPoint, context: CGContext) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    let attrStr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attrStr)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    context.saveGState()
    // Flip for text rendering
    context.textMatrix = CGAffineTransform(scaleX: 1, y: 1)
    context.textPosition = CGPoint(
        x: point.x - bounds.width / 2,
        y: point.y - bounds.height / 2
    )
    CTLineDraw(line, context)
    context.restoreGState()
}

// --- Angle brackets: </> in warm amber behind the hammer ---
let bracketFont = NSFont.systemFont(ofSize: 320, weight: .ultraLight)
let bracketColor = NSColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.12)
drawText("</>", font: bracketFont, color: bracketColor, at: CGPoint(x: 512, y: 460), context: ctx)

// --- Hammer symbol using SF Symbol rendering ---
// Draw a stylized hammer shape manually for maximum control
ctx.saveGState()

// Hammer head (rotated rectangle with gradient)
let hammerAmber = CGColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)
let hammerOrange = CGColor(red: 1.0, green: 0.42, blue: 0.17, alpha: 1)
let hammerGrad = CGGradient(colorsSpace: colorSpace, colors: [hammerAmber, hammerOrange] as CFArray, locations: [0, 1])!

ctx.saveGState()
ctx.translateBy(x: 512, y: 560)
ctx.rotate(by: -0.6) // tilt the hammer

// Hammer head
let headRect = CGRect(x: -120, y: 20, width: 240, height: 80)
let headPath = CGPath(roundedRect: headRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
ctx.addPath(headPath)
ctx.clip()
ctx.drawLinearGradient(hammerGrad, start: CGPoint(x: -120, y: 60), end: CGPoint(x: 120, y: 60), options: [])
ctx.resetClip()
ctx.restoreGState()

// Hammer handle
ctx.saveGState()
ctx.translateBy(x: 512, y: 560)
ctx.rotate(by: -0.6)

let handleColor = CGColor(red: 0.65, green: 0.45, blue: 0.25, alpha: 1)
let handleDarkColor = CGColor(red: 0.45, green: 0.30, blue: 0.15, alpha: 1)
let handleGrad = CGGradient(colorsSpace: colorSpace, colors: [handleColor, handleDarkColor] as CFArray, locations: [0, 1])!

let handleRect = CGRect(x: -14, y: -200, width: 28, height: 230)
let handlePath = CGPath(roundedRect: handleRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
ctx.addPath(handlePath)
ctx.clip()
ctx.drawLinearGradient(handleGrad, start: CGPoint(x: 0, y: 30), end: CGPoint(x: 0, y: -200), options: [])
ctx.resetClip()
ctx.restoreGState()

// Re-draw hammer head on top of handle
ctx.saveGState()
ctx.translateBy(x: 512, y: 560)
ctx.rotate(by: -0.6)
ctx.addPath(headPath)
ctx.clip()
ctx.drawLinearGradient(hammerGrad, start: CGPoint(x: -120, y: 60), end: CGPoint(x: 120, y: 60), options: [])
ctx.restoreGState()

// --- Spark particles around the hammer ---
let sparkColor = CGColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 0.9)
let sparkPositions: [(CGFloat, CGFloat, CGFloat)] = [
    (380, 680, 6),
    (420, 720, 4),
    (340, 650, 3),
    (640, 680, 5),
    (600, 720, 3),
    (660, 650, 4),
    (450, 750, 3),
    (570, 740, 4),
    (360, 710, 2.5),
    (650, 710, 3),
]

for (x, y, r) in sparkPositions {
    ctx.setFillColor(sparkColor)
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    // Add glow around spark
    let sparkGlowColors = [
        CGColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 0.4),
        CGColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 0.0),
    ]
    let sparkGlow = CGGradient(colorsSpace: colorSpace, colors: sparkGlowColors as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sparkGlow, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r * 4, options: [])
}

// --- "FORGE" text at bottom ---
let forgeFont = NSFont.systemFont(ofSize: 88, weight: .bold)
let forgeColor = NSColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.9)
drawText("FORGE", font: forgeFont, color: forgeColor, at: CGPoint(x: 512, y: 200), context: ctx)

// --- Subtle bottom highlight line ---
ctx.setStrokeColor(CGColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 0.15))
ctx.setLineWidth(2)
ctx.move(to: CGPoint(x: 300, y: 155))
ctx.addLine(to: CGPoint(x: 724, y: 155))
ctx.strokePath()

// --- Generate image ---
guard let cgImage = ctx.makeImage() else {
    fprint("Failed to create image")
    exit(1)
}

let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
guard let tiffData = nsImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fprint("Failed to create PNG")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let url = URL(fileURLWithPath: outputPath)
try! pngData.write(to: url)
print("Icon saved to \(outputPath)")
