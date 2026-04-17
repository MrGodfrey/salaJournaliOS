import Foundation

enum EntryKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case journal
    case blog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal:
            "Journal"
        case .blog:
            "Blog"
        }
    }

    var systemImage: String {
        switch self {
        case .journal:
            "book"
        case .blog:
            "doc.text.image"
        }
    }
}

struct EntryRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: EntryKind
    var title: String
    var body: String
    var blogTag: String?
    var happenedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var imageReference: String?

    init(
        id: UUID = UUID(),
        kind: EntryKind,
        title: String,
        body: String,
        blogTag: String? = nil,
        happenedAt: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imageReference: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.blogTag = blogTag?.trimmed.nilIfEmpty
        self.happenedAt = happenedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageReference = imageReference?.trimmed.nilIfEmpty
    }

    var summary: String {
        let normalizedBody = body.trimmed
        guard normalizedBody.count > 120 else {
            return normalizedBody
        }

        return normalizedBody.prefix(117) + "..."
    }

    var weekdayTitle: String {
        AppLanguage.weekdayTitle(for: happenedAt)
    }

    var timelineTitle: String {
        AppLanguage.timelineTitle(for: happenedAt)
    }

    var cardDateTitle: String {
        AppLanguage.cardDateTitle(for: happenedAt)
    }

    var searchableText: String {
        [title, body]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
