import SwiftUI
import PencilKit
import MessageUI

struct ContentView: View {
    let notebook: Notebook
    let notebookStore: NotebookStore
    let onBack: () -> Void

    @StateObject private var viewModel: CanvasViewModel
    @State private var showingSettings = false
    @State private var showingShare = false
    @State private var shareImage: UIImage?
    @State private var showingMessageCompose = false

    init(notebook: Notebook, notebookStore: NotebookStore, onBack: @escaping () -> Void) {
        self.notebook = notebook
        self.notebookStore = notebookStore
        self.onBack = onBack
        self._viewModel = StateObject(wrappedValue: CanvasViewModel(notebookStore: notebookStore))
    }

    var body: some View {
        ZStack {
            // Main canvas - fill entire screen (canvas provides its own background)
            CanvasView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            // Ink bleed overlay (Tom Riddle diary mode)
            if let bleedImage = viewModel.inkBleedImage {
                InkBleedOverlay(image: bleedImage) {
                    viewModel.inkBleedImage = nil
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }

            // Magic glow overlay on user's text while thinking
            MagicGlowOverlay(viewModel: viewModel)
                .allowsHitTesting(false)
                .ignoresSafeArea()


            // Settings panel
            if showingSettings {
                SettingsPanel(
                    viewModel: viewModel,
                    isPresented: $showingSettings,
                    onBack: {
                        viewModel.saveCurrentNotebook()
                        showingSettings = false
                        onBack()
                    },
                    onShare: {
                        showingSettings = false
                        shareCanvas()
                    }
                )
            }

            // Welcome overlay (shown when no API key is set)
            if viewModel.apiKey.isEmpty {
                WelcomeOverlay {
                    showingSettings = true
                }
            }

            // Debug overlay
            if viewModel.showDebugOverlay {
                DebugOverlayView(viewModel: viewModel, notebookStore: notebookStore)
                    .allowsHitTesting(false)
            }

            // RI Logo — bottom left
            VStack {
                Spacer()
                HStack {
                    Image("RILogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30)
                        .foregroundColor(.white)
                        .opacity(0.4)
                        .padding(.leading, 21)
                        .padding(.bottom, 21)
                    Spacer()
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // Error toast
            if let errorMessage = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(20)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { viewModel.errorMessage = nil }
                            }
                        }
                }
                .animation(.easeInOut, value: viewModel.errorMessage)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: viewModel.shouldShowSettings) { _, newValue in
            if newValue {
                showingSettings = true
                viewModel.shouldShowSettings = false
            }
        }
        .sheet(isPresented: $showingShare) {
            if let image = shareImage {
                ActivityViewController(
                    activityItems: [image],
                    applicationActivities: nil
                )
            }
        }
        .sheet(isPresented: $showingMessageCompose) {
            if let msg = viewModel.pendingMessage {
                MessageComposeView(
                    recipients: [msg.phone],
                    body: msg.body
                ) {
                    showingMessageCompose = false
                    viewModel.pendingMessage = nil
                }
            }
        }
        .onChange(of: viewModel.pendingMessage != nil) { _, hasPending in
            if hasPending && MFMessageComposeViewController.canSendText() {
                showingMessageCompose = true
            }
        }
        .onAppear {
            viewModel.loadNotebook(notebook)
        }
    }

    private func shareCanvas() {
        guard let canvasView = viewModel.canvasView else { return }

        // Save current notebook before sharing
        viewModel.saveCurrentNotebook()

        // Capture the visible canvas
        if let image = ShareSheet.captureCanvas(canvasView: canvasView) {
            shareImage = image
            showingShare = true
        }
    }
}

// MARK: - Style Indicator

struct StyleIndicator: View {
    let style: HandwritingStyle

    var body: some View {
        Text(style.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Welcome Overlay

struct WelcomeOverlay: View {
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Welcome to Penpal")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Tap here to add your API key, then write anything to start a conversation")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onTap)
        .frame(maxWidth: 320)
        .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height - 100)
    }
}

// MARK: - Settings Panel

