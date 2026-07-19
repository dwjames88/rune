import SwiftUI

/// Searchable SF Symbol grid. The grid covers a broad curated set; the text
/// field accepts *any* SF Symbol name, so it isn't limited to the list.
struct SymbolPicker: View {
    @Binding var symbol: String
    let tint: Color
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var custom = ""

    private var results: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.symbols }
        return Self.symbols.filter { $0.contains(q) }
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search symbols", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(results, id: \.self) { name in
                        Button { onPick(name) } label: {
                            Image(systemName: name)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                // Contrast-picked on the tint fill: a light
                                // folder colour needs black, not white.
                                .foregroundStyle(name == symbol ? (tint.prefersLightText ? .white : .black) : tint)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(name == symbol ? tint : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
                .padding(2)
            }
            .frame(height: 190)

            HStack(spacing: 6) {
                TextField("Any SF Symbol name…", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyCustom)
                Button("Set", action: applyCustom)
                    .disabled(NSImage(systemSymbolName: custom, accessibilityDescription: nil) == nil)
            }
        }
        .frame(width: 300)
        .padding(10)
    }

    private func applyCustom() {
        guard NSImage(systemSymbolName: custom, accessibilityDescription: nil) != nil else { return }
        onPick(custom)
    }

    /// A broad set across the common categories.
    static let symbols: [String] = [
        "folder.fill", "folder", "tray.full.fill", "archivebox.fill", "shippingbox.fill",
        "star.fill", "star", "heart.fill", "bolt.fill", "flame.fill", "sparkles", "crown.fill",
        "briefcase.fill", "case.fill", "building.2.fill", "building.columns.fill", "hammer.fill",
        "wrench.and.screwdriver.fill", "gearshape.fill", "cpu.fill", "server.rack", "terminal.fill",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "keyboard.fill", "desktopcomputer",
        "laptopcomputer", "iphone", "ipad", "applewatch", "headphones", "airpods",
        "book.fill", "books.vertical.fill", "text.book.closed.fill", "graduationcap.fill",
        "newspaper.fill", "doc.fill", "doc.text.fill", "note.text", "pencil", "highlighter",
        "paintbrush.fill", "paintpalette.fill", "photo.fill", "camera.fill", "video.fill",
        "film.fill", "tv.fill", "play.rectangle.fill", "music.note", "guitars.fill", "mic.fill",
        "gamecontroller.fill", "dice.fill", "puzzlepiece.fill", "trophy.fill", "medal.fill",
        "cart.fill", "bag.fill", "creditcard.fill", "dollarsign.circle.fill", "chart.pie.fill",
        "chart.bar.fill", "chart.line.uptrend.xyaxis", "banknote.fill", "wallet.pass.fill",
        "envelope.fill", "paperplane.fill", "message.fill", "bubble.left.and.bubble.right.fill",
        "phone.fill", "bell.fill", "megaphone.fill", "person.fill", "person.2.fill",
        "person.crop.circle.fill", "figure.walk", "figure.run", "hand.wave.fill",
        "house.fill", "bed.double.fill", "sofa.fill", "lamp.desk.fill", "shower.fill",
        "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "birthday.cake.fill", "carrot.fill",
        "leaf.fill", "tree.fill", "globe.americas.fill", "globe.europe.africa.fill", "map.fill",
        "mappin.and.ellipse", "location.fill", "airplane", "car.fill", "bus.fill", "bicycle",
        "tram.fill", "ferry.fill", "fuelpump.fill", "sailboat.fill",
        "sun.max.fill", "moon.fill", "cloud.fill", "cloud.rain.fill", "snowflake", "wind",
        "thermometer.medium", "drop.fill", "waveform", "antenna.radiowaves.left.and.right",
        "lock.fill", "lock.open.fill", "key.fill", "shield.fill", "eye.fill", "eye.slash.fill",
        "checkmark.seal.fill", "exclamationmark.triangle.fill", "questionmark.circle.fill",
        "info.circle.fill", "flag.fill", "tag.fill", "bookmark.fill", "pin.fill", "paperclip",
        "link", "magnifyingglass", "calendar", "clock.fill", "timer", "alarm.fill", "stopwatch.fill",
        "list.bullet", "square.grid.2x2.fill", "rectangle.stack.fill", "tray.2.fill",
        "arrow.up.circle.fill", "arrow.down.circle.fill", "arrow.triangle.2.circlepath",
        "trash.fill", "cross.case.fill", "pills.fill", "stethoscope", "heart.text.square.fill",
        "dumbbell.fill", "sportscourt.fill", "basketball.fill", "soccerball", "football.fill",
        "atom", "testtube.2", "microscope", "brain.head.profile", "lightbulb.fill", "wand.and.stars",
    ]
}
