import CloudKit
import Foundation

final class CloudChangeTokenStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func loadToken(for scope: CloudDatabaseScope) throws -> CKServerChangeToken? {
        let fileURL = tokenURL(for: scope)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func saveToken(_ token: CKServerChangeToken, for scope: CloudDatabaseScope) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        try data.write(to: tokenURL(for: scope), options: .atomic)
    }

    func removeToken(for scope: CloudDatabaseScope) throws {
        let fileURL = tokenURL(for: scope)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    func loadPendingZoneIDs(
        for scope: CloudDatabaseScope
    ) throws -> Set<CloudRepositoryZoneIdentity> {
        let fileURL = pendingZoneIDsURL(for: scope)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        return Set(
            try JSONDecoder().decode(
                [CloudRepositoryZoneIdentity].self,
                from: Data(contentsOf: fileURL)
            )
        )
    }

    func savePendingZoneIDs(
        _ zoneIDs: Set<CloudRepositoryZoneIdentity>,
        for scope: CloudDatabaseScope
    ) throws {
        let fileURL = pendingZoneIDsURL(for: scope)
        guard !zoneIDs.isEmpty else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sortedZoneIDs = zoneIDs.sorted {
            if $0.ownerName != $1.ownerName {
                return $0.ownerName < $1.ownerName
            }
            return $0.zoneName < $1.zoneName
        }
        let data = try JSONEncoder().encode(sortedZoneIDs)
        try data.write(to: fileURL, options: .atomic)
    }

    func acknowledgePendingZoneIDs(
        _ zoneIDs: Set<CloudRepositoryZoneIdentity>,
        for scope: CloudDatabaseScope
    ) throws {
        guard !zoneIDs.isEmpty else {
            return
        }

        var pendingZoneIDs = try loadPendingZoneIDs(for: scope)
        pendingZoneIDs.subtract(zoneIDs)
        try savePendingZoneIDs(pendingZoneIDs, for: scope)
    }

    func loadPendingDeletedZones(
        for scope: CloudDatabaseScope
    ) throws -> Set<CloudRepositoryZoneDeletion> {
        let fileURL = pendingDeletedZonesURL(for: scope)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        if let deletions = try? decoder.decode(
            [CloudRepositoryZoneDeletion].self,
            from: data
        ) {
            return Set(deletions)
        }

        // Migrate the short-lived ID-only inbox format conservatively.
        let legacyZoneIDs = try decoder.decode(
            [CloudRepositoryZoneIdentity].self,
            from: data
        )
        return Set(
            legacyZoneIDs.map {
                CloudRepositoryZoneDeletion(zoneID: $0, reason: .deleted)
            }
        )
    }

    func savePendingDeletedZones(
        _ deletions: Set<CloudRepositoryZoneDeletion>,
        for scope: CloudDatabaseScope
    ) throws {
        let fileURL = pendingDeletedZonesURL(for: scope)
        guard !deletions.isEmpty else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sortedDeletions = deletions.sorted {
            if $0.zoneID.ownerName != $1.zoneID.ownerName {
                return $0.zoneID.ownerName < $1.zoneID.ownerName
            }
            if $0.zoneID.zoneName != $1.zoneID.zoneName {
                return $0.zoneID.zoneName < $1.zoneID.zoneName
            }
            return $0.reason.rawValue < $1.reason.rawValue
        }
        let data = try JSONEncoder().encode(sortedDeletions)
        try data.write(to: fileURL, options: .atomic)
    }

    func acknowledgePendingDeletedZones(
        _ deletions: Set<CloudRepositoryZoneDeletion>,
        for scope: CloudDatabaseScope
    ) throws {
        guard !deletions.isEmpty else {
            return
        }

        var pendingDeletions = try loadPendingDeletedZones(for: scope)
        pendingDeletions.subtract(deletions)
        try savePendingDeletedZones(pendingDeletions, for: scope)
    }

    func removeAllTrackingState() throws {
        try removeToken(for: .privateDatabase)
        try removeToken(for: .sharedDatabase)
        try savePendingZoneIDs([], for: .privateDatabase)
        try savePendingZoneIDs([], for: .sharedDatabase)
        try savePendingDeletedZones([], for: .privateDatabase)
        try savePendingDeletedZones([], for: .sharedDatabase)
    }

    private func tokenURL(for scope: CloudDatabaseScope) -> URL {
        let filename: String
        switch scope {
        case .privateDatabase:
            filename = "private-database-change-token"
        case .sharedDatabase:
            filename = "shared-database-change-token"
        }

        return directoryURL
            .appendingPathComponent(filename)
            .appendingPathExtension("data")
    }

    private func pendingZoneIDsURL(for scope: CloudDatabaseScope) -> URL {
        let filename: String
        switch scope {
        case .privateDatabase:
            filename = "private-pending-zone-ids"
        case .sharedDatabase:
            filename = "shared-pending-zone-ids"
        }

        return directoryURL
            .appendingPathComponent(filename)
            .appendingPathExtension("json")
    }

    private func pendingDeletedZonesURL(for scope: CloudDatabaseScope) -> URL {
        let filename: String
        switch scope {
        case .privateDatabase:
            filename = "private-pending-deleted-zone-ids"
        case .sharedDatabase:
            filename = "shared-pending-deleted-zone-ids"
        }

        return directoryURL
            .appendingPathComponent(filename)
            .appendingPathExtension("json")
    }
}
