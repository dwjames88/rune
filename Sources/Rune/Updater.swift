import Foundation

/// In-app updates, the light way: Rune ships outside the App Store and is
/// ad-hoc signed, so there's no silent swap-the-bundle auto-update to do
/// safely. Instead this asks GitHub for the latest published release, compares
/// it to what's running, and — when there's something newer — points you at
/// the download. Zero dependencies: one JSON request to the public API.
@MainActor
final class Updater: ObservableObject {
    /// owner/repo the releases live under.
    static let repo = "dwjames88/rune"

    struct Release: Equatable {
        var version: String        // "1.13"
        var name: String           // release title
        var url: URL               // the release page
        var notes: String          // markdown body
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?
    /// Look for updates quietly on launch. A setting, like everything.
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: Self.autoKey) } }

    /// The VERSION baked into the bundle (CFBundleShortVersionString).
    var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static let lastCheckKey = "rune.updater.lastCheck"
    private static let autoKey = "rune.updater.autoCheck"

    init() {
        let t = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if t > 0 { lastChecked = Date(timeIntervalSince1970: t) }
        autoCheck = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
    }

    /// Check at most once a day unless the user asked — so launch checks stay
    /// quiet and a manual "Check Now" always runs.
    func checkIfDue() async {
        if let last = lastChecked, Date().timeIntervalSince(last) < 60 * 60 * 24 { return }
        await check()
    }

    func check(userInitiated: Bool = false) async {
        if case .checking = status { return }
        status = .checking
        do {
            let release = try await fetchLatest()
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked!.timeIntervalSince1970, forKey: Self.lastCheckKey)
            status = isNewer(release.version, than: current) ? .available(release) : .upToDate
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't check for updates.")
        }
    }

    private func fetchLatest() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Rune/\(current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { throw UpdaterError.unreachable }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Rune \(version)"
        return Release(version: version, name: name, url: page, notes: json["body"] as? String ?? "")
    }

    /// Numeric, component-wise: 1.13 > 1.12, 1.2 < 1.10. Non-numeric parts fall
    /// back to zero, which is fine for Rune's `major.minor` tags.
    func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private enum UpdaterError: LocalizedError {
        case unreachable
        var errorDescription: String? { "Couldn't reach the update server." }
    }
}
