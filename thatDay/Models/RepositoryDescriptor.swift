import CloudKit
import Foundation

enum RepositoryRole: String, Codable, Sendable {
    case local
    case owner
    case editor
    case viewer

    var title: String {
        switch self {
        case .local:
            "本地仓库"
        case .owner:
            "共享所有者"
        case .editor:
            "共享成员（可编辑）"
        case .viewer:
            "共享成员（只读）"
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
}

enum ShareAccessOption: String, CaseIterable, Codable, Identifiable, Sendable {
    case viewOnly
    case editable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .viewOnly:
            "仅查看"
        case .editable:
            "允许编辑"
        }
    }

    var description: String {
        switch self {
        case .viewOnly:
            "邀请对象只能查看当前仓库。"
        case .editable:
            "邀请对象可以查看并修改当前仓库。"
        }
    }
}

struct RepositoryDescriptor: Codable, Hashable, Sendable {
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
}
