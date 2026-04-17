import Foundation

enum RepositoryArchiveError: LocalizedError {
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "导入的 ZIP 不是 thatDay 导出的有效仓库。"
        }
    }
}

private struct RepositoryArchiveManifest: Codable {
    var version = 1
    var exportedAt: Date
    var repositoryID: String
    var repositoryName: String
}

struct RepositoryArchiveService {
    func exportArchive(
        from repositoryStore: LocalRepositoryStore,
        repositoryID: String,
        repositoryName: String,
        progress: @escaping @Sendable (_ totalFiles: Int, _ completedFiles: Int) async -> Void
    ) async throws -> URL {
        let fileManager = FileManager.default
        let workingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("thatDay-export-\(UUID().uuidString)", isDirectory: true)
        let repositoryDirectory = workingRoot.appendingPathComponent("repository", isDirectory: true)
        try fileManager.createDirectory(at: repositoryDirectory, withIntermediateDirectories: true)

        let files = try repositoryStore.exportableFileURLs()
        let totalFiles = max(files.count + 1, 1)
        var completedFiles = 0

        for fileURL in files {
            let relativePath = fileURL.path.replacingOccurrences(of: repositoryStore.rootURL.path + "/", with: "")
            let destinationURL = repositoryDirectory.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)
            completedFiles += 1
            await progress(totalFiles, completedFiles)
        }

        let manifest = RepositoryArchiveManifest(
            exportedAt: .now,
            repositoryID: repositoryID,
            repositoryName: repositoryName
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: workingRoot.appendingPathComponent("manifest.json"), options: .atomic)

