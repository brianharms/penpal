import PencilKit
import UIKit

/// Handwriting personality styles that mirror the user's writing
enum HandwritingStyle: String, Codable, CaseIterable {
    case elegant   // Neat, careful writing → consistent, smooth AI response
    case friendly  // Quick, casual writing → relaxed, natural AI response
    case bold      // Large, expressive writing → dramatic, playful AI response
    case riddle    // Tom Riddle diary: italic quill, thin and precise

    /// Display name for the style
    var displayName: String {
        switch self {
        case .elegant: return "Elegant"
        case .friendly: return "Friendly"
        case .bold: return "Bold"
        case .riddle: return "Riddle"
        }
    }

    /// Style parameters for AI handwriting generation
    struct Parameters {
        let baselineWobble: CGFloat      // How much the baseline varies
        let letterSizeVariance: CGFloat  // Variation in letter sizes
        let slantRange: ClosedRange<CGFloat>  // Random slant range
        let strokeWidthMultiplier: CGFloat    // Relative stroke thickness
        let spacingMultiplier: CGFloat   // Letter spacing adjustment
        let speedMultiplier: CGFloat     // Animation speed adjustment
    }

    var parameters: Parameters {
        switch self {
        case .elegant:
            return Parameters(
                baselineWobble: 0.03,        // Very stable baseline
                letterSizeVariance: 0.02,    // Consistent letter sizes
                slantRange: -0.01...0.01,    // Almost no slant variation
                strokeWidthMultiplier: 0.9,  // Slightly thinner strokes
                spacingMultiplier: 1.1,      // Slightly more spacing
                speedMultiplier: 0.85        // Slightly slower, deliberate
            )
        case .friendly:
            return Parameters(
                baselineWobble: 0.08,        // Natural wobble
                letterSizeVariance: 0.08,    // Some size variation
                slantRange: -0.04...0.04,    // Natural slant variation
                strokeWidthMultiplier: 1.0,  // Normal strokes
                spacingMultiplier: 1.0,      // Normal spacing
                speedMultiplier: 1.0         // Normal speed
            )
        case .bold:
            return Parameters(
                baselineWobble: 0.12,        // More expressive baseline
                letterSizeVariance: 0.15,    // Variable letter sizes
                slantRange: -0.06...0.06,    // More dramatic slant
                strokeWidthMultiplier: 1.2,  // Thicker strokes
                spacingMultiplier: 0.95,     // Slightly tighter
                speedMultiplier: 1.15        // Slightly faster, energetic
            )
        case .riddle:
            return Parameters(
                baselineWobble: 0.02,        // Very controlled quill
                letterSizeVariance: 0.01,    // Extremely consistent
                slantRange: 0.03...0.08,     // Consistent rightward italic
                strokeWidthMultiplier: 0.85, // Fountain pen base width (force variation creates thin/thick)
                spacingMultiplier: 1.15,     // Elegant wider spacing
                speedMultiplier: 0.75        // Slow, deliberate
            )
        }
    }
}

/// Analyzes PencilKit strokes to determine user's handwriting style
class HandwritingAnalyzer {

    /// Metrics extracted from stroke analysis
    struct StrokeMetrics {
        let averageSpeed: CGFloat           // Points per second
        let speedVariance: CGFloat          // How consistent is the speed
        let averagePressure: CGFloat        // Average force applied
        let pressureVariance: CGFloat       // How much pressure varies
        let averageStrokeHeight: CGFloat    // Average character height
        let heightVariance: CGFloat         // How consistent are heights
        let averageSlant: CGFloat           // Overall slant angle
        let strokeDensity: CGFloat          // Strokes per unit area
    }

    /// Analyze strokes to determine the user's handwriting style
    static func analyzeStyle(strokes: [PKStroke]) -> HandwritingStyle {
        guard strokes.count >= 3 else {
            return .friendly // Default for very little input
        }

        let metrics = calculateMetrics(strokes: strokes)

        // Score each style based on how well the metrics match
        var scores: [HandwritingStyle: CGFloat] = [:]

        // Elegant: slow, consistent pressure, consistent heights
        let elegantScore = calculateElegantScore(metrics: metrics)
        scores[.elegant] = elegantScore

        // Friendly: moderate speed and variance, natural feel
        let friendlyScore = calculateFriendlyScore(metrics: metrics)
        scores[.friendly] = friendlyScore

        // Bold: fast, high pressure variance, larger strokes
        let boldScore = calculateBoldScore(metrics: metrics)
        scores[.bold] = boldScore

        // Return the highest scoring style
        return scores.max(by: { $0.value < $1.value })?.key ?? .friendly
    }

