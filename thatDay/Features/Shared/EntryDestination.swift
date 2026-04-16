import Foundation

struct EntryDestination: Hashable {
    let entryID: UUID

    static func read(_ entryID: UUID) -> EntryDestination {
        EntryDestination(entryID: entryID)
    }
}
