import Foundation

struct LocalRepositoryStore {
    let rootURL: URL
    let archiveURL: URL
    let descriptorURL: URL
    let imagesURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        archiveURL = rootURL.appendingPathComponent("repository.json")
        descriptorURL = rootURL.appendingPathComponent("descriptor.json")
        imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
    }

    static func live(processInfo: ProcessInfo = .processInfo) -> LocalRepositoryStore {
        let rootURL: URL
        if let override = processInfo.environment["THATDAY_STORAGE_ROOT"]?.trimmed.nilIfEmpty {
            rootURL = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            rootURL = baseURL.appendingPathComponent("thatDay", isDirectory: true)
        }

        return LocalRepositoryStore(rootURL: rootURL)
    }

    func loadSnapshot() throws -> RepositorySnapshot? {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RepositorySnapshot.self, from: Data(contentsOf: archiveURL))
    }

    func saveSnapshot(_ snapshot: RepositorySnapshot) throws {
        try ensureDirectories()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: archiveURL, options: .atomic)
    }

    func makeSnapshot(
        entries: [EntryRecord],
        updatedAt: Date = Date(),
        embeddingImages: Bool = false
    ) throws -> RepositorySnapshot {
        let embeddedImages = embeddingImages ? try embeddedImages(for: entries) : []
        return RepositorySnapshot(
            entries: entries,
            updatedAt: updatedAt,
            embeddedImages: embeddedImages
        )
    }

    func saveCloudSnapshot(_ snapshot: RepositorySnapshot) throws {
        try syncEmbeddedImages(snapshot.embeddedImages)
        try saveSnapshot(snapshot.removingEmbeddedImages())
    }

    func loadDescriptor() throws -> RepositoryDescriptor? {
        guard FileManager.default.fileExists(atPath: descriptorURL.path) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(RepositoryDescriptor.self, from: Data(contentsOf: descriptorURL))
    }

    func saveDescriptor(_ descriptor: RepositoryDescriptor) throws {
        try ensureDirectories()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(descriptor)
        try data.write(to: descriptorURL, options: .atomic)
    }

    func storeImage(data: Data, suggestedID: UUID) throws -> String {
        try ensureDirectories()
        let compressedData = try EntryImageCompressor.compressedData(for: data)
        let filename = "\(suggestedID.uuidString).jpg"
        let fileURL = imagesURL.appendingPathComponent(filename)
        try compressedData.write(to: fileURL, options: .atomic)
        return filename
    }

    func imageURL(for reference: String?) -> URL? {
        guard let value = reference?.trimmed.nilIfEmpty else {
            return nil
        }

        if let remoteURL = URL(string: value),
           let scheme = remoteURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return remoteURL
        }

        guard let localReference = normalizedLocalImageReference(value) else {
            return nil
        }

        return imagesURL.appendingPathComponent(localReference)
    }

    func exportableFileURLs() throws -> [URL] {
        var files: [URL] = []

        if FileManager.default.fileExists(atPath: archiveURL.path) {
            files.append(archiveURL)
        }

        if FileManager.default.fileExists(atPath: descriptorURL.path) {
            files.append(descriptorURL)
        }

        if FileManager.default.fileExists(atPath: imagesURL.path) {
            let enumerator = FileManager.default.enumerator(
                at: imagesURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true {
                    files.append(url)
                }
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    func resetContents() throws {
        try reset()
        try ensureDirectories()
    }

    func reset() throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: rootURL)
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
    }

    private func embeddedImages(for entries: [EntryRecord]) throws -> [RepositoryImageAsset] {
        var seen: Set<String> = []

        return try entries.compactMap { entry in
            guard let reference = normalizedLocalImageReference(entry.imageReference),
                  seen.insert(reference).inserted else {
                return nil
            }

            let fileURL = imagesURL.appendingPathComponent(reference)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            return RepositoryImageAsset(reference: reference, data: try Data(contentsOf: fileURL))
        }
    }

    private func syncEmbeddedImages(_ embeddedImages: [RepositoryImageAsset]) throws {
        guard !embeddedImages.isEmpty else {
            return
        }

        try ensureDirectories()

        for asset in embeddedImages {
            guard let reference = normalizedLocalImageReference(asset.reference) else {
                continue
            }

            let fileURL = imagesURL.appendingPathComponent(reference)
            try asset.data.write(to: fileURL, options: .atomic)
        }
    }

    private func normalizedLocalImageReference(_ reference: String?) -> String? {
        guard let value = reference?.trimmed.nilIfEmpty else {
            return nil
        }

        if let remoteURL = URL(string: value),
           let scheme = remoteURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return nil
        }

        let normalized = URL(fileURLWithPath: value).lastPathComponent
        guard normalized == value else {
            return nil
        }

        return normalized
    }
}
