import SwiftUI

/// Typing space: a field over frosted glass with the favorites (and, one
/// day, the Mac's synced folders) right under your thumb. The phone's ⌘L.
struct SearchOverlay: View {
    @ObservedObject var store: MobileStore
    @Binding var isPresented: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 60)

            TextField("Search or enter address", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .focused($focused)
                .onSubmit { go(text) }
                .font(.system(size: 17))
                .padding(.horizontal, 16)
                .frame(height: 52)
                .runeGlass(in: RoundedRectangle(cornerRadius: RuneTheme.radius + 6, style: .continuous))
                .padding(.horizontal, 18)

            List {
                ForEach(store.favorites) { favorite in
                    Button { go(favorite.url) } label: {
                        HStack(spacing: 10) {
                            SiteGlyph(name: favorite.name)
                            Text(favorite.name).font(.system(size: RuneTheme.fontSize))
                            Spacer()
                            Image(systemName: "star")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(store.folders) { folder in
                    Section(folder.name) {
                        ForEach(folder.items) { item in
                            Button { go(item.url) } label: {
                                HStack(spacing: 10) {
                                    SiteGlyph(name: item.name)
                                    Text(item.name).font(.system(size: RuneTheme.fontSize))
                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(.ultraThinMaterial)
        .onAppear { focused = true }
        .onTapGesture { isPresented = false }
    }

    private func go(_ input: String) {
        store.activate(input)
        isPresented = false
    }
}

/// A letter chip standing in for the favicon — the accent's job until
/// favicons ride along.
struct SiteGlyph: View {
    let name: String
    var size: CGFloat = 26
    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RuneTheme.accent.gradient,
                        in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}
