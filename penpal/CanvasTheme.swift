import UIKit

enum CanvasTheme: String, Codable, CaseIterable {
    case defaultDark
    case paper
    case paperDark
    case grid
    case gridDark
    case dotted
    case dottedDark
    case tomRiddle

    // MARK: - Colors

    var userInkColor: UIColor {
        switch self {
        case .defaultDark, .paperDark, .gridDark, .dottedDark:
            return .white
        case .paper, .grid, .dotted:
            return UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        case .tomRiddle:
            return UIColor(red: 0.12, green: 0.08, blue: 0.04, alpha: 1.0)
        }
    }

    var responseColor: UIColor {
        switch self {
        case .defaultDark:
            return UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0) // Yellow
        case .paper:
            return UIColor(red: 0.15, green: 0.25, blue: 0.65, alpha: 1.0) // Blue ballpoint
        case .paperDark:
            return UIColor(red: 0.45, green: 0.6, blue: 0.95, alpha: 1.0) // Light blue
        case .grid, .dotted:
            return UIColor(red: 0.15, green: 0.25, blue: 0.65, alpha: 1.0) // Blue
        case .gridDark, .dottedDark:
            return UIColor(red: 0.45, green: 0.6, blue: 0.95, alpha: 1.0) // Light blue
        case .tomRiddle:
            return UIColor(red: 0.12, green: 0.08, blue: 0.04, alpha: 1.0) // Very dark ink
        }
    }

    var solidBackgroundColor: UIColor {
        switch self {
        case .defaultDark:
            return .black
        case .paper:
            return UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1.0) // Cream
        case .paperDark:
            return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        case .grid, .dotted:
            return UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0) // Near-white
        case .gridDark, .dottedDark:
            return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        case .tomRiddle:
            return UIColor(red: 0.83, green: 0.77, blue: 0.63, alpha: 1.0) // Aged parchment
        }
    }

    var isDark: Bool {
        switch self {
        case .defaultDark, .paperDark, .gridDark, .dottedDark:
            return true
        case .paper, .grid, .dotted, .tomRiddle:
            return false
        }
    }

    /// Returns the dark variant of the current theme, or self if already dark
    var darkVariant: CanvasTheme {
        switch self {
        case .paper: return .paperDark
        case .grid: return .gridDark
        case .dotted: return .dottedDark
        default: return self.isDark ? self : .defaultDark
        }
    }

    /// Returns the light variant of the current theme, or self if already light
    var lightVariant: CanvasTheme {
        switch self {
        case .paperDark: return .paper
        case .gridDark: return .grid
        case .dottedDark: return .dotted
        case .defaultDark: return .paper // Default light → paper
        default: return self
        }
    }

    // MARK: - Background (solid or pattern)

    private static let lineSpacing: CGFloat = 44

    func createBackgroundUIColor() -> UIColor {
        switch self {
        case .defaultDark, .tomRiddle:
            return solidBackgroundColor

        case .paper:
            return UIColor(patternImage: Self.ruledPattern(
                bgColor: solidBackgroundColor,
                lineColor: UIColor(red: 0.72, green: 0.8, blue: 0.9, alpha: 0.45),
                spacing: Self.lineSpacing
            ))

        case .paperDark:
            return UIColor(patternImage: Self.ruledPattern(
                bgColor: solidBackgroundColor,
                lineColor: UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 0.6),
                spacing: Self.lineSpacing
            ))

        case .grid:
            return UIColor(patternImage: Self.gridPattern(
                bgColor: solidBackgroundColor,
                lineColor: UIColor(red: 0.55, green: 0.65, blue: 0.78, alpha: 0.85),
                spacing: Self.lineSpacing
            ))

        case .gridDark:
            return UIColor(patternImage: Self.gridPattern(
                bgColor: solidBackgroundColor,
                lineColor: UIColor(red: 0.32, green: 0.32, blue: 0.38, alpha: 0.85),
                spacing: Self.lineSpacing
            ))

        case .dotted:
            return UIColor(patternImage: Self.dottedPattern(
                bgColor: solidBackgroundColor,
                dotColor: UIColor(red: 0.72, green: 0.75, blue: 0.78, alpha: 0.6),
                spacing: Self.lineSpacing
            ))

        case .dottedDark:
            return UIColor(patternImage: Self.dottedPattern(
                bgColor: solidBackgroundColor,
                dotColor: UIColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 0.7),
                spacing: Self.lineSpacing
            ))
        }
    }

    // MARK: - Pattern Generators

    private static func ruledPattern(bgColor: UIColor, lineColor: UIColor, spacing: CGFloat) -> UIImage {
        let size = CGSize(width: 4, height: spacing)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            lineColor.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: spacing - 0.25))
            path.addLine(to: CGPoint(x: size.width, y: spacing - 0.25))
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    private static func gridPattern(bgColor: UIColor, lineColor: UIColor, spacing: CGFloat) -> UIImage {
        let size = CGSize(width: spacing, height: spacing)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            lineColor.setStroke()
            let path = UIBezierPath()
            // Bottom edge
            path.move(to: CGPoint(x: 0, y: spacing - 0.25))
            path.addLine(to: CGPoint(x: spacing, y: spacing - 0.25))
            // Right edge
            path.move(to: CGPoint(x: spacing - 0.25, y: 0))
            path.addLine(to: CGPoint(x: spacing - 0.25, y: spacing))
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    private static func dottedPattern(bgColor: UIColor, dotColor: UIColor, spacing: CGFloat) -> UIImage {
        let size = CGSize(width: spacing, height: spacing)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            bgColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            dotColor.setFill()
            let dotSize: CGFloat = 2.5
            let dotRect = CGRect(
                x: spacing - dotSize / 2,
                y: spacing - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            ctx.cgContext.fillEllipse(in: dotRect)
        }
    }
}
