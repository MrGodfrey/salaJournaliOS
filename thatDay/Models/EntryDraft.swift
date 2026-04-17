import Foundation

struct EntryDraft: Equatable, Sendable {
    var kind: EntryKind
    var title: String
    var body: String
    var blogTag: String?
    var happenedAt: Date

    init(
        kind: EntryKind,
        title: String,
        body: String,
        blogTag: String? = nil,
        happenedAt: Date
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.blogTag = blogTag?.trimmed.nilIfEmpty
        self.happenedAt = happenedAt
    }

    var normalized: EntryDraft {
        EntryDraft(
            kind: kind,
            title: title.trimmed,
            body: body.trimmed,
            blogTag: blogTag?.trimmed.nilIfEmpty,
            happenedAt: happenedAt
        )
    }
}
