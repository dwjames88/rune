import SwiftUI

/// Cache so re-hovering a link doesn't re-summarize it. Capped so a long
/// session doesn't accumulate summaries forever (drops ~oldest half when full).
@MainActor
final class SummaryCache: ObservableObject {
    static let shared = SummaryCache()
    private var cache: [URL: String] = [:]
    private var order: [URL] = []
    private let cap = 200

    func get(_ url: URL) -> String? { cache[url] }
    func set(_ url: URL, _ text: String) {
        if cache[url] == nil { order.append(url) }
        cache[url] = text
        if order.count > cap {
            for old in order.prefix(cap / 2) { cache[old] = nil }
            order.removeFirst(cap / 2)
        }
    }
}

// MARK: - Link hover popover

/// Hover a link → Claude tells you where it goes, before you click.
struct LinkSummaryPopover: View {
    let target: HoverTarget
    @ObservedObject var claude: ClaudeService
    @EnvironmentObject var appearance: AppearanceStore
    @StateObject private var cache = SummaryCache.shared

    @State private var summary: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(appearance.accent)
                Text(target.url.host ?? target.url.absoluteString)
                    .font(appearance.font(11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            Group {
                if let summary {
                    Text(summary).font(appearance.font(12))
                } else if let error {
                    Text(error).font(appearance.font(11)).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                        Text("Reading…").font(appearance.font(11)).foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(appearance.hairline))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .task(id: target.url) { await load() }
    }

    private func load() async {
        summary = cache.get(target.url); error = nil
        guard summary == nil else { return }
        guard claude.hasKey else { error = "Add an API key in Settings ▸ Claude to preview links."; return }
        do {
            let text = try await PageBridge.remoteText(for: target.url)
            guard !text.isEmpty else { error = "Couldn't read that page."; return }
            let result = try await claude.complete(
                system: "You summarize a web page for someone deciding whether to click its link. "
                    + "Two sentences maximum. Lead with what the page actually is. No preamble.",
                user: "URL: \(target.url.absoluteString)\n\nPage text:\n\(text)",
                maxTokens: 160, effort: "low")
            cache.set(target.url, result)
            summary = result
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Selection actions

/// Select text → Explain / Summarize / Translate, in place.
struct SelectionActions: View {
    let target: SelectionTarget
    @ObservedObject var claude: ClaudeService
    @EnvironmentObject var appearance: AppearanceStore

    @State private var result: String?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                action("Explain", "lightbulb") {
                    await run(system: "Explain the passage plainly, for a smart reader who lacks the background. Be brief.")
                }
                action("Summarize", "text.alignleft") {
                    await run(system: "Summarize the passage in one or two sentences. No preamble.")
                }
                action("Translate", "globe") {
                    await run(system: "Translate the passage into English. If it is already English, translate it into plain, simple English.")
                }
                if working { ProgressView().controlSize(.small).scaleEffect(0.55) }
            }
            if let result {
                Divider()
                ScrollView {
                    Text(result).font(appearance.font(12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 180)
            }
            if let error {
                Text(error).font(appearance.font(11)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: result == nil ? 300 : 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(appearance.hairline))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private func action(_ title: String, _ icon: String, run: @escaping () async -> Void) -> some View {
        Button {
            Task { await run() }
        } label: {
            Label(title, systemImage: icon).font(appearance.font(11))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(appearance.hover, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private func run(system: String) async {
        guard claude.hasKey else { error = "Add an API key in Settings ▸ Claude."; return }
        working = true; error = nil
        defer { working = false }
        do {
            result = try await claude.complete(system: system, user: target.text,
                                               maxTokens: 500, effort: "low")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Ask bar (⌘J)

/// A slim bar that answers questions about the page you're on, then gets out of
/// the way. Not a chat window — no history, no sidebar.
struct AskBar: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var claude: ClaudeService
    @Binding var isPresented: Bool
    @EnvironmentObject var appearance: AppearanceStore

    @State private var question = ""
    @State private var answer = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(appearance.accent)
                TextField("Ask about this page…", text: $question)
                    .textFieldStyle(.plain).font(appearance.font(15))
                    .focused($focused)
                    .onSubmit { Task { await ask() } }
                if working { ProgressView().controlSize(.small).scaleEffect(0.6) }
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)

            if !answer.isEmpty || error != nil {
                Divider()
                ScrollView {
                    Text(error ?? answer)
                        .font(appearance.font(13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(appearance.hairline))
        .shadow(color: .black.opacity(0.22), radius: 24, y: 8)
        .padding(.top, 12)
        .onAppear { focused = true }
        .dismissOnEscape { close() }
    }

    private func close() { isPresented = false; answer = ""; error = nil; question = "" }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let tab = model.activeTab else { return }
        guard claude.hasKey else { error = "Add an API key in Settings ▸ Claude."; return }

        working = true; answer = ""; error = nil
        defer { working = false }

        let text = await tab.pageText()
        let system = "You answer questions about the web page the user is reading. "
            + "Answer from the page when it says; say so plainly when it doesn't. Be brief and direct."
        let user = "Page: \(tab.title) — \(tab.urlString)\n\n\(text)\n\nQuestion: \(q)"

        do {
            for try await chunk in claude.stream(system: system, user: user, maxTokens: 900, effort: "medium") {
                answer += chunk
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
