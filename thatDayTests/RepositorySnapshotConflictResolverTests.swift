import XCTest
@testable import thatDay

final class RepositorySnapshotConflictResolverTests:
    AppStoreTestCase {
    func testLegacyTwoWayMergeKeepsIndependentLocalAndRemoteEntries() {
        let localDate = fixtureDate("2026-07-27T05:00:00Z")
        let remoteDate = fixtureDate("2026-07-27T05:01:00Z")
        let localEntry = makeEntry(
            title: "Pending local journal",
            happenedAt: localDate
        )
        let remoteEntry = makeEntry(
            title: "Girlfriend remote journal",
            happenedAt: remoteDate
        )

        let resolution = RepositorySnapshotConflictResolver.merge(
            base: nil,
            local: RepositorySnapshot(
                entries: [localEntry],
                updatedAt: localDate,
                sharedUpdateNotificationScope: .all
            ),
            remote: RepositorySnapshot(
                entries: [remoteEntry],
                updatedAt: remoteDate,
                sharedUpdateNotificationScope: .blog
            ),
            mergedAt: remoteDate
        )

        XCTAssertEqual(
            Set(resolution.snapshot.entries.map(\.id)),
            Set([localEntry.id, remoteEntry.id])
        )
        XCTAssertEqual(resolution.conflictingEntryCopyCount, 0)
        XCTAssertEqual(
            resolution.snapshot.sharedUpdateNotificationScope,
            .blog
        )
    }

    func testThreeWayMergeHonorsUncontestedDeletionsAndPreservesDeleteEditConflicts() {
        let baseDate = fixtureDate("2026-07-27T05:10:00Z")
        let editDate = fixtureDate("2026-07-27T05:11:00Z")
        let locallyDeleted = makeEntry(
            title: "Locally deleted",
            happenedAt: baseDate
        )
        let remotelyDeleted = makeEntry(
            title: "Remotely deleted",
            happenedAt: baseDate
        )
        let remoteEditAfterLocalDelete = makeEntry(
            title: "Remote edit survives",
            happenedAt: baseDate
        )
        let localEditAfterRemoteDelete = makeEntry(
            title: "Local edit survives",
            happenedAt: baseDate
        )
        let baseEntries = [
            locallyDeleted,
            remotelyDeleted,
            remoteEditAfterLocalDelete,
            localEditAfterRemoteDelete
        ]
        var editedRemote = remoteEditAfterLocalDelete
        editedRemote.body = "Edited remotely while local deleted"
        editedRemote.updatedAt = editDate
        var editedLocal = localEditAfterRemoteDelete
        editedLocal.body = "Edited locally while remote deleted"
        editedLocal.updatedAt = editDate

        let resolution = RepositorySnapshotConflictResolver.merge(
            base: RepositorySnapshot(
                entries: baseEntries,
                updatedAt: baseDate
            ),
            local: RepositorySnapshot(
                entries: [remotelyDeleted, editedLocal],
                updatedAt: editDate
            ),
            remote: RepositorySnapshot(
                entries: [locallyDeleted, editedRemote],
                updatedAt: editDate
            ),
            mergedAt: editDate
        )
        let mergedByID = Dictionary(
            uniqueKeysWithValues:
                resolution.snapshot.entries.map { ($0.id, $0) }
        )

        XCTAssertNil(mergedByID[locallyDeleted.id])
        XCTAssertNil(mergedByID[remotelyDeleted.id])
        XCTAssertEqual(
            mergedByID[remoteEditAfterLocalDelete.id]?.body,
            editedRemote.body
        )
        XCTAssertEqual(
            mergedByID[localEditAfterRemoteDelete.id]?.body,
            editedLocal.body
        )
    }

    func testConcurrentSameEntryEditsKeepRemoteIdentityAndDeterministicLocalCopy() {
        let baseDate = fixtureDate("2026-07-27T05:20:00Z")
        let editDate = fixtureDate("2026-07-27T05:21:00Z")
        let entryID = UUID()
        let baseEntry = EntryRecord(
            id: entryID,
            kind: .journal,
            title: "Shared draft",
            body: "Base",
            happenedAt: baseDate,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        var localEntry = baseEntry
        localEntry.body = "Local edit"
        localEntry.updatedAt = editDate
        var remoteEntry = baseEntry
        remoteEntry.body = "Remote edit"
        remoteEntry.updatedAt =
            editDate.addingTimeInterval(1)
        let base = RepositorySnapshot(
            entries: [baseEntry],
            updatedAt: baseDate
        )
        let local = RepositorySnapshot(
            entries: [localEntry],
            updatedAt: editDate
        )
        let remote = RepositorySnapshot(
            entries: [remoteEntry],
            updatedAt: editDate.addingTimeInterval(1)
        )

        let first = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: local,
            remote: remote,
            mergedAt: editDate.addingTimeInterval(2)
        )
        let second = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: local,
            remote: remote,
            mergedAt: editDate.addingTimeInterval(2)
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.conflictingEntryCopyCount, 1)
        XCTAssertEqual(first.snapshot.entries.count, 2)
        XCTAssertEqual(
            first.snapshot.entries.first(where: {
                $0.id == entryID
            })?.body,
            "Remote edit"
        )
        let localCopy = try? XCTUnwrap(
            first.snapshot.entries.first(where: {
                $0.id != entryID
            })
        )
        XCTAssertEqual(localCopy?.body, "Local edit")
        XCTAssertEqual(localCopy?.title, localEntry.title)
    }

    func testCloudWireSecondPrecisionDoesNotCreateFalseEditOrDeleteConflicts() {
        let wholeSecond =
            fixtureDate("2026-07-27T05:25:00Z")
        let preciseDate =
            wholeSecond.addingTimeInterval(0.789)
        let canonicalDate = Date(
            timeIntervalSince1970:
                floor(preciseDate.timeIntervalSince1970)
        )
        let historicalPreciseDate = Date(
            timeIntervalSince1970: -100.789
        )
        let historicalCanonicalDate = Date(
            timeIntervalSince1970:
                floor(
                    historicalPreciseDate
                        .timeIntervalSince1970
                )
        )
        let editedID = UUID()
        let deletedID = UUID()
        let baseEditedEntry = EntryRecord(
            id: editedID,
            kind: .journal,
            title: "Local edit",
            body: "Base",
            happenedAt: historicalPreciseDate,
            createdAt: preciseDate,
            updatedAt: preciseDate
        )
        let baseDeletedEntry = EntryRecord(
            id: deletedID,
            kind: .journal,
            title: "Local delete",
            body: "Base",
            happenedAt: historicalPreciseDate,
            createdAt: preciseDate,
            updatedAt: preciseDate
        )
        var localEditedEntry = baseEditedEntry
        localEditedEntry.body = "Edited only on this device"
        localEditedEntry.updatedAt =
            preciseDate.addingTimeInterval(60)
        var remoteEditedEntry = baseEditedEntry
        remoteEditedEntry.happenedAt =
            historicalCanonicalDate
        remoteEditedEntry.createdAt = canonicalDate
        remoteEditedEntry.updatedAt = canonicalDate
        var remoteDeletedEntry = baseDeletedEntry
        remoteDeletedEntry.happenedAt =
            historicalCanonicalDate
        remoteDeletedEntry.createdAt = canonicalDate
        remoteDeletedEntry.updatedAt = canonicalDate

        let resolution = RepositorySnapshotConflictResolver.merge(
            base: RepositorySnapshot(
                entries: [baseEditedEntry, baseDeletedEntry],
                updatedAt: preciseDate
            ),
            local: RepositorySnapshot(
                entries: [localEditedEntry],
                updatedAt:
                    preciseDate.addingTimeInterval(60)
            ),
            remote: RepositorySnapshot(
                entries: [
                    remoteEditedEntry,
                    remoteDeletedEntry
                ],
                updatedAt: canonicalDate
            ),
            mergedAt: preciseDate.addingTimeInterval(61)
        )

        XCTAssertEqual(
            resolution.snapshot.entries.map(\.id),
            [editedID]
        )
        XCTAssertEqual(
            resolution.snapshot.entries.first?.body,
            "Edited only on this device"
        )
        XCTAssertEqual(resolution.conflictingEntryCopyCount, 0)
    }

    func testImageOnlyConflictKeepsBothByteSequencesWithStableReferences() throws {
        let baseDate = fixtureDate("2026-07-27T05:30:00Z")
        let entryID = UUID()
        let reference = "legacy-shared-image.jpg"
        let entry = EntryRecord(
            id: entryID,
            kind: .blog,
            title: "Image conflict",
            body: "Same fields",
            happenedAt: baseDate,
            createdAt: baseDate,
            updatedAt: baseDate,
            imageReference: reference
        )
        let baseData = Data("base-image".utf8)
        let localData = Data("local-image".utf8)
        let remoteData = Data("remote-image".utf8)
        let base = RepositorySnapshot(
            entries: [entry],
            updatedAt: baseDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: reference,
                    data: baseData
                )
            ]
        )
        let local = RepositorySnapshot(
            entries: [entry],
            updatedAt: baseDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: reference,
                    data: localData
                )
            ]
        )
        let remote = RepositorySnapshot(
            entries: [entry],
            updatedAt: baseDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: reference,
                    data: remoteData
                )
            ]
        )

        let resolution = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: local,
            remote: remote,
            mergedAt: baseDate
        )
        let remoteEntry = try XCTUnwrap(
            resolution.snapshot.entries.first {
                $0.id == entryID
            }
        )
        let localCopy = try XCTUnwrap(
            resolution.snapshot.entries.first {
                $0.id != entryID
            }
        )
        let assets = Dictionary(
            uniqueKeysWithValues:
                resolution.snapshot.embeddedImages.map {
                    ($0.reference, $0.data)
                }
        )

        XCTAssertEqual(remoteEntry.imageReference, reference)
        XCTAssertEqual(assets[reference], remoteData)
        XCTAssertNotEqual(localCopy.imageReference, reference)
        XCTAssertEqual(
            assets[try XCTUnwrap(localCopy.imageReference)],
            localData
        )
        XCTAssertEqual(resolution.conflictingEntryCopyCount, 1)
    }

    func testRebasingAnAlreadyMergedSnapshotDoesNotMultiplyConflictCopies() {
        let baseDate = fixtureDate("2026-07-27T05:40:00Z")
        let entryID = UUID()
        let baseEntry = EntryRecord(
            id: entryID,
            kind: .journal,
            title: "Stable conflict copy",
            body: "Base",
            happenedAt: baseDate,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        var localEntry = baseEntry
        localEntry.body = "Local"
        var remoteEntry = baseEntry
        remoteEntry.body = "Remote"
        let base = RepositorySnapshot(
            entries: [baseEntry],
            updatedAt: baseDate
        )
        let remote = RepositorySnapshot(
            entries: [remoteEntry],
            updatedAt: baseDate
        )
        let first = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: RepositorySnapshot(
                entries: [localEntry],
                updatedAt: baseDate
            ),
            remote: remote,
            mergedAt: baseDate
        )

        let second = RepositorySnapshotConflictResolver.merge(
            base: remote,
            local: first.snapshot,
            remote: remote,
            mergedAt: baseDate
        )

        XCTAssertEqual(second.snapshot.entries.count, 2)
        XCTAssertEqual(
            Set(second.snapshot.entries.map(\.id)),
            Set(first.snapshot.entries.map(\.id))
        )
    }

    func testReplayingStaleLocalEditDoesNotMultiplyConflictCopy() {
        let baseDate = fixtureDate("2026-07-27T05:50:00Z")
        let entryID = UUID()
        let baseEntry = EntryRecord(
            id: entryID,
            kind: .journal,
            title: "Stale replay",
            body: "Base",
            happenedAt: baseDate,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        var localEntry = baseEntry
        localEntry.body = "Local"
        var remoteEntry = baseEntry
        remoteEntry.body = "Remote"
        let base = RepositorySnapshot(
            entries: [baseEntry],
            updatedAt: baseDate
        )
        let staleLocal = RepositorySnapshot(
            entries: [localEntry],
            updatedAt: baseDate
        )
        let first = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: staleLocal,
            remote: RepositorySnapshot(
                entries: [remoteEntry],
                updatedAt: baseDate
            ),
            mergedAt: baseDate
        )

        let replay = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: staleLocal,
            remote: first.snapshot,
            mergedAt: baseDate
        )

        XCTAssertEqual(replay.snapshot.entries.count, 2)
        XCTAssertEqual(
            Set(replay.snapshot.entries.map(\.id)),
            Set(first.snapshot.entries.map(\.id))
        )
        XCTAssertEqual(replay.conflictingEntryCopyCount, 0)
    }

    func testReplayingStaleImageEditRecognizesRenamedConflictCopy() throws {
        let baseDate = fixtureDate("2026-07-27T06:00:00Z")
        let entryID = UUID()
        let reference = "same-reference.jpg"
        let entry = EntryRecord(
            id: entryID,
            kind: .blog,
            title: "Image replay",
            body: "Same fields",
            happenedAt: baseDate,
            createdAt: baseDate,
            updatedAt: baseDate,
            imageReference: reference
        )
        let base = RepositorySnapshot(
            entries: [entry],
            updatedAt: baseDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: reference,
                    data: Data("base".utf8)
                )
            ]
        )
        let staleLocal = RepositorySnapshot(
            entries: [entry],
            updatedAt: baseDate,
            embeddedImages: [
                RepositoryImageAsset(
                    reference: reference,
                    data: Data("local".utf8)
                )
            ]
        )
        let first = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: staleLocal,
            remote: RepositorySnapshot(
                entries: [entry],
                updatedAt: baseDate,
                embeddedImages: [
                    RepositoryImageAsset(
                        reference: reference,
                        data: Data("remote".utf8)
                    )
                ]
            ),
            mergedAt: baseDate
        )

        let replay = RepositorySnapshotConflictResolver.merge(
            base: base,
            local: staleLocal,
            remote: first.snapshot,
            mergedAt: baseDate
        )

        XCTAssertEqual(replay.snapshot.entries.count, 2)
        XCTAssertEqual(
            Set(replay.snapshot.entries.map(\.id)),
            Set(first.snapshot.entries.map(\.id))
        )
        XCTAssertEqual(replay.conflictingEntryCopyCount, 0)
        XCTAssertEqual(
            Set(replay.snapshot.embeddedImages.map(\.data)),
            Set([Data("local".utf8), Data("remote".utf8)])
        )
    }
}
