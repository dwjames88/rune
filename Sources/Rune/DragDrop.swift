import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let runeTab = UTType(exportedAs: "com.dwjames.Rune.tab")
    static let runeControl = UTType(exportedAs: "com.dwjames.Rune.control")
}

/// What's being dragged: a live session tab, or a saved (pinned/favorite) entry.
struct TabDrag: Codable, Transferable, Equatable {
    enum Origin: String, Codable { case session, pinned, favorite }
    var id: UUID
    var origin: Origin

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .runeTab)
    }
}

/// A control button on the move during wiggle mode — a command rawValue
/// dragged between the strip and the corner kit.
struct ControlDrag: Codable, Transferable, Equatable {
    var command: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .runeControl)
    }
}
