import CryptoKit
import Foundation

nonisolated struct CloudUploadReceipt: Codable, Equatable, Sendable {
    var descriptor: RepositoryDescriptor
    var serverModifiedAt: Date?
    var recordChangeTag: String?
    var uploadedAt: Date
}

nonisolated struct EncryptedResetAcknowledgement: Codable, Equatable, Sendable {
    var operationID: UUID
    var receipt: CloudUploadReceipt
    var attemptedAt: Date?
}

nonisolated enum CloudUploadMode: String, Codable, Equatable, Sendable {
    case normal
    case prepareShare
    case recreateAfterEncryptedDataReset
}

nonisolated struct CloudUploadOutboxRecord: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version: Int
    var repositoryID: String
    var descriptor: RepositoryDescriptor
    var displayName: String
    var snapshot: RepositorySnapshot
    var generation: Int
    var baseRecordChangeTag: String?
    var operationID: UUID
    var predecessorOperationIDs: [UUID]
    var mode: CloudUploadMode
    var contentDigest: String
    var createdAt: Date
    var receipt: CloudUploadReceipt?
    var encryptedResetAcknowledgement: EncryptedResetAcknowledgement?

    init(
        repositoryID: String,
        descriptor: RepositoryDescriptor,
        displayName: String,
        snapshot: RepositorySnapshot,
        generation: Int,
        baseRecordChangeTag: String?,
        operationID: UUID? = nil,
        predecessorOperationIDs: [UUID] = [],
        mode: CloudUploadMode = .normal,
        encryptedResetAcknowledgement: EncryptedResetAcknowledgement? = nil,
        createdAt: Date
    ) throws {
        let resolvedOperationID = operationID ?? UUID()
        var uploadSnapshot = snapshot
        uploadSnapshot.cloudUploadOperationID = resolvedOperationID
        try Self.validateEmbeddedImageCoverage(in: uploadSnapshot)

        version = Self.currentVersion
        self.repositoryID = repositoryID
        self.descriptor = descriptor
        self.displayName = displayName
        self.snapshot = uploadSnapshot
        self.generation = generation
        self.baseRecordChangeTag = baseRecordChangeTag
        self.operationID = resolvedOperationID
        self.predecessorOperationIDs = Array(
            Set(
                predecessorOperationIDs +
                    [encryptedResetAcknowledgement?.operationID].compactMap {
                        $0
                    }
            ).subtracting([resolvedOperationID])
        ).sorted { $0.uuidString < $1.uuidString }
        self.mode = mode
        contentDigest = try Self.digest(for: uploadSnapshot)
        self.createdAt = createdAt
        receipt = nil
        self.encryptedResetAcknowledgement =
            encryptedResetAcknowledgement
    }

    func validatingContent() throws -> CloudUploadOutboxRecord {
        guard version == Self.currentVersion,
              snapshot.cloudUploadOperationID == operationID,
              contentDigest == (try Self.digest(for: snapshot)) else {
            throw CloudRepositoryError.invalidRepositoryData
        }
        try Self.validateEmbeddedImageCoverage(in: snapshot)
        var validatedRecord = self
        if validatedRecord.encryptedResetAcknowledgement == nil,
           mode == .recreateAfterEncryptedDataReset,
           let receipt {
            validatedRecord.encryptedResetAcknowledgement =
                EncryptedResetAcknowledgement(
                    operationID: operationID,
                    receipt: receipt,
                    attemptedAt: nil
                )
        }
        return validatedRecord
    }

    mutating func markUploaded(
        descriptor: RepositoryDescriptor,
        serverModifiedAt: Date?,
        recordChangeTag: String?,
        uploadedAt: Date
    ) {
        let uploadedReceipt = CloudUploadReceipt(
            descriptor: descriptor,
            serverModifiedAt: serverModifiedAt,
            recordChangeTag: recordChangeTag,
            uploadedAt: uploadedAt
        )
        receipt = uploadedReceipt
        if mode == .recreateAfterEncryptedDataReset ||
            encryptedResetAcknowledgement != nil {
            recordEncryptedResetAcknowledgement(
                operationID: operationID,
                receipt: uploadedReceipt
            )
        }
    }

    mutating func recordEncryptedResetAcknowledgement(
        operationID: UUID,
        receipt: CloudUploadReceipt
    ) {
        encryptedResetAcknowledgement =
            EncryptedResetAcknowledgement(
                operationID: operationID,
                receipt: receipt,
                attemptedAt:
                    encryptedResetAcknowledgement?.attemptedAt
            )
    }

    mutating func markEncryptedResetAcknowledgementAttempted(
        at date: Date
    ) {
        guard var acknowledgement =
                encryptedResetAcknowledgement else {
            return
        }
        acknowledgement.attemptedAt = date
        encryptedResetAcknowledgement = acknowledgement
    }

    mutating func clearEncryptedResetAcknowledgement() {
        encryptedResetAcknowledgement = nil
    }

    var successorPredecessorOperationIDs: [UUID] {
        guard receipt == nil ||
                encryptedResetAcknowledgement != nil else {
            return []
        }
        return [operationID] + predecessorOperationIDs
    }

    mutating func advanceBaseRecordChangeTag(
        _ recordChangeTag: String?,
        retainingPredecessorOperationIDs retainedOperationIDs: [UUID] = []
    ) {
        baseRecordChangeTag = recordChangeTag
        predecessorOperationIDs = Array(
            Set(retainedOperationIDs).subtracting([operationID])
        ).sorted { $0.uuidString < $1.uuidString }
    }

    private static func digest(for snapshot: RepositorySnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func validateEmbeddedImageCoverage(
        in snapshot: RepositorySnapshot
    ) throws {
        let requiredReferences = Set(
            snapshot.entries.compactMap {
                normalizedLocalImageReference($0.imageReference)
            }
        )
        let embeddedReferences = Set(
            snapshot.embeddedImages.compactMap {
                normalizedLocalImageReference($0.reference)
            }
        )
        guard requiredReferences.isSubset(of: embeddedReferences) else {
            throw CloudRepositoryError.invalidRepositoryData
        }
    }

    private static func normalizedLocalImageReference(
        _ reference: String?
    ) -> String? {
        guard let value = reference?.trimmed.nilIfEmpty else {
            return nil
        }

        if let parsedURL = URL(string: value),
           let scheme = parsedURL.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return nil
            case "file":
                return parsedURL.lastPathComponent.trimmed.nilIfEmpty
            default:
                break
            }
        }

        return URL(fileURLWithPath: value)
            .lastPathComponent
            .trimmed
            .nilIfEmpty
    }
}

nonisolated struct CloudUploadOutboxStore: Sendable {
    private static let filename = "pending-cloud-upload.json"

    let fileURL: URL

    init(repositoryRootURL: URL) {
        fileURL = repositoryRootURL.appendingPathComponent(Self.filename)
    }

    func load() throws -> CloudUploadOutboxRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder
            .decode(CloudUploadOutboxRecord.self, from: Data(contentsOf: fileURL))
            .validatingContent()
    }

    func save(_ record: CloudUploadOutboxRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}
