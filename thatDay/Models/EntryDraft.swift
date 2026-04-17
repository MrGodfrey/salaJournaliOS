import Foundation

struct EntryDraft: Equatable, Sendable {
    var kind: EntryKind
    var title: String
    var body: String
    var blogTag: String?
    var blogImageLayout: BlogCardImageLayout
    var happenedAt: Date

    init(
        kind: EntryKind,
        title: String,
        body: String,
        blogTag: String? = nil,
        blogImageLayout: BlogCardImageLayout = .landscape,
        happenedAt: Date
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.blogTag = blogTag?.trimmed.nilIfEmpty
        self.blogImageLayout = blogImageLayout
        self.happenedAt = happenedAt
    }

    var normalized: EntryDraft {
        EntryDraft(
            kind: kind,
            title: title.trimmed,
            body: body.trimmed,
            blogTag: blogTag?.trimmed.nilIfEmpty,
            blogImageLayout: blogImageLayout,
            happenedAt: happenedAt
        )
    }
}
