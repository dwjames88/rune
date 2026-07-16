import Combine
import Foundation
import FoundationModels

// MARK: - What Rune asks of a model

/// How hard to think. Claude spends this on output effort; the local model has
/// no such dial and ignores it.
enum AIEffort: String {
    case low, medium, high
}

/// Everything Rune needs a model to do. Nothing above this layer knows — or can
/// ask — which model answered, which is the whole point: every AI feature is
/// written once and runs on whatever is available.
@MainActor
protocol AIProvider {
    func complete(system: String, user: String, maxTokens: Int, effort: AIEffort) async throws -> String
    /// Yields the *new* text each time, not the whole answer so far.
    func stream(system: String, user: String, maxTokens: Int, effort: AIEffort) -> AsyncThrowingStream<String, Error>
}

/// Which model runs Rune's AI. On-device is the default: free, private, offline,
/// instant, no account. Claude is the upgrade you opt into.
enum AIModel: String, Codable, CaseIterable, Identifiable {
    case onDevice, claude
    var id: String { rawValue }
    var label: String {
        switch self {
        case .onDevice: "On-device"
        case .claude: "Claude"
        }
    }
    var detail: String {
        switch self {
        case .onDevice: "Apple Intelligence. Private, offline, free."
        case .claude: "Sharper answers. Needs an API key and a connection."
        }
    }
}

enum AIError: LocalizedError {
    case unavailable
    var errorDescription: String? {
        "No model to answer with. Turn on Apple Intelligence, or add a Claude API key in Settings ▸ AI."
    }
}

// MARK: - Apple's on-device model

/// The local model, and Rune's default. It runs offline, costs nothing, and the
/// page never leaves the Mac — which for a browser is the whole argument.
@available(macOS 26, *)
struct LocalModelProvider: AIProvider {
    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    /// Why it can't run, in words worth showing someone.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is turned off in System Settings."
        case .unavailable(.modelNotReady): "The on-device model is still downloading."
        case .unavailable: "The on-device model isn't available right now."
        }
    }

    /// A fresh session per call: Rune's AI is one-shot everywhere — a hover
    /// summary must not remember the last page you hovered.
    private func session(_ system: String) -> LanguageModelSession {
        LanguageModelSession(instructions: system)
    }

    func complete(system: String, user: String, maxTokens: Int, effort: AIEffort) async throws -> String {
        try await session(system)
            .respond(to: user, options: GenerationOptions(maximumResponseTokens: maxTokens))
            .content
    }

    func stream(system: String, user: String, maxTokens: Int, effort: AIEffort) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // The framework re-sends the whole answer so far on every
                    // tick; Rune's contract is the new part only, the way Claude
                    // sends it. Diff instead of re-sending, or the ask bar would
                    // print the answer once per token.
                    var emitted = ""
                    let responses = session(system)
                        .streamResponse(to: user, options: GenerationOptions(maximumResponseTokens: maxTokens))
                    for try await snapshot in responses {
                        let text = snapshot.content
                        guard text.hasPrefix(emitted) else { emitted = text; continue }
                        continuation.yield(String(text.dropFirst(emitted.count)))
                        emitted = text
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - The one thing the app asks

/// Rune's AI, whichever model is behind it. Owns the choice, hides the
/// difference, and answers the only question the UI really has: is there any
/// AI here at all?
///
/// When there isn't — an old macOS with no key, or a Mac that can't run Apple
/// Intelligence and hasn't paid for Claude — every AI affordance disappears
/// rather than sitting there greyed out. Nobody gets shown a feature they
/// can't use.
@MainActor
final class AIService: ObservableObject {
    let claude: ClaudeService
    private let settings: SettingsStore
    private var cancellables: Set<AnyCancellable> = []

    init(claude: ClaudeService, settings: SettingsStore) {
        self.claude = claude
        self.settings = settings
        // Availability is computed from these two, so anything watching this
        // service has to hear about a new key or a changed setting.
        claude.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Can Apple's model actually run here: macOS 26+, an eligible Mac, Apple
    /// Intelligence switched on, model downloaded.
    var localAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return LocalModelProvider.isAvailable
    }

    var localUnavailableReason: String? {
        guard #available(macOS 26, *) else { return "The on-device model needs macOS 26 or later." }
        return LocalModelProvider.unavailableReason
    }

    /// Any AI at all.
    var isAvailable: Bool { localAvailable || claude.hasKey }

    /// Which model will actually answer. Honours the setting, but falls back
    /// rather than failing: asking for on-device on an older Mac still works if
    /// you have a key, and asking for Claude without one still works locally.
    var active: AIModel? {
        switch settings.aiModel {
        case .onDevice: localAvailable ? .onDevice : (claude.hasKey ? .claude : nil)
        case .claude: claude.hasKey ? .claude : (localAvailable ? .onDevice : nil)
        }
    }

    private func provider() throws -> any AIProvider {
        switch active {
        case .onDevice:
            guard #available(macOS 26, *) else { throw AIError.unavailable }
            return LocalModelProvider()
        case .claude:
            return claude
        case nil:
            throw AIError.unavailable
        }
    }

    func complete(system: String, user: String, maxTokens: Int = 400,
                  effort: AIEffort = .low) async throws -> String {
        try await provider().complete(system: system, user: user, maxTokens: maxTokens, effort: effort)
    }

    func stream(system: String, user: String, maxTokens: Int = 1024,
                effort: AIEffort = .medium) -> AsyncThrowingStream<String, Error> {
        do {
            return try provider().stream(system: system, user: user, maxTokens: maxTokens, effort: effort)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }
}
