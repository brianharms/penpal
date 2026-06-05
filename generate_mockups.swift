#!/usr/bin/env swift

import Cocoa
import CoreGraphics
import CoreText

// iPad-like dimensions (scaled down for preview)
let width = 1024
let height = 1366
let cgSize = CGSize(width: width, height: height)
let colorSpace = CGColorSpaceCreateDeviceRGB()

func createContext() -> CGContext {
    let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func savePNG(_ ctx: CGContext, to path: String) {
    guard let cgImage = ctx.makeImage() else { return }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Saved: \(path)")
}

func drawText(_ ctx: CGContext, text: String, x: CGFloat, y: CGFloat, fontSize: CGFloat,
              color: CGColor, weight: NSFont.Weight = .regular, maxWidth: CGFloat? = nil) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color)!
    ]
    let attrString = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)

    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = CGPoint(x: x, y: CGFloat(height) - y - fontSize)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func drawRoundedRect(_ ctx: CGContext, rect: CGRect, radius: CGFloat, fill: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
}

func drawRoundedRectStroke(_ ctx: CGContext, rect: CGRect, radius: CGFloat, stroke: CGColor, lineWidth: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(stroke)
    ctx.setLineWidth(lineWidth)
    ctx.strokePath()
}

func drawNotebookCard(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, name: String,
                       date: String, hasContent: Bool, thumbnailStyle: Int = 0) {
    let thumbH: CGFloat = 160
    let thumbRect = CGRect(x: x, y: y, width: w, height: thumbH)

    // Thumbnail background
    drawRoundedRect(ctx, rect: thumbRect, radius: 16,
                    fill: CGColor(red: 1, green: 1, blue: 1, alpha: 0.05))

    if hasContent {
        // Fake handwriting scribbles in thumbnail
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.4))
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)

        // A few wavy lines to simulate handwriting
        let lineY1 = y + 40
        let lineY2 = y + 65
        let lineY3 = y + 90
        let margin: CGFloat = 20

        for (i, ly) in [lineY1, lineY2, lineY3].enumerated() {
            ctx.move(to: CGPoint(x: x + margin, y: ly))
            let endX = x + w - margin - CGFloat(i) * 30
            for px in stride(from: x + margin, through: endX, by: 4) {
                let wave = sin((px - x) * 0.08) * 2
                ctx.addLine(to: CGPoint(x: px, y: ly + wave))
            }
            ctx.strokePath()
        }

        // Yellow response line
        ctx.setStrokeColor(CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 0.5))
        ctx.move(to: CGPoint(x: x + margin, y: y + 120))
        for px in stride(from: x + margin, through: x + w - margin - 40, by: 4) {
            let wave = sin((px - x) * 0.1) * 1.5
            ctx.addLine(to: CGPoint(x: px, y: y + 120 + wave))
        }
        ctx.strokePath()
    } else {
        // Empty doc icon
        let iconSize: CGFloat = 40
        let iconX = x + (w - iconSize) / 2
        let iconY = y + (thumbH - iconSize) / 2
        drawRoundedRect(ctx, rect: CGRect(x: iconX, y: iconY, width: iconSize * 0.7, height: iconSize),
                        radius: 4, fill: CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
        // Fold corner
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.1))
        ctx.fill(CGRect(x: iconX + iconSize * 0.5, y: iconY, width: iconSize * 0.2, height: iconSize * 0.25))
    }

    // Name
    drawText(ctx, text: name, x: x, y: y + thumbH + 12, fontSize: 16,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), weight: .medium)

    // Date
    drawText(ctx, text: date, x: x, y: y + thumbH + 34, fontSize: 12,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
}

func drawNewNotebookCard(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat) {
    let thumbH: CGFloat = 160
    let thumbRect = CGRect(x: x, y: y, width: w, height: thumbH)

    drawRoundedRect(ctx, rect: thumbRect, radius: 16,
                    fill: CGColor(red: 1, green: 1, blue: 1, alpha: 0.1))

    // Plus icon
    let cx = x + w / 2
    let cy = y + thumbH / 2
    let armLen: CGFloat = 25
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: cx - armLen, y: cy))
    ctx.addLine(to: CGPoint(x: cx + armLen, y: cy))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: cx, y: cy - armLen))
    ctx.addLine(to: CGPoint(x: cx, y: cy + armLen))
    ctx.strokePath()

    drawText(ctx, text: "New Notebook", x: x + (w - 120) / 2, y: y + thumbH + 12, fontSize: 15,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
}

