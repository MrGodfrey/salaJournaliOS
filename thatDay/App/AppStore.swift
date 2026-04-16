import CloudKit
import Observation
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case journal
    case calendar
    case search
    case blog
}

struct JournalSection: Identifiable, Equatable {
    var id: Int { year }

    let year: Int
    let entries: [EntryRecord]
}

enum EntryEditorMode: String, Sendable {
    case create
    case edit
}

struct EntryEditorSession: Identifiable, Equatable, Sendable {
    let id = UUID()
    let mode: EntryEditorMode
    let entry: EntryRecord?
    let kind: EntryKind
    let defaultDate: Date
}

struct SharingControllerItem: Identifiable {
    let id = UUID()
    let controller: UICloudSharingController
}

@MainActor
@Observable
final class AppStore {
    private let repositoryStore: LocalRepositoryStore
    private let cloudService: any CloudRepositoryServicing
    private let now: () -> Date
    private let calendar: Calendar

    private var didLoad = false

    var selectedTab: AppTab = .journal
    var selectedDate: Date
    var displayedMonth: Date
    var searchText = ""
    var incomingShareLink = ""
    var shareAccessOption: ShareAccessOption = .viewOnly
    var editorSession: EntryEditorSession?
    var isShowingSettings = false
    var sharingControllerItem: SharingControllerItem?
    var isBusy = false
    var alertMessage: String?

    private(set) var entries: [EntryRecord] = []
    private(set) var repositoryDescriptor: RepositoryDescriptor = .local

    init(
        repositoryStore: LocalRepositoryStore,
        cloudService: any CloudRepositoryServicing,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.repositoryStore = repositoryStore
        self.cloudService = cloudService
        self.calendar = calendar
        self.now = now

        let initialDate = calendar.startOfDay(for: now())
        selectedDate = initialDate
        displayedMonth = calendar.startOfMonth(for: initialDate)
    }

