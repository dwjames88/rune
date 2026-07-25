import SwiftUI

/// The page's verbs, gathered under the bar: a grid of quiet tiles, the way
/// the reference sheet arranges them, wearing Rune's radius and accent.
struct MenuSheet: View {
    @ObservedObject var store: MobileStore
    @ObservedObject var tab: MobileTab
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible()),
                           GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(.tertiary).frame(width: 36, height: 4).padding(.top, 10)

            HStack(spacing: 5) {
                if tab.urlString.hasPrefix("https://") {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                }
                Text(tab.compactHost.isEmpty ? "New Tab" : tab.compactHost)
                    .font(.system(size: RuneTheme.fontSize, weight: .medium))
            }
            .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                tile("Reload", icon: "arrow.clockwise") { tab.webView.reload(); dismiss() }
                tile("Copy URL", icon: "link") {
                    UIPasteboard.general.string = tab.urlString
                    dismiss()
                }
                if let url = URL(string: tab.urlString) {
                    ShareLink(item: url) { tileLabel("Share", icon: "paperplane") }
                        .buttonStyle(.plain)
                }
                tile("Favorite", icon: "star") {
                    store.favorites.append(Favorite(
                        name: tab.title.isEmpty ? tab.compactHost : tab.title,
                        url: tab.urlString))
                    store.persist()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 8)
        }
        .presentationDetents([.height(210)])
        .presentationBackground(.ultraThinMaterial)
    }

    private func tile(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title, icon: icon) }
            .buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium))
            Text(title).font(.system(size: 11))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .runeGlass(in: RoundedRectangle(cornerRadius: RuneTheme.radius + 4, style: .continuous))
        .contentShape(Rectangle())
    }
}
