import SwiftUI
import PencilKit
import Photos

enum ProcessingState {
    case idle
    case thinking
    case writing
}

// MARK: - Occupied Region (Convex Hull)

struct OccupiedRegion {
    let hull: [CGPoint]   // Convex hull vertices in order
    let bounds: CGRect    // Axis-aligned bounding rect for quick rejection

    /// Find the maximum Y (bottommost point) of the hull at a given X
    func maxYAtX(_ x: CGFloat) -> CGFloat? {
        guard x >= bounds.minX && x <= bounds.maxX else { return nil }
        guard hull.count >= 3 else { return nil }

        var maxY: CGFloat = -.infinity
        let n = hull.count

        for i in 0..<n {
            let a = hull[i]
            let b = hull[(i + 1) % n]

            let minEdgeX = min(a.x, b.x)
            let maxEdgeX = max(a.x, b.x)
            guard x >= minEdgeX && x <= maxEdgeX else { continue }

            if abs(b.x - a.x) < 0.001 {
                maxY = max(maxY, max(a.y, b.y))
            } else {
                let t = (x - a.x) / (b.x - a.x)
                maxY = max(maxY, a.y + t * (b.y - a.y))
            }
        }

        return maxY > -.infinity ? maxY : nil
    }

    /// Check if a rectangle intersects this convex hull
    func intersectsRect(_ rect: CGRect) -> Bool {
        guard bounds.intersects(rect) else { return false }

        // Any hull vertex inside the rect?
        for p in hull {
            if rect.contains(p) { return true }
        }

        // Any rect corner inside the hull?
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        for corner in corners {
            if containsPoint(corner) { return true }
        }

        return false
    }

    /// Point-in-convex-polygon via cross product sign consistency
    func containsPoint(_ point: CGPoint) -> Bool {
        let n = hull.count
        guard n >= 3 else { return false }

        var allPositive = true
        var allNegative = true

        for i in 0..<n {
            let a = hull[i]
            let b = hull[(i + 1) % n]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)

            if cross < 0 { allPositive = false }
            if cross > 0 { allNegative = false }
            if !allPositive && !allNegative { return false }
        }

        return true
    }

    // MARK: - Convex Hull Algorithm (Andrew's Monotone Chain)

    static func computeConvexHull(points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard sorted.count >= 3 else { return sorted }

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    /// Expand hull outward from centroid by padding distance
    static func padHull(_ hull: [CGPoint], padding: CGFloat) -> [CGPoint] {
        guard hull.count >= 3 else { return hull }

        let cx = hull.map(\.x).reduce(0, +) / CGFloat(hull.count)
        let cy = hull.map(\.y).reduce(0, +) / CGFloat(hull.count)

        return hull.map { p in
            let dx = p.x - cx
            let dy = p.y - cy
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 0 else { return p }
            let scale = (dist + padding) / dist
            return CGPoint(x: cx + dx * scale, y: cy + dy * scale)
        }
    }
}