// ============================================================
// OPTION A: Current implementation — pure black, large title
// ============================================================
do {
    let ctx = createContext()

    // Pure black background
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: cgSize))

    // Large title
    drawText(ctx, text: "Notebooks", x: 30, y: 70, fontSize: 42,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), weight: .bold)

    // Grid of cards
    let cardW: CGFloat = 220
    let spacing: CGFloat = 24
    let startX: CGFloat = 30
    let startY: CGFloat = 150

    drawNewNotebookCard(ctx, x: startX, y: startY, w: cardW)
    drawNotebookCard(ctx, x: startX + cardW + spacing, y: startY, w: cardW,
                     name: "Physics Notes", date: "2 min ago", hasContent: true)
    drawNotebookCard(ctx, x: startX + (cardW + spacing) * 2, y: startY, w: cardW,
                     name: "Brainstorm", date: "1 hr ago", hasContent: true)
    drawNotebookCard(ctx, x: startX + (cardW + spacing) * 3, y: startY, w: cardW,
                     name: "Untitled", date: "Yesterday", hasContent: false)

    // Second row
    drawNotebookCard(ctx, x: startX, y: startY + 230, w: cardW,
                     name: "Meeting Notes", date: "3 days ago", hasContent: true)
    drawNotebookCard(ctx, x: startX + cardW + spacing, y: startY + 230, w: cardW,
                     name: "Sketch Ideas", date: "Last week", hasContent: true)

    // Label
    drawText(ctx, text: "A — Pure black, bold title", x: 30, y: CGFloat(height) - 40, fontSize: 18,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.4), weight: .medium)

    savePNG(ctx, to: "mockup_A_current.png")
}

// ============================================================
// OPTION B: Subtle gradient background, centered title with app icon feel
// ============================================================
do {
    let ctx = createContext()

    // Dark gradient background (very subtle, near-black to slightly lighter)
    let gradColors: [CGFloat] = [
        0.06, 0.06, 0.08, 1.0,  // top: very dark blue-grey
        0.0, 0.0, 0.0, 1.0,     // bottom: pure black
    ]
    let gradLocs: [CGFloat] = [0.0, 1.0]
    if let grad = CGGradient(colorSpace: colorSpace, colorComponents: gradColors,
                              locations: gradLocs, count: 2) {
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: CGFloat(height)),
                               options: [])
    }

    // Centered layout
    let titleX: CGFloat = CGFloat(width) / 2 - 100

    // Small pen nib icon above title
    let nibCX = CGFloat(width) / 2
    let nibTop: CGFloat = 55
    let nibH: CGFloat = 50
    let nibW: CGFloat = 16
    let nibPath = CGMutablePath()
    nibPath.move(to: CGPoint(x: nibCX - nibW/2, y: nibTop))
    nibPath.addLine(to: CGPoint(x: nibCX, y: nibTop + nibH))
    nibPath.addLine(to: CGPoint(x: nibCX + nibW/2, y: nibTop))
    nibPath.addCurve(to: CGPoint(x: nibCX - nibW/2, y: nibTop),
                      control1: CGPoint(x: nibCX + 4, y: nibTop - 5),
                      control2: CGPoint(x: nibCX - 4, y: nibTop - 5))
    nibPath.closeSubpath()
    ctx.addPath(nibPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
    ctx.fillPath()

    // Yellow dot at nib tip
    ctx.addEllipse(in: CGRect(x: nibCX - 3, y: nibTop + nibH + 2, width: 6, height: 6))
    ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.6))
    ctx.fillPath()

    // Title
    drawText(ctx, text: "Notebooks", x: titleX, y: 120, fontSize: 36,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9), weight: .semibold)

    // Thin separator line
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: 30, y: 175))
    ctx.addLine(to: CGPoint(x: CGFloat(width) - 30, y: 175))
    ctx.strokePath()

    // Grid of cards
    let cardW: CGFloat = 220
    let spacing: CGFloat = 24
    let startX: CGFloat = 30
    let startY: CGFloat = 200

    drawNewNotebookCard(ctx, x: startX, y: startY, w: cardW)
    drawNotebookCard(ctx, x: startX + cardW + spacing, y: startY, w: cardW,
                     name: "Physics Notes", date: "2 min ago", hasContent: true)
    drawNotebookCard(ctx, x: startX + (cardW + spacing) * 2, y: startY, w: cardW,
                     name: "Brainstorm", date: "1 hr ago", hasContent: true)
    drawNotebookCard(ctx, x: startX + (cardW + spacing) * 3, y: startY, w: cardW,
                     name: "Untitled", date: "Yesterday", hasContent: false)

    drawNotebookCard(ctx, x: startX, y: startY + 230, w: cardW,
                     name: "Meeting Notes", date: "3 days ago", hasContent: true)
    drawNotebookCard(ctx, x: startX + cardW + spacing, y: startY + 230, w: cardW,
                     name: "Sketch Ideas", date: "Last week", hasContent: true)

    drawText(ctx, text: "B — Subtle gradient, centered with nib icon", x: 30, y: CGFloat(height) - 40,
             fontSize: 18, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.4), weight: .medium)

    savePNG(ctx, to: "mockup_B_gradient.png")
}