        let sanitizedName = repositoryName
            .trimmed
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let fallbackName = sanitizedName.nilIfEmpty ?? "thatDay-repository"
        let zipURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(fallbackName)-\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("zip")

        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        try SimpleZipArchive.create(fromDirectory: workingRoot, to: zipURL)
        await progress(totalFiles, totalFiles)
        return zipURL
    }

    func importArchive(
        from zipURL: URL,
        into repositoryStore: LocalRepositoryStore,
        preserving descriptor: RepositoryDescriptor,
        progress: @escaping @Sendable (_ totalFiles: Int, _ completedFiles: Int) async -> Void
    ) async throws -> RepositorySnapshot {
        let fileManager = FileManager.default
        let unzipRoot = fileManager.temporaryDirectory
            .appendingPathComponent("thatDay-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: unzipRoot, withIntermediateDirectories: true)
        try SimpleZipArchive.extract(zipURL: zipURL, to: unzipRoot)

        let repositoryDirectory = try locateRepositoryDirectory(in: unzipRoot)
        let importStore = LocalRepositoryStore(rootURL: repositoryDirectory)
        let sourceArchiveURL = importStore.archiveURL
        guard fileManager.fileExists(atPath: sourceArchiveURL.path) else {
            throw RepositoryArchiveError.invalidArchive
        }

        let sourceFiles = try importStore.exportableFileURLs()
            .filter { $0.lastPathComponent != repositoryStore.descriptorURL.lastPathComponent }
        let totalFiles = max(sourceFiles.count, 1)
        var completedFiles = 0

        try repositoryStore.resetContents()

        let destinationFiles = sourceFiles.map { sourceURL in
            (
                source: sourceURL,
                destination: repositoryStore.rootURL.appendingPathComponent(
                    sourceURL.path.replacingOccurrences(of: repositoryDirectory.path + "/", with: "")
                )
            )
        }

        for pair in destinationFiles {
            try fileManager.createDirectory(at: pair.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: pair.destination.path) {
                try fileManager.removeItem(at: pair.destination)
            }
            try fileManager.copyItem(at: pair.source, to: pair.destination)
            completedFiles += 1
            await progress(totalFiles, completedFiles)
        }

        try repositoryStore.saveDescriptor(descriptor)

        guard let snapshot = try repositoryStore.loadSnapshot() else {
            throw RepositoryArchiveError.invalidArchive
        }

        return snapshot
    }

    private func locateRepositoryDirectory(in unzipRoot: URL) throws -> URL {
        let directRepository = unzipRoot.appendingPathComponent("repository", isDirectory: true)
        if FileManager.default.fileExists(atPath: directRepository.path) {
            return directRepository
        }

        let childDirectories = try FileManager.default.contentsOfDirectory(
            at: unzipRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for child in childDirectories {
            let candidate = child.appendingPathComponent("repository", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw RepositoryArchiveError.invalidArchive
    }
}

private enum SimpleZipArchive {
    private struct Entry {
        let path: String
        let data: Data
        let crc32: UInt32
        let localHeaderOffset: UInt32
    }

    private enum Signature {
        static let localFileHeader: UInt32 = 0x04034b50
        static let centralDirectoryHeader: UInt32 = 0x02014b50
        static let endOfCentralDirectory: UInt32 = 0x06054b50
    }

    static func create(fromDirectory directoryURL: URL, to zipURL: URL) throws {
        let fileURLs = try enumerateFiles(in: directoryURL)

        var archiveData = Data()
        var entries: [Entry] = []

        for fileURL in fileURLs {
            let relativePath = fileURL.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
            let fileData = try Data(contentsOf: fileURL)
            let pathData = Data(relativePath.replacingOccurrences(of: "\\", with: "/").utf8)
            let crc32 = CRC32.checksum(fileData)
            let localHeaderOffset = UInt32(archiveData.count)

            archiveData.append(littleEndian: Signature.localFileHeader)
            archiveData.append(littleEndian: UInt16(20))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: crc32)
            archiveData.append(littleEndian: UInt32(fileData.count))
            archiveData.append(littleEndian: UInt32(fileData.count))
            archiveData.append(littleEndian: UInt16(pathData.count))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(pathData)
            archiveData.append(fileData)

            entries.append(
                Entry(
                    path: relativePath,
                    data: fileData,
                    crc32: crc32,
                    localHeaderOffset: localHeaderOffset
                )
            )
        }

        let centralDirectoryOffset = UInt32(archiveData.count)

        for entry in entries {
            let pathData = Data(entry.path.replacingOccurrences(of: "\\", with: "/").utf8)
            archiveData.append(littleEndian: Signature.centralDirectoryHeader)
            archiveData.append(littleEndian: UInt16(20))
            archiveData.append(littleEndian: UInt16(20))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: entry.crc32)
            archiveData.append(littleEndian: UInt32(entry.data.count))
            archiveData.append(littleEndian: UInt32(entry.data.count))
            archiveData.append(littleEndian: UInt16(pathData.count))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt16(0))
            archiveData.append(littleEndian: UInt32(0))
            archiveData.append(littleEndian: entry.localHeaderOffset)
            archiveData.append(pathData)
        }

        let centralDirectorySize = UInt32(archiveData.count) - centralDirectoryOffset
        archiveData.append(littleEndian: Signature.endOfCentralDirectory)
        archiveData.append(littleEndian: UInt16(0))
        archiveData.append(littleEndian: UInt16(0))
        archiveData.append(littleEndian: UInt16(entries.count))
        archiveData.append(littleEndian: UInt16(entries.count))
        archiveData.append(littleEndian: centralDirectorySize)
        archiveData.append(littleEndian: centralDirectoryOffset)
        archiveData.append(littleEndian: UInt16(0))

        try archiveData.write(to: zipURL, options: .atomic)
    }

    static func extract(zipURL: URL, to directoryURL: URL) throws {
        let data = try Data(contentsOf: zipURL)
        let fileManager = FileManager.default
        var offset = 0

        while offset + 4 <= data.count {
            let signature = try data.readUInt32(at: offset)
            if signature == Signature.localFileHeader {
                let compressionMethod = try data.readUInt16(at: offset + 8)
                guard compressionMethod == 0 else {
                    throw RepositoryArchiveError.invalidArchive
                }

                let compressedSize = try data.readUInt32(at: offset + 18)
                let fileNameLength = Int(try data.readUInt16(at: offset + 26))
                let extraFieldLength = Int(try data.readUInt16(at: offset + 28))
                let fileNameStart = offset + 30
                let fileNameEnd = fileNameStart + fileNameLength
                guard fileNameEnd <= data.count else {
                    throw RepositoryArchiveError.invalidArchive
                }

                let pathData = data.subdata(in: fileNameStart..<fileNameEnd)
                guard let path = String(data: pathData, encoding: .utf8)?.trimmed.nilIfEmpty else {
                    throw RepositoryArchiveError.invalidArchive
                }

                let payloadStart = fileNameEnd + extraFieldLength
                let payloadEnd = payloadStart + Int(compressedSize)
                guard payloadEnd <= data.count else {
                    throw RepositoryArchiveError.invalidArchive
                }

                let outputURL = directoryURL.appendingPathComponent(path)
                try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.subdata(in: payloadStart..<payloadEnd).write(to: outputURL, options: .atomic)
                offset = payloadEnd
                continue
            }

            if signature == Signature.centralDirectoryHeader || signature == Signature.endOfCentralDirectory {
                break
            }

            throw RepositoryArchiveError.invalidArchive
        }
    }

    private static func enumerateFiles(in directoryURL: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url)
            }
        }

        return files.sorted { $0.path < $1.path }
    }
}

private enum CRC32 {
    private static let polynomial: UInt32 = 0xEDB88320
    private static let table: [UInt32] = {
        (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = polynomial ^ (value >> 1)
                } else {
                    value >>= 1
                }
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var normalizedValue = value.littleEndian
        Swift.withUnsafeBytes(of: &normalizedValue) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }

    func readUInt16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else {
            throw RepositoryArchiveError.invalidArchive
        }

        let low = UInt16(self[offset])
        let high = UInt16(self[offset + 1]) << 8
        return low | high
    }

    func readUInt32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw RepositoryArchiveError.invalidArchive
        }

        let byte0 = UInt32(self[offset])
        let byte1 = UInt32(self[offset + 1]) << 8
        let byte2 = UInt32(self[offset + 2]) << 16
        let byte3 = UInt32(self[offset + 3]) << 24
        return byte0 | byte1 | byte2 | byte3
    }
}
