import SwiftUI

/// The phone's whole chrome is one floating bar at the thumb: back, the
/// address pill, tabs, and the menu. The page keeps every other pixel —
/// zen by default, which is the Mac app's direction distilled.
struct BrowserScreen: View {
    @ObservedObject var store: MobileStore
    @State private var showSearch = false
    @State private var showSwitcher = false
    @State private var showMenu = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let tab = store.activeTab, !tab.urlString.isEmpty {
                PageView(tab: tab)
            } else {
                StartPage(store: store) { showSearch = true }
            }
            bottomBar
        }
        .sheet(isPresented: $showMenu) {
            if let tab = store.activeTab { MenuSheet(store: store, tab: tab) }
        }
        .fullScreenCover(isPresented: $showSwitcher) {
            TabSwitcher(store: store)
        }
        .overlay {
            if showSearch {
                SearchOverlay(store: store, isPresented: $showSearch)
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if let tab = store.activeTab {
            BarSurface(tab: tab) { barContent(for: tab) }
        } else {
            barContent(for: nil)
                .padding(.horizontal, 12)
                .runeGlass(in: Capsule())
                .padding(.horizontal, 14).padding(.bottom, 6)
        }
    }

    private func barContent(for tab: MobileTab?) -> some View {
        HStack(spacing: 10) {
            if let tab, tab.canGoBack {
                BarButton(icon: "chevron.left") { tab.webView.goBack() }
            }
            addressPill
            BarButton(icon: "square.on.square") {
                store.activeTab?.takeSnapshot()
                showSwitcher = true
            }
            BarButton(icon: "ellipsis") { showMenu = true }
        }
    }

    private var addressPill: some View {
        Button {
            showSearch = true
        } label: {
            HStack(spacing: 5) {
                let tab = store.activeTab
                let host = tab?.compactHost ?? ""
                Image(systemName: (tab?.urlString.hasPrefix("https://") ?? false)
                      ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                Text(host.isEmpty ? "Search or enter address" : host)
                    .font(.system(size: RuneTheme.fontSize))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The page, with the bar's height held clear beneath it.
private struct PageView: View {
    @ObservedObject var tab: MobileTab
    var body: some View {
        WebContainer(webView: tab.webView)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                if tab.isLoading {
                    ProgressView().tint(RuneTheme.accent).padding(.top, 4)
                }
            }
    }
}

/// The floating bar's surface: native Liquid Glass with the page's own
/// colour — the Mac strip's trick — poured through as a tint. The tint is
/// translucent, so system ink stays legible over it.
private struct BarSurface<Content: View>: View {
    @ObservedObject var tab: MobileTab
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .runeGlass(tint: tab.themeColor.map(Color.init(uiColor:)), in: Capsule())
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .animation(.easeOut(duration: 0.2), value: tab.themeColor)
    }
}

struct BarButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The start page, carried over whole: the wordmark, the pill, the
/// favorites — the same room the Mac opens into.
struct StartPage: View {
    @ObservedObject var store: MobileStore
    let search: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Rune").font(.system(size: 42, weight: .bold))
            Button(action: search) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13))
                    Text("Search or enter address").font(.system(size: RuneTheme.fontSize))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Capsule().strokeBorder(.secondary.opacity(0.4)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
