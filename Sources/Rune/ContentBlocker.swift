import Foundation
import WebKit

// MARK: - The rules

/// What Rune blocks. WebKit wants its own JSON, so the rules live here as
/// ordinary Swift and the JSON is generated — a list of hosts diffs readably
/// and can't be mis-escaped, which a hand-written blob can be both of.
///
/// Deliberately curated and small. EasyList is ABP syntax, which WebKit doesn't
/// speak, and the usual converter is a dependency Rune doesn't take — so this
/// covers the trackers you actually meet every day, and a full EasyList
/// pipeline can land behind the same seam later without touching anything else.
enum BlockRules {
    /// Bump when the lists below change. It's part of the cache key, so this is
    /// what tells a already-compiled list that it's stale.
    static let version = 1

    /// Ad and tracking hosts, blocked as third-party loads — so if you actually
    /// navigate to one of these, it still opens.
    static let hosts = [
        // Google's ad and measurement stack
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adservice.google.com",
        // Exchanges and SSPs
        "adnxs.com", "rubiconproject.com", "pubmatic.com", "openx.net",
        "casalemedia.com", "criteo.com", "criteo.net", "adsrvr.org",
        "bidswitch.net", "smartadserver.com", "indexww.com", "sharethrough.com",
        "33across.com", "teads.tv", "amazon-adsystem.com",
        // Content recommendation ("chumboxes")
        "outbrain.com", "taboola.com",
        // Viewability and verification
        "moatads.com", "adsafeprotected.com", "doubleverify.com",
        // Analytics and session recording
        "scorecardresearch.com", "quantserve.com", "hotjar.com", "mouseflow.com",
        "fullstory.com", "mixpanel.com", "amplitude.com", "chartbeat.com",
        "chartbeat.net", "parsely.com", "clarity.ms", "mc.yandex.ru",
        // Adobe's marketing cloud
        "demdex.net", "omtrdc.net", "everesttech.net", "2o7.net",
        // Attribution / mobile measurement
        "branch.io", "appsflyer.com", "adjust.com", "crwdcntrl.net",
        // Social tracking pixels (not the sites themselves)
        "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
        "px.ads.linkedin.com", "snap.licdn.com", "ct.pinterest.com",
        "analytics.tiktok.com", "bat.bing.com",
    ]

    /// Cookie-consent walls. Hidden rather than blocked: the markup is usually
    /// served by the page itself, so there's no request to stop.
    static let bannerSelectors = [
        "#onetrust-consent-sdk", "#onetrust-banner-sdk", ".onetrust-pc-dark-filter",
        "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
        ".cc-window", ".cc-banner",
        "#cookie-law-info-bar", "#cookie-notice", "#cookieChoiceInfo",
        ".qc-cmp2-container", ".qc-cmp-ui-container",
        "#usercentrics-root", "#didomi-host",
        ".truste_overlay", ".truste_box_overlay",
        ".osano-cm-window", "#hs-eu-cookie-confirmation",
        ".fc-consent-root", "[id^=\"sp_message_container\"]",
        "#cookie-banner", ".cookie-banner",
    ]

    /// WebKit's JSON. `unless-domain` is matched against the *page* you're on,
    /// which is exactly what a per-site exception means, so exceptions are baked
    /// into the compiled list rather than checked at request time.
    static func json(hideCookieBanners: Bool, exceptions: [String]) -> String {
        // "*example.com" covers subdomains too.
        let unless = exceptions.map { "*\($0)" }

        var rules: [[String: Any]] = hosts.map { host in
            var trigger: [String: Any] = [
                // Matches the resource's own URL, so the host is stopped
                // wherever it's embedded.
                "url-filter": "^https?://([^/]+\\.)?\(NSRegularExpression.escapedPattern(for: host))[:/]",
                "load-type": ["third-party"],
            ]
            if !unless.isEmpty { trigger["unless-domain"] = unless }
            return ["trigger": trigger, "action": ["type": "block"]]
        }

        if hideCookieBanners {
            var trigger: [String: Any] = ["url-filter": ".*"]
            if !unless.isEmpty { trigger["unless-domain"] = unless }
            rules.append([
                "trigger": trigger,
                "action": ["type": "css-display-none",
                           "selector": bannerSelectors.joined(separator: ", ")],
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Compiling and applying

/// Content blocking, natively. WebKit compiles the rules to bytecode once and
/// enforces them in its own networking path, so a blocked request is never made
/// and the page pays nothing at runtime. No extension, no proxy, no daemon.
@MainActor
final class ContentBlocker: ObservableObject {
    private let settings: SettingsStore
    private let sites: SiteSettings

    /// The compiled list, handed to every web view that asks.
    @Published private(set) var list: WKContentRuleList?
    /// Set when WebKit refuses to compile — worth surfacing rather than
    /// silently browsing unprotected while Settings claims otherwise.
    @Published private(set) var failure: String?

    init(settings: SettingsStore, sites: SiteSettings) {
        self.settings = settings
        self.sites = sites
    }

    /// Identifier doubles as the cache key: WebKit keeps compiled lists on disk
    /// between launches, and a name carrying the rule version, the banner
    /// setting and the exception set means "already compiled" can be trusted.
    private var identifier: String {
        var hasher = Hasher()
        hasher.combine(BlockRules.version)
        hasher.combine(settings.hideCookieBanners)
        for host in exceptions { hasher.combine(host) }
        return "rune.rules.\(UInt(bitPattern: hasher.finalize()))"
    }

    private var exceptions: [String] { sites.blockingExceptions.sorted() }

    /// Compile if we must, look it up if we already did. Cheap on every launch
    /// after the first, which is why the identifier carries the whole config.
    func reload() async {
        guard settings.blockContent else {
            list = nil; failure = nil
            return
        }
        let id = identifier
        let store = WKContentRuleListStore.default()

        if let cached = try? await store?.contentRuleList(forIdentifier: id) {
            list = cached; failure = nil
            await prune(keeping: id)
            return
        }
        do {
            let json = BlockRules.json(hideCookieBanners: settings.hideCookieBanners,
                                       exceptions: exceptions)
            list = try await store?.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json)
            failure = nil
            await prune(keeping: id)
        } catch {
            // A bad rule shouldn't take the browser down with it.
            list = nil
            failure = error.localizedDescription
            NSLog("Rune content blocker: compile failed — %@", error.localizedDescription)
        }
    }

    /// Every config change mints a new identifier, so the old compilations would
    /// pile up on disk forever if nobody swept them.
    private func prune(keeping id: String) async {
        guard let store = WKContentRuleListStore.default(),
              let all = try? await store.availableIdentifiers() else { return }
        for stale in all where stale != id && stale.hasPrefix("rune.rules.") {
            try? await store.removeContentRuleList(forIdentifier: stale)
        }
    }

    /// Hand the current list to a web view's controller.
    func apply(to controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        if let list { controller.add(list) }
    }
}
