import PencilKit
import UIKit

class HandwritingGenerator {
    private let fontSize: CGFloat
    private let inkColor: UIColor
    private let strokeWidth: CGFloat
    private let maxWidth: CGFloat
    private let baselinePath: [CGPoint]  // Path to follow for text baseline
    private let style: HandwritingStyle
    private let occupiedRegions: [OccupiedRegion]  // Content regions to avoid

    // Baseline drift for organic line feel
    private var baselineDrift: CGFloat = 0
    private var driftVelocity: CGFloat = 0
    private var globalSlant: CGFloat = 0

    // Cached line offsets adjusted for collision avoidance
    private var computedLineOffsets: [CGFloat] = [0]

    // Style-based parameters (computed once at init)
    private let baselineWobble: CGFloat
    private let letterSizeVariance: CGFloat
    private let slantRange: ClosedRange<CGFloat>
    private let effectiveStrokeWidth: CGFloat
    private let spacingMultiplier: CGFloat

    init(fontSize: CGFloat, inkColor: UIColor = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0), strokeWidth: CGFloat = 7.5, maxWidth: CGFloat = 800, baselinePath: [CGPoint] = [], style: HandwritingStyle = .friendly, occupiedRegions: [OccupiedRegion] = []) {
        self.fontSize = fontSize
        self.inkColor = inkColor
        self.strokeWidth = strokeWidth
        self.maxWidth = maxWidth
        self.baselinePath = baselinePath
        self.style = style
        self.occupiedRegions = occupiedRegions

        // Apply style parameters (wobble reduced 30% for cleaner look)
        let params = style.parameters
        self.baselineWobble = params.baselineWobble * 0.7
        self.letterSizeVariance = params.letterSizeVariance
        self.slantRange = params.slantRange
        self.effectiveStrokeWidth = strokeWidth * params.strokeWidthMultiplier
        self.spacingMultiplier = params.spacingMultiplier
    }

    func generateStrokes(for text: String, startingAt origin: CGPoint) -> [PKStroke] {
        var strokes: [PKStroke] = []
        var currentX = origin.x
        let originX = origin.x

        let charWidth = fontSize * 0.55
        let charSpacing = fontSize * 0.08 * spacingMultiplier
        let spaceWidth = charWidth * 0.45
        let lineHeight = fontSize * 1.5

        // Reset computed line offsets for this generation (line 0 starts at 0, collision checked below)
        computedLineOffsets = []

        // Initialize random variation for this text block (scaled by style)
        baselineDrift = 0
        driftVelocity = CGFloat.random(in: -0.2...0.2) * (baselineWobble / 0.08)
        globalSlant = CGFloat.random(in: slantRange)

        // Split into words for proper wrapping
        let words = text.components(separatedBy: " ")
        var charIndex = 0
        var currentLineNumber = 0  // Track which line we're on for vertical offset

        for (wordIndex, word) in words.enumerated() {
            let lines = word.components(separatedBy: "\n")

            for (lineIndex, line) in lines.enumerated() {
                if lineIndex > 0 {
                    currentX = originX
                    currentLineNumber += 1
                    baselineDrift = 0
                    driftVelocity = CGFloat.random(in: -0.2...0.2)
                }

                // Calculate word width
                let wordWidth = CGFloat(line.count) * (charWidth + charSpacing)

                // Wrap before word if needed
                if currentX > originX && currentX + wordWidth > originX + maxWidth {
                    currentX = originX
                    currentLineNumber += 1
                    baselineDrift = 0
                    driftVelocity = CGFloat.random(in: -0.2...0.2)
                }

                // Draw each character
                for char in line {
                    // Update baseline drift for organic line variation
                    updateBaselineDrift()

                    // Get Y position from baseline path, plus collision-aware line offset
                    let lineOffset = collisionAwareLineOffset(
                        for: currentLineNumber,
                        nominalLineHeight: lineHeight,
                        originY: origin.y,
                        originX: originX
                    )
                    let pathY = getYForX(currentX, defaultY: origin.y) + lineOffset

                    // Get stroke paths for this character
                    let charStrokes = SingleLineFont.strokes(for: char, variation: charIndex)

                    for path in charStrokes {
                        guard path.count >= 2 else { continue }

                        var strokePoints: [PKStrokePoint] = []
                        let startTime = Date()

                        // Per-character size variation based on style
                        let sizeVariation = 1.0 + CGFloat.random(in: -letterSizeVariance...letterSizeVariance)
                        let effectiveCharWidth = charWidth * sizeVariation

                        for (pointIndex, point) in path.enumerated() {
                            // Apply character position, baseline from path, drift, and slant
                            let slantOffset = point.y * fontSize * globalSlant
                            let x = currentX + point.x * effectiveCharWidth + slantOffset
                            let y = pathY + point.y * fontSize * sizeVariation + baselineDrift

                            // Add micro-variation to each point (scaled by style wobble)
                            let microVar = CGFloat(sin(Double(charIndex * 7 + pointIndex) * 0.9)) * effectiveStrokeWidth * 0.15 * (baselineWobble / 0.08)

                            // Fountain pen effect for riddle style: thick downstrokes, thin upstrokes
                            let force: CGFloat
                            let azimuth: CGFloat
                            let altitude: CGFloat
                            if style == .riddle, let prev = strokePoints.last {
                                let dy = y - prev.location.y
                                let normalized = max(-1.0, min(1.0, dy / 3.0))
                                force = 0.5 + normalized * 0.4   // 0.1 (upstroke) to 0.9 (downstroke)
                                azimuth = CGFloat.pi * 0.25      // Nib angle ~45°
                                altitude = CGFloat.pi * 0.5      // Nib flat to paper for max width variation
                            } else {
                                force = 0.5
                                azimuth = 0
                                altitude = .pi / 2
                            }

                            let strokePoint = PKStrokePoint(
                                location: CGPoint(x: x + microVar, y: y),
                                timeOffset: TimeInterval(pointIndex) * 0.015,
                                size: CGSize(width: effectiveStrokeWidth, height: effectiveStrokeWidth),
                                opacity: 1.0,
                                force: force,
                                azimuth: azimuth,
                                altitude: altitude
                            )
                            strokePoints.append(strokePoint)
                        }

                        if strokePoints.count >= 2 {
                            let strokePath = PKStrokePath(controlPoints: strokePoints, creationDate: startTime)
                            let inkType: PKInk.InkType = style == .riddle ? .fountainPen : .pen
                            let ink = PKInk(inkType, color: inkColor)
                            let stroke = PKStroke(ink: ink, path: strokePath)
                            strokes.append(stroke)
                        }
                    }

                    currentX += charWidth + charSpacing
                    charIndex += 1
                }
            }

            // Add space after word
            if wordIndex < words.count - 1 {
                currentX += spaceWidth
            }
        }

        return strokes
    }

    /// Compute collision-aware Y offset for a given line number
    /// Builds offsets lazily — each line starts one lineHeight below the previous,
    /// then gets pushed down if it would collide with an occupied region
    private func collisionAwareLineOffset(
        for lineNumber: Int,
        nominalLineHeight: CGFloat,
        originY: CGFloat,
        originX: CGFloat
    ) -> CGFloat {
        // Build up offsets lazily as we encounter new lines
        while computedLineOffsets.count <= lineNumber {
            let prevOffset = computedLineOffsets.last ?? 0
            var nextOffset = computedLineOffsets.isEmpty ? 0 : prevOffset + nominalLineHeight

            // Check if this proposed line collides with any occupied region
            let baseY = baselinePath.first?.y ?? originY
            let lineY = baseY + nextOffset
            let lineTop = lineY - fontSize * 0.3
            let lineBottom = lineY + fontSize * 1.2

            for region in occupiedRegions {
                // Quick bounding box rejection
                guard originX + maxWidth > region.bounds.minX && originX < region.bounds.maxX else { continue }

                // Check if the proposed line rect intersects this hull
                let lineRect = CGRect(x: originX, y: lineTop, width: maxWidth, height: lineBottom - lineTop)
                if region.intersectsRect(lineRect) {
                    // Find the actual max Y of the hull across our X range
                    var hullMaxY = region.bounds.maxY  // fallback
                    let sampleCount = 5
                    let step = maxWidth / CGFloat(sampleCount)
                    for s in 0...sampleCount {
                        let sampleX = originX + CGFloat(s) * step
                        if let y = region.maxYAtX(sampleX) {
                            hullMaxY = max(hullMaxY, y)
                        }
                    }
                    let needed = hullMaxY + fontSize * 0.5 - baseY + fontSize * 0.3
                    if needed > nextOffset {
                        nextOffset = needed
                    }
                }
            }

            computedLineOffsets.append(nextOffset)
        }
        return computedLineOffsets[lineNumber]
    }

    /// Get the Y coordinate for a given X position along the baseline path
    /// Uses linear interpolation between path points
    private func getYForX(_ x: CGFloat, defaultY: CGFloat) -> CGFloat {
        guard baselinePath.count >= 2 else { return defaultY }

        // Find the two points that bracket this x position
        var leftPoint: CGPoint?
        var rightPoint: CGPoint?

        for i in 0..<baselinePath.count {
            let point = baselinePath[i]
            if point.x <= x {
                leftPoint = point
            }
            if point.x >= x && rightPoint == nil {
                rightPoint = point
            }
        }

        // Handle edge cases
        if leftPoint == nil {
            // x is before the first point, use first point's y
            return baselinePath.first?.y ?? defaultY
        }
        if rightPoint == nil {
            // x is after the last point, use last point's y
            return baselinePath.last?.y ?? defaultY
        }

        guard let left = leftPoint, let right = rightPoint else {
            return defaultY
        }

        // Same point (avoid division by zero)
        if left.x == right.x {
            return left.y
        }

        // Linear interpolation
        let t = (x - left.x) / (right.x - left.x)
        return left.y + t * (right.y - left.y)
    }

    private func updateBaselineDrift() {
        // Random walk for organic baseline movement (scaled by style)
        let driftSpeed = baselineWobble / 0.08  // Normalize to friendly style
        driftVelocity += CGFloat.random(in: -0.08...0.08) * driftSpeed
        driftVelocity = max(-0.4 * driftSpeed, min(0.4 * driftSpeed, driftVelocity))

        baselineDrift += driftVelocity * fontSize * 0.025
        // Allow more drift but gently pull back toward center
        let pullBack = -baselineDrift * 0.02
        baselineDrift += pullBack

        // Max drift scaled by style
        let maxDrift = fontSize * baselineWobble * 1.5
        baselineDrift = max(-maxDrift, min(maxDrift, baselineDrift))
    }
}
