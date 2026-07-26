import XCTest
@testable import thatDay

final class CloudImageMutationPlanTests: AppStoreTestCase {
    func testTextOnlyEditWithHundredsOfImmutableImagesTransfersNoImageRecords() throws {
        let references = (0..<300).map {
            "immutable-image-\($0).jpg"
        }
        var previousSnapshot = snapshot(
            references: references,
            embeddedReferences: []
        )
        let currentSnapshot = snapshot(
            references: references,
            embeddedReferences: references
        )
        previousSnapshot.imageContentHashes =
            try CloudRepositoryService.imageContentHashes(
                in: currentSnapshot
            )

        let plan = try CloudRepositoryService.imageMutationPlan(
            for: currentSnapshot,
            replacing: previousSnapshot
        )

        XCTAssertTrue(plan.assetsToSave.isEmpty)
        XCTAssertTrue(plan.referencesToDelete.isEmpty)
    }

    func testImmutableImageReplacementUploadsNewRecordAndDeletesOldRecord() throws {
        let previousSnapshot = snapshot(
            references: ["old-image.jpg"],
            embeddedReferences: []
        )
        let currentSnapshot = snapshot(
            references: ["new-image.jpg"],
            embeddedReferences: ["new-image.jpg"]
        )

        let plan = try CloudRepositoryService.imageMutationPlan(
            for: currentSnapshot,
            replacing: previousSnapshot
        )

        XCTAssertEqual(plan.assetsToSave.map(\.reference), ["new-image.jpg"])
        XCTAssertEqual(plan.referencesToDelete, ["old-image.jpg"])
    }

    func testSameReferenceWithChangedBytesIsUpdatedForRollingUpgradeCompatibility() throws {
        let reference = "legacy-entry-id.jpg"
        var previousSnapshot = snapshot(
            references: [reference],
            embeddedReferences: []
        )
        previousSnapshot.imageContentHashes = [
            reference: "previous-content-hash"
        ]
        let currentSnapshot = snapshot(
            references: [reference],
            embeddedReferences: [reference]
        )

        let plan = try CloudRepositoryService.imageMutationPlan(
            for: currentSnapshot,
            replacing: previousSnapshot
        )

        XCTAssertEqual(plan.assetsToSave.map(\.reference), [reference])
        XCTAssertEqual(
            plan.referencesToInspectBeforeSave,
            [reference]
        )
        XCTAssertTrue(plan.referencesToDelete.isEmpty)
    }

    func testLegacyRootWithoutHashesInspectsEveryExistingImageOnce() throws {
        let references = ["legacy-one.jpg", "legacy-two.jpg"]
        let previousSnapshot = snapshot(
            references: references,
            embeddedReferences: []
        )
        let currentSnapshot = snapshot(
            references: references,
            embeddedReferences: references
        )

        let plan = try CloudRepositoryService.imageMutationPlan(
            for: currentSnapshot,
            replacing: previousSnapshot
        )

        XCTAssertEqual(
            plan.assetsToSave.map(\.reference),
            references
        )
        XCTAssertEqual(
            plan.referencesToInspectBeforeSave,
            references
        )
        XCTAssertTrue(plan.referencesToDelete.isEmpty)
    }

    func testRootNewReferenceIsInspectedForLegacyOrphanRecord() throws {
        let reference = "previously-orphaned-entry-id.jpg"
        let currentSnapshot = snapshot(
            references: [reference],
            embeddedReferences: [reference]
        )

        let plan = try CloudRepositoryService.imageMutationPlan(
            for: currentSnapshot,
            replacing: RepositorySnapshot(entries: [])
        )

        XCTAssertEqual(plan.assetsToSave.map(\.reference), [reference])
        XCTAssertEqual(
            plan.referencesToInspectBeforeSave,
            [reference]
        )
        XCTAssertTrue(plan.referencesToDelete.isEmpty)
    }