struct SettingsPanel: View {
    @ObservedObject var viewModel: CanvasViewModel
    @Binding var isPresented: Bool
    var onBack: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var body: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .onTapGesture { isPresented = false }

        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    if let onBack = onBack {
                        Button(action: onBack) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.subheadline.weight(.semibold))
                                Text("Notebooks")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(0.08))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }

                    if let onShare = onShare {
                        Button(action: onShare) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                Text("Share")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(0.08))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }
                }

                SettingsSectionDivider()

                // API Key Section
                SettingsSectionHeader(title: "API Key", icon: "key")

                SecureField("Anthropic API key", text: $viewModel.apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                    .font(.system(.body, design: .monospaced))

                SettingsSectionDivider()

                // Email (Resend) Section
                SettingsSectionHeader(title: "Email (Resend)", icon: "envelope")

                SecureField("Resend API key", text: $viewModel.resendApiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                    .font(.system(.body, design: .monospaced))

                TextField("From email (e.g. you@yourdomain.com)", text: $viewModel.resendFromEmail)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                    .font(.system(.body, design: .monospaced))

                SettingsSectionDivider()

                // Pen Settings Section
                SettingsSectionHeader(title: "Pen Settings", icon: "pencil.tip")

                SettingsSlider(
                    title: "Pen Thickness",
                    value: $viewModel.penThickness,
                    range: 1...10,
                    format: "%.1f"
                )

                SettingsSectionDivider()

                // AI Response Section
                SettingsSectionHeader(title: "AI Response", icon: "sparkles")

                SettingsSlider(
                    title: "Response Size",
                    value: $viewModel.responseSize,
                    range: 12...72,
                    format: "%.0f"
                )

                SettingsSlider(
                    title: "AI Size Multiplier",
                    value: $viewModel.responseSizeMultiplier,
                    range: 0.3...1.5,
                    format: "%.1fx"
                )

                SettingsSlider(
                    title: "AI Pen Thickness",
                    value: $viewModel.responseStrokeWidth,
                    range: 0.5...5,
                    format: "%.1f"
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Response Verbosity")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f%%", viewModel.responseVerbosity * 100))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $viewModel.responseVerbosity, in: 0...1)
                }

                SettingsSectionDivider()

                // Timing Section
                SettingsSectionHeader(title: "Timing", icon: "clock")

                SettingsSlider(
                    title: "Pause Duration (sec)",
                    value: $viewModel.pauseDuration,
                    range: 0.5...6,
                    format: "%.1f"
                )

                SettingsSlider(
                    title: "Glow Animation Speed",
                    value: $viewModel.glowAnimationSpeed,
                    range: 0.25...4,
                    format: "%.2fx"
                )

                SettingsSlider(
                    title: "Text Writing Speed",
                    value: $viewModel.textAnimationSpeed,
                    range: 0.1...2,
                    format: "%.2fx"
                )

                SettingsSectionDivider()

                // Debug Section
                SettingsSectionHeader(title: "Debug", icon: "ladybug")

                Toggle("Show Occupied Regions", isOn: $viewModel.showOccupiedRegions)
                    .font(.subheadline)

                SettingsSectionDivider()

                // Spotify Section
                SpotifySettingsSection()

                SettingsSectionDivider()

                // Save Defaults Button
                Button(action: {
                    viewModel.saveAsDefaults()
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save as Defaults")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                Button("Close") {
                    isPresented = false
                }
                .foregroundColor(.secondary)

                // Version
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                Text("Penpal \(version) (\(build))")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(20)
        }
        .frame(maxWidth: 350, maxHeight: 700)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Spotify Settings Section

struct SpotifySettingsSection: View {
    @ObservedObject private var spotify = SpotifyService.shared
    @State private var diagResult: String? = nil
    @State private var diagRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Spotify", icon: "music.note")

