import Foundation

struct RepositoryLibraryStore {
    private enum Constant {
        static let catalogFilename = "repositories.json"
        static let preferencesFilename = "preferences.json"
        static let repositoriesDirectory = "repositories"
    }

    let rootURL: URL
    let repositoriesURL: URL
    let catalogURL: URL
    let preferencesURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        repositoriesURL = rootURL.appendingPathComponent(Constant.repositoriesDirectory, isDirectory: true)
        catalogURL = rootURL.appendingPathComponent(Constant.catalogFilename)
        preferencesURL = rootURL.appendingPathComponent(Constant.preferencesFilename)
    }

    static func live(processInfo: ProcessInfo = .processInfo) -> RepositoryLibraryStore {
        let rootURL: URL
        if let override = processInfo.environment["THATDAY_STORAGE_ROOT"]?.trimmed.nilIfEmpty {
            rootURL = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            rootURL = baseURL.appendingPathComponent("thatDay", isDirectory: true)
        }

        return RepositoryLibraryStore(rootURL: rootURL)
    }

    func repositoryStore(for repositoryID: String) -> LocalRepositoryStore {
        LocalRepositoryStore(rootURL: repositoriesURL.appendingPathComponent(repositoryID, isDirectory: true))
    }

    func loadCatalog() throws -> [RepositoryReference] {
        try migrateLegacySingleRepositoryIfNeeded()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let references: [RepositoryReference]
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            references = try decoder.decode([RepositoryReference].self, from: Data(contentsOf: catalogURL))
        } else {
            references = [try makeLocalReference()]
            try saveCatalog(references)
        }

        let normalized = try normalizeCatalog(references)
        if normalized != references {
            try saveCatalog(normalized)
        }

        return normalized
    }

    func saveCatalog(_ references: [RepositoryReference]) throws {
        try ensureDirectories()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(references)
        try data.write(to: catalogURL, options: .atomic)
    }

    func loadPreferences() throws -> AppPreferences {
        try ensureDirectories()

        guard FileManager.default.fileExists(atPath: preferencesURL.path) else {
            let preferences = AppPreferences()
            try savePreferences(preferences)
            return preferences
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AppPreferences.self, from: Data(contentsOf: preferencesURL))
    }

    func savePreferences(_ preferences: AppPreferences) throws {
        try ensureDirectories()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: preferencesURL, options: .atomic)
    }

    func repositoryID(for descriptor: RepositoryDescriptor) -> String {
        descriptor.storageIdentifier
    }

    func removeRepositoryDirectory(repositoryID: String) throws {
        guard repositoryID != RepositoryReference.localRepositoryID else {
            return
        }

        let url = repositoriesURL.appendingPathComponent(repositoryID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    private func normalizeCatalog(_ references: [RepositoryReference]) throws -> [RepositoryReference] {
        let localReference = try makeLocalReference()
        var normalized = references.filter { $0.id != RepositoryReference.localRepositoryID }
        normalized.insert(localReference, at: 0)

        var seen: Set<String> = []
        normalized = normalized.filter { reference in
            seen.insert(reference.id).inserted
        }

        return normalized
    }

    private func makeLocalReference() throws -> RepositoryReference {
        let localStore = repositoryStore(for: RepositoryReference.localRepositoryID)
        let descriptor = try localStore.loadDescriptor() ?? .local
        let snapshot = try localStore.loadSnapshot()

        return RepositoryReference(
            id: RepositoryReference.localRepositoryID,
            displayName: "My Repository",
            descriptor: descriptor,
            source: .local,
            lastKnownSnapshotUpdatedAt: snapshot?.updatedAt
        )
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoriesURL, withIntermediateDirectories: true)
    }

    private func migrateLegacySingleRepositoryIfNeeded() throws {
        try ensureDirectories()

        let localStore = repositoryStore(for: RepositoryReference.localRepositoryID)
        if FileManager.default.fileExists(atPath: localStore.rootURL.path) {
            return
        }

        let legacyStore = LocalRepositoryStore(rootURL: rootURL)
        let hasLegacyFiles =
            FileManager.default.fileExists(atPath: legacyStore.archiveURL.path) ||
            FileManager.default.fileExists(atPath: legacyStore.descriptorURL.path) ||
            FileManager.default.fileExists(atPath: legacyStore.imagesURL.path)

        guard hasLegacyFiles else {
            try FileManager.default.createDirectory(at: localStore.rootURL, withIntermediateDirectories: true)
            try localStore.saveDescriptor(.local)
            return
        }

        try FileManager.default.createDirectory(at: localStore.rootURL, withIntermediateDirectories: true)

        let migrations: [(URL, URL)] = [
            (legacyStore.archiveURL, localStore.archiveURL),
            (legacyStore.descriptorURL, localStore.descriptorURL),
            (legacyStore.imagesURL, localStore.imagesURL)
        ]

        for (source, destination) in migrations {
            guard FileManager.default.fileExists(atPath: source.path),
                  !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }

            try FileManager.default.moveItem(at: source, to: destination)
        }

        if try localStore.loadDescriptor() == nil {
            try localStore.saveDescriptor(.local)
        }
    }
}
