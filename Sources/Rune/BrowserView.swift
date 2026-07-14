import SwiftUI
import WebKit

struct BrowserView: View {
    @ObservedObject var model: BrowserModel
    let dispatch: (Command) -> Void

    @State private var showPalette = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    Sidebar(model: model)
                        .frame(width: Theme.sidebarWidth)
                        .transition(.move(edge: .leading))
                    Divider()
                }
                ContentArea(model: model)
            }
            .animation(.easeInOut(duration: 0.18), value: model.sidebarVisible)
            .background(Theme.windowBG)

            if showPalette {
                CommandPalette(model: model, dispatch: dispatch, isPresented: $showPalette)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
            showPalette = true
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 28)   // breathing room under traffic lights

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.pinnedTabs.isEmpty {
                        TabGroup(title: "Apps", tabs: model.pinnedTabs, model: model)
                    }
                    TabGroup(title: "Tabs", tabs: model.unpinnedTabs, model: model)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)

            Button {
                model.newTab()
            } label: {
                Label("New Tab", systemImage: "plus")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .background(Theme.sidebarBG)
    }
}

private struct TabGroup: View {
    let title: String
    let tabs: [Tab]
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 8).padding(.bottom, 2)
            ForEach(tabs) { tab in
                TabRow(tab: tab, isSelected: tab.id == model.selectedTabID) {
                    model.select(tab)
                } close: {
                    model.close(tab)
                }
            }
        }
    }
}

private struct TabRow: View {
    @ObservedObject var tab: Tab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if tab.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 16, height: 16)
                } else if tab.isPinned {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Theme.accent)
                        .frame(width: 16)
                } else {
                    Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 16)
                }
            }
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .lineLimit(1)
                .font(.callout)
            Spacer(minLength: 4)
            if hovering {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .background(Theme.hover, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isSelected ? Theme.selection : (hovering ? Theme.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(tab.isPinned ? "Unpin" : "Pin") { tab.isPinned.toggle() }
            Button("Close") { close() }
        }
    }
}

// MARK: - Content

private struct ContentArea: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(model: model)
            Divider()
            ZStack {
                Theme.windowBG
                if let tab = model.selectedTab {
                    TabContent(tab: tab, model: model)
                } else {
                    EmptyState(model: model)
                }
            }
        }
    }
}

/// Shows the native start page until the tab has navigated somewhere.
private struct TabContent: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: BrowserModel

    var body: some View {
        if tab.urlString.isEmpty && !tab.isLoading {
            StartPage(model: model)
        } else {
            WebContainer(webView: tab.webView).id(tab.id)
        }
    }
}

private struct StartPage: View {
    @ObservedObject var model: BrowserModel
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Rune")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(model.settings.searchEngine.name) or enter address", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit {
                        model.navigate(query)
                        query = ""
                    }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: 560)
            .background(Theme.chrome, in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? Theme.accent : Theme.hairline, lineWidth: 1))
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBG)
        .onAppear { focused = true }
    }
}

private struct Toolbar: View {
    @ObservedObject var model: BrowserModel
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            toolbarButton("sidebar.left") { model.sidebarVisible.toggle() }
            toolbarButton("chevron.left") { model.goBack() }
                .disabled(!(model.selectedTab?.canGoBack ?? false))
            toolbarButton("chevron.right") { model.goForward() }
                .disabled(!(model.selectedTab?.canGoForward ?? false))
            toolbarButton(model.selectedTab?.isLoading == true ? "xmark" : "arrow.clockwise") {
                model.reload()
            }

            AddressField(text: $address, focused: $addressFocused) {
                model.navigate(address)
                addressFocused = false
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.chrome)
        .onChange(of: model.selectedTabID) { syncAddress() }
        .onChange(of: model.selectedTab?.urlString) { if !addressFocused { syncAddress() } }
        .onAppear { syncAddress() }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in
            addressFocused = true
        }
    }

    private func syncAddress() { address = model.selectedTab?.urlString ?? "" }

    private func toolbarButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

private struct AddressField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
            TextField("Search or enter address", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.windowBG, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused.wrappedValue ? Theme.accent : Theme.hairline, lineWidth: 1)
        )
    }
}

private struct EmptyState: View {
    @ObservedObject var model: BrowserModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text("No tab open").font(.title3).foregroundStyle(.secondary)
            Button("New Tab") { model.newTab() }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
    }
}
