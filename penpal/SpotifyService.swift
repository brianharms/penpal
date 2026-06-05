import Foundation
import CryptoKit
import UIKit
import AuthenticationServices
import SpotifyiOS

@MainActor
class SpotifyService: NSObject, ObservableObject {
    static let shared = SpotifyService()

    @Published var isConnected = false
    var hasAccessToken: Bool { accessToken != nil }

    var clientId: String = "" {
        didSet { KeychainHelper.save(clientId, forKey: "spotify_client_id") }
    }

    private let redirectURI = "penpal://callback"
    private let scopes = "user-modify-playback-state user-read-playback-state app-remote-control"
    private var codeVerifier: String = ""
    private var authSession: ASWebAuthenticationSession?
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    // MARK: - App Remote
    private var appRemote: SPTAppRemote?
    private var pendingCommand: (() -> Void)?
    private var pendingContinuation: CheckedContinuation<String, Never>?
    private(set) var lastConnectionError: String = "none yet"

    private override init() {
        clientId = KeychainHelper.load(forKey: "spotify_client_id") ?? "YOUR_SPOTIFY_CLIENT_ID"
        codeVerifier = KeychainHelper.load(forKey: "spotify_code_verifier") ?? ""
        accessToken = KeychainHelper.load(forKey: "spotify_access_token")
        refreshToken = KeychainHelper.load(forKey: "spotify_refresh_token")
        if let expiryStr = KeychainHelper.load(forKey: "spotify_token_expiry"),
           let expiryInterval = Double(expiryStr) {
            tokenExpiry = Date(timeIntervalSince1970: expiryInterval)
        }
        isConnected = refreshToken != nil
    }

    // MARK: - App Remote Setup

    private func buildAppRemote(with token: String) -> SPTAppRemote {
        let config = SPTConfiguration(clientID: clientId, redirectURL: URL(string: redirectURI)!)
        let remote = SPTAppRemote(configuration: config, logLevel: .none)
        remote.connectionParameters.accessToken = token
        remote.delegate = self
        return remote
    }

    /// Called from penpalApp.onOpenURL when Spotify returns the App Remote access token.
    func handleAppRemoteURL(_ url: URL) {
        guard let remote = appRemote else { return }
        if let params = remote.authorizationParameters(from: url),
           let token = params[SPTAppRemoteAccessTokenKey] {
            remote.connectionParameters.accessToken = token
            remote.connect()
        }
    }

