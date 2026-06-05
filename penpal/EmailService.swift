import Foundation

class EmailService {
    static let shared = EmailService()

    /// Send an email via Resend API. Returns a confirmation string or error message.
    func sendEmail(
        to: String,
        subject: String,
        body: String,
        fromName: String = "Magic Notebook"
    ) async -> String {
        guard let apiKey = KeychainHelper.load(forKey: "resend_api_key"), !apiKey.isEmpty else {
            return "no Resend API key — add one in settings"
        }
        guard let fromAddress = KeychainHelper.load(forKey: "resend_from_email"), !fromAddress.isEmpty else {
            return "no from address — add one in settings"
        }

        let url = URL(string: "https://api.resend.com/emails")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "from": "\(fromName) <\(fromAddress)>",
            "to": [to],
            "subject": subject,
            "text": body
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            return "failed to build email"
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return "sent"
            } else {
                let errorText = String(data: data, encoding: .utf8) ?? "unknown error"
                print("Resend error: \(errorText)")
                return "email failed to send"
            }
        } catch {
            print("Email send error: \(error)")
            return "couldn't reach Resend — check your connection"
        }
    }
}