@MainActor
class CanvasViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var processingState: ProcessingState = .idle
    @Published var shouldShowSettings = false
    @Published var apiKey: String = "" {
        didSet { KeychainHelper.save(apiKey, forKey: "anthropic_api_key") }
    }
    @Published var resendApiKey: String = "" {
        didSet { KeychainHelper.save(resendApiKey, forKey: "resend_api_key") }
    }
    @Published var resendFromEmail: String = "" {
        didSet { KeychainHelper.save(resendFromEmail, forKey: "resend_from_email") }
    }
    @Published var errorMessage: String?
    @Published var showDebugOverlay = false
    @Published var showOccupiedRegions = false
    @Published var tomRiddleMode = false
    @Published var inkBleedImage: UIImage?
    private var hasPendingAIStrokes = false

    // User-configurable settings
    @Published var penThickness: CGFloat = 4.5
    @Published var userInkColor: UIColor = UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)
    @Published var backgroundColor: UIColor = .black
    @Published var responseColor: UIColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0)  // Yellow
    @Published var responseSize: CGFloat = 24.0
    @Published var pauseDuration: TimeInterval = 1.5
    @Published var glowAnimationSpeed: Double = 1.0  // Slithering light speed: 1.0 = normal
    var thinkingStartTime: Date = Date()
    @Published var textAnimationSpeed: Double = 0.5  // AI text writing speed: 0.5 = slower, more natural
    @Published var responseSizeMultiplier: Double = 1.125  // AI text size relative to user's
    @Published var responseStrokeWidth: CGFloat = 7.5  // AI response pen thickness
    @Published var responseVerbosity: Double = 0.5  // 0 = very terse, 1 = verbose

    // Flag to prevent cancellation when we're adding AI strokes
    var isAnimatingResponse = false

    // Track user stroke count (before AI adds its strokes)
    @Published var userStrokeCount: Int = 0

    // Track which strokes have been responded to (for glow animation)
    @Published var lastRespondedStrokeIndex: Int = 0

    // Estimated font size of user's text (for glow scaling)
    @Published var estimatedUserFontSize: CGFloat = 24

    // Detected handwriting style for AI response matching
    @Published var detectedStyle: HandwritingStyle = .friendly

    // Notebook persistence
    let notebookStore: NotebookStore
    private var autoSaveTimer: Timer?

    weak var canvasView: PKCanvasView?
    private var claudeService: ClaudeService?
    private var currentTask: Task<Void, Never>?

    // Canvas theme
    @Published var currentTheme: CanvasTheme = .defaultDark

    // Snapshot saved before entering diary mode, for full restore on exit
    private struct ThemeSnapshot {
        let theme: CanvasTheme
        let userInkColor: UIColor
        let responseColor: UIColor
        let responseStrokeWidth: CGFloat
    }
    private var preRiddleSnapshot: ThemeSnapshot?

    // Conversation memory — stores previous turns for multi-turn context
    private var conversationHistory: [ConversationTurn] = []

    init(notebookStore: NotebookStore) {
        self.notebookStore = notebookStore

        // Load from persistent defaults file first (survives rebuilds)
        loadFromDefaults()

        // Then load from UserDefaults (may have more recent changes)
        loadSettings()

        // Load API keys from Keychain
        if let saved = KeychainHelper.load(forKey: "anthropic_api_key") {
            apiKey = saved
        }
        if let saved = KeychainHelper.load(forKey: "resend_api_key"), !saved.isEmpty {
            resendApiKey = saved
        } else {
            resendApiKey = ""
        }
        if let saved = KeychainHelper.load(forKey: "resend_from_email"), !saved.isEmpty {
            resendFromEmail = saved
        } else {
            resendFromEmail = ""
        }

        // Start auto-save timer
        startAutoSave()
    }

    private func startAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentNotebook()
            }
        }
    }

    /// Save the current canvas state to the notebook
    func saveCurrentNotebook() {
        guard let canvasView = canvasView else { return }
        notebookStore.updateCurrentNotebook(
            drawing: canvasView.drawing,
            lastRespondedStrokeIndex: lastRespondedStrokeIndex,
            userStrokeCount: userStrokeCount
        )
    }

    /// Load a notebook into the canvas
    func loadNotebook(_ notebook: Notebook) {
        guard let canvasView = canvasView else { return }
        canvasView.drawing = notebook.drawing
        lastRespondedStrokeIndex = notebook.lastRespondedStrokeIndex
        userStrokeCount = notebook.userStrokeCount
        notebookStore.switchTo(notebook)
    }

    /// Called when canvas view is ready
    func onCanvasReady() {
        // Canvas is now set up — notebook will be loaded via ContentView.onAppear
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "penThickness") != nil {
            penThickness = defaults.double(forKey: "penThickness")
        }
        if defaults.object(forKey: "responseSize") != nil {
            responseSize = defaults.double(forKey: "responseSize")
        }
        if defaults.object(forKey: "pauseDuration") != nil {
            pauseDuration = defaults.double(forKey: "pauseDuration")
        }
        if defaults.object(forKey: "glowAnimationSpeed") != nil {
            glowAnimationSpeed = defaults.double(forKey: "glowAnimationSpeed")
        }
        if defaults.object(forKey: "textAnimationSpeed") != nil {
            textAnimationSpeed = defaults.double(forKey: "textAnimationSpeed")
        }
        // Colors stored as hex strings
        if let colorHex = defaults.string(forKey: "userInkColor") {
            userInkColor = UIColor(hex: colorHex) ?? .white
        }
        if let colorHex = defaults.string(forKey: "backgroundColor") {
            backgroundColor = UIColor(hex: colorHex) ?? .black
        }
        // Note: responseColor intentionally not loaded from old settings to ensure yellow default
        if defaults.object(forKey: "responseSizeMultiplier") != nil {
            responseSizeMultiplier = defaults.double(forKey: "responseSizeMultiplier")
        }
        if defaults.object(forKey: "responseStrokeWidth") != nil {
            responseStrokeWidth = defaults.double(forKey: "responseStrokeWidth")
        }
        if defaults.object(forKey: "responseVerbosity") != nil {
            responseVerbosity = defaults.double(forKey: "responseVerbosity")
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(penThickness, forKey: "penThickness")
        defaults.set(responseSize, forKey: "responseSize")
        defaults.set(pauseDuration, forKey: "pauseDuration")
        defaults.set(glowAnimationSpeed, forKey: "glowAnimationSpeed")
        defaults.set(textAnimationSpeed, forKey: "textAnimationSpeed")
        defaults.set(userInkColor.toHex(), forKey: "userInkColor")
        defaults.set(backgroundColor.toHex(), forKey: "backgroundColor")
        defaults.set(responseColor.toHex(), forKey: "responseColor")
        defaults.set(responseSizeMultiplier, forKey: "responseSizeMultiplier")
        defaults.set(responseStrokeWidth, forKey: "responseStrokeWidth")
        defaults.set(responseVerbosity, forKey: "responseVerbosity")
    }

    func saveAsDefaults() {
        // Save to a persistent file that survives rebuilds
        let settings: [String: Any] = [
            "penThickness": penThickness,
            "responseSize": responseSize,
            "pauseDuration": pauseDuration,
            "glowAnimationSpeed": glowAnimationSpeed,
            "textAnimationSpeed": textAnimationSpeed,
            "userInkColor": userInkColor.toHex(),
            "backgroundColor": backgroundColor.toHex(),
            "responseColor": responseColor.toHex(),
            "responseSizeMultiplier": responseSizeMultiplier,
            "responseStrokeWidth": responseStrokeWidth,
            "responseVerbosity": responseVerbosity
        ]

        if let url = getDefaultsFileURL() {
            do {
                let data = try JSONSerialization.data(withJSONObject: settings)
                try data.write(to: url)
                print("Saved defaults to: \(url.path)")
            } catch {
                print("Failed to save defaults: \(error)")
            }
        }

        // Also save to UserDefaults
        saveSettings()
    }

    private func loadFromDefaults() {
        guard let url = getDefaultsFileURL(),
              FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            if let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let v = settings["penThickness"] as? Double { penThickness = v }
                if let v = settings["responseSize"] as? Double { responseSize = v }
                if let v = settings["pauseDuration"] as? Double { pauseDuration = v }
                if let v = settings["glowAnimationSpeed"] as? Double { glowAnimationSpeed = v }
                if let v = settings["textAnimationSpeed"] as? Double { textAnimationSpeed = v }
                if let v = settings["userInkColor"] as? String { userInkColor = UIColor(hex: v) ?? .white }
                if let v = settings["backgroundColor"] as? String { backgroundColor = UIColor(hex: v) ?? .black }
                // responseColor intentionally not loaded - using yellow default
                if let v = settings["responseSizeMultiplier"] as? Double { responseSizeMultiplier = v }
                if let v = settings["responseStrokeWidth"] as? Double { responseStrokeWidth = v }
                if let v = settings["responseVerbosity"] as? Double { responseVerbosity = v }
                print("Loaded defaults from file")
            }
        } catch {
            print("Failed to load defaults: \(error)")
        }
    }

    private func getDefaultsFileURL() -> URL? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths.first?.appendingPathComponent("rite_defaults.json")
    }

    func applySettingsChange(_ settings: AIResponse.SettingsChange) {
        // Pen thickness
        if let thickness = settings.penThickness {
            switch thickness.lowercased() {
            case "thicker":
                penThickness = min(penThickness + 1.5, 10)
            case "thinner":
                penThickness = max(penThickness - 1.5, 1)
            default:
                if let value = Double(thickness) {
                    penThickness = CGFloat(min(max(value, 1), 10))
                }
            }
            updateCanvasTool()
        }

        // User ink color
        if let colorName = settings.userInkColor {
            if let color = parseColor(colorName) {
                userInkColor = color
                updateCanvasTool()
            }
        }

        // Background color
        if let colorName = settings.backgroundColor {
            if let color = parseColor(colorName) {
                backgroundColor = color
            }
        }

        // Response color
        if let colorName = settings.responseColor {
            if let color = parseColor(colorName) {
                responseColor = color
            }
        }

        // Response size
        if let size = settings.responseSize {
            switch size.lowercased() {
            case "bigger", "larger":
                responseSize = min(responseSize + 6, 72)
            case "smaller":
                responseSize = max(responseSize - 6, 12)
            default:
                if let value = Double(size) {
                    responseSize = CGFloat(min(max(value, 12), 72))
                }
            }
        }

        // Pause duration
        if let duration = settings.pauseDuration {
            switch duration.lowercased() {
            case "longer", "more":
                pauseDuration = min(pauseDuration + 1, 6)
            case "shorter", "less", "quicker", "faster":
                pauseDuration = max(pauseDuration - 0.5, 0.5)
            default:
                if let value = Double(duration) {
                    pauseDuration = min(max(value, 0.5), 6)
                }
            }
        }

        // Animation speed (affects text writing animation)
        if let speed = settings.animationSpeed {
            switch speed.lowercased() {
            case "faster", "quicker":
                textAnimationSpeed = min(textAnimationSpeed * 1.5, 4.0)
            case "slower":
                textAnimationSpeed = max(textAnimationSpeed / 1.5, 0.1)
            default:
                break
            }
        }

        saveSettings()
    }

    private func updateCanvasTool() {
        guard let canvasView = canvasView else { return }
        let pen = PKInkingTool(.pen, color: userInkColor, width: penThickness)
        canvasView.tool = pen
    }

    private func parseColor(_ name: String) -> UIColor? {
        let lowercased = name.lowercased().trimmingCharacters(in: .whitespaces)

        // Check for hex
        if lowercased.hasPrefix("#") {
            return UIColor(hex: lowercased)
        }

        // Named colors
        switch lowercased {
        case "white": return .white
        case "black": return .black
        case "red": return UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        case "blue": return UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        case "green": return UIColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
        case "yellow": return UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0)
        case "orange": return UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        case "purple": return UIColor(red: 0.7, green: 0.3, blue: 1.0, alpha: 1.0)
        case "pink": return UIColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1.0)
        case "cyan": return UIColor(red: 0.3, green: 0.9, blue: 0.9, alpha: 1.0)
        case "gray", "grey": return UIColor(white: 0.5, alpha: 1.0)
        case "dark gray", "dark grey", "darkgray": return UIColor(white: 0.2, alpha: 1.0)
        case "light gray", "light grey", "lightgray": return UIColor(white: 0.7, alpha: 1.0)
        default: return nil
        }
    }

    func cancelProcessing() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
        processingState = .idle
    }

    func processCanvas() async {
        guard let canvasView = canvasView else { return }
        guard !apiKey.isEmpty else { return }
        guard !isAnimatingResponse else { return }
        guard !canvasView.drawing.strokes.isEmpty else { return }

        isProcessing = true
        thinkingStartTime = Date()
        processingState = .thinking

        // Save user stroke count before AI adds its response
        userStrokeCount = canvasView.drawing.strokes.count

        // Capture screenshot of canvas
        let image = captureCanvasImage(canvasView)

        // Get user stroke bounds for placement
        let userBounds = getUserStrokeBounds(canvasView.drawing)

        // Estimate user's font size from stroke heights
        let estimatedFontSize = estimateUserFontSize(canvasView.drawing)
        estimatedUserFontSize = estimatedFontSize

        // Analyze user's handwriting style for the recent strokes
        let recentStrokes = getRecentUserStrokes(from: canvasView.drawing)
        detectedStyle = HandwritingAnalyzer.analyzeStyle(strokes: recentStrokes)
        print("Detected handwriting style: \(detectedStyle.displayName)")

        // Tom Riddle mode: fade all strokes into the page while AI thinks
        if tomRiddleMode {
            fadeUserStrokesForDiary(canvasView: canvasView)
        }

        claudeService = ClaudeService(apiKey: apiKey)

        // Prepare base64 for conversation history
        let imageBase64 = image.jpegData(compressionQuality: 0.5)?.base64EncodedString() ?? ""

        currentTask = Task {
            do {
                let response = try await claudeService?.analyzeHandwriting(
                    image: image,
                    canvasSize: canvasView.bounds.size,
                    verbosity: responseVerbosity,
                    conversationHistory: conversationHistory,
                    tomRiddleMode: tomRiddleMode
                )

                guard !Task.isCancelled else { return }

                if let response = response {
                    // Save this turn to conversation history — only for conversational responses.
                    // Action commands (spotify, hue, reminder, email, etc.) are fire-and-forget;
                    // keeping them in history confuses Claude on the next turn.
                    let isActionCommand: Bool
                    if let cmd = response.command {
                        let conversationalCommands: Set<String> = ["diary", "debug", "screenshot"]
                        isActionCommand = !conversationalCommands.contains(cmd)
                    } else {
                        isActionCommand = false
                    }
                    if !isActionCommand, let historyText = response.text, !historyText.isEmpty {
                        conversationHistory.append(ConversationTurn(
                            userImageBase64: imageBase64,
                            assistantResponse: historyText
                        ))
                    }

                    // Check for commands
                    if let command = response.command {
                        let confirmation = await handleCommand(command, response: response)
                        // Use confirmation text, or fall through to response.text
                        let textToAnimate = confirmation ?? response.text
                        if let text = textToAnimate {
                            processingState = .writing
                            await animateResponse(
                                text: text,
                                userBounds: userBounds,
                                fontSize: estimatedFontSize,
                                canvasView: canvasView
                            )
                        }
                        lastRespondedStrokeIndex = canvasView.drawing.strokes.count
                        isProcessing = false
                        processingState = .idle
                        return
                    }

                    // Apply any settings changes
                    if let settings = response.settings {
                        applySettingsChange(settings)
                    }

                    // Animate the response
                    if let text = response.text {
                        processingState = .writing
                        await animateResponse(
                            text: text,
                            userBounds: userBounds,
                            fontSize: estimatedFontSize,
                            canvasView: canvasView
                        )
                    }
                }

                isProcessing = false
                processingState = .idle

            } catch {
                print("Error processing canvas: \(error)")
                isProcessing = false
                processingState = .idle
                if let claudeError = error as? ClaudeError {
                    switch claudeError {
                    case .apiError(let statusCode):
                        errorMessage = "Server error (\(statusCode))"
                    case .noContent:
                        errorMessage = "No response from Claude"
                    default:
                        errorMessage = "Something went wrong"
                    }
                } else if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                    errorMessage = "No internet connection"
                } else {
                    errorMessage = "Something went wrong"
                }
            }
        }
    }

    private func captureCanvasImage(_ canvasView: PKCanvasView) -> UIImage {
        let drawing = canvasView.drawing
        let bounds = canvasView.bounds

        // Only capture NEW strokes (since last response) to prevent re-triggering old commands
        let startIndex = lastRespondedStrokeIndex
        let endIndex = userStrokeCount

        // Create a drawing with only the new strokes
        let newStrokes: [PKStroke]
        if startIndex < endIndex && endIndex <= drawing.strokes.count {
            newStrokes = Array(drawing.strokes[startIndex..<endIndex])
        } else {
            newStrokes = []
        }

        var newDrawing = PKDrawing()
        newDrawing.strokes = newStrokes

        print("Capturing canvas - new strokes: \(newStrokes.count) (of \(drawing.strokes.count) total)")

        // Use UIGraphicsImageRenderer for proper capture
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { ctx in
            // Fill with solid black background
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))

            // Use LIGHT mode to match canvas - prevents color inversion
            // Canvas uses light mode so white strokes stay white
            let traitCollection = UITraitCollection(userInterfaceStyle: .light)
            traitCollection.performAsCurrent {
                let drawingImage = newDrawing.image(from: bounds, scale: UIScreen.main.scale)
                drawingImage.draw(at: .zero)
            }
        }
    }

    private func getUserStrokeBounds(_ drawing: PKDrawing) -> CGRect {
        guard !drawing.strokes.isEmpty else {
            return .zero
        }
        return drawing.bounds
    }

    private func estimateUserFontSize(_ drawing: PKDrawing) -> CGFloat {
        guard !drawing.strokes.isEmpty else { return 24 }

        // Estimate based on average stroke height
        var totalHeight: CGFloat = 0
        var count = 0

        for stroke in drawing.strokes {
            let bounds = stroke.renderBounds
            if bounds.height > 5 && bounds.height < 200 {
                totalHeight += bounds.height
                count += 1
            }
        }

        guard count > 0 else { return 24 }
        return min(max(totalHeight / CGFloat(count), 16), 48)
    }

    /// Get the user's recent strokes (since last AI response) for style analysis
    private func getRecentUserStrokes(from drawing: PKDrawing) -> [PKStroke] {
        let startIndex = lastRespondedStrokeIndex
        let endIndex = userStrokeCount

        guard startIndex < endIndex else { return [] }
        guard endIndex <= drawing.strokes.count else { return [] }

        return Array(drawing.strokes[startIndex..<endIndex])
    }

    /// Extract a smooth baseline path from the bottom edge of the user's recent text
    /// This creates a gentle curve that follows the overall shape of the user's writing
    private func extractBaselinePath(from drawing: PKDrawing, userBounds: CGRect, screenWidth: CGFloat) -> [CGPoint] {
        let startIndex = lastRespondedStrokeIndex
        let endIndex = min(userStrokeCount, drawing.strokes.count)

        guard startIndex < endIndex else { return [] }

        // Divide the user's text width into segments and find the lowest point in each
        let segmentWidth: CGFloat = 60  // Sample every 60 points horizontally
        let minX = userBounds.minX
        let maxX = userBounds.maxX

        guard maxX > minX else { return [] }

        var baselinePoints: [CGPoint] = []
        var currentX = minX

        while currentX < maxX {
            let segmentEnd = min(currentX + segmentWidth, maxX)
            var lowestY: CGFloat = userBounds.minY  // Start at top of bounds

            // Find the lowest (highest Y value) stroke bottom in this x segment
            for i in startIndex..<endIndex {
                let stroke = drawing.strokes[i]
                let bounds = stroke.renderBounds

                // Check if this stroke overlaps with our x segment
                if bounds.maxX >= currentX && bounds.minX <= segmentEnd {
                    // Use the bottom of this stroke if it's lower
                    if bounds.maxY > lowestY {
                        lowestY = bounds.maxY
                    }
                }
            }

            // If we found strokes in this segment, add a baseline point
            if lowestY > userBounds.minY {
                let midX = (currentX + segmentEnd) / 2
                baselinePoints.append(CGPoint(x: midX, y: lowestY))
            }

            // Always advance by at least segmentWidth to prevent infinite loop
            currentX = max(segmentEnd, currentX + segmentWidth)
        }

        // Need at least 2 points for a path
        guard baselinePoints.count >= 2 else {
            // Fall back to simple horizontal baseline at bottom of user bounds
            return [
                CGPoint(x: minX, y: userBounds.maxY),
                CGPoint(x: maxX, y: userBounds.maxY)
            ]
        }

        // Smooth the baseline by limiting how much adjacent points can differ
        // This prevents wild jumps in the curve
        let maxYDelta = estimatedUserFontSize * 0.5  // Max change per segment
        var smoothedPoints: [CGPoint] = [baselinePoints[0]]

        for i in 1..<baselinePoints.count {
            let prev = smoothedPoints[i - 1]
            var current = baselinePoints[i]

            // Limit how much Y can change from previous point
            let yDelta = current.y - prev.y
            if abs(yDelta) > maxYDelta {
                current.y = prev.y + (yDelta > 0 ? maxYDelta : -maxYDelta)
            }

            smoothedPoints.append(current)
        }

        return smoothedPoints
    }

    /// Cluster nearby strokes into occupied content regions
    /// Returns padded bounding rectangles for each content block
    func buildOccupiedRegions(from strokes: [PKStroke], padding: CGFloat = 25) -> [OccupiedRegion] {
        guard !strokes.isEmpty else { return [] }

        // Cluster strokes by overlapping padded bounding rects
        var rects = strokes.map { $0.renderBounds.insetBy(dx: -padding, dy: -padding) }
        var clusterIndices = Array(0..<strokes.count)  // Which cluster each stroke belongs to

        // Union-find style merge: group strokes whose padded rects overlap
        var didMerge = true
        while didMerge {
            didMerge = false
            for i in 0..<rects.count {
                for j in (i + 1)..<rects.count {
                    if clusterIndices[i] != clusterIndices[j] && rects[i].intersects(rects[j]) {
                        let oldCluster = clusterIndices[j]
                        let newCluster = clusterIndices[i]
                        rects[i] = rects[i].union(rects[j])
                        for k in 0..<clusterIndices.count {
                            if clusterIndices[k] == oldCluster {
                                clusterIndices[k] = newCluster
                            }
                        }
                        didMerge = true
                    }
                }
            }
        }

        // Group strokes by cluster
        var clusters: [Int: [Int]] = [:]
        for (i, cluster) in clusterIndices.enumerated() {
            clusters[cluster, default: []].append(i)
        }

        // Build convex hull per cluster from actual stroke control points
        var regions: [OccupiedRegion] = []
        for (_, strokeIndices) in clusters {
            var points: [CGPoint] = []
            for idx in strokeIndices {
                let stroke = strokes[idx]
                let path = stroke.path
                // Sample control points (every other for performance on dense strokes)
                let step = max(1, path.count / 30)
                for i in stride(from: 0, to: path.count, by: step) {
                    points.append(path[i].location)
                }
                // Always include last point
                if path.count > 1 {
                    points.append(path[path.count - 1].location)
                }
            }

            guard points.count >= 3 else { continue }

            let hull = OccupiedRegion.computeConvexHull(points: points)
            guard hull.count >= 3 else { continue }

            let padded = OccupiedRegion.padHull(hull, padding: padding)

            let xs = padded.map(\.x)
            let ys = padded.map(\.y)
            let bounds = CGRect(
                x: xs.min()!, y: ys.min()!,
                width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!
            )

            regions.append(OccupiedRegion(hull: padded, bounds: bounds))
        }

        return regions
    }

    /// Create a response baseline path offset below the user's text
    /// Ensures it doesn't collide with any occupied content regions on the canvas
    private func createResponseBaseline(
        userBaseline: [CGPoint],
        offset: CGFloat,
        occupiedRegions: [OccupiedRegion],
        startX: CGFloat,
        endX: CGFloat,
        defaultY: CGFloat
    ) -> [CGPoint] {
        // If no user baseline, create a simple horizontal line below all content
        guard !userBaseline.isEmpty else {
            var safeY = defaultY
            for region in occupiedRegions {
                if startX < region.bounds.maxX && endX > region.bounds.minX {
                    // Use hull's max Y at midpoint for tighter fit
                    let midX = (startX + endX) / 2
                    if let hullMaxY = region.maxYAtX(midX) {
                        let regionBottom = hullMaxY + 10
                        if safeY < regionBottom { safeY = regionBottom }
                    } else if safeY < region.bounds.maxY + 10 {
                        safeY = region.bounds.maxY + 10
                    }
                }
            }
            return [
                CGPoint(x: startX, y: safeY),
                CGPoint(x: endX, y: safeY)
            ]
        }

        // Flatten the user baseline to a single horizontal Y — use the max Y
        // so the response clears all user content, but doesn't follow any slant
        let flatY = userBaseline.map(\.y).max()! + offset

        var responsePath: [CGPoint] = [
            CGPoint(x: startX, y: flatY),
            CGPoint(x: endX, y: flatY)
        ]

        // Check occupied regions for collisions and push down if needed
        let safetyMargin: CGFloat = max(30, offset * 0.5)
        for i in 0..<responsePath.count {
            var point = responsePath[i]
            for region in occupiedRegions {
                if let hullMaxY = region.maxYAtX(point.x) {
                    let regionBottom = hullMaxY + safetyMargin
                    if point.y < regionBottom {
                        point.y = regionBottom
                    }
                }
            }
            responsePath[i] = point
        }

        return responsePath
    }

    // Pending message for iMessage compose sheet
    @Published var pendingMessage: (to: String, phone: String, body: String)?

    // Pending email for disambiguation (when multiple contacts match)
    private var pendingEmailData: (subject: String, body: String)?
    private var pendingEmailOptions: [(name: String, email: String)] = []

    private func handleCommand(_ command: String, response: AIResponse) async -> String? {
        switch command.lowercased() {
        case "settings":
            shouldShowSettings = true
            return nil
        case "clear":
            canvasView?.drawing = PKDrawing()
            lastRespondedStrokeIndex = 0
            userStrokeCount = 0
            conversationHistory = []
            pendingEmailData = nil
            pendingEmailOptions = []
            saveCurrentNotebook()
            return nil
        case "debug":
            showDebugOverlay.toggle()
            return nil
        case "screenshot", "screengrab":
            return await saveCanvasToPhotos()

        case "diary", "tom_riddle":
            tomRiddleMode.toggle()
            if tomRiddleMode {
                // Save current visual state before entering diary mode
                preRiddleSnapshot = ThemeSnapshot(
                    theme: currentTheme,
                    userInkColor: userInkColor,
                    responseColor: responseColor,
                    responseStrokeWidth: responseStrokeWidth
                )
                // Apply parchment theme (clears grid/paper, sets dark ink colors)
                applyTheme(.tomRiddle)
                // Fade user strokes into the page
                if let cv = canvasView {
                    fadeUserStrokesForDiary(canvasView: cv)
                }
            } else {
                // Restore previous visual state fully
                if let snap = preRiddleSnapshot {
                    applyTheme(snap.theme)
                    // applyTheme sets colors from theme defaults — override with exact saved values
                    userInkColor = snap.userInkColor
                    responseColor = snap.responseColor
                    responseStrokeWidth = snap.responseStrokeWidth
                    preRiddleSnapshot = nil
                }
                conversationHistory.removeAll()
            }
            return nil

        case "hue":
            return await handleHueCommand(response.hue)

        case "message":
            return await handleMessageCommand(response.message)

        case "email":
            return await handleEmailCommand(response.email)

        case "email_select":
            return await handleEmailSelection(response.text ?? "")

        case "reminder":
            return await handleReminderCommand(response.reminder)

        case "todo":
            return await handleTodoCommand(response.todo)

        case "calendar_event":
            return await handleCalendarCommand(response.calendarEvent)

        case "game_move":
            return await handleGameMove(response.gameMove, text: response.text)

        case "music":
            return await handleMusicCommand(response.music)

        case "theme":
            return handleThemeCommand(response.themeName)

        default:
            return nil
        }
    }

    // MARK: - Screenshot

    private func saveCanvasToPhotos() async -> String? {
        guard let canvasView = canvasView else { return "no canvas" }
        guard let image = ShareSheet.captureCanvas(canvasView: canvasView, includeWatermark: false) else {
            return "nothing to screenshot"
        }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    continuation.resume(returning: "photos permission needed")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, _ in
                    continuation.resume(returning: success ? "saved to photos!" : "couldn't save")
                }
            }
        }
    }

    // MARK: - Hue Commands

    private func handleHueCommand(_ hue: AIResponse.HueCommand?) async -> String? {
        guard let hue = hue else { return "couldn't understand that light command" }
        let service = HueService.shared

        switch hue.action.lowercased() {
        case "setup":
            do {
                let ip = try await service.discoverBridge()
                return "found hue bridge at \(ip)! press the button on the bridge, then write 'pair hue'"
            } catch HueError.noBridgeFound {
                return "no hue bridge found on your network"
            } catch {
                return "couldn't find a hue bridge — check your wifi"
            }

        case "pair":
            do {
                let _ = try await service.pair()
                return "paired! try writing 'lights off'"
            } catch HueError.buttonNotPressed {
                return "press the button on your hue bridge first, then write 'pair hue' again"
            } catch {
                return "pairing failed — try pressing the bridge button and write 'pair hue'"
            }

        default:
            guard service.isConfigured else {
                return "no hue bridge connected — write 'connect hue' to set up"
            }
            do {
                return try await service.execute(action: hue.action, brightness: hue.brightness, color: hue.color)
            } catch {
                return "couldn't control lights — \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Message Command

    private func handleMessageCommand(_ msg: AIResponse.MessageCommand?) async -> String? {
        guard let msg = msg else { return "couldn't understand that message" }

        let contact = await ContactService.shared.findContact(named: msg.to)
        if let contact = contact {
            // Set pending message for UI to present compose sheet
            pendingMessage = (to: contact.name, phone: contact.phone, body: msg.body)
            return "opening message to \(contact.name)..."
        } else {
            return "couldn't find '\(msg.to)' in your contacts"
        }
    }

    // MARK: - Email Command

    private func handleEmailCommand(_ email: AIResponse.EmailCommand?) async -> String? {
        guard let email = email else { return "couldn't understand that letter" }

        // Look up ALL matching contacts with email addresses
        let matches = await ContactService.shared.findAllContactEmails(named: email.to)

        if matches.isEmpty {
            return "couldn't find an email for '\(email.to)' in your contacts"
        } else if matches.count == 1 {
            // Single match — send automatically
            let contact = matches[0]
            let result = await EmailService.shared.sendEmail(
                to: contact.email,
                subject: email.subject,
                body: email.body
            )
            if result == "sent" {
                return "letter sent to \(contact.name)"
            } else {
                return result
            }
        } else {
            // Multiple matches — store pending and ask user to pick
            pendingEmailData = (subject: email.subject, body: email.body)
            pendingEmailOptions = matches
            var prompt = "found \(matches.count) contacts named \(email.to):\n"
            for (i, match) in matches.enumerated() {
                prompt += "\(i + 1). \(match.name) (\(match.email))\n"
            }
            prompt += "which one?"
            return prompt
        }
    }

    private func handleEmailSelection(_ selection: String) async -> String? {
        guard !pendingEmailOptions.isEmpty, let emailData = pendingEmailData else {
            return "no pending email to send"
        }

        // Try to parse as a number first
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var chosen: (name: String, email: String)?

        if let num = Int(trimmed), num >= 1 && num <= pendingEmailOptions.count {
            chosen = pendingEmailOptions[num - 1]
        } else {
            // Try name matching
            let lower = trimmed.lowercased()
            chosen = pendingEmailOptions.first { $0.name.lowercased().contains(lower) || $0.email.lowercased().contains(lower) }
        }

        guard let contact = chosen else {
            return "couldn't match that — pick a number 1-\(pendingEmailOptions.count)"
        }

        // Clear pending state
        let subject = emailData.subject
        let body = emailData.body
        pendingEmailData = nil
        pendingEmailOptions = []

        let result = await EmailService.shared.sendEmail(
            to: contact.email,
            subject: subject,
            body: body
        )
        if result == "sent" {
            return "letter sent to \(contact.name)"
        } else {
            return result
        }
    }

    // MARK: - Reminder Command

    private func handleReminderCommand(_ reminder: AIResponse.ReminderCommand?) async -> String? {
        guard let reminder = reminder else { return "couldn't understand that reminder" }

        do {
            return try await ReminderService.shared.createReminder(
                title: reminder.title,
                dateString: reminder.date,
                timeString: reminder.time
            )
        } catch ReminderError.accessDenied {
            return "need permission for reminders — check Settings > rite > Reminders"
        } catch {
            return "couldn't create reminder"
        }
    }

    // MARK: - Todo Command

    private func handleTodoCommand(_ todo: AIResponse.TodoCommand?) async -> String? {
        guard let todo = todo else { return "couldn't understand that list" }

        do {
            return try await ReminderService.shared.createTodoList(
                name: todo.listName,
                items: todo.items
            )
        } catch ReminderError.accessDenied {
            return "need permission for reminders — check Settings > rite > Reminders"
        } catch {
            return "couldn't create todo list"
        }
    }

    // MARK: - Calendar Command

    private func handleCalendarCommand(_ event: AIResponse.CalendarEventCommand?) async -> String? {
        guard let event = event else { return "couldn't understand that event" }

        do {
            return try await CalendarService.shared.createEvent(
                title: event.title,
                startString: event.start,
                endString: event.end,
                location: event.location
            )
        } catch CalendarError.accessDenied {
            return "need permission for calendar — check Settings > rite > Calendar"
        } catch CalendarError.invalidDate {
            return "couldn't understand that date/time"
        } catch {
            return "couldn't create event"
        }
    }

    // MARK: - Game Move

    private func handleGameMove(_ move: AIResponse.GameMoveCommand?, text: String?) async -> String? {
        guard let move = move, let canvasView = canvasView else { return text }

        let canvasWidth = canvasView.bounds.width
        let canvasHeight = canvasView.bounds.height
        let offsetY = canvasView.contentOffset.y

        isAnimatingResponse = true

        // Process draw instructions array
        if let draws = move.draws {
            for draw in draws {
                let p1 = CGPoint(
                    x: draw.x1 * canvasWidth,
                    y: draw.y1 * canvasHeight + offsetY
                )
                let size = CGFloat(draw.size ?? 40)

                switch draw.shape.lowercased() {
                case "circle", "o":
                    drawCircle(at: p1, size: size, on: canvasView)
                case "x":
                    drawX(at: p1, size: size, on: canvasView)
                case "line":
                    if let x2 = draw.x2, let y2 = draw.y2 {
                        let p2 = CGPoint(
                            x: x2 * canvasWidth,
                            y: y2 * canvasHeight + offsetY
                        )
                        drawLine(from: p1, to: p2, on: canvasView)
                    }
                case "dot":
                    drawDot(at: p1, size: size, on: canvasView)
                default:
                    break
                }

                // Small delay between shapes for visual effect
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }

        // Legacy single-shape fallback
        if move.draws == nil, let x = move.x, let y = move.y {
            let point = CGPoint(
                x: x * canvasWidth,
                y: y * canvasHeight + offsetY
            )
            let shape = move.shape?.lowercased() ?? "circle"
            switch shape {
            case "x":
                drawX(at: point, size: 40, on: canvasView)
            default:
                drawCircle(at: point, size: 40, on: canvasView)
            }
        }

        isAnimatingResponse = false
        return text
    }

    // MARK: - Music Command

    private func handleMusicCommand(_ music: AIResponse.MusicCommand?) async -> String? {
        guard let music = music else { return "couldn't understand that music command" }
        let spotify = SpotifyService.shared
        print("[MUSIC] isConnected=\(spotify.isConnected), action=\(music.action)")

        guard spotify.isConnected else {
            return "connect Spotify in settings first"
        }

        switch music.action.lowercased() {
        case "play", "resume": return await spotify.play()
        case "pause", "stop": return await spotify.pause()
        case "skip", "next": return await spotify.next()
        case "previous", "back": return await spotify.previous()
        case "volume_up", "louder": return await spotify.volumeUp()
        case "volume_down", "quieter": return await spotify.volumeDown()
        default: return "unknown music action"
        }
    }

    // MARK: - Theme Command

    private func handleThemeCommand(_ themeName: String?) -> String? {
        guard let name = themeName?.lowercased() else { return "couldn't understand that theme" }

        let theme: CanvasTheme
        switch name {
        case "paper": theme = .paper
        case "paperdark", "paper_dark": theme = .paperDark
        case "grid": theme = .grid
        case "griddark", "grid_dark": theme = .gridDark
        case "dotted": theme = .dotted
        case "dotteddark", "dotted_dark": theme = .dottedDark
        case "default", "defaultdark", "default_dark": theme = .defaultDark
        case "tomriddle", "tom_riddle", "riddle": theme = .tomRiddle
        default: return "unknown theme: \(name)"
        }

        applyTheme(theme)
        return "switched to \(theme.rawValue) theme"
    }

    // MARK: - Apply Theme

    func applyTheme(_ theme: CanvasTheme) {
        // Use the theme's canonical ink color (not userInkColor) — that's what updateUIView
        // actually passes to PKInkingTool, so it's what the strokes were physically drawn with.
        let oldThemeInkColor = currentTheme.userInkColor
        let oldTheme = currentTheme

        currentTheme = theme
        backgroundColor = theme.solidBackgroundColor
        userInkColor = theme.userInkColor
        responseColor = theme.responseColor

        // Apply background to canvas (pattern or solid)
        canvasView?.backgroundColor = theme.createBackgroundUIColor()

        // For light themes, use light interface style; for dark themes use light too
        // (we always use .light to prevent PencilKit color inversion)
        canvasView?.overrideUserInterfaceStyle = .light

        // Recolor existing user strokes when crossing the dark/light boundary
        // (e.g. white ink becomes invisible on white grid paper — fix it)
        // Skip for tomRiddle transitions — diary mode handles its own colors
        if theme != .tomRiddle && oldTheme != .tomRiddle && oldTheme.isDark != theme.isDark {
            recolorUserStrokes(from: oldThemeInkColor, to: theme.userInkColor)
        }
    }

    private func recolorUserStrokes(from oldColor: UIColor, to newColor: UIColor) {
        guard let canvasView = canvasView else { return }
        let drawing = canvasView.drawing
        guard !drawing.strokes.isEmpty else { return }

        // Luminance-based matching — avoids fragile exact-color comparison across color spaces.
        // We look for achromatic strokes (low saturation = not a colored AI response stroke)
        // whose brightness matches the old ink color.
        var oldR: CGFloat = 0, oldG: CGFloat = 0, oldB: CGFloat = 0, oldA: CGFloat = 0
        oldColor.getRed(&oldR, green: &oldG, blue: &oldB, alpha: &oldA)
        let oldLuminance = (oldR + oldG + oldB) / 3
        let lookingForLight = oldLuminance > 0.6   // dark→light: recolor white strokes

        var newStrokes = drawing.strokes
        var changed = false

        for i in 0..<newStrokes.count {
            let stroke = newStrokes[i]
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            stroke.ink.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let luminance = (r + g + b) / 3
            // Saturation: high = colored AI stroke (yellow, blue) — skip it
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let saturation = maxC > 0.001 ? (maxC - minC) / maxC : 0

            let isAchromatic = saturation < 0.25
            let matchesBrightness = lookingForLight ? luminance > 0.65 : luminance < 0.35

            if isAchromatic && matchesBrightness {
                let newInk = PKInk(stroke.ink.inkType, color: newColor)
                newStrokes[i] = PKStroke(ink: newInk, path: stroke.path, transform: stroke.transform, mask: stroke.mask)
                changed = true
            }
        }

        if changed {
            isAnimatingResponse = true
            var newDrawing = PKDrawing()
            newDrawing.strokes = newStrokes
            canvasView.drawing = newDrawing
            isAnimatingResponse = false
        }
    }

    // MARK: - Shape Drawing

    /// Draw a hand-drawn circle (hollow)
    private func drawCircle(at center: CGPoint, size: CGFloat, on canvasView: PKCanvasView) {
        let radius = size / 2
        let pointCount = 28
        var points: [PKStrokePoint] = []

        for i in 0...pointCount {
            let angle = CGFloat(i) / CGFloat(pointCount) * 2 * .pi
            let wobble = CGFloat.random(in: -1.5...1.5)
            let r = radius + wobble
            let px = center.x + r * cos(angle)
            let py = center.y + r * sin(angle)

            points.append(makeStrokePoint(x: px, y: py, timeOffset: TimeInterval(i) * 0.01))
        }

        addStrokeToCanvas(points: points, on: canvasView)
    }

    /// Draw a hand-drawn X mark
    private func drawX(at center: CGPoint, size: CGFloat, on canvasView: PKCanvasView) {
        let half = size / 2

        // First diagonal: top-left to bottom-right
        var stroke1Points: [PKStrokePoint] = []
        let steps = 12
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let wobble = CGFloat.random(in: -1.0...1.0)
            let px = center.x - half + t * size + wobble
            let py = center.y - half + t * size + wobble
            stroke1Points.append(makeStrokePoint(x: px, y: py, timeOffset: TimeInterval(i) * 0.01))
        }
        addStrokeToCanvas(points: stroke1Points, on: canvasView)

        // Second diagonal: top-right to bottom-left
        var stroke2Points: [PKStrokePoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let wobble = CGFloat.random(in: -1.0...1.0)
            let px = center.x + half - t * size + wobble
            let py = center.y - half + t * size + wobble
            stroke2Points.append(makeStrokePoint(x: px, y: py, timeOffset: TimeInterval(i) * 0.01))
        }
        addStrokeToCanvas(points: stroke2Points, on: canvasView)
    }

    /// Draw a hand-drawn line between two points
    private func drawLine(from start: CGPoint, to end: CGPoint, on canvasView: PKCanvasView) {
        let steps = 16
        var points: [PKStrokePoint] = []

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            // Slight wobble for hand-drawn feel
            let wobble = CGFloat.random(in: -0.8...0.8)
            let px = start.x + t * (end.x - start.x) + wobble
            let py = start.y + t * (end.y - start.y) + wobble
            points.append(makeStrokePoint(x: px, y: py, timeOffset: TimeInterval(i) * 0.01))
        }

        addStrokeToCanvas(points: points, on: canvasView)
    }

    /// Draw a filled dot
    private func drawDot(at center: CGPoint, size: CGFloat, on canvasView: PKCanvasView) {
        let radius = size / 3
        // Draw a small filled spiral to create a dot
        var points: [PKStrokePoint] = []
        let pointCount = 16

        for i in 0...pointCount {
            let angle = CGFloat(i) / CGFloat(pointCount) * 2 * .pi
            let r = radius * CGFloat(i) / CGFloat(pointCount)
            let px = center.x + r * cos(angle)
            let py = center.y + r * sin(angle)

            let point = PKStrokePoint(
                location: CGPoint(x: px, y: py),
                timeOffset: TimeInterval(i) * 0.01,
                size: CGSize(width: responseStrokeWidth * 2.5, height: responseStrokeWidth * 2.5),
                opacity: 1.0,
                force: 0.8,
                azimuth: 0,
                altitude: .pi / 2
            )
            points.append(point)
        }

        addStrokeToCanvas(points: points, on: canvasView)
    }

    private func makeStrokePoint(x: CGFloat, y: CGFloat, timeOffset: TimeInterval) -> PKStrokePoint {
        PKStrokePoint(
            location: CGPoint(x: x, y: y),
            timeOffset: timeOffset,
            size: CGSize(width: responseStrokeWidth * 1.2, height: responseStrokeWidth * 1.2),
            opacity: 1.0,
            force: 0.5,
            azimuth: 0,
            altitude: .pi / 2
        )
    }

    private func addStrokeToCanvas(points: [PKStrokePoint], on canvasView: PKCanvasView) {
        guard points.count >= 2 else { return }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let ink = PKInk(.pen, color: responseColor)
        let stroke = PKStroke(ink: ink, path: path)

        var drawing = canvasView.drawing
        drawing.strokes.append(stroke)
        canvasView.drawing = drawing
    }

    // MARK: - Tom Riddle Mode (Ink Bleed)

    /// Capture given strokes as a UIImage aligned to the visible canvas area
    private func captureStrokesForBleed(_ strokes: [PKStroke], canvasView: PKCanvasView) -> UIImage? {
        guard !strokes.isEmpty else { return nil }

        let bounds = canvasView.bounds
        let contentOffset = canvasView.contentOffset
        let visibleRect = CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: bounds.width,
            height: bounds.height
        )

        var tempDrawing = PKDrawing()
        tempDrawing.strokes = strokes

        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))

            let traitCollection = UITraitCollection(userInterfaceStyle: .light)
            traitCollection.performAsCurrent {
                let drawingImage = tempDrawing.image(from: visibleRect, scale: UIScreen.main.scale)
                drawingImage.draw(at: .zero)
            }
        }
    }

    /// Fade all visible strokes when AI starts processing (user text sinks into page)
    private func fadeUserStrokesForDiary(canvasView: PKCanvasView) {
        let allStrokes = canvasView.drawing.strokes
        guard !allStrokes.isEmpty else { return }
        guard let image = captureStrokesForBleed(allStrokes, canvasView: canvasView) else { return }

        isAnimatingResponse = true
        canvasView.drawing = PKDrawing()
        isAnimatingResponse = false

        lastRespondedStrokeIndex = 0
        inkBleedImage = image
    }

    /// Called from CanvasView when user starts drawing — fades AI strokes if in diary mode
    func fadeAIStrokesIfNeeded() {
        guard tomRiddleMode, hasPendingAIStrokes else { return }
        guard inkBleedImage == nil else { return }
        guard let canvasView = canvasView else { return }

        let drawing = canvasView.drawing
        let aiEndIndex = min(lastRespondedStrokeIndex, drawing.strokes.count)
        guard aiEndIndex > 0 else { return }

        // AI strokes to fade (everything up to lastRespondedStrokeIndex)
        let aiStrokes = Array(drawing.strokes[0..<aiEndIndex])
        // New user strokes to keep (anything the user just started drawing)
        let newUserStrokes = aiEndIndex < drawing.strokes.count
            ? Array(drawing.strokes[aiEndIndex...])
            : []

        guard let image = captureStrokesForBleed(aiStrokes, canvasView: canvasView) else { return }

        isAnimatingResponse = true
        var newDrawing = PKDrawing()
        newDrawing.strokes = newUserStrokes
        canvasView.drawing = newDrawing
        isAnimatingResponse = false

        lastRespondedStrokeIndex = 0
        userStrokeCount = newUserStrokes.count
        hasPendingAIStrokes = false

        inkBleedImage = image
    }

    private func scrollCanvasUp(by amount: CGFloat, canvasView: PKCanvasView) async {
        // Use proper content offset scrolling so user can scroll back up
        let startOffset = canvasView.contentOffset
        let targetOffset = CGPoint(x: startOffset.x, y: startOffset.y + amount)

        // Smooth scroll with ease-in-out animation
        let totalSteps = 30
        let duration: Double = 0.5 // seconds
        let stepDelay = UInt64(duration / Double(totalSteps) * 1_000_000_000)

        for step in 1...totalSteps {
            // Ease-in-out curve: slow start, fast middle, slow end
            let t = Double(step) / Double(totalSteps)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2

            let newY = startOffset.y + CGFloat(eased) * amount
            canvasView.contentOffset = CGPoint(x: startOffset.x, y: newY)

            try? await Task.sleep(nanoseconds: stepDelay)
        }

        // Ensure we end at exactly the target
        canvasView.contentOffset = targetOffset
    }

    private func animateResponse(
        text: String,
        userBounds: CGRect,
        fontSize: CGFloat,
        canvasView: PKCanvasView
    ) async {
        let screenWidth = canvasView.bounds.width
        let screenHeight = canvasView.bounds.height
        let margin: CGFloat = 60  // Comfortable margin from edges

        // Smart font sizing: scale relative to user's text but cap reasonably
        // Use a gentler multiplier when user text is small to avoid oversized responses
        let scaledSize = fontSize * responseSizeMultiplier
        let actualFontSize = min(max(scaledSize, 14), 36)

        // Use most of the screen width (with comfortable margins on both sides)
        let responseStartX = margin
        let responseEndX = screenWidth - margin
        let maxResponseWidth = responseEndX - responseStartX

        // Estimate how many chars fit in the available space
        let charWidth = actualFontSize * 0.55 + actualFontSize * 0.08
        let charsPerLine = Int(maxResponseWidth / charWidth)
        let lineHeight = actualFontSize * 1.5
        let availableHeight = screenHeight * 0.55  // Use ~55% of visible screen for response
        let maxLines = max(Int(availableHeight / lineHeight), 2)
        let charLimit = min(charsPerLine * maxLines, 200)

        // Limit text length based on available space, but truncate at sentence boundary
        var limitedText: String
        if text.count <= charLimit {
            limitedText = text
        } else {
            let truncated = String(text.prefix(charLimit))
            // Find the last sentence-ending punctuation within the limit
            if let lastSentenceEnd = truncated.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                limitedText = String(truncated[...lastSentenceEnd])
            } else {
                // No sentence end found — fall back to last space to avoid mid-word cut
                if let lastSpace = truncated.lastIndex(of: " ") {
                    limitedText = String(truncated[...lastSpace]).trimmingCharacters(in: .whitespaces) + "..."
                } else {
                    limitedText = truncated
                }
            }
        }

        // Extract baseline from user's text
        let userBaseline = extractBaselinePath(
            from: canvasView.drawing,
            userBounds: userBounds,
            screenWidth: screenWidth
        )

        // Calculate offset below user's text
        let responseOffset = actualFontSize * 1.2 + 20

        // Response Y position in content coordinates (below user's text)
        let responseY = userBounds.maxY + responseOffset

        // Check if we need to scroll - if response would be below visible area
        let currentOffset = canvasView.contentOffset.y
        let visibleBottom = currentOffset + screenHeight * 0.67
        if responseY > visibleBottom {
            // End the glow animation before scrolling
            lastRespondedStrokeIndex = userStrokeCount

            // Scroll so the response area is visible (in upper-middle of screen)
            let targetOffset = responseY - screenHeight * 0.4
            let scrollAmount = targetOffset - currentOffset
            await scrollCanvasUp(by: scrollAmount, canvasView: canvasView)
        }

        // Build occupied regions from ALL strokes on canvas
        let occupiedRegions = buildOccupiedRegions(from: canvasView.drawing.strokes)

        // Create response baseline with collision detection against occupied regions
        let responseBaseline = createResponseBaseline(
            userBaseline: userBaseline,
            offset: responseOffset,
            occupiedRegions: occupiedRegions,
            startX: responseStartX,
            endX: responseEndX,
            defaultY: responseY
        )

        // Adjust animation speed based on detected style
        let styleSpeedMultiplier = detectedStyle.parameters.speedMultiplier

        let handwriting = HandwritingGenerator(
            fontSize: actualFontSize,
            inkColor: responseColor,
            strokeWidth: responseStrokeWidth,
            maxWidth: maxResponseWidth,
            baselinePath: responseBaseline,
            style: detectedStyle,
            occupiedRegions: occupiedRegions
        )

        // Starting point: use first baseline point, or default based on user's text position
        let startPoint = responseBaseline.first ?? CGPoint(x: responseStartX, y: responseY)
        let strokes = handwriting.generateStrokes(for: limitedText, startingAt: startPoint)

        print("Animating \(strokes.count) strokes for text: \(limitedText)")

        // Set flag to prevent self-cancellation
        isAnimatingResponse = true

        // Calculate delay based on text animation speed and style
        // Base delay for natural handwriting feel (like someone is actually writing)
        let basePointDelay: UInt64 = 8_000_000 // 8ms per point for more natural writing
        let adjustedPointDelay = UInt64(Double(basePointDelay) / (textAnimationSpeed * styleSpeedMultiplier))

        // Animate each stroke by progressively adding points
        for (strokeIndex, stroke) in strokes.enumerated() {
            guard !Task.isCancelled else {
                print("Animation cancelled at stroke \(strokeIndex)")
                isAnimatingResponse = false
                return
            }

            let path = stroke.path
            let ink = stroke.ink
            let pointCount = path.count

            // Skip strokes with too few points
            guard pointCount >= 2 else {
                var drawing = canvasView.drawing
                drawing.strokes.append(stroke)
                canvasView.drawing = drawing
                continue
            }

            // Animate this stroke by adding points progressively
            for endIndex in 2...pointCount {
                guard !Task.isCancelled else {
                    isAnimatingResponse = false
                    return
                }

                // Create partial stroke with points 0..<endIndex
                var partialPoints: [PKStrokePoint] = []
                for i in 0..<endIndex {
                    partialPoints.append(path[i])
                }

                let partialPath = PKStrokePath(controlPoints: partialPoints, creationDate: Date())
                let partialStroke = PKStroke(ink: ink, path: partialPath)

                // Update drawing - remove previous partial and add new one
                var drawing = canvasView.drawing

                // If this isn't the first frame of this stroke, remove the previous partial
                if endIndex > 2 {
                    drawing.strokes.removeLast()
                }

                drawing.strokes.append(partialStroke)
                canvasView.drawing = drawing

                // Small delay between points for tracing effect
                try? await Task.sleep(nanoseconds: adjustedPointDelay)
            }
        }

        isAnimatingResponse = false

        // Update the responded stroke index to TOTAL strokes (including AI)
        // This ensures the glow only shows on NEW user input, not AI strokes
        lastRespondedStrokeIndex = canvasView.drawing.strokes.count

        // Tom Riddle mode: mark that AI strokes exist and should fade when user writes
        if tomRiddleMode {
            hasPendingAIStrokes = true
        }

        print("Animation complete")
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        if length == 6 {
            self.init(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else if length == 8 {
            self.init(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }

    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