    static func preview() -> AppStore {
        AppStore(
            repositoryStore: LocalRepositoryStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("thatDay-preview", isDirectory: true)),
            cloudService: PreviewCloudRepositoryService(),
            now: { Self.referenceDate(from: ["THATDAY_REFERENCE_DATE": "2026-04-16T09:00:00Z"]) ?? Date() }
        )
    }

    static func referenceDate(from environment: [String: String]) -> Date? {
        guard let rawValue = environment["THATDAY_REFERENCE_DATE"]?.trimmed.nilIfEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    var canEditRepository: Bool {
        repositoryDescriptor.role.canEdit
    }

    var repositoryStatusTitle: String {
        repositoryDescriptor.role.title
    }

    var repositorySummary: String {
        if repositoryDescriptor.role == .local {
            return "当前正在使用本地仓库。"
        }

        return "当前仓库来自 CloudKit 共享，权限为 \(repositoryDescriptor.role.title)。"
    }

    var selectedDateTitle: String {
        selectedDate.formatted(.dateTime.month(.wide).day())
    }

    var journalSections: [JournalSection] {
        let filtered = entries
            .filter { $0.kind == .journal && calendar.isSameMonthDay($0.happenedAt, selectedDate) }
            .sorted { lhs, rhs in
                if lhs.happenedAt != rhs.happenedAt {
                    return lhs.happenedAt > rhs.happenedAt
                }
                return lhs.createdAt > rhs.createdAt
            }

        let grouped = Dictionary(grouping: filtered) { entry in
            calendar.component(.year, from: entry.happenedAt)
        }

        return grouped.keys
            .sorted(by: >)
            .map { year in
                JournalSection(year: year, entries: grouped[year] ?? [])
            }
    }

    var blogEntries: [EntryRecord] {
        entries
            .filter { $0.kind == .blog }
            .sorted { lhs, rhs in
                if lhs.happenedAt != rhs.happenedAt {
                    return lhs.happenedAt > rhs.happenedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    var searchResults: [EntryRecord] {
        let normalizedQuery = searchText.trimmed
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        guard !normalizedQuery.isEmpty else {
            return []
        }

        return entries
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .filter { $0.searchableText.contains(normalizedQuery) }
    }

    var journalDates: [Date] {
        entries
            .filter { $0.kind == .journal }
            .map(\.happenedAt)
    }

    func loadIfNeeded() async {
        guard !didLoad else {
            return
        }

        didLoad = true
        isBusy = true
        defer { isBusy = false }

        do {
            repositoryDescriptor = try repositoryStore.loadDescriptor() ?? .local
            if let snapshot = try repositoryStore.loadSnapshot() {
                entries = snapshot.entries
            } else {
                entries = SampleData.makeEntries()
                try repositoryStore.saveSnapshot(RepositorySnapshot(entries: entries, updatedAt: now()))
            }

            if repositoryDescriptor.isCloudBacked {
                let snapshot = try await cloudService.loadSnapshot(using: repositoryDescriptor)
                entries = snapshot.entries
                try repositoryStore.saveSnapshot(snapshot)
            }
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            if entries.isEmpty {
                entries = SampleData.makeEntries()
            }
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        displayedMonth = calendar.startOfMonth(for: selectedDate)
    }

    func showEditor(for kind: EntryKind, entry: EntryRecord? = nil) {
        guard canEditRepository else {
            alertMessage = "当前仓库是只读的，不能修改内容。"
            return
        }

        editorSession = EntryEditorSession(
            mode: entry == nil ? .create : .edit,
            entry: entry,
            kind: kind,
            defaultDate: entry?.happenedAt ?? (kind == .journal ? selectedDate : now())
        )
    }

    func dismissEditor() {
        editorSession = nil
    }

    func saveEntry(draft: EntryDraft, importedImageData: Data?, editing editingEntry: EntryRecord? = nil) async -> Bool {
        guard canEditRepository else {
            alertMessage = "当前仓库是只读的，不能保存内容。"
            return false
        }

        let normalized = draft.normalized
        guard !normalized.title.isEmpty else {
            alertMessage = "请输入标题。"
            return false
        }
        guard !normalized.body.isEmpty else {
            alertMessage = "请输入正文。"
            return false
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let entryID = editingEntry?.id ?? UUID()
            let imageReference: String?
            if let importedImageData {
                imageReference = try repositoryStore.storeImage(
                    data: importedImageData,
                    suggestedID: entryID
                )
            } else {
                imageReference = editingEntry?.imageReference
            }

            let timestamp = now()
            if var existing = editingEntry {
                existing.title = normalized.title
                existing.body = normalized.body
                existing.happenedAt = normalized.happenedAt
                existing.updatedAt = timestamp
                existing.imageReference = imageReference

                if let index = entries.firstIndex(where: { $0.id == existing.id }) {
                    entries[index] = existing
                }
            } else {
                entries.append(
                    EntryRecord(
                        id: entryID,
                        kind: normalized.kind,
                        title: normalized.title,
                        body: normalized.body,
                        happenedAt: normalized.happenedAt,
                        createdAt: timestamp,
                        updatedAt: timestamp,
                        imageReference: imageReference
                    )
                )
            }

            try await persistEntries()
            editorSession = nil
            return true
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    func deleteEntry(_ entry: EntryRecord) async {
        guard canEditRepository else {
            alertMessage = "当前仓库是只读的，不能删除内容。"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            entries.removeAll { $0.id == entry.id }
            try await persistEntries()
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func imageURL(for entry: EntryRecord) -> URL? {
        repositoryStore.imageURL(for: entry.imageReference)
    }

    func entry(matching entryID: UUID) -> EntryRecord? {
        entries.first { $0.id == entryID }
    }

    func goToCalendar() {
        selectedTab = .calendar
    }

    func goToJournal(for date: Date) {
        selectDate(date)
        selectedTab = .journal
    }

    func previousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    func nextMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    func setDisplayedMonth(year: Int, month: Int) {
        var components = calendar.dateComponents([.day], from: displayedMonth)
        components.year = year
        components.month = month
        components.day = 1

        guard let date = calendar.date(from: components) else {
            return
        }

        displayedMonth = calendar.startOfMonth(for: date)
    }

    func moveSelectedDate(by days: Int) {
        guard let date = calendar.date(byAdding: .day, value: days, to: selectedDate) else {
            return
        }

        selectDate(date)
    }

    func returnToToday() {
        selectDate(now())
    }

    func presentSettings() {
        isShowingSettings = true
    }

    func presentSharingController() async {
        guard canEditRepository else {
            alertMessage = "只有可以编辑仓库的用户才能发起共享邀请。"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let snapshot = RepositorySnapshot(entries: entries, updatedAt: now())
            repositoryDescriptor = try await cloudService.saveSnapshot(snapshot, using: repositoryDescriptor)
            try repositoryStore.saveDescriptor(repositoryDescriptor)
            let controller = try await cloudService.makeSharingController(
                using: repositoryDescriptor,
                snapshot: snapshot,
                access: shareAccessOption
            )
            sharingControllerItem = SharingControllerItem(controller: controller)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func acceptIncomingShareLink() async {
        let rawValue = incomingShareLink.trimmed
        guard let url = URL(string: rawValue),
              url.absoluteString.contains("/share/") else {
            alertMessage = "请输入有效的 iCloud 共享链接。"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let accepted = try await cloudService.acceptShare(from: url)
            try applyAcceptedShare(accepted)
            incomingShareLink = ""
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func acceptShare(metadata: CKShare.Metadata) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let accepted = try await cloudService.acceptShare(metadata: metadata)
            try applyAcceptedShare(accepted)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    private func applyAcceptedShare(_ accepted: AcceptedSharedRepository) throws {
        repositoryDescriptor = accepted.descriptor
        entries = accepted.snapshot.entries
        try repositoryStore.saveDescriptor(repositoryDescriptor)
        try repositoryStore.saveSnapshot(accepted.snapshot)
    }

    private func persistEntries() async throws {
        let snapshot = RepositorySnapshot(entries: entries, updatedAt: now())
        try repositoryStore.saveSnapshot(snapshot)

        if repositoryDescriptor.role != .local {
            repositoryDescriptor = try await cloudService.saveSnapshot(snapshot, using: repositoryDescriptor)
            try repositoryStore.saveDescriptor(repositoryDescriptor)
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.trimmed.nilIfEmpty {
            return description
        }

        let localizedDescription = error.localizedDescription.trimmed
        if !localizedDescription.isEmpty {
            return localizedDescription
        }

        return "发生了未预期的错误。"
    }
}

private struct PreviewCloudRepositoryService: CloudRepositoryServicing {
    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        RepositorySnapshot(entries: SampleData.makeEntries())
    }

    func saveSnapshot(_ snapshot: RepositorySnapshot, using descriptor: RepositoryDescriptor) async throws -> RepositoryDescriptor {
        descriptor.role == .local
            ? RepositoryDescriptor(zoneName: "preview-zone", zoneOwnerName: CKCurrentUserDefaultName, shareRecordName: "preview-share", role: .owner)
            : descriptor
    }

    func shareURL(using descriptor: RepositoryDescriptor, snapshot: RepositorySnapshot) async throws -> URL {
        URL(string: "https://www.icloud.com/share/preview")!
    }

    @MainActor
    func makeSharingController(
        using descriptor: RepositoryDescriptor,
        snapshot: RepositorySnapshot,
        access: ShareAccessOption
    ) async throws -> UICloudSharingController {
        UICloudSharingController(
            share: CKShare(recordZoneID: CKRecordZone.ID(zoneName: "preview", ownerName: CKCurrentUserDefaultName)),
            container: CKContainer(identifier: "iCloud.yu.thatDay")
        )
    }

    func acceptShare(from url: URL) async throws -> AcceptedSharedRepository {
        AcceptedSharedRepository(
            descriptor: RepositoryDescriptor(zoneName: "preview-zone", zoneOwnerName: "_owner_", shareRecordName: "preview-share", role: .viewer),
            snapshot: RepositorySnapshot(entries: SampleData.makeEntries())
        )
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        try await acceptShare(from: URL(string: "https://www.icloud.com/share/preview")!)
    }
}
