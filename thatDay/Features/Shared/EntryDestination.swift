import Foundation

struct EntryDestination: Hashable {
    let entryID: UUID
    let startsInEditMode: Bool

    static func read(_ entryID: UUID) -> EntryDestination {
        EntryDestination(entryID: entryID, startsInEditMode: false)
    }

    static func edit(_ entryID: UUID) -> EntryDestination {
        EntryDestination(entryID: entryID, startsInEditMode: true)
    }
}
