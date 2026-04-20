import Foundation

nonisolated enum EntryKind: String, CaseIterable, Codable, Identifiable, Sendable {
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

nonisolated enum BlogCardImageLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case landscape
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .landscape:
            "Landscape"
        case .portrait:
            "Portrait"
        }
    }
}

nonisolated struct EntryRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: EntryKind
    var title: String
    var body: String
    var blogTag: String?
    var blogImageLayout: BlogCardImageLayout
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
        blogImageLayout: BlogCardImageLayout = .landscape,
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
        self.blogImageLayout = blogImageLayout
        self.happenedAt = happenedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageReference = imageReference?.trimmed.nilIfEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case body
        case blogTag
        case blogImageLayout
        case happenedAt
        case createdAt
        case updatedAt
        case imageReference
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(EntryKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        blogTag = try container.decodeIfPresent(String.self, forKey: .blogTag)?.trimmed.nilIfEmpty
        blogImageLayout = try container.decodeIfPresent(BlogCardImageLayout.self, forKey: .blogImageLayout) ?? .landscape
        happenedAt = try container.decode(Date.self, forKey: .happenedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        imageReference = try container.decodeIfPresent(String.self, forKey: .imageReference)?.trimmed.nilIfEmpty
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(blogTag, forKey: .blogTag)
        try container.encode(blogImageLayout, forKey: .blogImageLayout)
        try container.encode(happenedAt, forKey: .happenedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(imageReference, forKey: .imageReference)
    }

    var summary: String {
        let normalizedBody = body.trimmed
        guard normalizedBody.count > 120 else {
            return normalizedBody
        }

        return normalizedBody.prefix(117) + "..."
    }

    @MainActor
    var weekdayTitle: String {
        AppLanguage.weekdayTitle(for: happenedAt)
    }

    @MainActor
    var timelineTitle: String {
        AppLanguage.timelineTitle(for: happenedAt)
    }

    @MainActor
    var cardDateTitle: String {
        AppLanguage.cardDateTitle(for: happenedAt)
    }

    @MainActor
    var journalCardDateTitle: String {
        AppLanguage.journalCardDateTitle(for: happenedAt)
    }

    @MainActor
    var yearTitle: String {
        AppLanguage.yearTitle(for: happenedAt)
    }

    var displayTitle: String? {
        title.trimmed.nilIfEmpty
    }

    var searchableText: String {
        [title, body]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
