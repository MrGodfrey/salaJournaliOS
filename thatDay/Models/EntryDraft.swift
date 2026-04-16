import Foundation

struct EntryDraft: Equatable, Sendable {
    var kind: EntryKind
    var title: String
    var body: String
    var happenedAt: Date

    var normalized: EntryDraft {
        EntryDraft(
            kind: kind,
            title: title.trimmed,
            body: body.trimmed,
            happenedAt: happenedAt
        )
    }
}