    func testNewImageWithoutEmbeddedPayloadFailsBeforeRootMutation() throws {
        let currentSnapshot = snapshot(
            references: ["missing-image.jpg"],
            embeddedReferences: []
        )

        XCTAssertThrowsError(
            try CloudRepositoryService.imageMutationPlan(
                for: currentSnapshot,
                replacing: RepositorySnapshot(entries: [])
            )
        ) { error in
            guard case CloudRepositoryError.invalidRepositoryData = error else {
                return XCTFail("Expected invalidRepositoryData, got \(error)")
            }
        }
    }

    func testCachedImageIsReusedOnlyWhenRootManifestHashMatches() {
        var remoteSnapshot = snapshot(
            references: ["legacy-reference.jpg"],
            embeddedReferences: []
        )
        remoteSnapshot.imageContentHashes = [
            "legacy-reference.jpg": "remote-new-bytes"
        ]

        XCTAssertTrue(
            CloudRepositoryService.imageReferencesRequiringDownload(
                in: remoteSnapshot,
                availableImageContentHashes: [
                    "legacy-reference.jpg": "remote-new-bytes"
                ]
            ).isEmpty
        )
        XCTAssertEqual(
            CloudRepositoryService.imageReferencesRequiringDownload(
                in: remoteSnapshot,
                availableImageContentHashes: [
                    "legacy-reference.jpg": "local-old-bytes"
                ]
            ),
            Set(["legacy-reference.jpg"])
        )
    }

    func testLegacyRootWithoutHashManifestRedownloadsSameReference() {
        let legacySnapshot = snapshot(
            references: ["legacy-reference.jpg"],
            embeddedReferences: []
        )

        XCTAssertEqual(
            CloudRepositoryService.imageReferencesRequiringDownload(
                in: legacySnapshot,
                availableImageContentHashes: [
                    "legacy-reference.jpg": "local-old-bytes"
                ]
            ),
            Set(["legacy-reference.jpg"])
        )
    }

    func testDownloadedAssetMustMatchRecordAndRootHashes() throws {
        let data = Data("new-image-bytes".utf8)
        let actualHash = try CloudRepositoryService.imageContentHashes(
            in: RepositorySnapshot(
                entries: [
                    EntryRecord(
                        kind: .journal,
                        title: "Hash",
                        body: "",
                        happenedAt: fixtureDate(
                            "2026-07-25T12:00:00Z"
                        ),
                        imageReference: "hash.jpg"
                    )
                ],
                embeddedImages: [
                    RepositoryImageAsset(
                        reference: "hash.jpg",
                        data: data
                    )
                ]
            )
        )["hash.jpg"]

        XCTAssertNoThrow(
            try CloudRepositoryService.validatedImageAsset(
                requestedReference: "hash.jpg",
                storedReference: "hash.jpg",
                recordedContentHash: actualHash,
                expectedContentHash: actualHash,
                data: data
            )
        )
        XCTAssertThrowsError(
            try CloudRepositoryService.validatedImageAsset(
                requestedReference: "hash.jpg",
                storedReference: "different.jpg",
                recordedContentHash: actualHash,
                expectedContentHash: actualHash,
                data: data
            )
        )
        XCTAssertThrowsError(
            try CloudRepositoryService.validatedImageAsset(
                requestedReference: "hash.jpg",
                storedReference: "hash.jpg",
                recordedContentHash: actualHash,
                expectedContentHash: "different-root-hash",
                data: data
            )
        )
    }

    private func snapshot(
        references: [String],
        embeddedReferences: [String]
    ) -> RepositorySnapshot {
        RepositorySnapshot(
            entries: references.enumerated().map { index, reference in
                EntryRecord(
                    kind: .journal,
                    title: "Entry \(index)",
                    body: "Body",
                    happenedAt: fixtureDate("2026-07-25T12:00:00Z"),
                    imageReference: reference
                )
            },
            updatedAt: fixtureDate("2026-07-25T12:00:00Z"),
            embeddedImages: embeddedReferences.map {
                RepositoryImageAsset(
                    reference: $0,
                    data: Data("payload-\($0)".utf8)
                )
            }
        )
    }
}
