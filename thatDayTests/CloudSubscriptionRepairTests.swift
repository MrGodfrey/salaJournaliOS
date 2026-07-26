import CloudKit
import XCTest
@testable import thatDay

final class CloudSubscriptionRepairTests: XCTestCase {
    func testOnlyV2SharedSubscriptionRepairsStableProductionSubscriptionWithoutDeleting() throws {
        let descriptor = sharedDescriptor()
        let v2Subscription = CKDatabaseSubscription(
            subscriptionID: "repository-root-updates-shared-v2"
        )
        v2Subscription.recordType = "RepositoryRoot"
        v2Subscription.notificationInfo = silentNotificationInfo()

        let plan = CloudRepositoryService.subscriptionRepairPlan(
            using: descriptor,
            existingSubscriptions: [v2Subscription]
        )

        let stableSubscription = try XCTUnwrap(
            plan.subscriptionToSave as? CKDatabaseSubscription
        )
        XCTAssertEqual(
            stableSubscription.subscriptionID,
            "repository-updates-shared-database"
        )
        XCTAssertNil(stableSubscription.recordType)
        XCTAssertTrue(
            CloudRepositoryService.isSilentOnlyNotificationInfo(
                stableSubscription.notificationInfo
            )
        )
        XCTAssertTrue(plan.subscriptionIDsToDelete.isEmpty)
    }

    func testExistingStableSharedSubscriptionRequiresNoWriteOrDelete() {
        let stableSubscription = CKDatabaseSubscription(
            subscriptionID: "repository-updates-shared-database"
        )
        stableSubscription.notificationInfo = silentNotificationInfo()

        let plan = CloudRepositoryService.subscriptionRepairPlan(
            using: sharedDescriptor(),
            existingSubscriptions: [stableSubscription]
        )

        XCTAssertNil(plan.subscriptionToSave)
        XCTAssertTrue(plan.subscriptionIDsToDelete.isEmpty)
    }

    func testFilteredStableSharedSubscriptionIsRepairedToUnfilteredConfiguration() throws {
        let filteredSubscription = CKDatabaseSubscription(
            subscriptionID: "repository-updates-shared-database"
        )
        filteredSubscription.recordType = "RepositoryRoot"
        filteredSubscription.notificationInfo = silentNotificationInfo()

        let plan = CloudRepositoryService.subscriptionRepairPlan(
            using: sharedDescriptor(),
            existingSubscriptions: [filteredSubscription]
        )

        let repairedSubscription = try XCTUnwrap(
            plan.subscriptionToSave as? CKDatabaseSubscription
        )
        XCTAssertNil(repairedSubscription.recordType)
        XCTAssertTrue(plan.subscriptionIDsToDelete.isEmpty)
    }

    func testVisibleSharedSubscriptionIsNotAcceptedAsSilentBackgroundDelivery() {
        let visibleSubscription = CKDatabaseSubscription(
            subscriptionID: "repository-updates-shared-database"
        )
        let notificationInfo = silentNotificationInfo()
        notificationInfo.title = "Visible"
        visibleSubscription.notificationInfo = notificationInfo

        let plan = CloudRepositoryService.subscriptionRepairPlan(
            using: sharedDescriptor(),
            existingSubscriptions: [visibleSubscription]
        )

        XCTAssertNotNil(plan.subscriptionToSave)
        XCTAssertTrue(plan.subscriptionIDsToDelete.isEmpty)
        XCTAssertFalse(
            CloudRepositoryService.isSilentOnlyNotificationInfo(
                visibleSubscription.notificationInfo
            )
        )
    }