    /// Connect, execute a player command, return a result string.
    private func executeCommand(success: String, command: @escaping (SPTAppRemotePlayerAPI) -> Void) async -> String {
        guard let token = await validToken() else { return "token expired — reconnect Spotify" }
        guard !clientId.isEmpty else { return "Spotify client ID missing" }

        // Always rebuild to avoid stale disconnected state
        appRemote?.disconnect()
        appRemote = buildAppRemote(with: token)

        // Already connected — fire immediately
        if appRemote?.isConnected == true {
            if let api = appRemote?.playerAPI {
                command(api)
            }
            return success
        }

        // Cancel any previous pending call
        pendingContinuation?.resume(returning: "cancelled")
        pendingContinuation = nil
        pendingCommand = nil

        return await withCheckedContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(returning: "internal error")
                return
            }
            self.pendingContinuation = continuation
            self.pendingCommand = { [weak self] in
                if let api = self?.appRemote?.playerAPI {
                    command(api)
                }
                continuation.resume(returning: success)
                self?.pendingContinuation = nil
            }
            // connect() performs silent IPC — no Spotify foreground needed.
            // Requires a token with app-remote-control scope (obtained via PKCE re-auth).
            self.appRemote?.connect()
        }
    }

    // MARK: - Playback

    func play() async -> String {
        let result = await executeCommand(success: "playing") { api in api.resume(nil) }
        if result == "playing" { return result }
        // Spotify was suspended by iOS — wake it via URL scheme (will briefly flash Spotify)
        let wakeToken = await validToken()
        guard let token = wakeToken, !clientId.isEmpty else { return "playing" }
        appRemote?.disconnect()
        appRemote = buildAppRemote(with: token)
        await appRemote?.authorizeAndPlayURI("")
        return "playing"
    }

    func pause() async -> String {
        let result = await executeCommand(success: "paused") { api in api.pause(nil) }
        return result == "paused" ? result : "already paused"
    }

    func next() async -> String {
        let result = await executeCommand(success: "skipped") { api in api.skip(toNext: nil) }
        return result == "skipped" ? result : "spotify isn't playing"
    }

    func previous() async -> String {
        let result = await executeCommand(success: "going back") { api in api.skip(toPrevious: nil) }
        return result == "going back" ? result : "spotify isn't playing"
    }

    func volumeUp() async -> String {
        return await adjustVolume(by: 15)
    }

    func volumeDown() async -> String {
        return await adjustVolume(by: -15)
    }

    private func adjustVolume(by delta: Int) async -> String {
        guard let token = await validToken() else { return "not connected to Spotify" }
        var stateReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        stateReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: stateReq),
              let json = try? JSONDecoder().decode(PlayerState.self, from: data)
        else { return "couldn't get volume" }
        let newVol = max(0, min(100, json.device.volume_percent + delta))
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/volume?volume_percent=\(newVol)")!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
        return delta > 0 ? "volume up (\(newVol)%)" : "volume down (\(newVol)%)"
    }

    // MARK: - PKCE Auth

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func startAuth() {
        guard !clientId.isEmpty else { return }
        codeVerifier = generateCodeVerifier()
        KeychainHelper.save(codeVerifier, forKey: "spotify_code_verifier")
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: codeChallenge(for: codeVerifier)),
            .init(name: "state", value: UUID().uuidString),
        ]
        guard let url = components.url else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "penpal") { [weak self] callbackURL, error in
            if let error = error {
                print("[SPOTIFY] Auth session error: \(error)")
                return
            }
            guard let callbackURL = callbackURL else { return }
            Task { await self?.handleCallback(url: callbackURL) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func handleCallback(url: URL) async {
        guard url.scheme == "penpal",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        await exchangeCode(code)
    }

    private func exchangeCode(_ code: String) async {
        guard !clientId.isEmpty else { return }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "client_id", value: clientId),
            .init(name: "code_verifier", value: codeVerifier),
        ]
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)
        do {
            let (data, res) = try await URLSession.shared.data(for: request)
            let status = (res as? HTTPURLResponse)?.statusCode ?? 0
            print("[SPOTIFY] code exchange status: \(status)")
            if status != 200 {
                print("[SPOTIFY] code exchange error: \(String(data: data, encoding: .utf8) ?? "no body")")
                return
            }
            let json = try JSONDecoder().decode(TokenResponse.self, from: data)
            store(json)
        } catch {
            print("[SPOTIFY] code exchange error: \(error)")
        }
    }

    private func refreshAccessToken() async {
        guard !clientId.isEmpty, let refresh = refreshToken else { return }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refresh)",
            "client_id=\(clientId)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        do {
            let (data, res) = try await URLSession.shared.data(for: request)
            let status = (res as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                print("[SPOTIFY] refresh error \(status): \(String(data: data, encoding: .utf8) ?? "no body")")
            }
            let json = try JSONDecoder().decode(TokenResponse.self, from: data)
            store(json)
            print("[SPOTIFY] refresh succeeded")
        } catch {
            print("[SPOTIFY] refresh error: \(error)")
            accessToken = nil
            tokenExpiry = nil
            isConnected = false
        }
    }

    private func store(_ response: TokenResponse) {
        accessToken = response.access_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(response.expires_in - 60))
        KeychainHelper.save(response.access_token, forKey: "spotify_access_token")
        KeychainHelper.save(String(tokenExpiry!.timeIntervalSince1970), forKey: "spotify_token_expiry")
        if let refresh = response.refresh_token {
            refreshToken = refresh
            KeychainHelper.save(refresh, forKey: "spotify_refresh_token")
        }
        codeVerifier = ""
        KeychainHelper.delete(forKey: "spotify_code_verifier")
        isConnected = true
    }

    private func validToken() async -> String? {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
        await refreshAccessToken()
        return accessToken
    }

    // MARK: - Diagnostic

    func runDiagnostic() async -> String {
        var lines: [String] = []
        lines.append("=== SPOTIFY DIAGNOSTIC ===")
        lines.append("Time: \(Date())")
        lines.append("")

        if let expiry = tokenExpiry {
            let remaining = Int(expiry.timeIntervalSinceNow)
            lines.append("Token: \(accessToken != nil ? "present" : "nil")")
            lines.append("Expiry: \(remaining > 0 ? "\(remaining)s remaining" : "EXPIRED \(-remaining)s ago")")
        } else {
            lines.append("Token: \(accessToken != nil ? "present (no expiry stored)" : "nil")")
        }
        lines.append("Refresh token: \(refreshToken != nil ? "present" : "nil")")
        lines.append("clientId: \(clientId.isEmpty ? "MISSING" : "\(clientId.prefix(8))...")")
        lines.append("")
        lines.append("NOTE: If you haven't disconnected + reconnected since")
        lines.append("the last update, do that now to get app-remote-control scope.")
        lines.append("")

        guard let token = await validToken() else {
            lines.append("validToken() returned nil — cannot proceed")
            return lines.joined(separator: "\n")
        }
        lines.append("validToken(): OK")
        lines.append("")

        // --- App Remote connect test ---
        lines.append("Testing App Remote (Spotify must be running)...")
        let connectResult = await executeCommand(success: "CONNECTED ✓") { _ in /* no-op */ }
        lines.append("App Remote: \(connectResult)")
        if connectResult != "CONNECTED ✓" {
            lines.append("Last SDK error: \(lastConnectionError)")
        }
        lines.append("")

        // --- Web API checks ---
        var meReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        meReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (meData, meRes) = try? await URLSession.shared.data(for: meReq) {
            let status = (meRes as? HTTPURLResponse)?.statusCode ?? 0
            lines.append("/me status: \(status)")
            if let json = try? JSONSerialization.jsonObject(with: meData) as? [String: Any] {
                lines.append("  email: \(json["email"] ?? "n/a")")
                lines.append("  product: \(json["product"] ?? "n/a")")
            }
        } else {
            lines.append("/me: network error")
        }
        lines.append("")

        var playerReq = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        playerReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (playerData, playerRes) = try? await URLSession.shared.data(for: playerReq) {
            let status = (playerRes as? HTTPURLResponse)?.statusCode ?? 0
            lines.append("/me/player status: \(status)")
            if status == 204 {
                lines.append("  (204 = no active player)")
            } else if let json = try? JSONSerialization.jsonObject(with: playerData) as? [String: Any] {
                lines.append("  is_playing: \(json["is_playing"] ?? "n/a")")
                if let device = json["device"] as? [String: Any] {
                    lines.append("  device: \(device["name"] ?? "n/a") (\(device["type"] ?? "n/a"))")
                }
            }
        } else {
            lines.append("/me/player: network error")
        }

        return lines.joined(separator: "\n")
    }

    func disconnect() {
        appRemote?.disconnect()
        appRemote = nil
        accessToken = nil; refreshToken = nil; tokenExpiry = nil; isConnected = false
        KeychainHelper.delete(forKey: "spotify_access_token")
        KeychainHelper.delete(forKey: "spotify_refresh_token")
        KeychainHelper.delete(forKey: "spotify_token_expiry")
    }

    // MARK: - Models

    private struct TokenResponse: Codable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    private struct PlayerState: Codable {
        let device: DeviceState
        struct DeviceState: Codable { let volume_percent: Int }
    }
}

// MARK: - SPTAppRemoteDelegate

extension SpotifyService: @preconcurrency SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        print("[SPOTIFY] App Remote connected")
        appRemote.playerAPI?.delegate = self
        let cmd = pendingCommand
        pendingCommand = nil
        cmd?()
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let desc = error.map { "\($0)" } ?? "nil error"
        lastConnectionError = desc
        print("[SPOTIFY] Connection failed: \(desc)")
        pendingCommand = nil
        pendingContinuation?.resume(returning: "connection failed — spotify may be closed or token missing app-remote-control scope")
        pendingContinuation = nil
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        print("[SPOTIFY] Disconnected: \(error?.localizedDescription ?? "clean")")
    }
}

// MARK: - SPTAppRemotePlayerStateDelegate

extension SpotifyService: @preconcurrency SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        // State updates available here if needed
    }
}

// MARK: - ASWebAuthenticationSession presentation

extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return UIWindow() }
        return window
    }
}
