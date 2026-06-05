#!/usr/bin/env swift

import Cocoa
import CoreGraphics

let size = 1024
let cgSize = CGSize(width: size, height: size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create CGContext")
}

// CG origin: bottom-left
// Black background
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(origin: .zero, size: cgSize))

// === CONCEPT ===
// Two chat bubbles overlapping slightly — one from the left (user/white),
// one from the right (AI/warm). Each has a small triangular tail
// suggesting speech direction. Minimal, iconic, reads as "conversation".

let bubbleCornerRadius: CGFloat = 36

// --- Left bubble (user) — white, positioned left-of-center, slightly higher ---
let leftBubble = CGRect(x: 160, y: 390, width: 380, height: 280)

// Rounded rect
let leftPath = CGPath(roundedRect: leftBubble, cornerWidth: bubbleCornerRadius, cornerHeight: bubbleCornerRadius, transform: nil)
ctx.addPath(leftPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()

// Small tail on bottom-left
let leftTail = CGMutablePath()
leftTail.move(to: CGPoint(x: 220, y: 390))
leftTail.addLine(to: CGPoint(x: 190, y: 340))
leftTail.addLine(to: CGPoint(x: 280, y: 390))
leftTail.closeSubpath()
ctx.addPath(leftTail)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()

// --- Right bubble (AI) — warm off-white/cream, positioned right-of-center, slightly lower ---
let rightBubble = CGRect(x: 484, y: 310, width: 380, height: 280)

let rightPath = CGPath(roundedRect: rightBubble, cornerWidth: bubbleCornerRadius, cornerHeight: bubbleCornerRadius, transform: nil)
ctx.addPath(rightPath)
// Warm cream/ivory color
ctx.setFillColor(CGColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 1))
ctx.fillPath()

// Small tail on bottom-right
let rightTail = CGMutablePath()
rightTail.move(to: CGPoint(x: 804, y: 310))
rightTail.addLine(to: CGPoint(x: 834, y: 260))
rightTail.addLine(to: CGPoint(x: 744, y: 310))
rightTail.closeSubpath()
ctx.addPath(rightTail)
ctx.setFillColor(CGColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 1))
ctx.fillPath()

// --- Pen stroke lines inside left bubble (suggesting handwriting) ---
ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.15))
ctx.setLineWidth(4)
ctx.setLineCap(.round)

let lineInset: CGFloat = 40
let lineY1: CGFloat = 590
let lineSpacing: CGFloat = 40
for i in 0..<4 {
    let y = lineY1 - CGFloat(i) * lineSpacing
    let startX = leftBubble.minX + lineInset
    // Vary line lengths for natural look
    let lengths: [CGFloat] = [280, 240, 300, 180]
    let endX = startX + lengths[i]
    let line = CGMutablePath()
    line.move(to: CGPoint(x: startX, y: y))
    line.addLine(to: CGPoint(x: endX, y: y))
    ctx.addPath(line)
    ctx.strokePath()
}

// --- Pen stroke lines inside right bubble (AI writing back) ---
ctx.setStrokeColor(CGColor(red: 0.4, green: 0.3, blue: 0.1, alpha: 0.18))

let rLineY1: CGFloat = 510
for i in 0..<4 {
    let y = rLineY1 - CGFloat(i) * lineSpacing
    let startX = rightBubble.minX + lineInset
    let lengths: [CGFloat] = [260, 300, 220, 280]
    let endX = startX + lengths[i]
    let line = CGMutablePath()
    line.move(to: CGPoint(x: startX, y: y))
    line.addLine(to: CGPoint(x: endX, y: y))
    ctx.addPath(line)
    ctx.strokePath()
}

// === GENERATE IMAGE ===
guard let cgImage = ctx.makeImage() else {
    fatalError("Failed to create CGImage")
}

let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
guard let tiffData = nsImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to convert to PNG")
}

let outputPath = "penpal/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(outputPath)

do {
    try pngData.write(to: outputURL)
    print("Icon saved to \(outputPath)")
} catch {
    fatalError("Failed to write PNG: \(error)")
}
