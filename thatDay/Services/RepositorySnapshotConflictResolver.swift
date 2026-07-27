import CryptoKit
import Foundation

nonisolated struct RepositorySnapshotConflictResolution: Equatable, Sendable {
    var snapshot: RepositorySnapshot
    var conflictingEntryCopyCount: Int
}

nonisolated enum RepositorySnapshotConflictResolver {
    private enum EntrySource {
        case local
        case remote
    }

    private struct SourcedEntry {
        var entry: EntryRecord
        var source: EntrySource
    }

    static func merge(
        base: RepositorySnapshot?,
        local: RepositorySnapshot,
        remote: RepositorySnapshot,
        mergedAt: Date
    ) -> RepositorySnapshotConflictResolution {
        let baseByID = Dictionary(
            uniqueKeysWithValues: (base?.entries ?? []).map { ($0.id, $0) }
        )
        let localByID = Dictionary(
            uniqueKeysWithValues: local.entries.map { ($0.id, $0) }
        )
        let remoteByID = Dictionary(
            uniqueKeysWithValues: remote.entries.map { ($0.id, $0) }
        )
        let orderedIDs = orderedEntryIDs(local: local, remote: remote)
        var occupiedEntryIDs = Set(orderedIDs)

        var mergedEntries: [SourcedEntry] = []
        var conflictingEntryCopyCount = 0

        for entryID in orderedIDs {
            let baseEntry = baseByID[entryID]
            let localEntry = localByID[entryID]
            let remoteEntry = remoteByID[entryID]

            switch (baseEntry, localEntry, remoteEntry) {
            case (_, let localEntry?, let remoteEntry?)
                where entriesAreEquivalent(
                    localEntry,
                    in: local,
                    remoteEntry,
                    in: remote
                ):
                mergedEntries.append(
                    SourcedEntry(entry: remoteEntry, source: .remote)
                )

            case (let baseEntry?, let localEntry?, let remoteEntry?)
                where entriesAreEquivalent(
                    localEntry,
                    in: local,
                    baseEntry,
                    in: base
                ):
                mergedEntries.append(
                    SourcedEntry(entry: remoteEntry, source: .remote)
                )

            case (let baseEntry?, let localEntry?, let remoteEntry?)
                where entriesAreEquivalent(
                    remoteEntry,
                    in: remote,
                    baseEntry,
                    in: base
                ):
                mergedEntries.append(
                    SourcedEntry(entry: localEntry, source: .local)
                )

            case (_, let localEntry?, let remoteEntry?):
                mergedEntries.append(
                    SourcedEntry(entry: remoteEntry, source: .remote)
                )
                let preferredCopyID =
                    deterministicConflictCopyID(
                        for: localEntry,
                        in: local,
                        collisionIndex: 0
                    )
                let existingPreferredEntry =
                    remoteByID[preferredCopyID].map {
                        ($0, remote)
                    } ??
                    localByID[preferredCopyID].map {
                        ($0, local)
                    }
                let alreadyPreserved =
                    existingPreferredEntry.map {
                        entriesAreEquivalentConflictCopy(
                            localEntry,
                            in: local,
                            $0.0,
                            in: $0.1
                        )
                    } ?? false
                if !alreadyPreserved {
                    var collisionIndex = 0
                    var conflictCopyID = preferredCopyID
                    while occupiedEntryIDs.contains(conflictCopyID) {
                        collisionIndex += 1
                        conflictCopyID =
                            deterministicConflictCopyID(
                                for: localEntry,
                                in: local,
                                collisionIndex: collisionIndex
                            )
                    }
                    var conflictCopy = localEntry
                    conflictCopy.id = conflictCopyID
                    occupiedEntryIDs.insert(conflictCopyID)
                    mergedEntries.append(
                        SourcedEntry(
                            entry: conflictCopy,
                            source: .local
                        )
                    )
                    conflictingEntryCopyCount += 1
                }

            case (let baseEntry?, nil, let remoteEntry?):
                // A local deletion wins when the remote entry is unchanged.
                // If the remote entry was edited too, retain that edit so data
                // is never destroyed by an ambiguous delete/update conflict.
                if !entriesAreEquivalent(
                    remoteEntry,
                    in: remote,
                    baseEntry,
                    in: base
                ) {
                    mergedEntries.append(
                        SourcedEntry(entry: remoteEntry, source: .remote)
                    )
                }

            case (let baseEntry?, let localEntry?, nil):
                // A remote deletion wins when the local entry is unchanged.
                // If the local entry was edited too, retain that edit.
                if !entriesAreEquivalent(
                    localEntry,
                    in: local,
                    baseEntry,
                    in: base
                ) {
                    mergedEntries.append(
                        SourcedEntry(entry: localEntry, source: .local)
                    )
                }

            case (nil, nil, let remoteEntry?):
                mergedEntries.append(
                    SourcedEntry(entry: remoteEntry, source: .remote)
                )

            case (nil, let localEntry?, nil):
                mergedEntries.append(
                    SourcedEntry(entry: localEntry, source: .local)
                )

            case (_, nil, nil):
                break
            }
        }

        let mergedAssets = mergeImageAssets(
            entries: &mergedEntries,
            localAssets: local.embeddedImages,
            remoteAssets: remote.embeddedImages
        )
        let resolvedEntries = mergedEntries.map(\.entry)
        let resolvedTags = RepositorySnapshot.normalizedBlogTags(
            remote.blogTags + local.blogTags,
            entries: resolvedEntries
        )
        let resolvedNotificationScope = resolveSetting(
            base: base?.sharedUpdateNotificationScope,
            local: local.sharedUpdateNotificationScope,
            remote: remote.sharedUpdateNotificationScope
        )

        return RepositorySnapshotConflictResolution(
            snapshot: RepositorySnapshot(
                entries: resolvedEntries,
                updatedAt: max(
                    mergedAt,
                    max(local.updatedAt, remote.updatedAt)
                ),
                embeddedImages: mergedAssets,
                blogTags: resolvedTags,
                sharedUpdateNotificationScope: resolvedNotificationScope
            ),
            conflictingEntryCopyCount: conflictingEntryCopyCount
        )
    }

    private static func entriesAreEquivalent(
        _ lhs: EntryRecord,
        in lhsSnapshot: RepositorySnapshot,
        _ rhs: EntryRecord,
        in rhsSnapshot: RepositorySnapshot?
    ) -> Bool {
        guard entriesAreEquivalentAtCloudPayloadPrecision(
            lhs,
            rhs
        ) else {
            return false
        }
        guard let reference = lhs.imageReference,
              reference == rhs.imageReference,
              let rhsSnapshot else {
            return true
        }
        let lhsHash = imageContentHash(
            for: reference,
            in: lhsSnapshot
        )
        let rhsHash = imageContentHash(
            for: reference,
            in: rhsSnapshot
        )
        guard let lhsHash, let rhsHash else {
            // Old snapshots may not contain image hashes. In that case the
            // immutable reference remains the strongest available evidence.
            return true
        }
        return lhsHash == rhsHash
    }

    private static func entriesAreEquivalentConflictCopy(
        _ lhs: EntryRecord,
        in lhsSnapshot: RepositorySnapshot,
        _ rhs: EntryRecord,
        in rhsSnapshot: RepositorySnapshot
    ) -> Bool {
        let lhsImageReference = lhs.imageReference
        let rhsImageReference = rhs.imageReference
        var normalizedLHS = lhs
        var normalizedRHS = rhs
        normalizedRHS.id = lhs.id
        normalizedLHS.imageReference = nil
        normalizedRHS.imageReference = nil
        guard entriesAreEquivalentAtCloudPayloadPrecision(
            normalizedLHS,
            normalizedRHS
        ) else {
            return false
        }

        switch (lhsImageReference, rhsImageReference) {
        case (nil, nil):
            return true
        case (let lhsReference?, let rhsReference?):
            let lhsHash = imageContentHash(
                for: lhsReference,
                in: lhsSnapshot
            )
            let rhsHash = imageContentHash(
                for: rhsReference,
                in: rhsSnapshot
            )
            if let lhsHash, let rhsHash {
                return lhsHash == rhsHash
            }
            return lhsReference == rhsReference
        case (nil, _), (_, nil):
            return false
        }
    }

    private static func entriesAreEquivalentAtCloudPayloadPrecision(
        _ lhs: EntryRecord,
        _ rhs: EntryRecord
    ) -> Bool {
        lhs.id == rhs.id &&
            lhs.kind == rhs.kind &&
            lhs.title == rhs.title &&
            lhs.body == rhs.body &&
            lhs.blogTag == rhs.blogTag &&
            lhs.blogImageLayout == rhs.blogImageLayout &&
            cloudPayloadDatesAreEquivalent(
                lhs.happenedAt,
                rhs.happenedAt
            ) &&
            cloudPayloadDatesAreEquivalent(
                lhs.createdAt,
                rhs.createdAt
            ) &&
            cloudPayloadDatesAreEquivalent(
                lhs.updatedAt,
                rhs.updatedAt
            ) &&
            lhs.imageReference == rhs.imageReference
    }

    private static func cloudPayloadDatesAreEquivalent(
        _ lhs: Date,
        _ rhs: Date
    ) -> Bool {
        // CloudRepositoryService intentionally retains the existing
        // JSONEncoder.iso8601 wire format for compatibility with installed
        // clients. That format stores whole seconds, so the local durable
        // ancestor and its server round-trip must compare at the same
        // precision instead of creating a false conflict copy.
        floor(lhs.timeIntervalSince1970) ==
            floor(rhs.timeIntervalSince1970)
    }

    private static func imageContentHash(
        for reference: String,
        in snapshot: RepositorySnapshot
    ) -> String? {
        if let storedHash = snapshot.imageContentHashes[reference] {
            return storedHash
        }
        guard let data = snapshot.embeddedImages.first(where: {
            $0.reference == reference
        })?.data else {
            return nil
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func orderedEntryIDs(
        local: RepositorySnapshot,
        remote: RepositorySnapshot
    ) -> [UUID] {
        var seen: Set<UUID> = []
        var result: [UUID] = []
        for entry in remote.entries + local.entries
        where seen.insert(entry.id).inserted {
            result.append(entry.id)
        }
        return result
    }

    private static func resolveSetting<Value: Equatable>(
        base: Value?,
        local: Value,
        remote: Value
    ) -> Value {
        guard let base else {
            // Legacy v2 outboxes have no trustworthy ancestor. Keep the
            // server's canonical repository-level setting while still
            // conservatively unioning entry content.
            return remote
        }
        if local == remote {
            return local
        }
        if local == base {
            return remote
        }
        if remote == base {
            return local
        }
        return local
    }

    private static func deterministicConflictCopyID(
        for entry: EntryRecord,
        in snapshot: RepositorySnapshot,
        collisionIndex: Int
    ) -> UUID {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        var encodedEntry = (try? encoder.encode(entry)) ??
            Data(entry.id.uuidString.utf8)
        if let reference = entry.imageReference,
           let imageHash = imageContentHash(
                for: reference,
                in: snapshot
           ) {
            encodedEntry.append(Data(imageHash.utf8))
        }
        var bigEndianCollisionIndex =
            UInt64(collisionIndex).bigEndian
        withUnsafeBytes(of: &bigEndianCollisionIndex) {
            encodedEntry.append(contentsOf: $0)
        }
        let digest = SHA256.hash(data: encodedEntry)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    private static func mergeImageAssets(
        entries: inout [SourcedEntry],
        localAssets: [RepositoryImageAsset],
        remoteAssets: [RepositoryImageAsset]
    ) -> [RepositoryImageAsset] {
        let localByReference = Dictionary(
            localAssets.map { ($0.reference, $0.data) },
            uniquingKeysWith: { first, _ in first }
        )
        let remoteByReference = Dictionary(
            remoteAssets.map { ($0.reference, $0.data) },
            uniquingKeysWith: { first, _ in first }
        )
        var mergedByReference = remoteByReference

        for index in entries.indices {
            guard entries[index].source == .local,
                  let reference = entries[index].entry.imageReference,
                  let localData = localByReference[reference] else {
                continue
            }

            if let remoteData = remoteByReference[reference],
               remoteData != localData {
                let conflictReference = deterministicConflictImageReference(
                    originalReference: reference,
                    data: localData
                )
                entries[index].entry.imageReference = conflictReference
                mergedByReference[conflictReference] = localData
            } else {
                mergedByReference[reference] = localData
            }
        }

        let referencedImages = Set(
            entries.compactMap { $0.entry.imageReference }
        )
        return referencedImages.compactMap { reference in
            guard let data = mergedByReference[reference] else {
                return nil
            }
            return RepositoryImageAsset(reference: reference, data: data)
        }
        .sorted { $0.reference < $1.reference }
    }

    private static func deterministicConflictImageReference(
        originalReference: String,
        data: Data
    ) -> String {
        let filename = URL(fileURLWithPath: originalReference)
            .lastPathComponent
        let pathExtension = (filename as NSString).pathExtension
        let basename = (filename as NSString).deletingPathExtension
        let suffix = SHA256.hash(data: data)
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
        let resolvedBasename = basename.isEmpty ? "image" : basename
        let resolvedExtension = pathExtension.isEmpty
            ? ""
            : ".\(pathExtension)"
        return "\(resolvedBasename)-local-conflict-\(suffix)\(resolvedExtension)"
    }
}
