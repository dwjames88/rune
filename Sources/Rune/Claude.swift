import Foundation
import Security

/// Minimal Anthropic Messages API client over raw HTTP (no SDK exists for Swift,
/// and zero dependencies is a project rule). The API key lives in the macOS
/// Keychain — it is never written to Rune's JSON settings.
///
/// One of two `AIProvider`s. Nothing in the app talks to this directly any
/// more; it goes through `AIService`, which decides whether Claude or the local
/// model answers.
@MainActor
final class ClaudeService: ObservableObject, AIProvider {
    static let model = "claude-sonnet-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    @Published var hasKey: Bool = Keychain.read() != nil

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { Keychain.delete() } else { Keychain.write(trimmed) }
        hasKey = Keychain.read() != nil
    }

    // MARK: Request building

    private func request(body: [String: Any], stream: Bool) throws -> URLRequest {
        guard let key = Keychain.read() else { throw ClaudeError.noKey }
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var body = body
        body["model"] = Self.model
        if stream { body["stream"] = true }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// One-shot completion. `effort` trades depth for latency (low | medium | high).
    /// Thinking is disabled here: Sonnet 5 runs adaptive thinking by default, which
    /// is too slow for ambient UI like a hover popover.
    func complete(system: String, user: String, maxTokens: Int = 400,
                  effort: AIEffort = .low) async throws -> String {
        let req = try request(body: [
            "max_tokens": maxTokens,
            "system": system,
            "thinking": ["type": "disabled"],
            "output_config": ["effort": effort.rawValue],
            "messages": [["role": "user", "content": user]],
        ], stream: false)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard http.statusCode == 200 else {
            throw ClaudeError.api(Self.errorMessage(from: data, status: http.statusCode))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.badResponse
        }
        // Always check stop_reason before reading content — a refusal returns 200
        // with an empty content array.
        if json["stop_reason"] as? String == "refusal" { throw ClaudeError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        guard !text.isEmpty else { throw ClaudeError.empty }
        return text.joined()
    }

    /// Streaming completion — used by the Ask bar so answers appear as they're written.
    func stream(system: String, user: String, maxTokens: Int = 1024,
                effort: AIEffort = .medium) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let req = try request(body: [
                        "max_tokens": maxTokens,
                        "system": system,
                        "thinking": ["type": "disabled"],
                        "output_config": ["effort": effort.rawValue],
                        "messages": [["role": "user", "content": user]],
                    ], stream: true)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw ClaudeError.api("HTTP \(status)")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if event["type"] as? String == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           delta["type"] as? String == "text_delta",
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "HTTP \(status)"
    }
}

enum ClaudeError: LocalizedError {
    case noKey, badResponse, empty, refused
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "Add your Anthropic API key in Settings ▸ Claude."
        case .badResponse: "Unexpected response from the API."
        case .empty: "Claude returned no text."
        case .refused: "Claude declined this request."
        case .api(let message): message
        }
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.dwjames.Rune"
    private static let account = "anthropic-api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    static func write(_ key: String) {
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
