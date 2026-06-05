import SwiftUI
import PencilKit

/// Captures and shares canvas content with optional watermark
struct ShareSheet {

    /// Generate a shareable image from the canvas
    static func captureCanvas(canvasView: PKCanvasView, includeWatermark: Bool = true) -> UIImage? {
        let drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { return nil }

        // Get bounds of all content
        let contentBounds = drawing.bounds
        let padding: CGFloat = 40

        // Create image with padding
        let imageSize = CGSize(
            width: contentBounds.width + padding * 2,
            height: contentBounds.height + padding * 2 + (includeWatermark ? 30 : 0)
        )

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { ctx in
            // Dark background
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: imageSize))

            // Draw the content
            let traitCollection = UITraitCollection(userInterfaceStyle: .light)
            traitCollection.performAsCurrent {
                let drawingImage = drawing.image(from: contentBounds, scale: UIScreen.main.scale)
                drawingImage.draw(at: CGPoint(x: padding, y: padding))
            }

            // Add watermark if requested
            if includeWatermark {
                addWatermark(to: ctx.cgContext, size: imageSize)
            }
        }
    }

    /// Capture the full visible canvas area
    static func captureVisibleCanvas(canvasView: PKCanvasView, includeWatermark: Bool = true) -> UIImage? {
        let bounds = canvasView.bounds
        let contentOffset = canvasView.contentOffset

        // Capture what's visible on screen
        let visibleRect = CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: bounds.width,
            height: bounds.height
        )

        let drawing = canvasView.drawing

        // Add padding for watermark
        let imageHeight = bounds.height + (includeWatermark ? 30 : 0)
        let imageSize = CGSize(width: bounds.width, height: imageHeight)

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { ctx in
            // Dark background
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: imageSize))

            // Draw the visible content
            let traitCollection = UITraitCollection(userInterfaceStyle: .light)
            traitCollection.performAsCurrent {
                // Get image of just the visible area
                let drawingImage = drawing.image(from: visibleRect, scale: UIScreen.main.scale)
                drawingImage.draw(at: .zero)
            }

            // Add watermark if requested
            if includeWatermark {
                addWatermark(to: ctx.cgContext, size: imageSize)
            }
        }
    }

    private static func addWatermark(to context: CGContext, size: CGSize) {
        let watermarkText = "made with rite"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .light),
            .foregroundColor: UIColor.white.withAlphaComponent(0.4)
        ]

        let string = NSAttributedString(string: watermarkText, attributes: attributes)
        let textSize = string.size()

        let textX = size.width - textSize.width - 15
        let textY = size.height - textSize.height - 10

        string.draw(at: CGPoint(x: textX, y: textY))
    }
}

/// SwiftUI wrapper for UIActivityViewController
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

