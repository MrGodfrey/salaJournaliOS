import Foundation

nonisolated struct RepositoryImageAsset: Codable, Hashable, Sendable, Identifiable {
    var id: String { reference }

    var reference: String
    var data: Data
}

nonisolated struct RepositorySnapshot: Codable, Hashable, Sendable {
    static let defaultBlogTags = ["Reading", "Watching", "Game", "Trip", "note"]

    var version: Int = 2
    var entries: [EntryRecord]
    var updatedAt: Date
    var embeddedImages: [RepositoryImageAsset]
    var blogTags: [String]

    init(
        entries: [EntryRecord],
        updatedAt: Date = Date(),
        embeddedImages: [RepositoryImageAsset] = [],
        blogTags: [String] = RepositorySnapshot.defaultBlogTags
    ) {
        self.entries = entries
        self.updatedAt = updatedAt
        self.embeddedImages = embeddedImages
        self.blogTags = blogTags
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case entries
        case updatedAt
        case embeddedImages = "images"
        case blogTags
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        entries = try container.decode([EntryRecord].self, forKey: .entries)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        embeddedImages = try container.decodeIfPresent([RepositoryImageAsset].self, forKey: .embeddedImages) ?? []
        blogTags = try container.decodeIfPresent([String].self, forKey: .blogTags) ?? RepositorySnapshot.defaultBlogTags
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(blogTags, forKey: .blogTags)
        if !embeddedImages.isEmpty {
            try container.encode(embeddedImages, forKey: .embeddedImages)
        }
    }

    func removingEmbeddedImages() -> RepositorySnapshot {
        RepositorySnapshot(
            entries: entries,
            updatedAt: updatedAt,
            embeddedImages: [],
            blogTags: blogTags
        )
    }

    static func normalizedBlogTags(_ rawTags: [String], entries: [EntryRecord]) -> [String] {
        var normalized: [String] = []
        var seen: Set<String> = []

        func append(_ value: String?) {
            guard let trimmed = value?.trimmed.nilIfEmpty else {
                return
            }

            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else {
                return
            }

            normalized.append(trimmed)
        }

        rawTags.forEach(append)

        if normalized.isEmpty {
            defaultBlogTags.forEach(append)
        }

        entries
            .filter { $0.kind == .blog }
            .forEach { append($0.blogTag) }

        return normalized.isEmpty ? defaultBlogTags : normalized
    }
}
