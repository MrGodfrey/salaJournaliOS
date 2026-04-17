import CloudKit
import LocalAuthentication
import Observation
import SwiftUI
import UIKit
import UserNotifications

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

enum RepositoryTransferKind: String, Sendable {
    case export
    case `import`

    var title: String {
        switch self {
        case .export:
            "导出"
        case .import:
            "导入"
        }
    }
}

struct RepositoryTransferProgress: Equatable, Sendable {
    let kind: RepositoryTransferKind
    let totalFiles: Int
    let completedFiles: Int

    var fractionCompleted: Double {
        guard totalFiles > 0 else {
            return 0
        }

        return Double(completedFiles) / Double(totalFiles)
    }

    var statusText: String {
        "共 \(totalFiles) 个文件，已\(kind.title) \(completedFiles) 个"
    }
}

struct ExportedArchiveItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct EntryOpenRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let repositoryID: String
    let entryID: UUID
    let kind: EntryKind
}

enum SharedRepositoryRefreshTrigger: Sendable {
    case launch
    case foreground
    case push
    case manual
}

@MainActor
@Observable
final class AppStore {
    private let libraryStore: RepositoryLibraryStore
    private let cloudService: any CloudRepositoryServicing
    private let repositoryArchiveService = RepositoryArchiveService()
    private let now: () -> Date
    private let authenticateBiometricsAction: (String) async throws -> Void
    private let calendar: Calendar

    private var didLoad = false
    private var preferences = AppPreferences()
    private var shouldRequireAuthenticationOnNextActive = false

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
    var entryOpenRequest: EntryOpenRequest?
    var isAuthenticationRequired = false
    var isAuthenticating = false
    var transferProgress: RepositoryTransferProgress?
    var exportedArchiveItem: ExportedArchiveItem?

    private(set) var entries: [EntryRecord] = []
    private(set) var repositoryDescriptor: RepositoryDescriptor = .local
    private(set) var repositories: [RepositoryReference] = [.local]
    private(set) var currentRepositoryID = RepositoryReference.localRepositoryID

    init(
        libraryStore: RepositoryLibraryStore,
        cloudService: any CloudRepositoryServicing,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        authenticateBiometrics: @escaping (String) async throws -> Void = AppStore.systemAuthenticateBiometrics
    ) {
        self.libraryStore = libraryStore
        self.cloudService = cloudService
        self.calendar = calendar
        self.now = now
        authenticateBiometricsAction = authenticateBiometrics

        let initialDate = calendar.startOfDay(for: now())
        selectedDate = initialDate
        displayedMonth = calendar.startOfMonth(for: initialDate)
    }