// ============================================================
// OPTION C: Warm accent — yellow glow accent, left-aligned
// ============================================================
do {
    let ctx = createContext()

    // Pure black background
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: cgSize))

    // Subtle warm glow in top-left corner
    let glowColors: [CGFloat] = [
        1.0, 0.85, 0.2, 0.06,
        1.0, 0.85, 0.2, 0.0,
    ]
    let glowLocs: [CGFloat] = [0.0, 1.0]
    if let grad = CGGradient(colorSpace: colorSpace, colorComponents: glowColors,
                              locations: glowLocs, count: 2) {
        ctx.drawRadialGradient(grad, startCenter: CGPoint(x: 0, y: 0), startRadius: 0,
                               endCenter: CGPoint(x: 0, y: 0), endRadius: 500, options: [])
    }

    // "rite" small app name
    drawText(ctx, text: "rite", x: 30, y: 55, fontSize: 16,
             color: CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.7), weight: .medium)

    // Large title
    drawText(ctx, text: "Notebooks", x: 30, y: 80, fontSize: 42,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), weight: .bold)

    // Grid of cards with slightly warmer card backgrounds
    let cardW: CGFloat = 220
    let spacing: CGFloat = 24
    let startX: CGFloat = 30
    let startY: CGFloat = 160

    // Custom card with warm border
    func drawWarmCard(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat,
                      name: String, date: String, hasContent: Bool) {
        let thumbH: CGFloat = 160
        let thumbRect = CGRect(x: x, y: y, width: w, height: thumbH)

        drawRoundedRect(ctx, rect: thumbRect, radius: 16,
                        fill: CGColor(red: 1, green: 1, blue: 1, alpha: 0.04))
        drawRoundedRectStroke(ctx, rect: thumbRect, radius: 16,
                              stroke: CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.08),
                              lineWidth: 1)

        if hasContent {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            let lineY1 = y + 40; let lineY2 = y + 65; let lineY3 = y + 90
            let margin: CGFloat = 20
            for (i, ly) in [lineY1, lineY2, lineY3].enumerated() {
                ctx.move(to: CGPoint(x: x + margin, y: ly))
                let endX = x + w - margin - CGFloat(i) * 30
                for px in stride(from: x + margin, through: endX, by: 4) {
                    let wave = sin((px - x) * 0.08) * 2
                    ctx.addLine(to: CGPoint(x: px, y: ly + wave))
                }
                ctx.strokePath()
            }
            ctx.setStrokeColor(CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 0.5))
            ctx.move(to: CGPoint(x: x + margin, y: y + 120))
            for px in stride(from: x + margin, through: x + w - margin - 40, by: 4) {
                let wave = sin((px - x) * 0.1) * 1.5
                ctx.addLine(to: CGPoint(x: px, y: y + 120 + wave))
            }
            ctx.strokePath()
        }

        drawText(ctx, text: name, x: x, y: y + thumbH + 12, fontSize: 16,
                 color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), weight: .medium)
        drawText(ctx, text: date, x: x, y: y + thumbH + 34, fontSize: 12,
                 color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
    }

    drawNewNotebookCard(ctx, x: startX, y: startY, w: cardW)
    drawWarmCard(ctx, x: startX + cardW + spacing, y: startY, w: cardW,
                 name: "Physics Notes", date: "2 min ago", hasContent: true)
    drawWarmCard(ctx, x: startX + (cardW + spacing) * 2, y: startY, w: cardW,
                 name: "Brainstorm", date: "1 hr ago", hasContent: true)
    drawWarmCard(ctx, x: startX + (cardW + spacing) * 3, y: startY, w: cardW,
                 name: "Untitled", date: "Yesterday", hasContent: false)

    drawWarmCard(ctx, x: startX, y: startY + 230, w: cardW,
                 name: "Meeting Notes", date: "3 days ago", hasContent: true)
    drawWarmCard(ctx, x: startX + cardW + spacing, y: startY + 230, w: cardW,
                 name: "Sketch Ideas", date: "Last week", hasContent: true)

    drawText(ctx, text: "C — Warm yellow accent glow, \"rite\" branding", x: 30, y: CGFloat(height) - 40,
             fontSize: 18, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.4), weight: .medium)

    savePNG(ctx, to: "mockup_C_warm.png")
}

print("\nDone! Open the mockup_*.png files to compare.")
