import SwiftUI

/// Settings ▸ Spaces: every space and every profile in one place, rather than
/// only reachable by right-clicking the chip you happen to be standing on.
///
/// The two are shown together on purpose, because the relationship is the
/// point: a space is a *view* (a shelf and a look), a profile is an *identity*
/// (its own cookies and logins), and every space browses as exactly one profile.
struct SpacesPane: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var appearance: AppearanceStore

    @State private var renamingSpace: UUID?
    @State private var renamingProfile: UUID?
    @State private var pickingIcon: UUID?
    @State private var pickingProfileIcon: UUID?
    @State private var confirmingProfileDelete: Profile?

    var body: some View {
        Form {
            Section {
                ForEach(model.spaces) { space in SpaceRow(space: space) }
                    .onMove { from, to in
                        model.spaces.move(fromOffsets: from, toOffset: to)
                        model.persist()
                    }
                Button {
                    model.switchTo(space: model.addSpace().id)
                } label: {
                    Label("New Space", systemImage: "plus")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Spaces")
            } footer: {
                Text("A space keeps its own favorites, pinned tabs and theme. Drag to reorder — that's the order ⌃⌘[ and ⌃⌘] walk. Switching to a space never reloads what was open in it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(model.profiles) { profile in ProfileRow(profile: profile) }
                Button { _ = model.addProfile() } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Profiles")
            } footer: {
                Text("A profile is its own cookies, logins and storage — two profiles can be signed into the same site as different people. Assign a profile per space above. Moving a space to another profile closes its tabs: they were signed in as somebody else.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(item: $confirmingProfileDelete) { profile in
            Alert(title: Text("Delete “\(profile.name)”?"),
                  message: Text("Its cookies and logins are deleted with it, and any space using it moves to another profile. This can't be undone."),
                  primaryButton: .destructive(Text("Delete")) { model.deleteProfile(profile.id) },
                  secondaryButton: .cancel())
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func SpaceRow(space: Space) -> some View {
        HStack(spacing: 10) {
            Button { pickingIcon = space.id } label: {
                Image(systemName: space.icon)
                    .foregroundStyle(tint(space)).frame(width: 20)
            }
            .buttonStyle(.plain)
            .popover(isPresented: bind($pickingIcon, space.id)) {
                SymbolPicker(symbol: .constant(space.icon), tint: appearance.accent) { icon in
                    model.updateSpace(space.id) { $0.icon = icon }
                    pickingIcon = nil
                }
            }

            Text(space.name)
                .fontWeight(space.id == model.currentSpaceID ? .semibold : .regular)
            if space.id == model.currentSpaceID {
                Text("current").font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(appearance.accent.opacity(0.18), in: Capsule())
            }
            Spacer()

            // Theme. "" is the picker's way of saying nil — no theme is a real
            // answer, and means this space leaves your look alone.
            Picker("", selection: Binding(
                get: { space.preset ?? "" },
                set: { name in
                    model.updateSpace(space.id) { $0.preset = name.isEmpty ? nil : name }
                }
            )) {
                Text("No theme").tag("")
                ForEach(appearance.presets) { Text($0.name).tag($0.name) }
            }
            .labelsHidden().frame(width: 130)

            // Profile.
            Picker("", selection: Binding(
                get: { space.profileID ?? model.defaultProfileID },
                set: { model.setProfile($0, for: space.id) }
            )) {
                ForEach(model.profiles) { Text($0.name).tag($0.id) }
            }
            .labelsHidden().frame(width: 120)

            Menu {
                Button("Rename…") { renamingSpace = space.id }
                if model.spaces.count > 1 {
                    Button("Delete Space", role: .destructive) { model.deleteSpace(space.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).frame(width: 24)
            .popover(isPresented: bind($renamingSpace, space.id)) {
                RenameField(title: "Rename Space", name: space.name) { name in
                    model.updateSpace(space.id) { $0.name = name }
                    renamingSpace = nil
                }
            }
        }
    }

    @ViewBuilder
    private func ProfileRow(profile: Profile) -> some View {
        HStack(spacing: 10) {
            Button { pickingProfileIcon = profile.id } label: {
                Image(systemName: profile.icon).foregroundStyle(appearance.accent).frame(width: 20)
            }
            .buttonStyle(.plain)
            .popover(isPresented: bind($pickingProfileIcon, profile.id)) {
                SymbolPicker(symbol: .constant(profile.icon), tint: appearance.accent) { icon in
                    model.updateProfile(profile.id) { $0.icon = icon }
                    pickingProfileIcon = nil
                }
            }

            Text(profile.name)
            if profile.usesDefaultStore {
                Text("original").font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .help("The profile Rune has always browsed as — it keeps the logins you already have.")
            }
            Spacer()
            Text(usage(profile)).font(.caption).foregroundStyle(.secondary)

            Menu {
                Button("Rename…") { renamingProfile = profile.id }
                if model.profiles.count > 1 {
                    Button("Delete Profile", role: .destructive) { confirmingProfileDelete = profile }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).frame(width: 24)
            .popover(isPresented: bind($renamingProfile, profile.id)) {
                RenameField(title: "Rename Profile", name: profile.name) { name in
                    model.updateProfile(profile.id) { $0.name = name }
                    renamingProfile = nil
                }
            }
        }
    }

    // MARK: Bits

    private func tint(_ space: Space) -> Color {
        space.id == model.currentSpaceID ? appearance.accent : .secondary
    }

    private func usage(_ profile: Profile) -> String {
        let count = model.spaces.filter { ($0.profileID ?? model.defaultProfileID) == profile.id }.count
        return count == 1 ? "1 space" : "\(count) spaces"
    }

    /// One popover state per kind, keyed by the row that opened it — a @State
    /// per row would mean a popover per row.
    private func bind(_ state: Binding<UUID?>, _ id: UUID) -> Binding<Bool> {
        Binding(get: { state.wrappedValue == id }, set: { if !$0 { state.wrappedValue = nil } })
    }
}

/// The sidebar's rename popover is private to its file; this is the same shape
/// for Settings. Small enough that sharing it across the boundary would cost
/// more than it saves.
private struct RenameField: View {
    let title: String
    @State private var draft: String
    let apply: (String) -> Void

    init(title: String, name: String, apply: @escaping (String) -> Void) {
        self.title = title
        self.apply = apply
        _draft = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit { apply(draft) }
            HStack {
                Spacer()
                Button("Save") { apply(draft) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}