    static func preview() -> AppStore {
        AppStore(
            libraryStore: RepositoryLibraryStore(
                rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("thatDay-preview", isDirectory: true)
            ),
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

    var currentRepositoryName: String {
        currentRepositoryReference?.displayName ?? repositoryDescriptor.defaultDisplayName
    }

    var defaultRepositoryID: String {
        preferences.defaultRepositoryID
    }

    var isBiometricLockEnabled: Bool {
        preferences.isBiometricLockEnabled
    }

    var isSharedUpdateNotificationEnabled: Bool {
        preferences.isSharedUpdateNotificationEnabled
    }

    var repositorySummary: String {
        if repositoryDescriptor.role == .local {
            return "当前正在使用自己的本地仓库。"
        }

        return "当前仓库为 \(currentRepositoryName)，权限为 \(repositoryDescriptor.role.title)。"
    }

    var selectedDateTitle: String {
        selectedDate.formatted(.dateTime.month(.wide).day())
    }

    var currentRepositoryReference: RepositoryReference? {
        repositories.first { $0.id == currentRepositoryID }
    }

    var sortedRepositories: [RepositoryReference] {
        repositories.sorted { lhs, rhs in
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal
            }

            let lhsOpenedAt = lhs.lastOpenedAt ?? .distantPast
            let rhsOpenedAt = rhs.lastOpenedAt ?? .distantPast
            if lhsOpenedAt != rhsOpenedAt {
                return lhsOpenedAt > rhsOpenedAt
            }

            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
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
            repositories = try libraryStore.loadCatalog()
            preferences = try libraryStore.loadPreferences()
            let launchRepositoryID = repositories.contains(where: { $0.id == preferences.defaultRepositoryID })
                ? preferences.defaultRepositoryID
                : RepositoryReference.localRepositoryID
            try await loadRepository(repositoryID: launchRepositoryID)
            await ensureRepositorySubscriptions()
            await refreshSharedRepositories(trigger: .launch)
            if preferences.isBiometricLockEnabled {
                isAuthenticationRequired = true
                shouldRequireAuthenticationOnNextActive = false
                await unlockIfNeeded()
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
                imageReference = try currentRepositoryStore.storeImage(
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

    func clearCurrentRepository() async {
        guard canEditRepository else {
            alertMessage = "当前仓库是只读的，不能清空内容。"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            entries.removeAll()
            try await persistEntries()
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func imageURL(for entry: EntryRecord) -> URL? {
        currentRepositoryStore.imageURL(for: entry.imageReference)
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
            let snapshot = try currentRepositoryStore.makeSnapshot(
                entries: entries,
                updatedAt: now(),
                embeddingImages: true
            )
            repositoryDescriptor = try await cloudService.saveSnapshot(snapshot, using: repositoryDescriptor)
            try currentRepositoryStore.saveDescriptor(repositoryDescriptor)
            upsertRepositoryReference(
                repositoryID: currentRepositoryID,
                descriptor: repositoryDescriptor,
                displayName: currentRepositoryName,
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
            try persistRepositoryCatalog()

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
            try await loadRepository(repositoryID: accepted.descriptor.storageIdentifier)
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
            try await loadRepository(repositoryID: accepted.descriptor.storageIdentifier)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func switchRepository(to repositoryID: String) async {
        guard repositoryID != currentRepositoryID else {
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await loadRepository(repositoryID: repositoryID)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func setDefaultRepository(_ repositoryID: String) {
        guard repositories.contains(where: { $0.id == repositoryID }) else {
            return
        }

        preferences.defaultRepositoryID = repositoryID

        do {
            try libraryStore.savePreferences(preferences)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func setBiometricLockEnabled(_ isEnabled: Bool) {
        preferences.isBiometricLockEnabled = isEnabled

        do {
            try libraryStore.savePreferences(preferences)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func updateBiometricLockEnabled(_ isEnabled: Bool) async {
        if !isEnabled {
            setBiometricLockEnabled(false)
            isAuthenticationRequired = false
            shouldRequireAuthenticationOnNextActive = false
            return
        }

        do {
            try await authenticateBiometricsAction("启用生物识别保护")
            setBiometricLockEnabled(true)
            isAuthenticationRequired = false
            shouldRequireAuthenticationOnNextActive = false
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            setBiometricLockEnabled(false)
            isAuthenticationRequired = false
            shouldRequireAuthenticationOnNextActive = false
        }
    }

    func setSharedUpdateNotificationEnabled(_ isEnabled: Bool) {
        preferences.isSharedUpdateNotificationEnabled = isEnabled

        do {
            try libraryStore.savePreferences(preferences)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func updateSharedUpdateNotificationEnabled(_ isEnabled: Bool) async {
        if !isEnabled {
            setSharedUpdateNotificationEnabled(false)
            return
        }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                alertMessage = "通知权限未开启，无法接收共享仓库更新提醒。"
                setSharedUpdateNotificationEnabled(false)
                return
            }

            setSharedUpdateNotificationEnabled(true)
            await ensureRepositorySubscriptions()
            await refreshSharedRepositories(trigger: .launch)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            setSharedUpdateNotificationEnabled(false)
        }
    }

    func refreshSharedRepositories(trigger: SharedRepositoryRefreshTrigger) async {
        let sharedReferences = sortedRepositories.filter { $0.descriptor.isCloudBacked }
        guard !sharedReferences.isEmpty else {
            return
        }

        for reference in sharedReferences {
            do {
                try await refreshRepository(reference, trigger: trigger)
            } catch {
                if reference.id == currentRepositoryID {
                    alertMessage = Self.userFacingMessage(for: error)
                }
            }
        }
    }

    func handleNotificationRoute(_ route: NotificationEntryRoute) async {
        if route.repositoryID != currentRepositoryID {
            await switchRepository(to: route.repositoryID)
        }

        guard let entryID = route.entryID,
              let entry = entry(matching: entryID) else {
            return
        }

        routeToEntry(entry)
    }

    func exportCurrentRepository() async {
        guard transferProgress == nil else {
            return
        }

        transferProgress = RepositoryTransferProgress(kind: .export, totalFiles: 1, completedFiles: 0)
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "thatDay-export")
        defer {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }

        do {
            let zipURL = try await repositoryArchiveService.exportArchive(
                from: currentRepositoryStore,
                repositoryID: currentRepositoryID,
                repositoryName: currentRepositoryName
            ) { [self] totalFiles, completedFiles in
                await MainActor.run {
                    self.transferProgress = RepositoryTransferProgress(
                        kind: .export,
                        totalFiles: totalFiles,
                        completedFiles: completedFiles
                    )
                }
            }

            transferProgress = nil
            exportedArchiveItem = ExportedArchiveItem(url: zipURL)
        } catch {
            transferProgress = nil
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func importRepositoryArchive(from zipURL: URL) async {
        guard transferProgress == nil else {
            return
        }

        guard canEditRepository else {
            alertMessage = "当前仓库是只读的，不能导入内容。"
            return
        }

        transferProgress = RepositoryTransferProgress(kind: .import, totalFiles: 1, completedFiles: 0)
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "thatDay-import")
        defer {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }

        do {
            let importedSnapshot = try await repositoryArchiveService.importArchive(
                from: zipURL,
                into: currentRepositoryStore,
                preserving: repositoryDescriptor
            ) { [self] totalFiles, completedFiles in
                await MainActor.run {
                    self.transferProgress = RepositoryTransferProgress(
                        kind: .import,
                        totalFiles: totalFiles,
                        completedFiles: completedFiles
                    )
                }
            }

            entries = importedSnapshot.entries
            try await persistEntries()
            transferProgress = nil
        } catch {
            transferProgress = nil
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func routeToEntry(_ entry: EntryRecord) {
        if entry.kind == .journal {
            selectDate(entry.happenedAt)
            selectedTab = .journal
        } else {
            selectedTab = .blog
        }

        entryOpenRequest = EntryOpenRequest(
            repositoryID: currentRepositoryID,
            entryID: entry.id,
            kind: entry.kind
        )
    }

    func consumeEntryOpenRequest(for tab: AppTab) -> EntryDestination? {
        guard let entryOpenRequest else {
            return nil
        }

        let expectedTab: AppTab = entryOpenRequest.kind == .journal ? .journal : .blog
        guard expectedTab == tab,
              selectedTab == tab,
              entryOpenRequest.repositoryID == currentRepositoryID else {
            return nil
        }

        self.entryOpenRequest = nil
        return .read(entryOpenRequest.entryID)
    }

    func handleScenePhaseChange(_ phase: ScenePhase) async {
        guard preferences.isBiometricLockEnabled else {
            isAuthenticationRequired = false
            shouldRequireAuthenticationOnNextActive = false
            return
        }

        switch phase {
        case .background:
            guard !isAuthenticating else {
                return
            }

            shouldRequireAuthenticationOnNextActive = true
            isAuthenticationRequired = true
        case .active:
            guard shouldRequireAuthenticationOnNextActive else {
                return
            }

            isAuthenticationRequired = true
            await unlockIfNeeded()
        default:
            return
        }
    }

    func unlockIfNeeded() async {
        guard preferences.isBiometricLockEnabled,
              isAuthenticationRequired,
              !isAuthenticating else {
            return
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await authenticateBiometricsAction("打开 thatDay 需要验证")
            isAuthenticationRequired = false
            shouldRequireAuthenticationOnNextActive = false
        } catch {
            if let authError = error as? LAError,
               authError.code == .userCancel || authError.code == .systemCancel {
                return
            }

            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    private var currentRepositoryStore: LocalRepositoryStore {
        libraryStore.repositoryStore(for: currentRepositoryID)
    }

    private func applyAcceptedShare(_ accepted: AcceptedSharedRepository) throws {
        let repositoryID = accepted.descriptor.storageIdentifier
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        try repositoryStore.saveDescriptor(accepted.descriptor)
        try repositoryStore.saveCloudSnapshot(accepted.snapshot)

        upsertRepositoryReference(
            repositoryID: repositoryID,
            descriptor: accepted.descriptor,
            displayName: accepted.displayName ?? accepted.descriptor.defaultDisplayName,
            snapshotUpdatedAt: accepted.snapshot.updatedAt
        )
        try persistRepositoryCatalog()
    }

    private func loadRepository(repositoryID: String) async throws {
        let fallbackRepositoryID = repositories.contains(where: { $0.id == repositoryID })
            ? repositoryID
            : RepositoryReference.localRepositoryID
        currentRepositoryID = fallbackRepositoryID

        let repositoryStore = currentRepositoryStore
        let reference = repositoryReference(for: currentRepositoryID)
        repositoryDescriptor = try repositoryStore.loadDescriptor() ?? reference?.descriptor ?? .local

        if let snapshot = try repositoryStore.loadSnapshot() {
            entries = snapshot.entries
            upsertRepositoryReference(
                repositoryID: currentRepositoryID,
                descriptor: repositoryDescriptor,
                displayName: reference?.displayName ?? repositoryDescriptor.defaultDisplayName,
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
        } else if currentRepositoryID == RepositoryReference.localRepositoryID {
            entries = SampleData.makeEntries()
            let snapshot = RepositorySnapshot(entries: entries, updatedAt: now())
            try repositoryStore.saveDescriptor(.local)
            try repositoryStore.saveSnapshot(snapshot)
            repositoryDescriptor = .local
            upsertRepositoryReference(
                repositoryID: currentRepositoryID,
                descriptor: .local,
                displayName: "我的仓库",
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
        } else {
            entries = []
        }

        if repositoryDescriptor.isCloudBacked {
            let snapshot = try await cloudService.loadSnapshot(using: repositoryDescriptor)
            entries = snapshot.entries
            try repositoryStore.saveCloudSnapshot(snapshot)
            upsertRepositoryReference(
                repositoryID: currentRepositoryID,
                descriptor: repositoryDescriptor,
                displayName: reference?.displayName ?? repositoryDescriptor.defaultDisplayName,
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
        }

        try persistRepositoryCatalog()
    }

    private func persistEntries() async throws {
        let snapshot = RepositorySnapshot(entries: entries, updatedAt: now())
        try currentRepositoryStore.saveSnapshot(snapshot)

        if repositoryDescriptor.role != .local {
            let cloudSnapshot = try currentRepositoryStore.makeSnapshot(
                entries: entries,
                updatedAt: snapshot.updatedAt,
                embeddingImages: true
            )
            repositoryDescriptor = try await cloudService.saveSnapshot(cloudSnapshot, using: repositoryDescriptor)
            try currentRepositoryStore.saveDescriptor(repositoryDescriptor)
        } else {
            try currentRepositoryStore.saveDescriptor(.local)
            repositoryDescriptor = .local
        }

        upsertRepositoryReference(
            repositoryID: currentRepositoryID,
            descriptor: repositoryDescriptor,
            displayName: currentRepositoryName,
            snapshotUpdatedAt: snapshot.updatedAt,
            markAsOpened: true
        )
        try persistRepositoryCatalog()
        await ensureRepositorySubscriptions()
    }

    private func repositoryReference(for repositoryID: String) -> RepositoryReference? {
        repositories.first { $0.id == repositoryID }
    }

    private func upsertRepositoryReference(
        repositoryID: String,
        descriptor: RepositoryDescriptor,
        displayName: String,
        snapshotUpdatedAt: Date?,
        markAsOpened: Bool = false
    ) {
        let normalizedName = displayName.trimmed.nilIfEmpty ?? descriptor.defaultDisplayName
        let source: RepositorySource = repositoryID == RepositoryReference.localRepositoryID ? .local : .shared
        let existing = repositories.first(where: { $0.id == repositoryID })
        let updatedReference = RepositoryReference(
            id: repositoryID,
            displayName: source == .local ? "我的仓库" : normalizedName,
            descriptor: descriptor,
            source: source,
            lastKnownSnapshotUpdatedAt: snapshotUpdatedAt,
            subscribedAt: existing?.subscribedAt ?? now(),
            lastOpenedAt: markAsOpened ? now() : existing?.lastOpenedAt
        )

        if let index = repositories.firstIndex(where: { $0.id == repositoryID }) {
            repositories[index] = updatedReference
        } else {
            repositories.append(updatedReference)
        }
    }

    private func persistRepositoryCatalog() throws {
        repositories = sortedRepositories
        try libraryStore.saveCatalog(repositories)
    }

    private func ensureRepositorySubscriptions() async {
        guard preferences.isSharedUpdateNotificationEnabled else {
            return
        }

        var ensuredSharedDatabaseSubscription = false

        for reference in repositories where reference.descriptor.isCloudBacked {
            if reference.descriptor.role == .editor || reference.descriptor.role == .viewer {
                guard !ensuredSharedDatabaseSubscription else {
                    continue
                }
                ensuredSharedDatabaseSubscription = true
            }

            do {
                try await cloudService.ensureRepositorySubscription(using: reference.descriptor)
            } catch {
                if reference.id == currentRepositoryID {
                    alertMessage = Self.userFacingMessage(for: error)
                }
            }
        }
    }

    private func refreshRepository(_ reference: RepositoryReference, trigger: SharedRepositoryRefreshTrigger) async throws {
        let repositoryStore = libraryStore.repositoryStore(for: reference.id)
        let previousSnapshot = try repositoryStore.loadSnapshot()
        let remoteSnapshot = try await cloudService.loadSnapshot(using: reference.descriptor)
        let previousUpdatedAt = reference.lastKnownSnapshotUpdatedAt ?? previousSnapshot?.updatedAt
        let shouldNotify = previousUpdatedAt != nil && remoteSnapshot.updatedAt > (previousUpdatedAt ?? .distantPast)

        try repositoryStore.saveDescriptor(reference.descriptor)
        try repositoryStore.saveCloudSnapshot(remoteSnapshot)

        upsertRepositoryReference(
            repositoryID: reference.id,
            descriptor: reference.descriptor,
            displayName: reference.displayName,
            snapshotUpdatedAt: remoteSnapshot.updatedAt,
            markAsOpened: reference.id == currentRepositoryID
        )
        try persistRepositoryCatalog()

        if reference.id == currentRepositoryID {
            repositoryDescriptor = reference.descriptor
            entries = remoteSnapshot.entries
        }

        guard shouldNotify,
              preferences.isSharedUpdateNotificationEnabled,
              trigger != .manual,
              let notification = makeSharedRepositoryNotification(
                for: reference,
                previousEntries: previousSnapshot?.entries ?? [],
                latestEntries: remoteSnapshot.entries
              ) else {
            return
        }

        if trigger != .launch {
            await scheduleLocalNotification(notification)
        }
    }

    private func makeSharedRepositoryNotification(
        for reference: RepositoryReference,
        previousEntries: [EntryRecord],
        latestEntries: [EntryRecord]
    ) -> RepositoryUpdateNotification? {
        let previousByID = Dictionary(uniqueKeysWithValues: previousEntries.map { ($0.id, $0) })
        let changedEntries = latestEntries.filter { entry in
            guard let previousEntry = previousByID[entry.id] else {
                return true
            }

            return previousEntry.updatedAt != entry.updatedAt ||
                previousEntry.title != entry.title ||
                previousEntry.body != entry.body ||
                previousEntry.imageReference != entry.imageReference
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }

        guard let firstEntry = changedEntries.first else {
            return nil
        }

        let title: String
        let body: String
        if changedEntries.count == 1 {
            title = "\(reference.displayName) 有更新"
            body = firstEntry.title
        } else {
            title = "\(reference.displayName) 有 \(changedEntries.count) 条更新"
            body = "\(firstEntry.title) 等 \(changedEntries.count) 篇内容"
        }

        return RepositoryUpdateNotification(
            repositoryID: reference.id,
            entryID: firstEntry.id,
            title: title,
            body: body
        )
    }

    private func scheduleLocalNotification(_ notification: RepositoryUpdateNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = [
            LocalNotificationPayload.repositoryIDKey: notification.repositoryID,
            LocalNotificationPayload.entryIDKey: notification.entryID.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "repository-update-\(notification.repositoryID)-\(notification.entryID.uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func systemAuthenticateBiometrics(reason: String) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = "使用密码"

        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evaluationError) else {
            throw evaluationError ?? LAError(.biometryNotAvailable)
        }

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: error ?? LAError(.authenticationFailed))
                }
            }
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

private struct RepositoryUpdateNotification {
    let repositoryID: String
    let entryID: UUID
    let title: String
    let body: String
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

    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws {}

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
            snapshot: RepositorySnapshot(entries: SampleData.makeEntries()),
            displayName: "共享仓库"
        )
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        try await acceptShare(from: URL(string: "https://www.icloud.com/share/preview")!)
    }
}
