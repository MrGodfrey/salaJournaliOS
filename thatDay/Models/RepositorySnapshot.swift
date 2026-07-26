import Foundation

nonisolated struct RepositoryImageAsset: Codable, Hashable, Sendable, Identifiable {
    var id: String { reference }

    var reference: String
    var data: Data
}

nonisolated struct RepositorySnapshot: Codable, Hashable, Sendable {
    static let defaultVersion = 4
    static let defaultBlogTags = ["Reading", "Watching", "Game", "Trip", "note"]

    var version: Int = RepositorySnapshot.defaultVersion
    var entries: [EntryRecord]
    var updatedAt: Date
    var embeddedImages: [RepositoryImageAsset]
    var blogTags: [String]
    var sharedUpdateNotificationScope: SharedUpdateNotificationScope
    var cloudUploadOperationID: UUID?
    var imageContentHashes: [String: String]

    init(
        entries: [EntryRecord],
        updatedAt: Date = Date(),
        embeddedImages: [RepositoryImageAsset] = [],
        blogTags: [String] = RepositorySnapshot.defaultBlogTags,
        sharedUpdateNotificationScope: SharedUpdateNotificationScope = .all,
        cloudUploadOperationID: UUID? = nil,
        imageContentHashes: [String: String] = [:]
    ) {
        self.entries = entries
        self.updatedAt = updatedAt
        self.embeddedImages = embeddedImages
        self.blogTags = blogTags
        self.sharedUpdateNotificationScope = sharedUpdateNotificationScope
        self.cloudUploadOperationID = cloudUploadOperationID
        self.imageContentHashes = imageContentHashes
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case entries
        case updatedAt
        case embeddedImages = "images"
        case blogTags
        case sharedUpdateNotificationScope
        case cloudUploadOperationID
        case imageContentHashes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        entries = try container.decode([EntryRecord].self, forKey: .entries)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        embeddedImages = try container.decodeIfPresent([RepositoryImageAsset].self, forKey: .embeddedImages) ?? []
        blogTags = try container.decodeIfPresent([String].self, forKey: .blogTags) ?? RepositorySnapshot.defaultBlogTags
        sharedUpdateNotificationScope = try container.decodeIfPresent(SharedUpdateNotificationScope.self, forKey: .sharedUpdateNotificationScope) ?? .all
        cloudUploadOperationID = try container.decodeIfPresent(
            UUID.self,
            forKey: .cloudUploadOperationID
        )
        imageContentHashes = try container.decodeIfPresent(
            [String: String].self,
            forKey: .imageContentHashes
        ) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(blogTags, forKey: .blogTags)
        try container.encode(sharedUpdateNotificationScope, forKey: .sharedUpdateNotificationScope)
        try container.encodeIfPresent(
            cloudUploadOperationID,
            forKey: .cloudUploadOperationID
        )
        if !imageContentHashes.isEmpty {
            try container.encode(
                imageContentHashes,
                forKey: .imageContentHashes
            )
        }
        if !embeddedImages.isEmpty {
            try container.encode(embeddedImages, forKey: .embeddedImages)
        }
    }

    func removingEmbeddedImages() -> RepositorySnapshot {
        RepositorySnapshot(
            entries: entries,
            updatedAt: updatedAt,
            embeddedImages: [],
            blogTags: blogTags,
            sharedUpdateNotificationScope: sharedUpdateNotificationScope,
            cloudUploadOperationID: cloudUploadOperationID,
            imageContentHashes: imageContentHashes
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