            if spotify.isConnected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected")
                        .font(.subheadline)
                    Spacer()
                    Button("Disconnect") {
                        spotify.disconnect()
                    }
                    .font(.subheadline)
                    .foregroundColor(.red)
                }
                .padding(10)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(8)

                Button(action: {
                    diagRunning = true
                    Task {
                        let result = await spotify.runDiagnostic()
                        diagResult = result
                        diagRunning = false
                    }
                }) {
                    HStack {
                        if diagRunning {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "stethoscope")
                        }
                        Text(diagRunning ? "Running..." : "Diagnose")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
                }
                .disabled(diagRunning)

                if let result = diagResult {
                    ScrollView {
                        Text(result)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 220)
                    .background(Color.black.opacity(0.08))
                    .cornerRadius(8)

                    Button("Copy") {
                        UIPasteboard.general.string = result
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                TextField("Spotify Client ID", text: $spotify.clientId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                    .font(.system(.body, design: .monospaced))

                Button(action: { spotify.startAuth() }) {
                    HStack {
                        Image(systemName: "link")
                        Text("Connect Spotify")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(spotify.clientId.isEmpty ? Color.secondary.opacity(0.3) : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(spotify.clientId.isEmpty)

                Text("Get your Client ID from developer.spotify.com → Create App → set redirect URI to penpal://callback")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Settings Section Header

struct SettingsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - Settings Section Divider

struct SettingsSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

// MARK: - Settings Slider

struct SettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    init(title: String, value: Binding<CGFloat>, range: ClosedRange<Double>, format: String) {
        self.title = title
        self._value = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = CGFloat($0) }
        )
        self.range = range
        self.format = format
    }

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: format, value))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Debug Overlay

struct DebugOverlayView: View {
    @ObservedObject var viewModel: CanvasViewModel
    let notebookStore: NotebookStore

    private var totalStrokes: Int {
        viewModel.canvasView?.drawing.strokes.count ?? 0
    }

    private var aiStrokes: Int {
        max(totalStrokes - viewModel.userStrokeCount, 0)
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    debugRow("State", value: stateString)
                    debugRow("Strokes", value: "\(totalStrokes) total, \(viewModel.userStrokeCount) user, \(aiStrokes) AI")
                    debugRow("Last responded", value: "\(viewModel.lastRespondedStrokeIndex)")
                    debugRow("Style", value: viewModel.detectedStyle.displayName)
                    debugRow("Font size", value: String(format: "%.1f", viewModel.estimatedUserFontSize))
                    debugRow("Notebook", value: notebookStore.currentNotebook?.name ?? "—")
                    debugRow("Auto-save", value: "5s timer")
                    debugRow("API key", value: viewModel.apiKey.isEmpty ? "not set" : "set (\(viewModel.apiKey.prefix(8))...)")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .padding(.trailing, 16)
                .padding(.top, 60)
            }
            Spacer()
        }
    }

    private var stateString: String {
        switch viewModel.processingState {
        case .idle: return "idle"
        case .thinking: return "thinking"
        case .writing: return "writing"
        }
    }

    private func debugRow(_ label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .foregroundColor(.white.opacity(0.6))
            Text(": ")
                .foregroundColor(.white.opacity(0.4))
            Text(value)
        }
    }
}

// MARK: - Ink Bleed Overlay (Tom Riddle diary effect)

struct InkBleedOverlay: View {
    let image: UIImage
    let onComplete: () -> Void

    @State private var blur: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 1.0
    @State private var warmth: Double = 0

    var body: some View {
        Image(uiImage: image)
            .blur(radius: blur)
            .scaleEffect(scale)
            .opacity(opacity)
            // Warm tint as ink "ages" before absorbing
            .overlay(
                Color(red: 0.4, green: 0.25, blue: 0.1)
                    .opacity(warmth)
                    .blendMode(.multiply)
            )
            .onAppear {
                // Phase 1: Ink starts soaking — slight spread, warm tint (0-0.5s)
                withAnimation(.easeIn(duration: 0.5)) {
                    blur = 3
                    scale = 1.015
                    warmth = 0.15
                }

                // Phase 2: Ink bleeds into paper — heavy diffuse, fading (0.5-1.3s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeIn(duration: 0.8)) {
                        blur = 12
                        scale = 1.04
                        opacity = 0.2
                        warmth = 0.3
                    }
                }

                // Phase 3: Fully absorbed — gone (1.3-1.7s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        blur = 20
                        opacity = 0
                        warmth = 0
                    }
                }

                // Cleanup
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    onComplete()
                }
            }
    }
}

// MARK: - Message Compose View

struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.onDismiss()
            }
        }
    }
}

