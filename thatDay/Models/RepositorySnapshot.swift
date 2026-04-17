import Foundation

struct RepositoryImageAsset: Codable, Hashable, Sendable, Identifiable {
    var id: String { reference }

    var reference: String
    var data: Data
}

struct RepositorySnapshot: Codable, Hashable, Sendable {
    var version: Int = 1
    var entries: [EntryRecord]
    var updatedAt: Date
    var embeddedImages: [RepositoryImageAsset]

    init(
        entries: [EntryRecord],
        updatedAt: Date = Date(),
        embeddedImages: [RepositoryImageAsset] = []
    ) {
        self.entries = entries
        self.updatedAt = updatedAt
        self.embeddedImages = embeddedImages
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case entries
        case updatedAt
        case embeddedImages = "images"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        entries = try container.decode([EntryRecord].self, forKey: .entries)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        embeddedImages = try container.decodeIfPresent([RepositoryImageAsset].self, forKey: .embeddedImages) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(updatedAt, forKey: .updatedAt)
        if !embeddedImages.isEmpty {
            try container.encode(embeddedImages, forKey: .embeddedImages)
        }
    }

    func removingEmbeddedImages() -> RepositorySnapshot {
        RepositorySnapshot(
            entries: entries,
            updatedAt: updatedAt,
            embeddedImages: []
        )
    }
}
