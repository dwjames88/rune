import AppKit
import Combine
import SwiftUI
import WebKit

// MARK: - Where files land

/// Where a finished download ends up. A setting, like everything else.
enum DownloadLocation: String, Codable, CaseIterable, Identifiable {
    case downloadsFolder, ask, finderLibrary
    var id: String { rawValue }
    var label: String {
        switch self {
        case .downloadsFolder: "The Downloads folder"
        case .ask: "Ask where to save each file"
        case .finderLibrary: "The Rune Finder library"
        }
    }
}

// MARK: - One download

/// A file Rune is fetching, or has fetched. Owns its progress subscription so
/// the store above it only has to aggregate.
@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    nonisolated let id = UUID()
    let filename: String
    let source: URL

    @Published var destination: URL?
    @Published var completed: Int64 = 0
    @Published var total: Int64 = 0
    @Published var state: State = .running

    enum State: Equatable { case running, finished, failed(String) }

    private weak var download: WKDownload?
    private var cancellables: Set<AnyCancellable> = []

    init(filename: String, source: URL, download: WKDownload) {
        self.filename = filename
        self.source = source
        self.download = download

        // Progress ticks per packet; the UI can't use more than a few frames a
        // second, so throttle rather than republish on every byte.
        let progress = download.progress
        progress.publisher(for: \.completedUnitCount)
            .throttle(for: .milliseconds(150), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.completed = $0 }
            .store(in: &cancellables)
        progress.publisher(for: \.totalUnitCount)
            .removeDuplicates()
            .sink { [weak self] in self?.total = $0 }
            .store(in: &cancellables)
    }

    var isRunning: Bool { state == .running }

    /// 0…1, or nil when the server never declared a length (indeterminate).
    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }

    /// "2.4 MB of 11 MB" while running, final size once done.
    var sizeLabel: String {
        let f = ByteCountFormatter.string(fromByteCount:countStyle:)
        switch state {
        case .failed(let why): return why
        case .finished: return f(max(completed, total), .file)
        case .running:
            return total > 0 ? "\(f(completed, .file)) of \(f(total, .file))" : f(completed, .file)
        }
    }

    func cancel() {
        download?.cancel()
        state = .failed("Cancelled")
    }

    /// Reveal in the system Finder (not Rune's — this is a file on disk).
    func reveal() {
        guard let destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func open() {
        guard let destination else { return }
        NSWorkspace.shared.open(destination)
    }
}

// MARK: - The list

/// Every download this launch. App-wide: one list, shared by every window.
@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    /// Aggregates, republished only when they actually change — the toolbar
    /// button observes this store and must not re-render per packet.
    @Published private(set) var activeCount = 0
    @Published private(set) var activeFraction: Double?
    /// Something finished while the panel was closed.
    @Published var hasUnseen = false

    /// One subscription bundle per download, dropped when its row goes.
    private var watches: [UUID: Set<AnyCancellable>] = [:]

    func add(_ item: DownloadItem) {
        items.insert(item, at: 0)
        // Aggregate from the items rather than having each report upward.
        var watch: Set<AnyCancellable> = []
        item.$completed.sink { [weak self] _ in self?.recompute() }.store(in: &watch)
        item.$state.sink { [weak self] state in
            if state == .finished { self?.hasUnseen = true }
            self?.recompute()
        }.store(in: &watch)
        watches[item.id] = watch
        recompute()
    }

    func clearFinished() {
        for item in items where !item.isRunning { watches[item.id] = nil }
        items.removeAll { !$0.isRunning }
        recompute()
    }

    private func recompute() {
        let running = items.filter(\.isRunning)
        if running.count != activeCount { activeCount = running.count }

        let sized = running.filter { $0.total > 0 }
        let next: Double? = sized.isEmpty ? nil
            : Double(sized.reduce(0) { $0 + $1.completed }) / Double(sized.reduce(0) { $0 + $1.total })
        // Whole percents only: below that the ring can't show the difference.
        if next.map({ ($0 * 100).rounded() }) != activeFraction.map({ ($0 * 100).rounded() }) {
            activeFraction = next
        }
    }

    // MARK: Destinations

    /// A free path in `directory` for `filename` — "report.pdf", then
    /// "report 2.pdf", and so on. Never overwrites what's already there.
    static func uniqueURL(in directory: URL, filename: String) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = directory.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }

    static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}

// MARK: - UI

/// Toolbar button: a tray icon that becomes a progress ring while files are in
/// flight, with a dot when something finished you haven't looked at.
struct DownloadsButton: View {
    @ObservedObject var downloads: DownloadStore
    @Binding var showing: Bool
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Button { showing.toggle() } label: {
            ZStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .medium))
                if downloads.activeCount > 0 {
                    Circle()
                        .trim(from: 0, to: downloads.activeFraction ?? 0.15)
                        .stroke(appearance.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 18, height: 18)
                        .animation(.linear(duration: 0.15), value: downloads.activeFraction)
                }
            }
            .frame(width: 26, height: 24)
            .overlay(alignment: .topTrailing) {
                if downloads.hasUnseen && downloads.activeCount == 0 {
                    Circle().fill(appearance.accent).frame(width: 5, height: 5).offset(x: -3, y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
        .help("Downloads (⌥⌘L)")
    }
}

/// The list itself. Lives as a panel in the content area rather than a popover
/// on the button, so ⌥⌘L works whether or not the button is in your toolbar.
struct DownloadsPanel: View {
    @ObservedObject var downloads: DownloadStore
    @Binding var showing: Bool
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(appearance.font(13, weight: .semibold))
                Spacer()
                if downloads.items.contains(where: { !$0.isRunning }) {
                    Button("Clear") { downloads.clearFinished() }
                        .buttonStyle(.plain).font(appearance.font(11))
                        .foregroundStyle(appearance.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(appearance.chromeText)

            if downloads.items.isEmpty {
                Text("Nothing downloaded yet.")
                    .font(appearance.font(12))
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
                    .padding(.horizontal, 12).padding(.bottom, 12)
            } else {
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(downloads.items) { DownloadRow(item: $0) }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appearance.cornerRadius + 2))
        .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius + 2).strokeBorder(appearance.hairline))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject var appearance: AppearanceStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(item.state == .running ? appearance.accent
                                                        : appearance.secondaryText(on: appearance.chrome))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).lineLimit(1)
                    .font(appearance.font(12)).foregroundStyle(appearance.chromeText)
                if item.state == .running, let fraction = item.fraction {
                    ProgressView(value: fraction).progressViewStyle(.linear).tint(appearance.accent)
                } else if item.state == .running {
                    ProgressView().progressViewStyle(.linear).tint(appearance.accent)
                }
                Text(item.sizeLabel).font(appearance.font(10))
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
            }
            Spacer(minLength: 0)
            if item.isRunning {
                Button { item.cancel() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).help("Cancel")
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
            } else if item.state == .finished, hovering {
                Button { item.reveal() } label: { Image(systemName: "magnifyingglass.circle.fill") }
                    .buttonStyle(.plain).help("Show in Finder")
                    .foregroundStyle(appearance.secondaryText(on: appearance.chrome))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(hovering ? appearance.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { item.open() }
    }

    private var icon: String {
        switch item.state {
        case .running: "arrow.down.circle"
        case .finished: "doc"
        case .failed: "exclamationmark.triangle"
        }
    }
}
