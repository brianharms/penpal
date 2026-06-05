import SwiftUI
import PencilKit

struct MagicGlowOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel

    // Glow color
    private let glowColor = Color(red: 0.5, green: 0.7, blue: 1.0)

    var body: some View {
        GeometryReader { geometry in
            // Only show glow during thinking phase, not while AI is writing
            if viewModel.processingState == .thinking, let canvasView = viewModel.canvasView {
                // 30fps for good balance of smoothness and performance
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let drawing = canvasView.drawing
                    let userStrokes = getRecentUserStrokes(drawing: drawing)

                    // Get content offset to convert from content coords to screen coords
                    let contentOffset = canvasView.contentOffset

                    // Glow cycle duration based on animation speed setting
                    // At 1.0x speed = 2.0 seconds, at 2.0x = 1.0 seconds, at 0.5x = 4.0 seconds
                    let cycleDuration = 2.0 / viewModel.glowAnimationSpeed
                    let elapsed = timeline.date.timeIntervalSince(viewModel.thinkingStartTime)
                    let cycleProgress = max(0, elapsed).truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

                    let fontSize = viewModel.estimatedUserFontSize

                    Canvas { context, size in
                        drawSequentialGlow(
                            context: context,
                            strokes: userStrokes,
                            progress: cycleProgress,
                            fontSize: fontSize,
                            contentOffset: contentOffset
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func getRecentUserStrokes(drawing: PKDrawing) -> [PKStroke] {
        let startIndex = viewModel.lastRespondedStrokeIndex
        let endIndex = viewModel.userStrokeCount

        guard startIndex < endIndex else { return [] }
        guard endIndex <= drawing.strokes.count else { return [] }

        return Array(drawing.strokes[startIndex..<endIndex])
    }

    /// Draw glow that travels sequentially across all strokes from start to end
    private func drawSequentialGlow(
        context: GraphicsContext,
        strokes: [PKStroke],
        progress: Double,
        fontSize: CGFloat,
        contentOffset: CGPoint
    ) {
        guard !strokes.isEmpty else { return }

        // Sort strokes by their starting x position (left to right reading order)
        let sortedStrokes = strokes.sorted { stroke1, stroke2 in
            let x1 = stroke1.path.first?.location.x ?? 0
            let x2 = stroke2.path.first?.location.x ?? 0
            return x1 < x2
        }

        // Calculate total length of all strokes
        var strokeInfos: [(path: Path, length: CGFloat, startOffset: CGFloat)] = []
        var totalLength: CGFloat = 0

        for stroke in sortedStrokes {
            let points = stroke.path
            guard points.count > 1 else { continue }

            // Build path from stroke points, converting from content to screen coordinates
            var path = Path()
            let firstPoint = CGPoint(
                x: points[0].location.x - contentOffset.x,
                y: points[0].location.y - contentOffset.y
            )
            path.move(to: firstPoint)

            var strokeLength: CGFloat = 0
            for i in 1..<points.count {
                let prevPoint = points[i-1].location
                let currPoint = points[i].location
                let dx = currPoint.x - prevPoint.x
                let dy = currPoint.y - prevPoint.y
                strokeLength += sqrt(dx*dx + dy*dy)

                let screenPoint = CGPoint(
                    x: currPoint.x - contentOffset.x,
                    y: currPoint.y - contentOffset.y
                )
                path.addLine(to: screenPoint)
            }

            strokeInfos.append((path: path, length: strokeLength, startOffset: totalLength))
            totalLength += strokeLength
        }

        guard totalLength > 0 else { return }

        // Glow covers 15% of total text length
        let glowLength = totalLength * 0.40  // 40% of text lit up at once
        let glowHalfLength = glowLength / 2

        // Calculate glow center position (travels from 0 to totalLength)
        let glowCenter = CGFloat(progress) * (totalLength + glowLength) - glowHalfLength

        // Draw glow on each stroke that overlaps with the glow region
        for info in strokeInfos {
            let strokeStart = info.startOffset
            let strokeEnd = info.startOffset + info.length

            // Check if glow overlaps this stroke
            let glowStart = glowCenter - glowHalfLength
            let glowEnd = glowCenter + glowHalfLength

            if glowEnd >= strokeStart && glowStart <= strokeEnd {
                // Calculate the portion of this stroke to highlight
                let overlapStart = max(glowStart, strokeStart)
                let overlapEnd = min(glowEnd, strokeEnd)

                // Convert to fraction within this stroke
                let strokeFracStart = (overlapStart - strokeStart) / info.length
                let strokeFracEnd = (overlapEnd - strokeStart) / info.length

                // Calculate fade based on distance from glow center
                let overlapCenter = (overlapStart + overlapEnd) / 2
                let distFromCenter = abs(overlapCenter - glowCenter)
                let fadeAmount = 1.0 - smoothstep(0, glowHalfLength, distFromCenter)

                drawGlowSegment(
                    context: context,
                    path: info.path,
                    startFrac: strokeFracStart,
                    endFrac: strokeFracEnd,
                    intensity: fadeAmount,
                    fontSize: fontSize
                )
            }
        }
    }

    private func drawGlowSegment(
        context: GraphicsContext,
        path: Path,
        startFrac: CGFloat,
        endFrac: CGFloat,
        intensity: Double,
        fontSize: CGFloat
    ) {
        guard let segmentPath = trimPath(path, from: startFrac, to: endFrac) else { return }

        let scale = max(fontSize / 24.0, 0.5)

        // Outer glow
        var outerContext = context
        outerContext.addFilter(.blur(radius: 12 * scale))
        outerContext.stroke(
            segmentPath,
            with: .color(glowColor.opacity(0.7 * intensity)),
            lineWidth: 14 * scale
        )

        // Middle glow
        var midContext = context
        midContext.addFilter(.blur(radius: 6 * scale))
        midContext.stroke(
            segmentPath,
            with: .color(glowColor.opacity(0.8 * intensity)),
            lineWidth: 8 * scale
        )

        // Bright core
        var coreContext = context
        coreContext.addFilter(.blur(radius: 2 * scale))
        coreContext.stroke(
            segmentPath,
            with: .color(Color.white.opacity(0.9 * intensity)),
            lineWidth: 3 * scale
        )
    }

    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func trimPath(_ path: Path, from startFraction: CGFloat, to endFraction: CGFloat) -> Path? {
        var result = Path()
        let pathElements = path.cgPath.getPathElements()

        guard !pathElements.isEmpty else { return nil }

        var points: [CGPoint] = []
        for element in pathElements {
            switch element {
            case .move(to: let p):
                points.append(p)
            case .line(to: let p):
                points.append(p)
            case .quadCurve(to: let p, control: _):
                points.append(p)
            case .curve(to: let p, control1: _, control2: _):
                points.append(p)
            case .closeSubpath:
                break
            }
        }

        guard points.count > 1 else { return nil }

        var lengths: [CGFloat] = [0]
        var totalLength: CGFloat = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i-1].x
            let dy = points[i].y - points[i-1].y
            let segmentLength = sqrt(dx*dx + dy*dy)
            totalLength += segmentLength
            lengths.append(totalLength)
        }

        guard totalLength > 0 else { return nil }

        let startLength = startFraction * totalLength
        let endLength = endFraction * totalLength

        var started = false
        for i in 1..<points.count {
            let segmentStart = lengths[i-1]
            let segmentEnd = lengths[i]

            if segmentEnd >= startLength && segmentStart <= endLength {
                let p1 = points[i-1]
                let p2 = points[i]

                var drawStart = p1
                if segmentStart < startLength {
                    let t = (startLength - segmentStart) / (segmentEnd - segmentStart)
                    drawStart = CGPoint(
                        x: p1.x + (p2.x - p1.x) * t,
                        y: p1.y + (p2.y - p1.y) * t
                    )
                }

                var drawEnd = p2
                if segmentEnd > endLength {
                    let t = (endLength - segmentStart) / (segmentEnd - segmentStart)
                    drawEnd = CGPoint(
                        x: p1.x + (p2.x - p1.x) * t,
                        y: p1.y + (p2.y - p1.y) * t
                    )
                }

                if !started {
                    result.move(to: drawStart)
                    started = true
                }
                result.addLine(to: drawEnd)
            }
        }

        return result
    }
}

// Extension to get path elements from CGPath
extension CGPath {
    func getPathElements() -> [PathElement] {
        var elements: [PathElement] = []
        self.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                elements.append(.move(to: element.pointee.points[0]))
            case .addLineToPoint:
                elements.append(.line(to: element.pointee.points[0]))
            case .addQuadCurveToPoint:
                elements.append(.quadCurve(to: element.pointee.points[1], control: element.pointee.points[0]))
            case .addCurveToPoint:
                elements.append(.curve(to: element.pointee.points[2], control1: element.pointee.points[0], control2: element.pointee.points[1]))
            case .closeSubpath:
                elements.append(.closeSubpath)
            @unknown default:
                break
            }
        }
        return elements
    }
}

enum PathElement {
    case move(to: CGPoint)
    case line(to: CGPoint)
    case quadCurve(to: CGPoint, control: CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case closeSubpath
}