    private static func calculateMetrics(strokes: [PKStroke]) -> StrokeMetrics {
        var speeds: [CGFloat] = []
        var pressures: [CGFloat] = []
        var heights: [CGFloat] = []
        var slants: [CGFloat] = []
        var totalArea: CGFloat = 0

        for stroke in strokes {
            let path = stroke.path
            let bounds = stroke.renderBounds

            // Calculate height
            if bounds.height > 5 && bounds.height < 200 {
                heights.append(bounds.height)
            }

            // Calculate speed (distance / time)
            if path.count >= 2 {
                var totalDistance: CGFloat = 0
                var totalTime: TimeInterval = 0

                for i in 1..<path.count {
                    let p1 = path[i-1]
                    let p2 = path[i]

                    let dx = p2.location.x - p1.location.x
                    let dy = p2.location.y - p1.location.y
                    totalDistance += sqrt(dx*dx + dy*dy)
                    totalTime += p2.timeOffset - p1.timeOffset

                    // Collect pressure values
                    pressures.append(p2.force)
                }

                if totalTime > 0 {
                    speeds.append(totalDistance / CGFloat(totalTime))
                }
            }

            // Calculate slant (angle from vertical)
            if bounds.height > 10 {
                let slant = atan2(bounds.width, bounds.height)
                slants.append(slant)
            }

            totalArea += bounds.width * bounds.height
        }

        // Calculate averages and variances
        let avgSpeed = speeds.isEmpty ? 100 : speeds.reduce(0, +) / CGFloat(speeds.count)
        let speedVar = calculateVariance(speeds)

        let avgPressure = pressures.isEmpty ? 0.5 : pressures.reduce(0, +) / CGFloat(pressures.count)
        let pressureVar = calculateVariance(pressures)

        let avgHeight = heights.isEmpty ? 30 : heights.reduce(0, +) / CGFloat(heights.count)
        let heightVar = calculateVariance(heights)

        let avgSlant = slants.isEmpty ? 0 : slants.reduce(0, +) / CGFloat(slants.count)

        let density = totalArea > 0 ? CGFloat(strokes.count) / totalArea * 1000 : 1

        return StrokeMetrics(
            averageSpeed: avgSpeed,
            speedVariance: speedVar,
            averagePressure: avgPressure,
            pressureVariance: pressureVar,
            averageStrokeHeight: avgHeight,
            heightVariance: heightVar,
            averageSlant: avgSlant,
            strokeDensity: density
        )
    }

    private static func calculateVariance(_ values: [CGFloat]) -> CGFloat {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / CGFloat(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return sqrt(squaredDiffs.reduce(0, +) / CGFloat(values.count))
    }

    private static func calculateElegantScore(metrics: StrokeMetrics) -> CGFloat {
        var score: CGFloat = 0

        // Slow, deliberate writing
        if metrics.averageSpeed < 150 {
            score += 0.3
        }

        // Consistent speed
        if metrics.speedVariance < 50 {
            score += 0.2
        }

        // Consistent pressure
        if metrics.pressureVariance < 0.2 {
            score += 0.2
        }

        // Consistent letter heights
        if metrics.heightVariance < 10 {
            score += 0.3
        }

        return score
    }

    private static func calculateFriendlyScore(metrics: StrokeMetrics) -> CGFloat {
        var score: CGFloat = 0

        // Moderate speed
        if metrics.averageSpeed >= 100 && metrics.averageSpeed <= 300 {
            score += 0.25
        }

        // Some variation (not too perfect, not too wild)
        if metrics.speedVariance >= 30 && metrics.speedVariance <= 100 {
            score += 0.25
        }

        // Natural pressure variation
        if metrics.pressureVariance >= 0.1 && metrics.pressureVariance <= 0.4 {
            score += 0.25
        }

        // Medium density
        if metrics.strokeDensity >= 0.5 && metrics.strokeDensity <= 2 {
            score += 0.25
        }

        return score
    }

    private static func calculateBoldScore(metrics: StrokeMetrics) -> CGFloat {
        var score: CGFloat = 0

        // Fast writing
        if metrics.averageSpeed > 200 {
            score += 0.25
        }

        // High speed variance (expressive)
        if metrics.speedVariance > 80 {
            score += 0.2
        }

        // Higher pressure
        if metrics.averagePressure > 0.6 {
            score += 0.2
        }

        // Larger strokes
        if metrics.averageStrokeHeight > 35 {
            score += 0.2
        }

        // Variable heights (more expressive)
        if metrics.heightVariance > 12 {
            score += 0.15
        }

        return score
    }
}
