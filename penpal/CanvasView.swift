import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Papyrus image layer (fixed behind canvas — doesn't scroll with content)
        let papyrusView = UIImageView(image: UIImage(named: "papyrus"))
        papyrusView.contentMode = .scaleAspectFill
        papyrusView.clipsToBounds = true
        papyrusView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        papyrusView.frame = container.bounds
        papyrusView.isHidden = !viewModel.tomRiddleMode
        container.addSubview(papyrusView)
        context.coordinator.papyrusView = papyrusView

        // PKCanvasView on top
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = viewModel.tomRiddleMode ? .clear : viewModel.currentTheme.createBackgroundUIColor()
        canvasView.isOpaque = !viewModel.tomRiddleMode
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.isScrollEnabled = true
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.frame = container.bounds

        let screenSize = UIScreen.main.bounds.size
        canvasView.contentSize = CGSize(width: screenSize.width, height: screenSize.height * 5)

        canvasView.delegate = context.coordinator
        container.addSubview(canvasView)
        context.coordinator.managedCanvasView = canvasView

        viewModel.canvasView = canvasView

        // Add occupied region debug overlay
        let overlay = RegionOverlayView(frame: CGRect(origin: .zero, size: canvasView.contentSize))
        overlay.isHidden = true
        canvasView.addSubview(overlay)
        context.coordinator.regionOverlay = overlay

        DispatchQueue.main.async {
            viewModel.onCanvasReady()
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let canvasView = context.coordinator.managedCanvasView,
              let papyrusView = context.coordinator.papyrusView else { return }

        // Update user ink tool
        if !viewModel.isAnimatingResponse {
            canvasView.tool = PKInkingTool(.pen, color: viewModel.currentTheme.userInkColor, width: viewModel.penThickness)
        }

        // Papyrus visibility + canvas transparency
        let isDiary = viewModel.tomRiddleMode
        papyrusView.isHidden = !isDiary
        if isDiary {
            canvasView.backgroundColor = .clear
            canvasView.isOpaque = false
        } else {
            canvasView.backgroundColor = viewModel.currentTheme.createBackgroundUIColor()
            canvasView.isOpaque = true
        }

        // Occupied region debug overlay
        if let overlay = context.coordinator.regionOverlay {
            if viewModel.showOccupiedRegions {
                overlay.isHidden = false
                let regions = viewModel.buildOccupiedRegions(from: canvasView.drawing.strokes)
                let path = CGMutablePath()
                for region in regions {
                    guard region.hull.count >= 3 else { continue }
                    path.move(to: region.hull[0])
                    for i in 1..<region.hull.count {
                        path.addLine(to: region.hull[i])
                    }
                    path.closeSubpath()
                }
                overlay.shapeLayer.path = path
            } else {
                overlay.isHidden = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let viewModel: CanvasViewModel
        var regionOverlay: RegionOverlayView?
        var papyrusView: UIImageView?
        var managedCanvasView: PKCanvasView?
        private var pauseTimer: Timer?
        private var lastStrokeTime: Date?

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if viewModel.isAnimatingResponse { return }

            viewModel.fadeAIStrokesIfNeeded()
            pauseTimer?.invalidate()

            if viewModel.isProcessing {
                viewModel.cancelProcessing()
            }

            lastStrokeTime = Date()

            pauseTimer = Timer.scheduledTimer(withTimeInterval: viewModel.pauseDuration, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.viewModel.processCanvas()
                }
            }
        }
    }
}

// MARK: - Occupied Region Debug Overlay

class RegionOverlayView: UIView {
    let shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        shapeLayer.fillColor = UIColor.systemCyan.withAlphaComponent(0.1).cgColor
        shapeLayer.strokeColor = UIColor.systemCyan.withAlphaComponent(0.5).cgColor
        shapeLayer.lineWidth = 1.5
        shapeLayer.lineDashPattern = [6, 4]
        shapeLayer.frame = bounds
        layer.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.frame = bounds
    }
}
