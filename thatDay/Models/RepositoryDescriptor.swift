import CloudKit
import Foundation

nonisolated enum RepositoryRole: String, Codable, Sendable {
    case local
    case owner
    case editor
    case viewer

    var title: String {
        switch self {
        case .local:
            "Local Repository"
        case .owner:
            "Shared Owner"
        case .editor:
            "Shared Member (Can Edit)"
        case .viewer:
            "Shared Member (Read-Only)"
        }
    }

    var canEdit: Bool {
        switch self {
        case .local, .owner, .editor:
            true
        case .viewer:
            false
        }
    }

    var canCreateShareInvite: Bool {
        switch self {
        case .local, .owner:
            true
        case .editor, .viewer:
            false
        }
    }

    var canManageRepositoryNotificationScope: Bool {
        switch self {
        case .local, .owner:
            true
        case .editor, .viewer:
            false
        }
    }
}

nonisolated enum ShareAccessOption: String, CaseIterable, Codable, Identifiable, Sendable {
    case viewOnly
    case editable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .viewOnly:
            "View Only"
        case .editable:
            "Can Edit"
        }
    }

    var description: String {
        switch self {
        case .viewOnly:
            "Invitees can only view this repository."
        case .editable:
            "Invitees can view and edit this repository."
        }
    }
}

nonisolated struct RepositoryDescriptor: Codable, Hashable, Sendable {
    var zoneName: String?
    var zoneOwnerName: String?
    var shareRecordName: String?
    var role: RepositoryRole

    static let local = RepositoryDescriptor(
        zoneName: nil,
        zoneOwnerName: nil,
        shareRecordName: nil,
        role: .local
    )

    var isCloudBacked: Bool {
        zoneID != nil && role != .local
    }

    var zoneID: CKRecordZone.ID? {
        guard let zoneName, let zoneOwnerName else {
            return nil
        }

        return CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
    }

    var storageIdentifier: String {
        guard isCloudBacked else {
            return RepositoryReference.localRepositoryID
        }

        let rawValue = [zoneOwnerName, zoneName, shareRecordName]
            .compactMap(\.self)
            .joined(separator: "-")
        let normalized = rawValue.lowercased().map { character -> Character in
            switch character {
            case "a"..."z", "0"..."9":
                return character
            default:
                return "-"
            }
        }

        let trimmed = String(normalized)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return "shared-\(trimmed.nilIfEmpty ?? UUID().uuidString.lowercased())"
    }

    var defaultDisplayName: String {
        guard isCloudBacked else {
            return "My Repository"
        }

        guard let ownerName = zoneOwnerName?.trimmed.nilIfEmpty,
              ownerName != CKCurrentUserDefaultName,
              ownerName != "_defaultOwner_" else {
            return "Shared Repository"
        }

        return "Shared Repository · \(ownerName)"
    }
}
