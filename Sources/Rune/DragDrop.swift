import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let runeTab = UTType(exportedAs: "com.dwjames.Rune.tab")
    static let runeFinderItem = UTType(exportedAs: "com.dwjames.Rune.finderItem")
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

/// A Finder library item on the move — dropped onto a rail folder to file it.
struct FinderItemDrag: Codable, Transferable, Equatable {
    var id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .runeFinderItem)
    }
}
