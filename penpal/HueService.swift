import Foundation

/// Philips Hue bridge integration via local HTTP API (v1)
class HueService {
    static let shared = HueService()

    private let bridgeIPKey = "hue_bridge_ip"
    private let bridgeUserKey = "hue_bridge_username"

    var bridgeIP: String? {
        get { KeychainHelper.load(forKey: bridgeIPKey) }
        set {
            if let v = newValue { KeychainHelper.save(v, forKey: bridgeIPKey) }
        }
    }

    var bridgeUsername: String? {
        get { KeychainHelper.load(forKey: bridgeUserKey) }
        set {
            if let v = newValue { KeychainHelper.save(v, forKey: bridgeUserKey) }
        }
    }

    var isConfigured: Bool {
        bridgeIP != nil && bridgeUsername != nil
    }

    // MARK: - Discovery

    /// Discover Hue bridge via meethue.com cloud endpoint
    func discoverBridge() async throws -> String {
        guard let url = URL(string: "https://discovery.meethue.com") else {
            throw HueError.discoveryFailed
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let bridges = try JSONDecoder().decode([HueBridgeDiscovery].self, from: data)

        guard let first = bridges.first else {
            throw HueError.noBridgeFound
        }

        bridgeIP = first.internalipaddress
        return first.internalipaddress
    }

    // MARK: - Authentication

    /// Pair with bridge — user must press the bridge button first
    func pair() async throws -> String {
        guard let ip = bridgeIP else {
            throw HueError.noBridgeFound
        }

        guard let url = URL(string: "http://\(ip)/api") else {
            throw HueError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["devicetype": "rite#ipad"])

        let (data, _) = try await URLSession.shared.data(for: request)
        let results = try JSONDecoder().decode([HueAuthResponse].self, from: data)

        if let success = results.first?.success {
            bridgeUsername = success.username
            return success.username
        }

        if let error = results.first?.error {
            if error.type == 101 {
                throw HueError.buttonNotPressed
            }
            throw HueError.authError(error.description)
        }

        throw HueError.authError("Unknown error")
    }

    // MARK: - Light Control

    /// Control all lights at once via group 0
    func setAllLights(on: Bool? = nil, brightness: Int? = nil, hue: Int? = nil, saturation: Int? = nil) async throws {
        guard let ip = bridgeIP, let user = bridgeUsername else {
            throw HueError.notConfigured
        }

        guard let url = URL(string: "http://\(ip)/api/\(user)/groups/0/action") else {
            throw HueError.invalidURL
        }

        var body: [String: Any] = [:]
        if let on = on { body["on"] = on }
        if let brightness = brightness { body["bri"] = min(max(brightness, 0), 254) }
        if let hue = hue { body["hue"] = min(max(hue, 0), 65535) }
        if let saturation = saturation { body["sat"] = min(max(saturation, 0), 254) }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    /// Execute a parsed hue command
    func execute(action: String, brightness: Int? = nil, color: String? = nil) async throws -> String {
        switch action.lowercased() {
        case "on":
            try await setAllLights(on: true)
            return "lights on!"
        case "off":
            try await setAllLights(on: false)
            return "lights off!"
        case "dim":
            let bri = brightness ?? 50
            try await setAllLights(on: true, brightness: bri)
            return "dimmed to \(Int(Double(bri) / 254.0 * 100))%"
        case "brighten", "bright", "full":
            try await setAllLights(on: true, brightness: 254)
            return "full brightness!"
        default:
            // Try color
            if let (h, s) = parseHueColor(action.lowercased()) ?? parseHueColor(color?.lowercased() ?? "") {
                try await setAllLights(on: true, brightness: 254, hue: h, saturation: s)
                return "color set!"
            }
            // Try percentage brightness
            if let pct = Int(action.replacingOccurrences(of: "%", with: "")) {
                let bri = Int(Double(pct) / 100.0 * 254.0)
                try await setAllLights(on: true, brightness: bri)
                return "set to \(pct)%"
            }
            return "done!"
        }
    }

    private func parseHueColor(_ name: String) -> (hue: Int, saturation: Int)? {
        switch name {
        case "red": return (0, 254)
        case "orange": return (5000, 254)
        case "yellow": return (10000, 254)
        case "green": return (25500, 254)
        case "blue": return (46920, 254)
        case "purple": return (50000, 254)
        case "pink": return (56100, 200)
        case "white": return (0, 0)
        case "warm", "warm white": return (8000, 140)
        case "cool", "cool white": return (34000, 50)
        default: return nil
        }
    }
}

// MARK: - Models

struct HueBridgeDiscovery: Codable {
    let id: String
    let internalipaddress: String
}

struct HueAuthResponse: Codable {
    let success: HueAuthSuccess?
    let error: HueAuthError?
}

struct HueAuthSuccess: Codable {
    let username: String
}

struct HueAuthError: Codable {
    let type: Int
    let address: String?
    let description: String
}

enum HueError: Error {
    case discoveryFailed
    case noBridgeFound
    case invalidURL
    case buttonNotPressed
    case authError(String)
    case notConfigured
    case controlFailed(String)
}