    func testOwnerDatabaseV2SubscriptionRepairsPerZoneStableSubscription() throws {
        let descriptor = ownerDescriptor(shareRecordName: "share-one")
        let v2Subscription = CKDatabaseSubscription(
            subscriptionID: "repository-root-updates-private-v2"
        )
        v2Subscription.recordType = "RepositoryRoot"
        v2Subscription.notificationInfo = silentNotificationInfo()

        let plan = CloudRepositoryService.subscriptionRepairPlan(
            using: descriptor,
            existingSubscriptions: [v2Subscription]
        )
        let stableSubscription = try XCTUnwrap(
            plan.subscriptionToSave as? CKRecordZoneSubscription
        )

        XCTAssertEqual(stableSubscription.zoneID, descriptor.zoneID)
        XCTAssertTrue(plan.subscriptionIDsToDelete.isEmpty)

        let descriptorWithChangedShare = ownerDescriptor(
            shareRecordName: "share-two"
        )
        let secondPlan = CloudRepositoryService.subscriptionRepairPlan(
            using: descriptorWithChangedShare,
            existingSubscriptions: []
        )
        XCTAssertEqual(
            secondPlan.subscriptionToSave?.subscriptionID,
            stableSubscription.subscriptionID,
            "The stable owner subscription ID must not change with share metadata."
        )
    }

    func testExistingMatchingOwnerZoneSubscriptionRequiresNoRepair() {
        let descriptor = ownerDescriptor(shareRecordName: "current-share")
        let existingSubscription = CKRecordZoneSubscription(
            zoneID: descriptor.zoneID!,
            subscriptionID: "repository-updates-an-older-share-based-id"
        )
        existingSubscription.notificationInfo = silentNotificationInfo()

        let plan = CloudRepositoryService.subscriptionRepairPlan(
            using: descriptor,
            existingSubscriptions: [existingSubscription]
        )

        XCTAssertNil(plan.subscriptionToSave)
        XCTAssertTrue(plan.subscriptionIDsToDelete.isEmpty)
    }

    func testFilteredOwnerZoneSubscriptionIsRepairedToAllRecords() throws {
        let descriptor = ownerDescriptor(shareRecordName: "current-share")
        let filteredSubscription = CKRecordZoneSubscription(
            zoneID: descriptor.zoneID!,
            subscriptionID: "filtered-owner-zone"
        )
        filteredSubscription.recordType = "RepositoryImageAsset"
        filteredSubscription.notificationInfo = silentNotificationInfo()

        let plan = CloudRepositoryService.subscriptionRepairPlan(
            using: descriptor,
            existingSubscriptions: [filteredSubscription]
        )
        let repairedSubscription = try XCTUnwrap(
            plan.subscriptionToSave as? CKRecordZoneSubscription
        )

        XCTAssertNil(repairedSubscription.recordType)
        XCTAssertTrue(plan.subscriptionIDsToDelete.isEmpty)
    }

    func testSilentOnlyValidationRejectsEveryHighPriorityFlag() {
        let badgeInfo = silentNotificationInfo()
        badgeInfo.shouldBadge = true
        XCTAssertFalse(
            CloudRepositoryService.isSilentOnlyNotificationInfo(badgeInfo)
        )

        let soundInfo = silentNotificationInfo()
        soundInfo.soundName = "default"
        XCTAssertFalse(
            CloudRepositoryService.isSilentOnlyNotificationInfo(soundInfo)
        )

        let mutableInfo = silentNotificationInfo()
        mutableInfo.shouldSendMutableContent = true
        XCTAssertFalse(
            CloudRepositoryService.isSilentOnlyNotificationInfo(mutableInfo)
        )
    }

    private func sharedDescriptor() -> RepositoryDescriptor {
        RepositoryDescriptor(
            zoneName: "shared-zone",
            zoneOwnerName: "_shared-owner_",
            shareRecordName: "shared-record",
            role: .viewer
        )
    }

    private func ownerDescriptor(
        shareRecordName: String
    ) -> RepositoryDescriptor {
        RepositoryDescriptor(
            zoneName: "owner-zone",
            zoneOwnerName: CKCurrentUserDefaultName,
            shareRecordName: shareRecordName,
            role: .owner
        )
    }

    private func silentNotificationInfo()
        -> CKSubscription.NotificationInfo {
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        return notificationInfo
    }
}
