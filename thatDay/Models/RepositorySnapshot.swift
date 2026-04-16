import Foundation

struct RepositorySnapshot: Codable, Hashable, Sendable {
    var version: Int = 1
    var entries: [EntryRecord]
    var updatedAt: Date

    init(entries: [EntryRecord], updatedAt: Date = Date()) {
        self.entries = entries
        self.updatedAt = updatedAt
    }
}
