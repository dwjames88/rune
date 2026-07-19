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

        // Progress is KVO, and it fires from whatever thread moved the bytes —
        // so both of these have to be brought back to the main actor before
        // they touch anything published. Progress also ticks per packet, and
        // the UI can't use more than a few frames a second, so the byte count
        // is throttled rather than republished on every one.
        let progress = download.progress
        progress.publisher(for: \.completedUnitCount)
            .throttle(for: .milliseconds(150), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.completed = $0 }
            .store(in: &cancellables)
        progress.publisher(for: \.totalUnitCount)
            .removeDuplicates()
            .receive(on: RunLoop.main)
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
        // receive(on:) is load-bearing: @Published publishes on willSet, so a
        // same-tick recompute still reads the OLD state — which left the
        // progress card on stage forever after a cancel, the one state
        // change that no later progress tick arrives to correct.
        var watch: Set<AnyCancellable> = []
        item.$completed.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }.store(in: &watch)
        item.$state.receive(on: RunLoop.main).sink { [weak self] state in
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

    /// Drop one row — a retry replaces it with a fresh download.
    func remove(_ item: DownloadItem) {
        watches[item.id] = nil
        items.removeAll { $0.id == item.id }
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
/// Pressing it opens the Downloads section of the Rune Finder — the list
/// lives there now, not in an overlay.
struct DownloadsButton: View {
    @ObservedObject var downloads: DownloadStore
    /// On glass (the corner kit) it inks with the semantic label colour so it
    /// matches the other icons; on the solid chrome bar it keeps chrome ink.
    var onGlass = false
    let action: () -> Void
    @EnvironmentObject var appearance: AppearanceStore

    var body: some View {
        Button(action: action) {
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
        .foregroundStyle(onGlass ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(appearance.secondaryText(on: appearance.chrome)))
        .help("Downloads (⌥⌘L)")
    }
}

/// The list, as a Finder pane: ⌥⌘L and the toolbar button land here now,
/// where a file you kept can be found next to everything else you've kept —
/// not in an overlay racing you to disappear.
struct DownloadsList: View {
    @ObservedObject var downloads: DownloadStore
    var query = ""
    /// How to try a failed row again — provided by whoever has a web view.
    var retry: ((DownloadItem) -> Void)? = nil
    @EnvironmentObject var appearance: AppearanceStore

    private var rows: [DownloadItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return downloads.items }
        return downloads.items.filter { $0.filename.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        if rows.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "arrow.down.circle").font(.system(size: 28))
                    .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
                Text(query.isEmpty ? "Nothing downloaded this session." : "No downloads match.")
                    .font(appearance.type(.body))
                    .foregroundStyle(appearance.secondaryText(on: appearance.windowBG))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if downloads.items.contains(where: { !$0.isRunning }) {
                        HStack {
                            Spacer()
                            Button("Clear Finished") { downloads.clearFinished() }
                                .buttonStyle(.plain).font(appearance.font(11))
                                .foregroundStyle(appearance.accent)
                        }
                        .padding(.horizontal, 14).padding(.top, 10)
                    }
                    ForEach(rows) { item in
                        DownloadRow(item: item, retry: retry.map { r in { r(item) } })
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// The quiet word from the corner while bytes land: one card, bottom-left,
/// naming the file (or counting them) with a live bar. It leaves when the
/// downloads do — completion's badge lives on the corner kit's grab tab.
struct DownloadProgressCard: View {
    @ObservedObject var downloads: DownloadStore
    @EnvironmentObject var appearance: AppearanceStore

    private var title: String {
        let running = downloads.items.filter(\.isRunning)
        return running.count == 1 ? (running.first?.filename ?? "Downloading")
                                  : "\(running.count) downloads"
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.down.circle").font(.system(size: 14))
                .foregroundStyle(appearance.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1).font(appearance.type(.label))
                    .foregroundStyle(.primary)
                if let fraction = downloads.activeFraction {
                    ProgressView(value: fraction).progressViewStyle(.linear)
                        .tint(appearance.accent)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(appearance.accent)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: 230)
        .runeSurface(appearance, .large)
    }
}

struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    var retry: (() -> Void)? = nil
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
            } else if case .failed = item.state, let retry {
                // Cancelled or broken — the source URL is still known, so the
                // row offers to go get it again.
                Button(action: retry) { Image(systemName: "arrow.clockwise.circle.fill") }
                    .buttonStyle(.plain).help("Try Again")
                    .foregroundStyle(appearance.accent)
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
