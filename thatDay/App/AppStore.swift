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
            L10n.string("Exporting")
        case .import:
            L10n.string("Importing")
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
        L10n.format("%@ %lld of %lld files", kind.title, Int64(completedFiles), Int64(totalFiles))
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

enum SharedRepositoryRefreshTrigger: Equatable, Sendable {
    case launch
    case foreground
    case push
    case manual
    case backgroundRecovery
}

struct SharedRepositoryRefreshResult: Equatable, Sendable {
    var checkedRepositoryCount = 0
    var updatedRepositoryCount = 0
    var failedRepositoryCount = 0

    var backgroundFetchResult: UIBackgroundFetchResult {
        if updatedRepositoryCount > 0 {
            return .newData
        }
        if failedRepositoryCount > 0 {
            return .failed
        }
        return .noData
    }
}

protocol AppLocalAuthenticationContext: AnyObject {
    var localizedFallbackTitle: String? { get set }

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void)
}

extension LAContext: AppLocalAuthenticationContext {}

private enum RepositoryLoadBehavior: Equatable, Sendable {
    case localCacheOnly
    case blockingCloudFetchIfNoLocalSnapshot
}

private struct PendingRepositoryCloudSync {
    var descriptor: RepositoryDescriptor
    var displayName: String
    var mutationCount: Int
}

private enum RepositoryRefreshOutcome {
    case unchanged
    case updated
    case deferred
}

private struct SharedRepositoryRefreshSelection {
    var references: [RepositoryReference]
    var databaseScope: CloudDatabaseScope?
    var changedZoneIDs: Set<CloudRepositoryZoneIdentity>
    var deletedZones: Set<CloudRepositoryZoneDeletion>
}

@MainActor
@Observable
final class AppStore {
    private static let foregroundSharedRefreshMinimumInterval: TimeInterval = 30
    private static let subscriptionConfigurationVersion = 2
    private static let subscriptionRevalidationInterval: TimeInterval = 7 * 24 * 60 * 60

    private let libraryStore: RepositoryLibraryStore
    private let cloudService: any CloudRepositoryServicing
    private let repositoryArchiveService = RepositoryArchiveService()
    private let now: () -> Date
    private let sleepUntilSharedCloudRetry: @Sendable (Date) async throws -> Void
    private let scheduleBackgroundRefreshAfter: (Date) -> Void
    private let authenticateBiometricsAction: (String) async throws -> Void
    private let setApplicationBadgeCount: (Int) -> Void
    private let baseCalendar: Calendar
    private var systemTimeZone: TimeZone

    private var didLoad = false
    private var didLoadPersistentState = false
    private var hasLoadedPreferences = false
    private var isApplicationActive = false
    private var preferences = AppPreferences()
    private var shouldRequireAuthenticationOnNextActive = false
    private var shouldEnsureSubscriptionsAfterUnlock = false
    private var pendingPostUnlockSharedRefreshTrigger: SharedRepositoryRefreshTrigger?
    private var lastSharedRepositoryRefreshAt: Date?
    private var sharedCloudThrottleUntil: Date?
    private var sharedCloudThrottleRetryTask: Task<Void, Never>?
    private var sharedRepositoryRefreshTask: Task<SharedRepositoryRefreshResult, Never>?
    private var sharedRepositoryRefreshTaskID: UUID?
    private var repositoryMutationGenerations: [String: Int] = [:]
    private var repositoryMutationInFlightCounts: [String: Int] = [:]
    private var repositoriesPendingRefreshAfterMutation: Set<String> = []
    private var pendingRepositoryCloudSyncs: [String: PendingRepositoryCloudSync] = [:]
    private var repositoryCloudSyncTasks: [String: Task<Void, Never>] = [:]

    var selectedTab: AppTab = .journal
    var selectedDate: Date
    var displayedMonth: Date
    var searchText = ""
    var selectedBlogTag: String?
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
    var imageRefreshVersion = 0

    private(set) var entries: [EntryRecord] = []
    private(set) var repositoryDescriptor: RepositoryDescriptor = .local
    private(set) var repositories: [RepositoryReference] = [.local]
    private(set) var currentRepositoryID = RepositoryReference.localRepositoryID
    private(set) var blogTags: [String] = RepositorySnapshot.defaultBlogTags
    private(set) var repositorySharedUpdateNotificationScope: SharedUpdateNotificationScope = .all

    init(
        libraryStore: RepositoryLibraryStore,
        cloudService: any CloudRepositoryServicing,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        sleepUntilSharedCloudRetry: @escaping @Sendable (Date) async throws -> Void = { deadline in
            let delay = deadline.timeIntervalSinceNow
            guard delay > 0 else {
                return
            }
            try await Task.sleep(for: .seconds(delay))
        },
        scheduleBackgroundRefreshAfter: @escaping (Date) -> Void = { _ in },
        authenticateBiometrics: @escaping (String) async throws -> Void = AppStore.systemAuthenticateBiometrics,
        setApplicationBadgeCount: @escaping (Int) -> Void = { badgeCount in
            UNUserNotificationCenter.current().setBadgeCount(badgeCount) { _ in }
        }
    ) {
        self.libraryStore = libraryStore
        self.cloudService = cloudService
        baseCalendar = calendar
        systemTimeZone = calendar.timeZone
        self.now = now
        self.sleepUntilSharedCloudRetry = sleepUntilSharedCloudRetry
        self.scheduleBackgroundRefreshAfter = scheduleBackgroundRefreshAfter
        authenticateBiometricsAction = authenticateBiometrics
        self.setApplicationBadgeCount = setApplicationBadgeCount

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
        repositoryDescriptor.role.canEdit &&
            currentRepositoryReference?.cloudZoneUnavailableAt == nil
    }

    var repositoryStatusTitle: String {
        if currentRepositoryReference?.cloudZoneUnavailableAt != nil {
            return L10n.string("Unavailable · Cached Read-Only")
        }
        return repositoryDescriptor.role.title
    }

    var currentRepositoryName: String {
        currentRepositoryReference?.localizedDisplayName ?? repositoryDescriptor.defaultDisplayName
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

    var sharedUpdateNotificationScope: SharedUpdateNotificationScope {
        preferences.sharedUpdateNotificationScope
    }

    var appTimeZone: AppTimeZone {
        preferences.appTimeZone
    }

    var timeZone: TimeZone {
        appTimeZone.resolve(systemTimeZone: systemTimeZone)
    }

    var calendar: Calendar {
        var configuredCalendar = baseCalendar
        configuredCalendar.locale = AppLanguage.locale
        configuredCalendar.timeZone = timeZone
        return configuredCalendar
    }

    var effectiveCurrentRepositoryNotificationScope: SharedUpdateNotificationScope {
        effectiveNotificationScope(for: repositorySharedUpdateNotificationScope)
    }

    var canCreateShareInvite: Bool {
        repositoryDescriptor.role.canCreateShareInvite &&
            currentRepositoryReference?.cloudZoneUnavailableAt == nil
    }

    var canManageRepositoryNotificationScope: Bool {
        repositoryDescriptor.role.canManageRepositoryNotificationScope &&
            currentRepositoryReference?.cloudZoneUnavailableAt == nil
    }

    var isCurrentRepositoryNotificationScopeOverridingLocalPreference: Bool {
        repositorySharedUpdateNotificationScope != .all
    }

    var repositoryNotificationScopeDescription: String {
        switch repositoryDescriptor.role {
        case .local:
            if repositorySharedUpdateNotificationScope == .all {
                return L10n.string("When this repository is shared, members can use their own Push Updates preference.")
            }

            return L10n.format(
                "When this repository is shared, every member will be limited to %@ for this repository.",
                repositorySharedUpdateNotificationScope.summary.lowercased(with: AppLanguage.locale)
            )
        case .owner:
            if repositorySharedUpdateNotificationScope == .all {
                return L10n.string("Members can use their own Push Updates preference while this repository stays on All.")
            }

            return L10n.format(
                "This repository is locked to %@ for every member. Personal Push Updates preferences are ignored here until you switch back to All.",
                repositorySharedUpdateNotificationScope.summary.lowercased(with: AppLanguage.locale)
            )
        case .editor, .viewer:
            if repositorySharedUpdateNotificationScope == .all {
                return L10n.string("The owner allows each member to use their own Push Updates preference for this repository.")
            }

            return L10n.format(
                "The owner locked this repository to %@. Your personal Push Updates preference is ignored here until the owner switches back to All.",
                repositorySharedUpdateNotificationScope.summary.lowercased(with: AppLanguage.locale)
            )
        }
    }

    var personalNotificationScopeDescription: String {
        if repositorySharedUpdateNotificationScope == .all {
            return L10n.string("This is your personal default. It applies to the current repository because the owner allows All.")
        }

        return L10n.format(
            "This is still your personal default, but the current repository follows the owner's %@ rule instead.",
            repositorySharedUpdateNotificationScope.title
        )
    }

    var selectedDateTitle: String {
        AppLanguage.monthDayTitle(for: selectedDate, timeZone: timeZone)
    }

    func monthYearTitle(for date: Date) -> String {
        AppLanguage.monthYearTitle(for: date, timeZone: timeZone)
    }

    func timelineTitle(for entry: EntryRecord) -> String {
        AppLanguage.timelineTitle(for: entry.happenedAt, timeZone: timeZone)
    }

    func cardDateTitle(for entry: EntryRecord) -> String {
        AppLanguage.cardDateTitle(for: entry.happenedAt, timeZone: timeZone)
    }

    func journalCardDateTitle(for entry: EntryRecord) -> String {
        AppLanguage.journalCardDateTitle(for: entry.happenedAt, timeZone: timeZone)
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

    var journalEntries: [EntryRecord] {
        journalEntries(for: selectedDate)
    }

    func journalEntries(for date: Date) -> [EntryRecord] {
        entries
            .filter { $0.kind == .journal && calendar.isSameMonthDay($0.happenedAt, date) }
            .sorted { lhs, rhs in
                if lhs.happenedAt != rhs.happenedAt {
                    return lhs.happenedAt > rhs.happenedAt
                }
                return lhs.createdAt > rhs.createdAt
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

    func blogEntries(for tag: String?) -> [EntryRecord] {
        guard let matchedTag = matchedBlogTag(for: tag) else {
            return blogEntries
        }

        return blogEntries.filter { $0.blogTag == matchedTag }
    }

    var blogTagPageSelections: [String?] {
        var selections: [String?] = [nil]
        selections.append(contentsOf: blogTags.map { Optional.some($0) })
        return selections
    }

    func blogTagPageIndex(for tag: String?) -> Int {
        let matchedTag = matchedBlogTag(for: tag)
        return blogTagPageSelections.firstIndex { $0 == matchedTag } ?? 0
    }

    func blogTag(byAdding offset: Int, to tag: String?) -> String? {
        let selections = blogTagPageSelections
        let currentIndex = blogTagPageIndex(for: tag)
        let targetIndex = min(max(currentIndex + offset, 0), selections.count - 1)
        return selections[targetIndex]
    }

    var journalEntryCount: Int {
        entries.filter { $0.kind == .journal }.count
    }

    var blogEntryCount: Int {
        blogEntries.count
    }

    var writtenWordCount: Int {
        entries.reduce(into: 0) { total, entry in
            total += [entry.title, entry.body]
                .joined(separator: " ")
                .writtenWordCount
        }
    }

    var formattedWrittenWordCount: String {
        Self.abbreviatedCount(writtenWordCount)
    }

    var blogTagUsageCounts: [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: blogTags.map { ($0, 0) })
        for entry in blogEntries {
            guard let tag = entry.blogTag else {
                continue
            }
            counts[tag, default: 0] += 1
        }

        return counts
    }

    var defaultBlogTag: String {
        Self.defaultBlogTag(in: blogTags)
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
        clearApplicationBadge()

        do {
            try await preparePersistentStateIfNeeded()
            await resumePendingCloudSyncs()
            await ensureRepositorySubscriptions()
            if preferences.isBiometricLockEnabled {
                isAuthenticationRequired = true
                shouldRequireAuthenticationOnNextActive = false
                pendingPostUnlockSharedRefreshTrigger = .launch
                await unlockIfNeeded()
            } else {
                await refreshSharedRepositories(trigger: .launch)
            }
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
            if entries.isEmpty {
                entries = []
                blogTags = RepositorySnapshot.defaultBlogTags
                repositorySharedUpdateNotificationScope = .all
            }
        }
    }

    private func preparePersistentStateIfNeeded() async throws {
        guard !didLoadPersistentState else {
            return
        }

        repositories = try libraryStore.loadCatalog()
        for reference in repositories {
            try repositoryArchiveService.recoverInterruptedImport(
                for: libraryStore.repositoryStore(for: reference.id)
            )
        }
        preferences = try libraryStore.loadPreferences()
        try reconcilePendingCloudPurges()
        try reconcileCloudUploadOutboxes()
        sharedCloudThrottleUntil = preferences.cloudRetryAfter
        scheduleSharedCloudRetryIfNeeded()
        await reconcileAttemptedEncryptedResetAcknowledgements()
        lastSharedRepositoryRefreshAt = preferences.lastSuccessfulCloudRefreshAt
        if repositories.contains(where: { $0.cloudUploadConflictDetectedAt != nil }) {
            alertMessage = Self.userFacingMessage(
                for: CloudRepositoryError.repositoryConflict(
                    serverRecordChangeTag: nil
                )
            )
        }
        hasLoadedPreferences = true
        resetCalendarContextToToday()
        let launchRepositoryID = repositories.contains(where: { $0.id == preferences.defaultRepositoryID })
            ? preferences.defaultRepositoryID
            : RepositoryReference.localRepositoryID
        try await loadRepository(repositoryID: launchRepositoryID, behavior: .localCacheOnly)
        didLoadPersistentState = true
    }

    private func resetCalendarContextToToday() {
        let today = calendar.startOfDay(for: now())
        selectedDate = today
        displayedMonth = calendar.startOfMonth(for: today)
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        displayedMonth = calendar.startOfMonth(for: selectedDate)
    }

    func startOfJournalDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func journalDate(byAdding days: Int, to date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let adjustedDate = calendar.date(byAdding: .day, value: days, to: startOfDay) ?? startOfDay
        return calendar.startOfDay(for: adjustedDate)
    }

    func showEditor(for kind: EntryKind, entry: EntryRecord? = nil) {
        guard canEditRepository else {
            alertMessage = L10n.string("The current repository is read-only and cannot be changed.")
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

    func saveEntry(
        draft: EntryDraft,
        importedImageData: Data?,
        removeExistingImage: Bool = false,
        editing editingEntry: EntryRecord? = nil
    ) async -> Bool {
        guard canEditRepository else {
            alertMessage = L10n.string("The current repository is read-only and cannot save changes.")
            return false
        }

        let normalized = draft.normalized
        guard !normalized.title.isEmpty || !normalized.body.isEmpty else {
            alertMessage = L10n.string("Enter a title or content.")
            return false
        }

        isBusy = true
        defer { isBusy = false }

        let entriesBeforeSave = entries
        var didStageImageChange = false
        var snapshotBeforeImageChange: RepositorySnapshot?

        do {
            normalizeRepositoryState()
            let entryID = editingEntry?.id ?? UUID()
            let existingImageReference = editingEntry?.imageReference
            let didChangeImage = importedImageData != nil || (removeExistingImage && existingImageReference != nil)
            didStageImageChange = didChangeImage
            if didChangeImage {
                snapshotBeforeImageChange = try currentRepositoryStore.loadSnapshot()
            }
            let imageReference: String?
            if let importedImageData {
                // Image references are immutable so the committed snapshot keeps
                // pointing at its original bytes until the replacement is durable.
                imageReference = try currentRepositoryStore.storeImage(
                    data: importedImageData,
                    suggestedID: UUID()
                )
            } else if removeExistingImage {
                imageReference = nil
            } else {
                imageReference = existingImageReference
            }

            let timestamp = now()
            let blogTag = normalized.kind == .blog
                ? normalizedBlogTag(for: normalized.blogTag, availableTags: blogTags)
                : nil
            let blogImageLayout = normalized.kind == .blog ? normalized.blogImageLayout : .landscape
            if var existing = editingEntry {
                existing.title = normalized.title
                existing.body = normalized.body
                existing.blogTag = blogTag
                existing.blogImageLayout = blogImageLayout
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
                        blogTag: blogTag,
                        blogImageLayout: blogImageLayout,
                        happenedAt: normalized.happenedAt,
                        createdAt: timestamp,
                        updatedAt: timestamp,
                        imageReference: imageReference
                    )
                )
            }

            try await persistEntries(pruningUnreferencedImages: !didChangeImage)
            if didChangeImage {
                try? currentRepositoryStore.pruneUnreferencedImages(referencedBy: entries)
                invalidateImageViews()
            }
            editorSession = nil
            return true
        } catch {
            if didStageImageChange {
                entries = entriesBeforeSave
                if let snapshotBeforeImageChange {
                    try? currentRepositoryStore.saveSnapshot(
                        snapshotBeforeImageChange,
                        pruningUnreferencedImages: false
                    )
                }
                try? currentRepositoryStore.pruneUnreferencedImages(referencedBy: entriesBeforeSave)
                invalidateImageViews()
            }
            alertMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    func addBlogTag(named rawName: String) async {
        guard canEditRepository else {
            alertMessage = L10n.string("The current repository is read-only and cannot change blog tags.")
            return
        }

        let name = rawName.trimmed
        guard !name.isEmpty else {
            alertMessage = L10n.string("Enter a tag name.")
            return
        }

        guard !blogTags.contains(where: { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            alertMessage = L10n.string("That blog tag already exists.")
            return
        }

        let previousEntries = entries
        let previousBlogTags = blogTags
        blogTags.append(name)
        await persistCurrentRepositoryMutation(
            previousEntries: previousEntries,
            previousBlogTags: previousBlogTags,
            previousRepositoryNotificationScope: repositorySharedUpdateNotificationScope
        )
    }

    func moveBlogTags(fromOffsets source: IndexSet, toOffset destination: Int) async {
        guard canEditRepository else {
            alertMessage = L10n.string("The current repository is read-only and cannot change blog tags.")
            return
        }

        var updatedBlogTags = blogTags
        updatedBlogTags.move(fromOffsets: source, toOffset: destination)
        await updateBlogTags(updatedBlogTags)
    }

    func moveBlogTag(named sourceTag: String, relativeTo targetTag: String, placingAfter: Bool) async {
        guard canEditRepository else {
            alertMessage = L10n.string("The current repository is read-only and cannot change blog tags.")
            return
        }

        guard sourceTag != targetTag,
              let sourceIndex = blogTags.firstIndex(of: sourceTag),
              let targetIndex = blogTags.firstIndex(of: targetTag) else {
            return
        }

        var updatedBlogTags = blogTags
        updatedBlogTags.remove(at: sourceIndex)

        let adjustedTargetIndex = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
        let insertionIndex = min(
            max(adjustedTargetIndex + (placingAfter ? 1 : 0), 0),
            updatedBlogTags.count
        )
        updatedBlogTags.insert(sourceTag, at: insertionIndex)

        await updateBlogTags(updatedBlogTags)
    }

    func deleteBlogTag(_ tag: String, reassigningEntriesTo replacementTag: String?) async {
        guard canEditRepository else {
            alertMessage = L10n.string("The current repository is read-only and cannot change blog tags.")
            return
        }

        guard blogTags.contains(tag) else {
            return
        }

        guard blogTags.count > 1 else {
            alertMessage = L10n.string("At least one blog tag must remain.")
            return
        }

        let usageCount = blogEntries.filter { $0.blogTag == tag }.count
        if usageCount > 0 {
            guard let replacementTag,
                  replacementTag != tag,
                  blogTags.contains(replacementTag) else {
                alertMessage = L10n.string("Choose a destination tag for existing blog posts.")
                return
            }
        }

        let previousEntries = entries
        let previousBlogTags = blogTags
        entries = entries.map { entry in
            guard entry.kind == .blog,
                  entry.blogTag == tag else {
                return entry
            }

            var updatedEntry = entry
            updatedEntry.blogTag = replacementTag
            updatedEntry.updatedAt = now()
            return updatedEntry
        }
        blogTags.removeAll { $0 == tag }

        await persistCurrentRepositoryMutation(
            previousEntries: previousEntries,
            previousBlogTags: previousBlogTags,
            previousRepositoryNotificationScope: repositorySharedUpdateNotificationScope
        )
    }

    func deleteEntry(_ entry: EntryRecord) async {
        guard canEditRepository else {
            alertMessage = L10n.string("The current repository is read-only and cannot delete content.")
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
            alertMessage = L10n.string("The current repository is read-only and cannot be cleared.")
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

    func openBlog(tag: String? = nil) {
        selectBlogTag(tag)
        selectedTab = .blog
    }

    func selectBlogTag(_ tag: String?) {
        selectedBlogTag = matchedBlogTag(for: tag)
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
        guard canCreateShareInvite else {
            alertMessage = L10n.string("Only the repository owner can create a share invite.")
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let repositoryID = currentRepositoryID
            try await persistEntries()

            if repositoryDescriptor.role == .local {
                let repositoryStore = libraryStore.repositoryStore(
                    for: repositoryID
                )
                guard let localSnapshot = try repositoryStore.loadSnapshot()
                else {
                    throw CloudRepositoryError.invalidRepositoryData
                }
                let cloudSnapshot = try repositoryStore.makeSnapshot(
                    entries: localSnapshot.entries,
                    updatedAt: localSnapshot.updatedAt,
                    embeddingImages: true,
                    blogTags: localSnapshot.blogTags,
                    sharedUpdateNotificationScope:
                        localSnapshot.sharedUpdateNotificationScope
                )
                let outboxStore = cloudUploadOutboxStore(for: repositoryID)
                let existingOutbox = try outboxStore.load()
                let generation = max(
                    existingOutbox?.generation ?? 0,
                    repositoryReference(for: repositoryID)?
                        .pendingCloudUploadGeneration ?? 0
                ) &+ 1
                let predecessorOperationIDs: [UUID]
                if let existingOutbox, existingOutbox.receipt == nil {
                    predecessorOperationIDs =
                        [existingOutbox.operationID] +
                        existingOutbox.predecessorOperationIDs
                } else {
                    predecessorOperationIDs = []
                }
                let shareOutbox = try CloudUploadOutboxRecord(
                    repositoryID: repositoryID,
                    descriptor: .local,
                    displayName: currentRepositoryName,
                    snapshot: cloudSnapshot,
                    generation: generation,
                    baseRecordChangeTag: nil,
                    predecessorOperationIDs: predecessorOperationIDs,
                    mode: .prepareShare,
                    createdAt: now()
                )
                try outboxStore.save(shareOutbox)
                markCloudUploadPending(
                    for: repositoryID,
                    snapshotUpdatedAt: cloudSnapshot.updatedAt,
                    generation: generation,
                    baseRecordChangeTag: nil
                )
                try persistRepositoryCatalog()
                scheduleCloudSync(
                    repositoryID: repositoryID,
                    descriptor: .local,
                    displayName: currentRepositoryName,
                    mutationCount: 0
                )
            }

            if let uploadTask = repositoryCloudSyncTasks[repositoryID] {
                await uploadTask.value
            }

            guard let reference = repositoryReference(for: repositoryID)
            else {
                throw CloudRepositoryError.repositoryNotFound
            }
            if reference.cloudUploadConflictDetectedAt != nil {
                throw CloudRepositoryError.repositoryConflict(
                    serverRecordChangeTag:
                        reference.cloudUploadConflictServerChangeTag
                )
            }
            guard reference.pendingCloudUploadGeneration == nil,
                  reference.descriptor.role == .owner else {
                throw CloudRepositoryError.shareUnavailable
            }

            repositoryDescriptor = reference.descriptor
            let snapshot = try currentRepositoryStore.makeSnapshot(
                entries: entries,
                updatedAt: reference.lastKnownSnapshotUpdatedAt ?? now(),
                embeddingImages: true,
                blogTags: blogTags,
                sharedUpdateNotificationScope:
                    repositorySharedUpdateNotificationScope
            )

            let controller = try await cloudService.makeSharingController(
                using: repositoryDescriptor,
                snapshot: snapshot,
                access: shareAccessOption
            )
            sharingControllerItem = SharingControllerItem(controller: controller)
        } catch {
            _ = recordSharedCloudThrottleIfNeeded(for: error)
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func acceptIncomingShareLink() async {
        let rawValue = incomingShareLink.trimmed
        guard let url = URL(string: rawValue),
              url.absoluteString.contains("/share/") else {
            alertMessage = L10n.string("Enter a valid iCloud share link.")
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let accepted = try await cloudService.acceptShare(from: url)
            try applyAcceptedShare(accepted)
            incomingShareLink = ""
            try await loadRepository(
                repositoryID: accepted.descriptor.storageIdentifier,
                behavior: .localCacheOnly
            )
            await ensureRepositorySubscriptions()
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
            try await loadRepository(
                repositoryID: accepted.descriptor.storageIdentifier,
                behavior: .localCacheOnly
            )
            await ensureRepositorySubscriptions()
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func switchRepository(to repositoryID: String) async {
        guard repositoryID != currentRepositoryID else {
            return
        }

        let shouldBlockOnRemoteLoad = shouldBlockWhenSwitchingRepository(to: repositoryID)
        if shouldBlockOnRemoteLoad {
            isBusy = true
        }
        defer {
            if shouldBlockOnRemoteLoad {
                isBusy = false
            }
        }

        do {
            try await loadRepository(
                repositoryID: repositoryID,
                behavior: .blockingCloudFetchIfNoLocalSnapshot
            )
            if !shouldBlockOnRemoteLoad {
                await silentlyRefreshCurrentRepository(trigger: .foreground)
            }
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

    func setAppTimeZone(_ appTimeZone: AppTimeZone) {
        guard appTimeZone != preferences.appTimeZone else {
            return
        }

        let previousCalendar = calendar
        let selectedDateComponents = previousCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        let displayedMonthComponents = previousCalendar.dateComponents([.year, .month], from: displayedMonth)
        preferences.appTimeZone = appTimeZone

        let updatedCalendar = calendar
        preserveCalendarContext(
            selectedDateComponents: selectedDateComponents,
            displayedMonthComponents: displayedMonthComponents,
            in: updatedCalendar
        )

        do {
            try libraryStore.savePreferences(preferences)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func systemTimeZoneDidChange() {
        let previousCalendar = calendar
        let selectedDateComponents = previousCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        let displayedMonthComponents = previousCalendar.dateComponents([.year, .month], from: displayedMonth)
        systemTimeZone = .autoupdatingCurrent

        guard appTimeZone == .system else {
            return
        }

        preserveCalendarContext(
            selectedDateComponents: selectedDateComponents,
            displayedMonthComponents: displayedMonthComponents,
            in: calendar
        )
    }

    private func preserveCalendarContext(
        selectedDateComponents: DateComponents,
        displayedMonthComponents: DateComponents,
        in updatedCalendar: Calendar
    ) {
        if let updatedSelectedDate = updatedCalendar.date(from: selectedDateComponents) {
            selectedDate = updatedCalendar.startOfDay(for: updatedSelectedDate)
        }
        if let updatedDisplayedMonth = updatedCalendar.date(from: displayedMonthComponents) {
            displayedMonth = updatedCalendar.startOfMonth(for: updatedDisplayedMonth)
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
            try await authenticateBiometricsAction(L10n.string("Enable biometric lock"))
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

    func setSharedUpdateNotificationScope(_ scope: SharedUpdateNotificationScope) {
        preferences.sharedUpdateNotificationScope = scope

        do {
            try libraryStore.savePreferences(preferences)
        } catch {
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    func updateRepositorySharedUpdateNotificationScope(_ scope: SharedUpdateNotificationScope) async {
        guard canManageRepositoryNotificationScope else {
            alertMessage = L10n.string("Only the repository owner can change this repository's push update rule.")
            return
        }

        guard scope != repositorySharedUpdateNotificationScope else {
            return
        }

        let previousEntries = entries
        let previousBlogTags = blogTags
        let previousRepositoryScope = repositorySharedUpdateNotificationScope
        repositorySharedUpdateNotificationScope = scope
        await persistCurrentRepositoryMutation(
            previousEntries: previousEntries,
            previousBlogTags: previousBlogTags,
            previousRepositoryNotificationScope: previousRepositoryScope
        )
    }

    func updateSharedUpdateNotificationEnabled(_ isEnabled: Bool) async {
        if !isEnabled {
            setSharedUpdateNotificationEnabled(false)
            clearApplicationBadge()
            return
        }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                alertMessage = L10n.string(
                    "Notification permission is disabled, so visible shared repository alerts cannot be shown. Background synchronization stays enabled."
                )
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

    @discardableResult
    func refreshSharedRepositories(
        trigger: SharedRepositoryRefreshTrigger,
        target: CloudRemoteNotificationTarget? = nil
    ) async -> SharedRepositoryRefreshResult {
        while let existingTask = sharedRepositoryRefreshTask {
            _ = await existingTask.value
        }

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return SharedRepositoryRefreshResult(failedRepositoryCount: 1)
            }

            let result = await self.performSharedRepositoryRefresh(
                trigger: trigger,
                target: target
            )
            if self.sharedRepositoryRefreshTaskID == taskID {
                self.sharedRepositoryRefreshTask = nil
                self.sharedRepositoryRefreshTaskID = nil
            }
            return result
        }
        sharedRepositoryRefreshTask = task
        sharedRepositoryRefreshTaskID = taskID

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func handleRemoteRepositoryChange(
        _ target: CloudRemoteNotificationTarget?,
        trigger: SharedRepositoryRefreshTrigger
    ) async -> UIBackgroundFetchResult {
        do {
            try await preparePersistentStateIfNeeded()
        } catch {
            return .failed
        }

        let result: SharedRepositoryRefreshResult
        if trigger == .backgroundRecovery, target == nil {
            result = await performIncrementalBackgroundRecovery()
        } else {
            result = await refreshSharedRepositories(trigger: trigger, target: target)
        }
        guard !Task.isCancelled else {
            return .failed
        }
        await resumePendingCloudSyncs(
            waitForCompletion: trigger == .backgroundRecovery
        )
        if trigger == .backgroundRecovery {
            await ensureRepositorySubscriptions()
        }
        return result.backgroundFetchResult
    }

    private func performIncrementalBackgroundRecovery() async -> SharedRepositoryRefreshResult {
        guard activeSharedCloudThrottleUntil() == nil else {
            return SharedRepositoryRefreshResult()
        }

        let hasPrivateRepositories = repositories.contains {
            $0.descriptor.role == .owner &&
                $0.cloudZoneUnavailableAt == nil
        }
        let hasSharedRepositories = repositories.contains {
            ($0.descriptor.role == .editor || $0.descriptor.role == .viewer) &&
                $0.cloudZoneUnavailableAt == nil
        }
        var scopes: [CloudDatabaseScope] = []
        if hasPrivateRepositories {
            scopes.append(.privateDatabase)
        }
        if hasSharedRepositories {
            scopes.append(.sharedDatabase)
        }

        var combinedResult = SharedRepositoryRefreshResult()
        for scope in scopes {
            guard !Task.isCancelled else {
                combinedResult.failedRepositoryCount += 1
                break
            }

            let result = await refreshSharedRepositories(
                trigger: .backgroundRecovery,
                target: .database(scope)
            )
            combinedResult.checkedRepositoryCount += result.checkedRepositoryCount
            combinedResult.updatedRepositoryCount += result.updatedRepositoryCount
            combinedResult.failedRepositoryCount += result.failedRepositoryCount
        }
        if combinedResult.failedRepositoryCount == 0 {
            recordSuccessfulFullCloudRefresh()
        }
        return combinedResult
    }

    func handleCloudAccountChange() async {
        do {
            try await preparePersistentStateIfNeeded()
        } catch {
            return
        }

        for index in repositories.indices {
            repositories[index].subscriptionConfigurationVersion = nil
            repositories[index].subscriptionValidatedAt = nil
            repositories[index].lastKnownServerRecordChangeTag = nil
            repositories[index].lastKnownServerModifiedAt = nil
            repositories[index].cloudZoneUnavailableAt = nil
            if repositories[index].pendingCloudUploadGeneration != nil {
                repositories[index].cloudUploadConflictServerChangeTag = nil
                repositories[index].cloudUploadConflictDetectedAt = now()
            }
        }
        try? persistRepositoryCatalog()
        try? await cloudService.resetRemoteChangeTracking()
        await ensureRepositorySubscriptions()
        await refreshSharedRepositories(trigger: .foreground)
    }

    private func performSharedRepositoryRefresh(
        trigger: SharedRepositoryRefreshTrigger,
        target: CloudRemoteNotificationTarget?
    ) async -> SharedRepositoryRefreshResult {
        guard !Task.isCancelled else {
            return SharedRepositoryRefreshResult(failedRepositoryCount: 1)
        }

        if let throttleUntil = activeSharedCloudThrottleUntil() {
            if trigger == .manual {
                alertMessage = sharedCloudThrottleMessage(until: throttleUntil)
            }
            return SharedRepositoryRefreshResult()
        }

        let selection: SharedRepositoryRefreshSelection
        do {
            selection = try await sharedRepositoryRefreshSelection(for: trigger, target: target)
        } catch {
            _ = recordSharedCloudThrottleIfNeeded(for: error)
            return SharedRepositoryRefreshResult(failedRepositoryCount: 1)
        }

        var result = SharedRepositoryRefreshResult()
        if selection.databaseScope == .privateDatabase {
            do {
                try completeAttemptedEncryptedResetAcknowledgements(
                    notPendingIn: selection.deletedZones
                )
            } catch {
                result.failedRepositoryCount += 1
            }
        }
        let selectedZoneIDs = Set(
            selection.references.compactMap { cloudZoneIdentity(for: $0) }
        )
        var acknowledgedModifiedZoneIDs =
            selection.changedZoneIDs.subtracting(selectedZoneIDs)
        var acknowledgedDeletedZones: Set<CloudRepositoryZoneDeletion> = []
        var didEncounterCloudThrottle = false

        for deletion in selection.deletedZones {
            guard !Task.isCancelled else {
                result.failedRepositoryCount += 1
                break
            }

            do {
                let deletionResult = try await handleRepositoryZoneDeletion(
                    deletion,
                    databaseScope: selection.databaseScope
                )
                result.checkedRepositoryCount += deletionResult.checkedCount
                result.updatedRepositoryCount += deletionResult.updatedCount
                acknowledgedDeletedZones.insert(deletion)
            } catch {
                result.failedRepositoryCount += 1
                if recordSharedCloudThrottleIfNeeded(for: error) != nil {
                    didEncounterCloudThrottle = true
                    break
                }
            }
        }

        for reference in selection.references where !didEncounterCloudThrottle {
            guard !Task.isCancelled else {
                result.failedRepositoryCount += 1
                break
            }

            result.checkedRepositoryCount += 1
            do {
                switch try await refreshRepository(reference, trigger: trigger) {
                case .updated:
                    result.updatedRepositoryCount += 1
                    if let zoneID = cloudZoneIdentity(for: reference) {
                        acknowledgedModifiedZoneIDs.insert(zoneID)
                    }
                case .unchanged:
                    if let zoneID = cloudZoneIdentity(for: reference) {
                        acknowledgedModifiedZoneIDs.insert(zoneID)
                    }
                case .deferred:
                    result.failedRepositoryCount += 1
                }
            } catch {
                result.failedRepositoryCount += 1
                let throttleUntil = recordSharedCloudThrottleIfNeeded(for: error)
                if trigger == .manual, reference.id == currentRepositoryID {
                    alertMessage = throttleUntil.map(sharedCloudThrottleMessage(until:))
                        ?? Self.userFacingMessage(for: error)
                }
                if throttleUntil != nil {
                    didEncounterCloudThrottle = true
                    break
                }
            }
        }

        if let databaseScope = selection.databaseScope,
           (!acknowledgedModifiedZoneIDs.isEmpty ||
            !acknowledgedDeletedZones.isEmpty) {
            do {
                try commitEncryptedResetAcknowledgementReceipts(
                    acknowledgedDeletedZones
                )
                try markEncryptedResetAcknowledgementsAttempted(
                    acknowledgedDeletedZones
                )
                try await cloudService.acknowledgeRepositoryZoneChanges(
                    CloudRepositoryDatabaseChanges(
                        modifiedZoneIDs: acknowledgedModifiedZoneIDs,
                        deletedZones: acknowledgedDeletedZones
                    ),
                    in: databaseScope
                )
                try completeEncryptedResetAcknowledgements(
                    acknowledgedDeletedZones
                )
            } catch {
                result.failedRepositoryCount += 1
                _ = recordSharedCloudThrottleIfNeeded(for: error)
            }
        }

        if result.failedRepositoryCount == 0,
           target == nil,
           trigger == .launch || trigger == .foreground {
            recordSuccessfulFullCloudRefresh()
        }

        return result
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
            alertMessage = L10n.string("The current repository is read-only and cannot import content.")
            return
        }

        let repositoryID = currentRepositoryID
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let repositoryName = currentRepositoryName
        var preparedImport: PreparedRepositoryImport?
        var previousOutbox: CloudUploadOutboxRecord?
        var didWriteSuccessorOutbox = false
        var didInstallPreparedImport = false
        var didBeginMutation = false

        transferProgress = RepositoryTransferProgress(kind: .import, totalFiles: 1, completedFiles: 0)
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "thatDay-import")
        defer {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }

        do {
            let stagedImport = try await repositoryArchiveService.prepareImportArchive(
                from: zipURL,
                nextTo: repositoryStore,
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
            preparedImport = stagedImport

            beginRepositoryMutation(for: repositoryID)
            didBeginMutation = true
            await quiesceRepositoryCloudSync(for: repositoryID)

            guard currentRepositoryID == repositoryID,
                  let currentReference = repositoryReference(for: repositoryID)
            else {
                throw CloudRepositoryError.repositoryNotFound
            }

            let descriptor = currentReference.descriptor
            let outboxStore = cloudUploadOutboxStore(for: repositoryID)
            let existingOutbox = try outboxStore.load()
            previousOutbox = existingOutbox
            let isPendingLocalShare =
                descriptor.role == .local &&
                existingOutbox?.mode == .prepareShare &&
                existingOutbox?.receipt == nil
            let shouldCreateCloudOutbox =
                descriptor.isCloudBacked || isPendingLocalShare
            var successorOutbox: CloudUploadOutboxRecord?

            if shouldCreateCloudOutbox {
                let cloudSnapshot = try stagedImport.repositoryStore.makeSnapshot(
                    entries: stagedImport.snapshot.entries,
                    updatedAt: stagedImport.snapshot.updatedAt,
                    embeddingImages: true,
                    blogTags: stagedImport.snapshot.blogTags,
                    sharedUpdateNotificationScope:
                        stagedImport.snapshot.sharedUpdateNotificationScope
                )
                let generation = max(
                    currentReference.pendingCloudUploadGeneration ?? 0,
                    existingOutbox?.generation ?? 0
                ) &+ 1
                let uploadMode = existingOutbox?.receipt == nil
                    ? existingOutbox?.mode ?? .normal
                    : .normal
                let baseRecordChangeTag =
                    uploadMode == .recreateAfterEncryptedDataReset
                    ? nil
                    : existingOutbox?.receipt?.recordChangeTag ??
                        existingOutbox?.baseRecordChangeTag ??
                        currentReference.pendingCloudUploadBaseChangeTag ??
                        currentReference.lastKnownServerRecordChangeTag
                let outbox = try CloudUploadOutboxRecord(
                    repositoryID: repositoryID,
                    descriptor: descriptor,
                    displayName: repositoryName,
                    snapshot: cloudSnapshot,
                    generation: generation,
                    baseRecordChangeTag: baseRecordChangeTag,
                    predecessorOperationIDs:
                        existingOutbox?
                            .successorPredecessorOperationIDs ?? [],
                    mode: uploadMode,
                    encryptedResetAcknowledgement:
                        existingOutbox?
                            .encryptedResetAcknowledgement,
                    createdAt: now()
                )

                try outboxStore.save(outbox)
                didWriteSuccessorOutbox = true
                try CloudUploadOutboxStore(
                    repositoryRootURL: stagedImport.repositoryStore.rootURL
                ).save(outbox)
                successorOutbox = outbox
            }
            try stagedImport.repositoryStore.saveDescriptor(descriptor)

            let importedSnapshot = try repositoryArchiveService
                .installPreparedImport(
                    stagedImport,
                    replacing: repositoryStore
                )
            didInstallPreparedImport = true
            preparedImport = nil

            applySnapshot(importedSnapshot)
            repositoryDescriptor = descriptor
            upsertRepositoryReference(
                repositoryID: repositoryID,
                descriptor: descriptor,
                displayName: repositoryName,
                snapshotUpdatedAt: importedSnapshot.updatedAt,
                markAsOpened: true
            )
            if let successorOutbox {
                markCloudUploadPending(
                    for: repositoryID,
                    snapshotUpdatedAt: successorOutbox.snapshot.updatedAt,
                    generation: successorOutbox.generation,
                    baseRecordChangeTag: successorOutbox.baseRecordChangeTag
                )
            }
            try persistRepositoryCatalog()
            invalidateImageViews()
            transferProgress = nil

            if let successorOutbox,
               repositoryReference(for: repositoryID)?
                .cloudUploadConflictDetectedAt == nil {
                scheduleCloudSync(
                    repositoryID: repositoryID,
                    descriptor: successorOutbox.descriptor,
                    displayName: repositoryName,
                    mutationCount: 1
                )
                didBeginMutation = false
            } else {
                await finishRepositoryMutations(for: repositoryID, count: 1)
                didBeginMutation = false
            }
        } catch {
            if didWriteSuccessorOutbox && !didInstallPreparedImport {
                let outboxStore = cloudUploadOutboxStore(for: repositoryID)
                if let previousOutbox {
                    try? outboxStore.save(previousOutbox)
                } else {
                    try? outboxStore.remove()
                }
            }
            if let preparedImport {
                try? repositoryArchiveService.discardPreparedImport(
                    preparedImport
                )
            }
            if didBeginMutation {
                await finishRepositoryMutations(for: repositoryID, count: 1)
            }
            if didInstallPreparedImport {
                try? reconcileCloudUploadOutboxes()
                await resumePendingCloudSyncs(waitForCompletion: false)
            }
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
        isApplicationActive = phase == .active

        if phase == .active {
            clearApplicationBadge()
        }

        guard hasLoadedPreferences else {
            return
        }

        switch phase {
        case .background:
            guard preferences.isBiometricLockEnabled else {
                isAuthenticationRequired = false
                shouldRequireAuthenticationOnNextActive = false
                return
            }

            guard !isAuthenticating else {
                return
            }

            shouldRequireAuthenticationOnNextActive = true
            isAuthenticationRequired = true
        case .active:
            await resumePendingCloudSyncs()
            await ensureRepositorySubscriptions()

            if preferences.isBiometricLockEnabled {
                if shouldRequireAuthenticationOnNextActive,
                   shouldRefreshSharedRepositoriesOnForeground() {
                    pendingPostUnlockSharedRefreshTrigger = .foreground
                }

                if shouldRequireAuthenticationOnNextActive {
                    isAuthenticationRequired = true
                    await unlockIfNeeded()
                    guard !isAuthenticationRequired else {
                        return
                    }
                }
            } else {
                isAuthenticationRequired = false
                shouldRequireAuthenticationOnNextActive = false
            }

            if preferences.isBiometricLockEnabled, isAuthenticationRequired {
                return
            }

            await refreshSharedRepositoriesIfNeededOnForeground()
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
            try await authenticateBiometricsAction(L10n.string("Unlock thatDay"))
            isAuthenticationRequired = false
            shouldRequireAuthenticationOnNextActive = false
            await runDeferredPostUnlockWorkIfNeeded()
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

    private func cloudUploadOutboxStore(for repositoryID: String) -> CloudUploadOutboxStore {
        CloudUploadOutboxStore(
            repositoryRootURL: libraryStore.repositoryStore(for: repositoryID).rootURL
        )
    }

    private func reconcilePendingCloudPurges() throws {
        let repositoryIDs = Set(
            repositories.compactMap { reference in
                reference.cloudPurgeRequestedAt == nil ? nil : reference.id
            }
        )
        guard !repositoryIDs.isEmpty else {
            return
        }

        try completePurgedRepositoryCleanup(repositoryIDs: repositoryIDs)
    }

    private func reconcileCloudUploadOutboxes() throws {
        var didChangeCatalog = false
        var uploadedOutboxesToRemove: [CloudUploadOutboxStore] = []

        for index in repositories.indices {
            let reference = repositories[index]
            let repositoryStore = libraryStore.repositoryStore(for: reference.id)
            let outboxStore = cloudUploadOutboxStore(for: reference.id)

            if let outbox = try outboxStore.load() {
                guard outbox.repositoryID == reference.id else {
                    throw CloudRepositoryError.invalidRepositoryData
                }

                if let receipt = outbox.receipt {
                    try stageCloudUploadReceiptCommit(
                        outbox,
                        receipt: receipt,
                        repositoryIndex: index
                    )
                    if outbox.mode != .recreateAfterEncryptedDataReset,
                       outbox.encryptedResetAcknowledgement == nil {
                        uploadedOutboxesToRemove.append(outboxStore)
                    }
                } else {
                    try repositoryStore.saveCloudSnapshot(outbox.snapshot)
                    try repositoryStore.saveDescriptor(outbox.descriptor)
                    repositories[index].descriptor = outbox.descriptor
                    repositories[index].lastKnownSnapshotUpdatedAt = outbox.snapshot.updatedAt
                    repositories[index].pendingCloudUploadAt = outbox.createdAt
                    repositories[index].pendingCloudUploadGeneration = outbox.generation
                    repositories[index].pendingCloudUploadBaseChangeTag =
                        outbox.baseRecordChangeTag
                }
                didChangeCatalog = true
                continue
            }

            guard reference.descriptor.isCloudBacked else {
                continue
            }

            guard reference.pendingCloudUploadAt != nil ||
                    reference.pendingCloudUploadGeneration != nil else {
                continue
            }

            guard let localSnapshot = try repositoryStore.loadSnapshot() else {
                continue
            }
            let cloudSnapshot = try repositoryStore.makeSnapshot(
                entries: localSnapshot.entries,
                updatedAt: localSnapshot.updatedAt,
                embeddingImages: true,
                blogTags: localSnapshot.blogTags,
                sharedUpdateNotificationScope: localSnapshot.sharedUpdateNotificationScope
            )
            let migratedOutbox = try CloudUploadOutboxRecord(
                repositoryID: reference.id,
                descriptor: reference.descriptor,
                displayName: reference.displayName,
                snapshot: cloudSnapshot,
                generation: reference.pendingCloudUploadGeneration ?? 1,
                baseRecordChangeTag: reference.pendingCloudUploadBaseChangeTag ??
                    reference.lastKnownServerRecordChangeTag,
                createdAt: reference.pendingCloudUploadAt ?? localSnapshot.updatedAt
            )
            try outboxStore.save(migratedOutbox)
            repositories[index].pendingCloudUploadGeneration = migratedOutbox.generation
            repositories[index].pendingCloudUploadBaseChangeTag =
                migratedOutbox.baseRecordChangeTag
            didChangeCatalog = true
        }

        if didChangeCatalog {
            repositories = sortedRepositories
            try libraryStore.saveCatalog(repositories)
        }
        for outboxStore in uploadedOutboxesToRemove {
            try outboxStore.remove()
        }
    }

    private func stageCloudUploadReceiptCommit(
        _ outbox: CloudUploadOutboxRecord,
        receipt: CloudUploadReceipt,
        repositoryIndex index: Int
    ) throws {
        guard repositories[index].id == outbox.repositoryID,
              repositories[index].pendingCloudUploadGeneration == nil ||
                repositories[index].pendingCloudUploadGeneration ==
                    outbox.generation else {
            throw CloudRepositoryError.invalidRepositoryData
        }

        let repositoryStore = libraryStore.repositoryStore(
            for: outbox.repositoryID
        )
        try repositoryStore.saveCloudSnapshot(outbox.snapshot)
        try repositoryStore.saveDescriptor(receipt.descriptor)
        repositories[index].descriptor = receipt.descriptor
        repositories[index].lastKnownSnapshotUpdatedAt =
            outbox.snapshot.updatedAt
        repositories[index].lastKnownServerRecordChangeTag =
            receipt.recordChangeTag
        repositories[index].lastKnownServerModifiedAt =
            receipt.serverModifiedAt
        repositories[index].pendingCloudUploadAt = nil
        repositories[index].pendingCloudUploadGeneration = nil
        repositories[index].pendingCloudUploadBaseChangeTag = nil
        repositories[index].cloudUploadConflictServerChangeTag = nil
        repositories[index].cloudUploadConflictDetectedAt = nil
        repositories[index].cloudZoneUnavailableAt = nil

        if currentRepositoryID == outbox.repositoryID {
            repositoryDescriptor = receipt.descriptor
        }
    }

    private func applySnapshot(_ snapshot: RepositorySnapshot) {
        let normalizedTags = RepositorySnapshot.normalizedBlogTags(snapshot.blogTags, entries: snapshot.entries)
        blogTags = normalizedTags
        repositorySharedUpdateNotificationScope = snapshot.sharedUpdateNotificationScope
        selectedBlogTag = matchedBlogTag(for: selectedBlogTag, availableTags: normalizedTags)
        entries = normalizedEntries(snapshot.entries, using: normalizedTags)
    }

    private func normalizeRepositoryState() {
        let normalizedTags = RepositorySnapshot.normalizedBlogTags(blogTags, entries: entries)
        blogTags = normalizedTags
        selectedBlogTag = matchedBlogTag(for: selectedBlogTag, availableTags: normalizedTags)
        entries = normalizedEntries(entries, using: normalizedTags)
    }

    private func normalizedEntries(_ entries: [EntryRecord], using blogTags: [String]) -> [EntryRecord] {
        entries.map { entry in
            var normalizedEntry = entry
            if entry.kind == .blog {
                normalizedEntry.blogTag = normalizedBlogTag(for: entry.blogTag, availableTags: blogTags)
            } else {
                normalizedEntry.blogTag = nil
            }
            return normalizedEntry
        }
    }

    private func normalizedBlogTag(for rawTag: String?, availableTags: [String]) -> String {
        guard let tag = rawTag?.trimmed.nilIfEmpty else {
            return Self.defaultBlogTag(in: availableTags)
        }

        if let matchedTag = availableTags.first(where: {
            $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return matchedTag
        }

        return Self.defaultBlogTag(in: availableTags)
    }

    private func matchedBlogTag(for rawTag: String?, availableTags: [String]? = nil) -> String? {
        guard let tag = rawTag?.trimmed.nilIfEmpty else {
            return nil
        }

        let tags = availableTags ?? blogTags
        return tags.first(where: {
            $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
    }

    private func persistCurrentRepositoryMutation(
        previousEntries: [EntryRecord],
        previousBlogTags: [String],
        previousRepositoryNotificationScope: SharedUpdateNotificationScope
    ) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await persistEntries()
        } catch {
            entries = previousEntries
            blogTags = previousBlogTags
            repositorySharedUpdateNotificationScope = previousRepositoryNotificationScope
            alertMessage = Self.userFacingMessage(for: error)
        }
    }

    private func updateBlogTags(_ updatedBlogTags: [String]) async {
        guard updatedBlogTags != blogTags else {
            return
        }

        let previousEntries = entries
        let previousBlogTags = blogTags
        blogTags = updatedBlogTags
        await persistCurrentRepositoryMutation(
            previousEntries: previousEntries,
            previousBlogTags: previousBlogTags,
            previousRepositoryNotificationScope: repositorySharedUpdateNotificationScope
        )
    }

    private func beginRepositoryMutation(for repositoryID: String) {
        repositoryMutationGenerations[repositoryID, default: 0] += 1
        repositoryMutationInFlightCounts[repositoryID, default: 0] += 1
    }

    private func finishRepositoryMutation(for repositoryID: String) -> RepositoryReference? {
        let remainingMutations = max(0, (repositoryMutationInFlightCounts[repositoryID] ?? 0) - 1)
        if remainingMutations == 0 {
            repositoryMutationInFlightCounts.removeValue(forKey: repositoryID)
        } else {
            repositoryMutationInFlightCounts[repositoryID] = remainingMutations
        }

        guard remainingMutations == 0,
              repositoriesPendingRefreshAfterMutation.remove(repositoryID) != nil else {
            return nil
        }

        return repositoryReference(for: repositoryID)
    }

    private func repositoryMutationGeneration(for repositoryID: String) -> Int {
        repositoryMutationGenerations[repositoryID] ?? 0
    }

    private func isRepositoryMutationInFlight(_ repositoryID: String) -> Bool {
        (repositoryMutationInFlightCounts[repositoryID] ?? 0) > 0
    }

    private func applyAcceptedShare(_ accepted: AcceptedSharedRepository) throws {
        let repositoryID = accepted.descriptor.storageIdentifier
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        try repositoryStore.saveDescriptor(accepted.descriptor)
        try repositoryStore.saveCloudSnapshot(accepted.snapshot)
        invalidateImageViews()

        upsertRepositoryReference(
            repositoryID: repositoryID,
            descriptor: accepted.descriptor,
            displayName: accepted.displayName ?? accepted.descriptor.defaultDisplayName,
            snapshotUpdatedAt: accepted.snapshot.updatedAt
        )
        if let index = repositories.firstIndex(where: { $0.id == repositoryID }) {
            repositories[index].cloudZoneUnavailableAt = nil
            repositories[index].lastKnownServerModifiedAt = accepted.serverModifiedAt
            repositories[index].lastKnownServerRecordChangeTag = accepted.recordChangeTag
        }
        try persistRepositoryCatalog()
    }

    private func loadRepository(
        repositoryID: String,
        behavior: RepositoryLoadBehavior
    ) async throws {
        let fallbackRepositoryID = repositories.contains(where: { $0.id == repositoryID })
            ? repositoryID
            : RepositoryReference.localRepositoryID
        currentRepositoryID = fallbackRepositoryID

        let repositoryStore = currentRepositoryStore
        let reference = repositoryReference(for: currentRepositoryID)
        repositoryDescriptor = try repositoryStore.loadDescriptor() ?? reference?.descriptor ?? .local
        let hasLocalSnapshot = try repositoryStore.loadSnapshot()

        if let snapshot = hasLocalSnapshot {
            applySnapshot(snapshot)
            upsertRepositoryReference(
                repositoryID: currentRepositoryID,
                descriptor: repositoryDescriptor,
                displayName: reference?.displayName ?? repositoryDescriptor.defaultDisplayName,
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
        } else if currentRepositoryID == RepositoryReference.localRepositoryID {
            entries = []
            blogTags = RepositorySnapshot.defaultBlogTags
            repositorySharedUpdateNotificationScope = .all
            let snapshot = RepositorySnapshot(
                entries: entries,
                updatedAt: now(),
                blogTags: blogTags,
                sharedUpdateNotificationScope: repositorySharedUpdateNotificationScope
            )
            try repositoryStore.saveDescriptor(.local)
            try repositoryStore.saveSnapshot(snapshot)
            repositoryDescriptor = .local
            upsertRepositoryReference(
                repositoryID: currentRepositoryID,
                descriptor: .local,
                displayName: "My Repository",
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
        } else {
            entries = []
            blogTags = RepositorySnapshot.defaultBlogTags
            repositorySharedUpdateNotificationScope = .all
            if let reference {
                upsertRepositoryReference(
                    repositoryID: currentRepositoryID,
                    descriptor: repositoryDescriptor,
                    displayName: reference.displayName,
                    snapshotUpdatedAt: reference.lastKnownSnapshotUpdatedAt,
                    markAsOpened: true
                )
            }
        }

        if repositoryDescriptor.isCloudBacked,
           behavior == .blockingCloudFetchIfNoLocalSnapshot,
           hasLocalSnapshot == nil,
           let reference {
            try await refreshRepository(reference, trigger: .foreground)
        }

        try persistRepositoryCatalog()
    }

    private func persistEntries(pruningUnreferencedImages: Bool = true) async throws {
        let repositoryID = currentRepositoryID
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let repositoryName = currentRepositoryName
        let descriptorAtStart = repositoryDescriptor
        let outboxStore = cloudUploadOutboxStore(for: repositoryID)

        beginRepositoryMutation(for: repositoryID)

        do {
            let existingOutbox = try outboxStore.load()
            let isPendingLocalShare =
                descriptorAtStart.role == .local &&
                existingOutbox?.mode == .prepareShare &&
                existingOutbox?.receipt == nil
            let shouldCreateCloudOutbox =
                descriptorAtStart.role != .local || isPendingLocalShare

            normalizeRepositoryState()
            let snapshot = RepositorySnapshot(
                entries: entries,
                updatedAt: now(),
                blogTags: blogTags,
                sharedUpdateNotificationScope: repositorySharedUpdateNotificationScope
            )

            if shouldCreateCloudOutbox {
                let cloudSnapshot = try repositoryStore.makeSnapshot(
                    entries: snapshot.entries,
                    updatedAt: snapshot.updatedAt,
                    embeddingImages: true,
                    blogTags: snapshot.blogTags,
                    sharedUpdateNotificationScope: snapshot.sharedUpdateNotificationScope
                )
                let currentReference = repositoryReference(for: repositoryID)
                let generation = max(
                    currentReference?.pendingCloudUploadGeneration ?? 0,
                    existingOutbox?.generation ?? 0
                ) &+ 1
                let uploadMode = existingOutbox?.receipt == nil
                    ? existingOutbox?.mode ?? .normal
                    : .normal
                let baseRecordChangeTag = uploadMode == .recreateAfterEncryptedDataReset
                    ? nil
                    : existingOutbox?.receipt?.recordChangeTag ??
                        existingOutbox?.baseRecordChangeTag ??
                        currentReference?.pendingCloudUploadBaseChangeTag ??
                        currentReference?.lastKnownServerRecordChangeTag
                let outbox = try CloudUploadOutboxRecord(
                    repositoryID: repositoryID,
                    descriptor: descriptorAtStart,
                    displayName: repositoryName,
                    snapshot: cloudSnapshot,
                    generation: generation,
                    baseRecordChangeTag: baseRecordChangeTag,
                    predecessorOperationIDs:
                        existingOutbox?
                            .successorPredecessorOperationIDs ?? [],
                    mode: uploadMode,
                    encryptedResetAcknowledgement:
                        existingOutbox?
                            .encryptedResetAcknowledgement,
                    createdAt: now()
                )
                try outboxStore.save(outbox)

                upsertRepositoryReference(
                    repositoryID: repositoryID,
                    descriptor: descriptorAtStart,
                    displayName: repositoryName,
                    snapshotUpdatedAt: snapshot.updatedAt,
                    markAsOpened: true
                )
                markCloudUploadPending(
                    for: repositoryID,
                    snapshotUpdatedAt: snapshot.updatedAt,
                    generation: generation,
                    baseRecordChangeTag: baseRecordChangeTag
                )
                try persistRepositoryCatalog()
            }

            try repositoryStore.saveSnapshot(
                snapshot,
                pruningUnreferencedImages: pruningUnreferencedImages
            )

            if descriptorAtStart.role != .local {
                try repositoryStore.saveDescriptor(descriptorAtStart)
            } else {
                try repositoryStore.saveDescriptor(.local)
            }

            if currentRepositoryID == repositoryID {
                repositoryDescriptor = descriptorAtStart.role == .local ? .local : descriptorAtStart
            }

            upsertRepositoryReference(
                repositoryID: repositoryID,
                descriptor: descriptorAtStart.role == .local ? .local : descriptorAtStart,
                displayName: repositoryName,
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
            try persistRepositoryCatalog()

            if shouldCreateCloudOutbox {
                if repositoryReference(for: repositoryID)?
                    .cloudUploadConflictDetectedAt == nil {
                    scheduleCloudSync(
                        repositoryID: repositoryID,
                        descriptor: descriptorAtStart,
                        displayName: repositoryName
                    )
                } else {
                    await finishRepositoryMutations(for: repositoryID, count: 1)
                }
            } else {
                await finishRepositoryMutations(for: repositoryID, count: 1)
            }
        } catch {
            await finishRepositoryMutations(for: repositoryID, count: 1)
            throw error
        }
    }

    private func scheduleCloudSync(
        repositoryID: String,
        descriptor: RepositoryDescriptor,
        displayName: String,
        mutationCount: Int = 1
    ) {
        if var pendingSync = pendingRepositoryCloudSyncs[repositoryID] {
            pendingSync.descriptor = descriptor
            pendingSync.displayName = displayName
            pendingSync.mutationCount += mutationCount
            pendingRepositoryCloudSyncs[repositoryID] = pendingSync
        } else {
            pendingRepositoryCloudSyncs[repositoryID] = PendingRepositoryCloudSync(
                descriptor: descriptor,
                displayName: displayName,
                mutationCount: mutationCount
            )
        }

        guard repositoryCloudSyncTasks[repositoryID] == nil else {
            return
        }

        repositoryCloudSyncTasks[repositoryID] = Task { [weak self] in
            await self?.runPendingCloudSyncs(for: repositoryID)
        }
    }

    private func runPendingCloudSyncs(for repositoryID: String) async {
        let backgroundTask = ApplicationBackgroundTaskLease(
            name: "Upload shared repository \(repositoryID)"
        )
        defer { backgroundTask.end() }

        while !Task.isCancelled {
            guard let pendingSync = pendingRepositoryCloudSyncs
                .removeValue(forKey: repositoryID) else {
                break
            }
            await uploadPendingCloudSync(pendingSync, repositoryID: repositoryID)
            await finishRepositoryMutations(for: repositoryID, count: pendingSync.mutationCount)
        }

        repositoryCloudSyncTasks[repositoryID] = nil
    }

    private func quiesceRepositoryCloudSync(
        for repositoryID: String
    ) async {
        while let task = repositoryCloudSyncTasks[repositoryID] {
            task.cancel()
            await task.value
        }
        repositoryCloudSyncTasks.removeValue(forKey: repositoryID)

        if let queuedSync = pendingRepositoryCloudSyncs
            .removeValue(forKey: repositoryID) {
            if queuedSync.mutationCount > 0 {
                await finishRepositoryMutations(
                    for: repositoryID,
                    count: queuedSync.mutationCount
                )
            }
        }
    }

    private func uploadPendingCloudSync(
        _ pendingSync: PendingRepositoryCloudSync,
        repositoryID: String
    ) async {
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let outboxStore = cloudUploadOutboxStore(for: repositoryID)

        do {
            guard activeSharedCloudThrottleUntil() == nil else {
                return
            }

            guard let outbox = try outboxStore.load(),
                  outbox.receipt == nil,
                  !Task.isCancelled else {
                return
            }

            let saveResult: SavedRepositorySnapshot
            switch outbox.mode {
            case .normal, .prepareShare:
                saveResult = try await cloudService.saveSnapshot(
                    outbox.snapshot,
                    using: outbox.descriptor,
                    expectedRecordChangeTag: outbox.baseRecordChangeTag,
                    acceptedPredecessorOperationIDs: Set(
                        outbox.predecessorOperationIDs
                    )
                )
            case .recreateAfterEncryptedDataReset:
                saveResult = try await cloudService.recreateSnapshotAfterEncryptedDataReset(
                    outbox.snapshot,
                    using: outbox.descriptor,
                    acceptedPredecessorOperationIDs: Set(
                        outbox.predecessorOperationIDs
                    )
                )
            }
            guard !Task.isCancelled else {
                return
            }
            let savedDescriptor = saveResult.descriptor

            var latestOutbox = try outboxStore.load()
            var shouldRemoveUploadedOutbox = false
            if latestOutbox?.generation == outbox.generation {
                latestOutbox?.markUploaded(
                    descriptor: savedDescriptor,
                    serverModifiedAt: saveResult.serverModifiedAt,
                    recordChangeTag: saveResult.recordChangeTag,
                    uploadedAt: now()
                )
                if let latestOutbox {
                    try outboxStore.save(latestOutbox)
                }
                shouldRemoveUploadedOutbox =
                    outbox.mode != .recreateAfterEncryptedDataReset &&
                    latestOutbox?
                        .encryptedResetAcknowledgement == nil
            } else if var latestOutbox {
                if latestOutbox.encryptedResetAcknowledgement == nil {
                    latestOutbox.encryptedResetAcknowledgement =
                        outbox.encryptedResetAcknowledgement
                }
                let carriesEncryptedResetAcknowledgement =
                    outbox.mode ==
                        .recreateAfterEncryptedDataReset ||
                    outbox.encryptedResetAcknowledgement != nil ||
                    latestOutbox
                        .encryptedResetAcknowledgement != nil
                if carriesEncryptedResetAcknowledgement {
                    latestOutbox.recordEncryptedResetAcknowledgement(
                        operationID: outbox.operationID,
                        receipt: CloudUploadReceipt(
                            descriptor: savedDescriptor,
                            serverModifiedAt:
                                saveResult.serverModifiedAt,
                            recordChangeTag:
                                saveResult.recordChangeTag,
                            uploadedAt: now()
                        )
                    )
                }
                latestOutbox.advanceBaseRecordChangeTag(
                    saveResult.recordChangeTag,
                    retainingPredecessorOperationIDs:
                        carriesEncryptedResetAcknowledgement
                            ? [outbox.operationID]
                            : []
                )
                latestOutbox.mode = .normal
                latestOutbox.descriptor = savedDescriptor
                try outboxStore.save(latestOutbox)
            }

            try repositoryStore.saveDescriptor(savedDescriptor)

            if currentRepositoryID == repositoryID {
                repositoryDescriptor = savedDescriptor
            }

            upsertRepositoryReference(
                repositoryID: repositoryID,
                descriptor: savedDescriptor,
                displayName: pendingSync.displayName,
                snapshotUpdatedAt: outbox.snapshot.updatedAt,
                markAsOpened: true
            )
            updateRemoteMetadata(
                for: repositoryID,
                serverModifiedAt: saveResult.serverModifiedAt,
                recordChangeTag: saveResult.recordChangeTag
            )
            completeCloudUpload(
                for: repositoryID,
                expectedGeneration: outbox.generation,
                savedRecordChangeTag: saveResult.recordChangeTag
            )
            try persistRepositoryCatalog()
            if shouldRemoveUploadedOutbox,
               try outboxStore.load()?.generation == outbox.generation {
                try outboxStore.remove()
            }
            await ensureRepositorySubscriptions()
        } catch CloudRepositoryError.repositoryConflict(let serverRecordChangeTag) {
            markCloudUploadConflict(
                for: repositoryID,
                serverRecordChangeTag: serverRecordChangeTag
            )
            try? persistRepositoryCatalog()
            alertMessage = Self.userFacingMessage(
                for: CloudRepositoryError.repositoryConflict(
                    serverRecordChangeTag: serverRecordChangeTag
                )
            )
        } catch {
            _ = recordSharedCloudThrottleIfNeeded(for: error)
        }
    }

    private func resumePendingCloudSyncs(waitForCompletion: Bool = true) async {
        let pendingReferences = repositories.filter {
            ($0.pendingCloudUploadAt != nil || $0.pendingCloudUploadGeneration != nil) &&
                ($0.descriptor.isCloudBacked ||
                 (try? cloudUploadOutboxStore(for: $0.id).load())?.mode == .prepareShare) &&
                $0.cloudUploadConflictDetectedAt == nil &&
                $0.cloudZoneUnavailableAt == nil &&
                $0.cloudPurgeRequestedAt == nil
        }
        guard !pendingReferences.isEmpty else {
            return
        }

        for reference in pendingReferences {
            scheduleCloudSync(
                repositoryID: reference.id,
                descriptor: reference.descriptor,
                displayName: reference.displayName,
                mutationCount: 0
            )
        }

        guard waitForCompletion else {
            return
        }

        let tasks = pendingReferences.compactMap { repositoryCloudSyncTasks[$0.id] }
        for task in tasks {
            await task.value
        }
    }

    private func markCloudUploadPending(
        for repositoryID: String,
        snapshotUpdatedAt: Date,
        generation: Int,
        baseRecordChangeTag: String?
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        let existingPendingDate = repositories[index].pendingCloudUploadAt ?? .distantPast
        repositories[index].pendingCloudUploadAt = max(existingPendingDate, snapshotUpdatedAt)
        repositories[index].pendingCloudUploadGeneration = generation
        repositories[index].pendingCloudUploadBaseChangeTag = baseRecordChangeTag
    }

    private func completeCloudUpload(
        for repositoryID: String,
        expectedGeneration: Int?,
        savedRecordChangeTag: String?
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        guard repositories[index].pendingCloudUploadGeneration == expectedGeneration else {
            if repositories[index].pendingCloudUploadGeneration != nil,
               let savedRecordChangeTag {
                repositories[index].pendingCloudUploadBaseChangeTag =
                    savedRecordChangeTag
            }
            return
        }

        repositories[index].pendingCloudUploadAt = nil
        repositories[index].pendingCloudUploadGeneration = nil
        repositories[index].pendingCloudUploadBaseChangeTag = nil
        repositories[index].cloudUploadConflictServerChangeTag = nil
        repositories[index].cloudUploadConflictDetectedAt = nil
    }

    private func markCloudUploadConflict(
        for repositoryID: String,
        serverRecordChangeTag: String?
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        repositories[index].cloudUploadConflictServerChangeTag =
            serverRecordChangeTag
        repositories[index].cloudUploadConflictDetectedAt = now()
    }

    private func finishRepositoryMutations(for repositoryID: String, count: Int) async {
        var deferredRefreshReference: RepositoryReference?

        for _ in 0..<count {
            if let reference = finishRepositoryMutation(for: repositoryID) {
                deferredRefreshReference = reference
            }
        }

        if count == 0,
           repositoriesPendingRefreshAfterMutation.remove(repositoryID) != nil {
            deferredRefreshReference = repositoryReference(for: repositoryID)
        }

        if let deferredRefreshReference,
           activeSharedCloudThrottleUntil() == nil {
            do {
                try await refreshRepository(deferredRefreshReference, trigger: .foreground)
            } catch {
                _ = recordSharedCloudThrottleIfNeeded(for: error)
            }
        }
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
            displayName: source == .local ? "My Repository" : normalizedName,
            descriptor: descriptor,
            source: source,
            lastKnownSnapshotUpdatedAt: snapshotUpdatedAt,
            subscribedAt: existing?.subscribedAt ?? now(),
            lastOpenedAt: markAsOpened ? now() : existing?.lastOpenedAt,
            lastKnownServerRecordChangeTag: existing?.lastKnownServerRecordChangeTag,
            lastKnownServerModifiedAt: existing?.lastKnownServerModifiedAt,
            pendingCloudUploadAt: existing?.pendingCloudUploadAt,
            pendingCloudUploadGeneration: existing?.pendingCloudUploadGeneration,
            pendingCloudUploadBaseChangeTag: existing?.pendingCloudUploadBaseChangeTag,
            cloudUploadConflictServerChangeTag: existing?.cloudUploadConflictServerChangeTag,
            cloudUploadConflictDetectedAt: existing?.cloudUploadConflictDetectedAt,
            cloudZoneUnavailableAt: existing?.cloudZoneUnavailableAt,
            cloudPurgeRequestedAt: existing?.cloudPurgeRequestedAt,
            subscriptionConfigurationVersion: existing?.subscriptionConfigurationVersion,
            subscriptionValidatedAt: existing?.subscriptionValidatedAt
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

    private func sharedRepositoryRefreshSelection(
        for trigger: SharedRepositoryRefreshTrigger,
        target: CloudRemoteNotificationTarget?
    ) async throws -> SharedRepositoryRefreshSelection {
        if trigger == .manual {
            guard let currentRepositoryReference,
                  currentRepositoryReference.descriptor.isCloudBacked else {
                return SharedRepositoryRefreshSelection(
                    references: [],
                    databaseScope: nil,
                    changedZoneIDs: [],
                    deletedZones: []
                )
            }

            guard currentRepositoryReference.cloudZoneUnavailableAt == nil else {
                alertMessage = L10n.string(
                    "The shared repository is no longer available in iCloud. Its cached content is kept read-only on this device."
                )
                return SharedRepositoryRefreshSelection(
                    references: [],
                    databaseScope: nil,
                    changedZoneIDs: [],
                    deletedZones: []
                )
            }

            return SharedRepositoryRefreshSelection(
                references: [currentRepositoryReference],
                databaseScope: nil,
                changedZoneIDs: [],
                deletedZones: []
            )
        }

        let cloudReferences = sortedRepositories.filter {
            $0.descriptor.isCloudBacked &&
                $0.cloudZoneUnavailableAt == nil
        }
        guard let target else {
            return SharedRepositoryRefreshSelection(
                references: cloudReferences,
                databaseScope: nil,
                changedZoneIDs: [],
                deletedZones: []
            )
        }

        switch target {
        case let .zone(ownerName, zoneName):
            return SharedRepositoryRefreshSelection(
                references: cloudReferences.filter {
                    $0.descriptor.zoneOwnerName == ownerName &&
                        $0.descriptor.zoneName == zoneName
                },
                databaseScope: nil,
                changedZoneIDs: [],
                deletedZones: []
            )
        case let .database(scope):
            let databaseChanges = try await cloudService.pendingRepositoryZoneChanges(
                in: scope
            )
            let changedZones = databaseChanges.modifiedZoneIDs
            let references = cloudReferences.filter { reference in
                    let descriptor = reference.descriptor
                    let isMatchingDatabase: Bool
                    switch scope {
                    case .privateDatabase:
                        isMatchingDatabase = descriptor.role == .owner
                    case .sharedDatabase:
                        isMatchingDatabase = descriptor.role == .editor || descriptor.role == .viewer
                    }

                    guard isMatchingDatabase,
                          let zoneID = cloudZoneIdentity(for: reference) else {
                        return false
                    }

                    return changedZones.contains(zoneID)
                }
            return SharedRepositoryRefreshSelection(
                references: references,
                databaseScope: scope,
                changedZoneIDs: changedZones,
                deletedZones: databaseChanges.deletedZones
            )
        }
    }

    private func cloudZoneIdentity(
        for reference: RepositoryReference
    ) -> CloudRepositoryZoneIdentity? {
        guard let ownerName = reference.descriptor.zoneOwnerName,
              let zoneName = reference.descriptor.zoneName else {
            return nil
        }

        return CloudRepositoryZoneIdentity(ownerName: ownerName, zoneName: zoneName)
    }

    private func handleRepositoryZoneDeletion(
        _ deletion: CloudRepositoryZoneDeletion,
        databaseScope: CloudDatabaseScope?
    ) async throws -> (checkedCount: Int, updatedCount: Int) {
        switch deletion.reason {
        case .deleted:
            return try await markRepositoryZonesUnavailable([deletion.zoneID])
        case .purged:
            return try await purgeRepositoryZone(deletion.zoneID)
        case .encryptedDataReset:
            let ownerReferences = repositories.filter {
                $0.descriptor.role == .owner &&
                    cloudZoneIdentity(for: $0) == deletion.zoneID
            }
            guard databaseScope == .privateDatabase,
                  !ownerReferences.isEmpty else {
                return try await markRepositoryZonesUnavailable([deletion.zoneID])
            }

            var updatedCount = 0
            for reference in ownerReferences {
                try await recreateRepositoryAfterEncryptedDataReset(reference)
                updatedCount += 1
            }
            return (ownerReferences.count, updatedCount)
        }
    }

    private func markEncryptedResetAcknowledgementsAttempted(
        _ deletions: Set<CloudRepositoryZoneDeletion>
    ) throws {
        let recoveredZoneIDs = Set(
            deletions.compactMap { deletion in
                deletion.reason == .encryptedDataReset
                    ? deletion.zoneID
                    : nil
            }
        )
        guard !recoveredZoneIDs.isEmpty else {
            return
        }

        for reference in repositories {
            guard let zoneID = cloudZoneIdentity(for: reference),
                  recoveredZoneIDs.contains(zoneID),
                  reference.descriptor.role == .owner else {
                continue
            }

            let outboxStore = cloudUploadOutboxStore(for: reference.id)
            guard var outbox = try outboxStore.load(),
                  outbox.encryptedResetAcknowledgement != nil else {
                throw CloudRepositoryError.invalidRepositoryData
            }
            outbox.markEncryptedResetAcknowledgementAttempted(at: now())
            try outboxStore.save(outbox)
        }
    }

    private func commitEncryptedResetAcknowledgementReceipts(
        _ deletions: Set<CloudRepositoryZoneDeletion>
    ) throws {
        let recoveredZoneIDs = Set(
            deletions.compactMap { deletion in
                deletion.reason == .encryptedDataReset
                    ? deletion.zoneID
                    : nil
            }
        )
        guard !recoveredZoneIDs.isEmpty else {
            return
        }

        var didStageReceiptCommit = false
        for reference in repositories {
            guard let zoneID = cloudZoneIdentity(for: reference),
                  recoveredZoneIDs.contains(zoneID),
                  reference.descriptor.role == .owner else {
                continue
            }

            guard let outbox = try cloudUploadOutboxStore(
                for: reference.id
            ).load(),
                  let receipt = outbox.receipt,
                  let acknowledgement =
                    outbox.encryptedResetAcknowledgement,
                  acknowledgement.operationID ==
                    outbox.operationID,
                  acknowledgement.receipt == receipt,
                  let index = repositories.firstIndex(where: {
                      $0.id == reference.id
                  }) else {
                throw CloudRepositoryError.invalidRepositoryData
            }
            try stageCloudUploadReceiptCommit(
                outbox,
                receipt: receipt,
                repositoryIndex: index
            )
            didStageReceiptCommit = true
        }
        if didStageReceiptCommit {
            try persistRepositoryCatalog()
        }
    }

    private func completeEncryptedResetAcknowledgements(
        _ deletions: Set<CloudRepositoryZoneDeletion>
    ) throws {
        try completeEncryptedResetAcknowledgements(
            for: Set(
                deletions.compactMap { deletion in
                    deletion.reason == .encryptedDataReset
                        ? deletion.zoneID
                        : nil
                }
            )
        )
    }

    private func completeEncryptedResetAcknowledgements(
        for recoveredZoneIDs: Set<CloudRepositoryZoneIdentity>
    ) throws {
        guard !recoveredZoneIDs.isEmpty else {
            return
        }

        for reference in repositories {
            guard let zoneID = cloudZoneIdentity(for: reference),
                  recoveredZoneIDs.contains(zoneID),
                  reference.descriptor.role == .owner else {
                continue
            }

            let outboxStore = cloudUploadOutboxStore(for: reference.id)
            guard var outbox = try outboxStore.load(),
                  outbox.encryptedResetAcknowledgement != nil else {
                continue
            }
            if outbox.receipt != nil {
                try outboxStore.remove()
            } else {
                outbox.clearEncryptedResetAcknowledgement()
                try outboxStore.save(outbox)
            }
        }
    }

    private func reconcileAttemptedEncryptedResetAcknowledgements()
        async {
        guard activeSharedCloudThrottleUntil() == nil else {
            return
        }

        do {
            let attemptedZoneIDs =
                try encryptedResetAcknowledgementAttemptedZoneIDs()
            guard !attemptedZoneIDs.isEmpty else {
                return
            }
            let changes =
                try await cloudService.pendingRepositoryZoneChanges(
                    in: .privateDatabase
                )
            try completeAttemptedEncryptedResetAcknowledgements(
                notPendingIn: changes.deletedZones
            )
        } catch {
            _ = recordSharedCloudThrottleIfNeeded(for: error)
        }
    }

    private func completeAttemptedEncryptedResetAcknowledgements(
        notPendingIn deletions: Set<CloudRepositoryZoneDeletion>
    ) throws {
        let pendingResetZoneIDs = Set(
            deletions.compactMap { deletion in
                deletion.reason == .encryptedDataReset
                    ? deletion.zoneID
                    : nil
            }
        )
        let completedZoneIDs =
            try encryptedResetAcknowledgementAttemptedZoneIDs()
                .subtracting(pendingResetZoneIDs)
        try completeEncryptedResetAcknowledgements(
            for: completedZoneIDs
        )
    }

    private func encryptedResetAcknowledgementAttemptedZoneIDs()
        throws -> Set<CloudRepositoryZoneIdentity> {
        var zoneIDs: Set<CloudRepositoryZoneIdentity> = []
        for reference in repositories {
            guard reference.descriptor.role == .owner,
                  let zoneID = cloudZoneIdentity(for: reference),
                  let outbox = try cloudUploadOutboxStore(
                    for: reference.id
                  ).load(),
                  outbox.encryptedResetAcknowledgement?
                    .attemptedAt != nil else {
                continue
            }
            zoneIDs.insert(zoneID)
        }
        return zoneIDs
    }

    private func markRepositoryZonesUnavailable(
        _ zoneIDs: Set<CloudRepositoryZoneIdentity>
    ) async throws -> (checkedCount: Int, updatedCount: Int) {
        var checkedCount = 0
        var updatedCount = 0
        var didChangeCatalog = false
        var didAffectCurrentRepository = false
        var affectedRepositoryIDs: [String] = []

        for index in repositories.indices {
            guard let zoneID = cloudZoneIdentity(for: repositories[index]),
                  zoneIDs.contains(zoneID) else {
                continue
            }

            checkedCount += 1
            let repositoryID = repositories[index].id
            if repositories[index].cloudZoneUnavailableAt == nil {
                repositories[index].cloudZoneUnavailableAt = now()
                updatedCount += 1
                didChangeCatalog = true
            }
            affectedRepositoryIDs.append(repositoryID)
            if repositoryID == currentRepositoryID {
                didAffectCurrentRepository = true
            }
        }

        if didChangeCatalog {
            try persistRepositoryCatalog()
        }
        for repositoryID in affectedRepositoryIDs {
            repositoriesPendingRefreshAfterMutation.remove(repositoryID)
            await quiesceRepositoryCloudSync(for: repositoryID)
        }
        if didAffectCurrentRepository {
            alertMessage = L10n.string(
                "The shared repository is no longer available in iCloud. Its cached content is kept read-only on this device."
            )
        }
        return (checkedCount, updatedCount)
    }

    private func purgeRepositoryZone(
        _ zoneID: CloudRepositoryZoneIdentity
    ) async throws -> (checkedCount: Int, updatedCount: Int) {
        let matchingReferences = repositories.filter {
            cloudZoneIdentity(for: $0) == zoneID
        }
        guard !matchingReferences.isEmpty else {
            return (0, 0)
        }

        let affectedRepositoryIDs = Set(matchingReferences.map(\.id))
        let purgeRequestedAt = now()
        for index in repositories.indices
        where affectedRepositoryIDs.contains(repositories[index].id) {
            repositories[index].cloudPurgeRequestedAt =
                repositories[index].cloudPurgeRequestedAt ?? purgeRequestedAt
        }
        // Persist the upload-blocking tombstone before deleting any recoverable
        // state. Startup reconciliation completes this cleanup idempotently.
        try persistRepositoryCatalog()

        let tasksToCancel = affectedRepositoryIDs.compactMap {
            repositoryCloudSyncTasks[$0]
        }
        for task in tasksToCancel {
            task.cancel()
        }
        for task in tasksToCancel {
            await task.value
        }

        for repositoryID in affectedRepositoryIDs {
            pendingRepositoryCloudSyncs.removeValue(forKey: repositoryID)
            repositoryCloudSyncTasks.removeValue(forKey: repositoryID)
            repositoriesPendingRefreshAfterMutation.remove(repositoryID)
            repositoryMutationInFlightCounts.removeValue(forKey: repositoryID)
        }

        try completePurgedRepositoryCleanup(
            repositoryIDs: affectedRepositoryIDs
        )

        if affectedRepositoryIDs.contains(currentRepositoryID) {
            try await loadRepository(
                repositoryID: RepositoryReference.localRepositoryID,
                behavior: .localCacheOnly
            )
            alertMessage = L10n.string(
                "This iCloud repository was purged. Its local cached data was deleted as requested by iCloud."
            )
        }

        return (matchingReferences.count, matchingReferences.count)
    }

    private func completePurgedRepositoryCleanup(
        repositoryIDs: Set<String>
    ) throws {
        guard !repositoryIDs.isEmpty else {
            return
        }

        for repositoryID in repositoryIDs {
            try cloudUploadOutboxStore(for: repositoryID).remove()
        }

        if repositoryIDs.contains(RepositoryReference.localRepositoryID) {
            let localStore = libraryStore.repositoryStore(
                for: RepositoryReference.localRepositoryID
            )
            try localStore.resetContents()
            if let localIndex = repositories.firstIndex(where: {
                $0.id == RepositoryReference.localRepositoryID
            }) {
                repositories[localIndex] = .local
            }
        }

        let removedSharedRepositoryIDs = repositoryIDs.subtracting([
            RepositoryReference.localRepositoryID
        ])
        for repositoryID in removedSharedRepositoryIDs {
            try libraryStore.removeRepositoryDirectory(repositoryID: repositoryID)
        }
        repositories.removeAll {
            removedSharedRepositoryIDs.contains($0.id)
        }

        if removedSharedRepositoryIDs.contains(preferences.defaultRepositoryID) {
            preferences.defaultRepositoryID = RepositoryReference.localRepositoryID
            try libraryStore.savePreferences(preferences)
        }
        try persistRepositoryCatalog()
    }

    private func recreateRepositoryAfterEncryptedDataReset(
        _ reference: RepositoryReference
    ) async throws {
        let outboxStore = cloudUploadOutboxStore(for: reference.id)

        repositoriesPendingRefreshAfterMutation.remove(reference.id)
        await quiesceRepositoryCloudSync(for: reference.id)

        let repositoryStore = libraryStore.repositoryStore(for: reference.id)
        let existingOutbox = try outboxStore.load()
        let recoveryOutbox: CloudUploadOutboxRecord
        if var existingOutbox,
           existingOutbox.mode == .recreateAfterEncryptedDataReset ||
            existingOutbox.encryptedResetAcknowledgement != nil {
            existingOutbox.receipt = nil
            existingOutbox.baseRecordChangeTag = nil
            existingOutbox.descriptor = reference.descriptor
            existingOutbox.mode = .recreateAfterEncryptedDataReset
            try outboxStore.save(existingOutbox)
            recoveryOutbox = existingOutbox
        } else {
            let cloudSnapshot: RepositorySnapshot
            if let existingOutbox {
                cloudSnapshot = existingOutbox.snapshot
            } else if let localSnapshot = try repositoryStore.loadSnapshot() {
                cloudSnapshot = try repositoryStore.makeSnapshot(
                    entries: localSnapshot.entries,
                    updatedAt: localSnapshot.updatedAt,
                    embeddingImages: true,
                    blogTags: localSnapshot.blogTags,
                    sharedUpdateNotificationScope: localSnapshot.sharedUpdateNotificationScope
                )
            } else {
                throw CloudRepositoryError.invalidRepositoryData
            }

            let generation = max(
                existingOutbox?.generation ?? 0,
                reference.pendingCloudUploadGeneration ?? 0
            ) &+ 1
            recoveryOutbox = try CloudUploadOutboxRecord(
                repositoryID: reference.id,
                descriptor: reference.descriptor,
                displayName: reference.displayName,
                snapshot: cloudSnapshot,
                generation: generation,
                baseRecordChangeTag: nil,
                predecessorOperationIDs: existingOutbox.map {
                    [$0.operationID] + $0.predecessorOperationIDs
                } ?? [],
                mode: .recreateAfterEncryptedDataReset,
                createdAt: now()
            )
            try outboxStore.save(recoveryOutbox)
        }

        if let index = repositories.firstIndex(where: { $0.id == reference.id }) {
            repositories[index].pendingCloudUploadAt = recoveryOutbox.createdAt
            repositories[index].pendingCloudUploadGeneration =
                recoveryOutbox.generation
            repositories[index].pendingCloudUploadBaseChangeTag = nil
            repositories[index].cloudUploadConflictDetectedAt = nil
            repositories[index].cloudUploadConflictServerChangeTag = nil
        }
        try persistRepositoryCatalog()

        scheduleCloudSync(
            repositoryID: reference.id,
            descriptor: recoveryOutbox.descriptor,
            displayName: recoveryOutbox.displayName,
            mutationCount: 0
        )
        if let task = repositoryCloudSyncTasks[reference.id] {
            await task.value
        }

        if let remainingOutbox = try outboxStore.load() {
            guard remainingOutbox.receipt != nil else {
                throw CloudRepositoryError.shareUnavailable
            }
            return
        }

        guard repositoryReference(for: reference.id)?
            .pendingCloudUploadGeneration == nil else {
            throw CloudRepositoryError.shareUnavailable
        }
    }

    private func activeSharedCloudThrottleUntil() -> Date? {
        guard let sharedCloudThrottleUntil else {
            return nil
        }

        if sharedCloudThrottleUntil > now() {
            return sharedCloudThrottleUntil
        }

        self.sharedCloudThrottleUntil = nil
        sharedCloudThrottleRetryTask?.cancel()
        sharedCloudThrottleRetryTask = nil
        preferences.cloudRetryAfter = nil
        persistPreferencesSilently()
        return nil
    }

    private func recordSharedCloudThrottleIfNeeded(for error: Error) -> Date? {
        guard let retryAfterSeconds = Self.cloudKitRetryAfterSeconds(in: error) else {
            return nil
        }

        let throttleUntil = now().addingTimeInterval(retryAfterSeconds)
        if let existingThrottleUntil = sharedCloudThrottleUntil,
           existingThrottleUntil > throttleUntil {
            scheduleSharedCloudRetryIfNeeded()
            return existingThrottleUntil
        }

        sharedCloudThrottleUntil = throttleUntil
        preferences.cloudRetryAfter = throttleUntil
        persistPreferencesSilently()
        scheduleSharedCloudRetryIfNeeded()
        return throttleUntil
    }

    private func scheduleSharedCloudRetryIfNeeded() {
        sharedCloudThrottleRetryTask?.cancel()
        sharedCloudThrottleRetryTask = nil

        guard let throttleUntil = sharedCloudThrottleUntil,
              throttleUntil > now() else {
            return
        }

        scheduleBackgroundRefreshAfter(throttleUntil)
        let sleepUntilSharedCloudRetry = sleepUntilSharedCloudRetry
        sharedCloudThrottleRetryTask = Task { [weak self] in
            do {
                try await sleepUntilSharedCloudRetry(throttleUntil)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.retrySharedCloudWorkAfterThrottle(
                expectedDeadline: throttleUntil
            )
        }
    }

    private func retrySharedCloudWorkAfterThrottle(
        expectedDeadline: Date
    ) async {
        guard sharedCloudThrottleUntil == expectedDeadline else {
            return
        }
        guard expectedDeadline <= now() else {
            scheduleSharedCloudRetryIfNeeded()
            return
        }

        sharedCloudThrottleUntil = nil
        sharedCloudThrottleRetryTask = nil
        preferences.cloudRetryAfter = nil
        persistPreferencesSilently()

        await reconcileAttemptedEncryptedResetAcknowledgements()
        await resumePendingCloudSyncs()

        guard isApplicationActive,
              !isAuthenticationRequired else {
            return
        }
        _ = await refreshSharedRepositories(trigger: .foreground)
        await ensureRepositorySubscriptions()
    }

    private func persistPreferencesSilently() {
        try? libraryStore.savePreferences(preferences)
    }

    private func recordSuccessfulFullCloudRefresh() {
        lastSharedRepositoryRefreshAt = now()
        preferences.lastSuccessfulCloudRefreshAt =
            lastSharedRepositoryRefreshAt
        persistPreferencesSilently()
    }

    private func sharedCloudThrottleMessage(until throttleUntil: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.timeStyle = .short
        formatter.dateStyle = calendar.isDate(throttleUntil, inSameDayAs: now()) ? .none : .medium

        return L10n.format(
            "CloudKit is temporarily limiting sync. Try again after %@.",
            formatter.string(from: throttleUntil)
        )
    }

    private func ensureRepositorySubscriptions() async {
        guard activeSharedCloudThrottleUntil() == nil else {
            return
        }

        let validationCutoff = now().addingTimeInterval(-Self.subscriptionRevalidationInterval)
        let cloudReferences = repositories.filter { $0.descriptor.isCloudBacked }
        var ensuredSharedDatabaseSubscription = false
        var didUpdateCatalog = false

        for reference in cloudReferences {
            let isConfigurationCurrent =
                reference.subscriptionConfigurationVersion == Self.subscriptionConfigurationVersion &&
                (reference.subscriptionValidatedAt ?? .distantPast) >= validationCutoff
            if isConfigurationCurrent {
                continue
            }

            let scope: CloudDatabaseScope
            switch reference.descriptor.role {
            case .local:
                continue
            case .owner:
                scope = .privateDatabase
            case .editor, .viewer:
                guard !ensuredSharedDatabaseSubscription else {
                    continue
                }
                ensuredSharedDatabaseSubscription = true
                scope = .sharedDatabase
            }

            do {
                try await cloudService.ensureRepositorySubscription(using: reference.descriptor)
                if scope == .privateDatabase {
                    if let index = repositories.firstIndex(where: {
                        $0.id == reference.id
                    }) {
                        repositories[index].subscriptionConfigurationVersion =
                            Self.subscriptionConfigurationVersion
                        repositories[index].subscriptionValidatedAt = now()
                    }
                } else {
                    for index in repositories.indices
                    where repositoryReference(at: index, belongsTo: scope) {
                        repositories[index].subscriptionConfigurationVersion =
                            Self.subscriptionConfigurationVersion
                        repositories[index].subscriptionValidatedAt = now()
                    }
                }
                didUpdateCatalog = true
            } catch {
                if recordSharedCloudThrottleIfNeeded(for: error) != nil {
                    break
                }
            }
        }

        if didUpdateCatalog {
            try? persistRepositoryCatalog()
        }
    }

    private func repositoryReference(at index: Int, belongsTo scope: CloudDatabaseScope) -> Bool {
        switch scope {
        case .privateDatabase:
            return repositories[index].descriptor.role == .owner
        case .sharedDatabase:
            let role = repositories[index].descriptor.role
            return role == .editor || role == .viewer
        }
    }

    private func effectiveNotificationScope(for repositoryScope: SharedUpdateNotificationScope) -> SharedUpdateNotificationScope {
        repositoryScope == .all ? preferences.sharedUpdateNotificationScope : repositoryScope
    }

    private func refreshSharedRepositoriesIfNeededOnForeground() async {
        guard shouldRefreshSharedRepositoriesOnForeground() else {
            return
        }

        await refreshSharedRepositories(trigger: .foreground)
    }

    private func shouldRefreshSharedRepositoriesOnForeground() -> Bool {
        let hasSharedRepositories = sortedRepositories.contains { $0.descriptor.isCloudBacked }
        guard hasSharedRepositories else {
            return false
        }

        guard let lastSharedRepositoryRefreshAt else {
            return true
        }

        return now().timeIntervalSince(lastSharedRepositoryRefreshAt) >= Self.foregroundSharedRefreshMinimumInterval
    }

    private func runDeferredPostUnlockWorkIfNeeded() async {
        let deferredSubscriptionRefresh = shouldEnsureSubscriptionsAfterUnlock
        let deferredRefreshTrigger = pendingPostUnlockSharedRefreshTrigger

        self.shouldEnsureSubscriptionsAfterUnlock = false
        self.pendingPostUnlockSharedRefreshTrigger = nil

        if deferredSubscriptionRefresh {
            await ensureRepositorySubscriptions()
        }

        if let deferredRefreshTrigger {
            await refreshSharedRepositories(trigger: deferredRefreshTrigger)
        }
    }

    @discardableResult
    private func refreshRepository(
        _ reference: RepositoryReference,
        trigger: SharedRepositoryRefreshTrigger
    ) async throws -> RepositoryRefreshOutcome {
        try Task.checkCancellation()
        let repositoryStore = libraryStore.repositoryStore(for: reference.id)
        let mutationGenerationBeforeLoad = repositoryMutationGeneration(for: reference.id)
        let previousSnapshot = try repositoryStore.loadSnapshot()

        if repositoryReference(for: reference.id)?.pendingCloudUploadAt != nil {
            repositoriesPendingRefreshAfterMutation.insert(reference.id)
            return .deferred
        }

        let metadata = try await cloudService.loadSnapshotMetadata(using: reference.descriptor)
        try Task.checkCancellation()
        if let previousSnapshot {
            if let remoteChangeTag = metadata.recordChangeTag {
                if reference.lastKnownServerRecordChangeTag == remoteChangeTag {
                    return .unchanged
                }
            } else if previousSnapshot.updatedAt > metadata.updatedAt ||
                        (previousSnapshot.updatedAt == metadata.updatedAt &&
                         previousSnapshot.entries.count == metadata.entryCount) {
                return .unchanged
            }
        }

        let locallyAvailableImageContentHashes = try repositoryStore
            .imageContentHashes(
                referencedBy: previousSnapshot?.entries ?? []
            )
        let remoteSnapshot = try await cloudService.loadSnapshot(
            using: reference.descriptor,
            availableImageContentHashes:
                locallyAvailableImageContentHashes
        )
        try Task.checkCancellation()
        let normalizedRemoteSnapshot = remoteSnapshot.removingEmbeddedImages()
        let latestLocalSnapshot = try repositoryStore.loadSnapshot()

        if isRepositoryMutationInFlight(reference.id) {
            repositoriesPendingRefreshAfterMutation.insert(reference.id)
            return .deferred
        }

        if repositoryReference(for: reference.id)?.pendingCloudUploadAt != nil {
            repositoriesPendingRefreshAfterMutation.insert(reference.id)
            return .deferred
        }

        if let latestLocalSnapshot {
            if repositoryMutationGeneration(for: reference.id) != mutationGenerationBeforeLoad,
               latestLocalSnapshot != normalizedRemoteSnapshot {
                return .deferred
            }
        }

        let didChangeLocalSnapshot = previousSnapshot != normalizedRemoteSnapshot
        let shouldNotify = previousSnapshot != nil && didChangeLocalSnapshot

        try repositoryStore.saveDescriptor(reference.descriptor)
        try repositoryStore.saveCloudSnapshot(remoteSnapshot)

        upsertRepositoryReference(
            repositoryID: reference.id,
            descriptor: reference.descriptor,
            displayName: reference.displayName,
            snapshotUpdatedAt: normalizedRemoteSnapshot.updatedAt,
            markAsOpened: reference.id == currentRepositoryID
        )
        updateRemoteMetadata(for: reference.id, metadata: metadata)
        try persistRepositoryCatalog()

        if reference.id == currentRepositoryID {
            repositoryDescriptor = reference.descriptor
            applySnapshot(normalizedRemoteSnapshot)
            invalidateImageViews()
        }

        guard shouldNotify,
              preferences.isSharedUpdateNotificationEnabled,
              trigger != .manual,
              let notification = makeSharedRepositoryNotification(
                for: reference,
                previousEntries: previousSnapshot?.entries ?? [],
                latestEntries: normalizedRemoteSnapshot.entries,
                repositoryNotificationScope: normalizedRemoteSnapshot.sharedUpdateNotificationScope
              ) else {
            return didChangeLocalSnapshot ? .updated : .unchanged
        }

        let shouldApplyBadge = shouldApplySharedUpdateBadge(for: trigger)
        if shouldApplyBadge {
            setApplicationBadgeCount(1)
        }

        if trigger != .launch {
            await scheduleLocalNotification(notification, includeBadge: shouldApplyBadge)
        }
        return didChangeLocalSnapshot ? .updated : .unchanged
    }

    private func updateRemoteMetadata(
        for repositoryID: String,
        metadata: RepositorySnapshotMetadata
    ) {
        updateRemoteMetadata(
            for: repositoryID,
            serverModifiedAt: metadata.serverModifiedAt,
            recordChangeTag: metadata.recordChangeTag
        )
    }

    private func updateRemoteMetadata(
        for repositoryID: String,
        serverModifiedAt: Date?,
        recordChangeTag: String?
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        repositories[index].lastKnownServerRecordChangeTag = recordChangeTag
        repositories[index].lastKnownServerModifiedAt = serverModifiedAt
        repositories[index].cloudZoneUnavailableAt = nil
    }

    private func silentlyRefreshCurrentRepository(trigger: SharedRepositoryRefreshTrigger) async {
        guard let reference = repositoryReference(for: currentRepositoryID),
              reference.descriptor.isCloudBacked else {
            return
        }

        guard activeSharedCloudThrottleUntil() == nil else {
            return
        }

        do {
            try await refreshRepository(reference, trigger: trigger)
        } catch {
            _ = recordSharedCloudThrottleIfNeeded(for: error)
        }
    }

    func makeSharedRepositoryNotification(
        for reference: RepositoryReference,
        previousEntries: [EntryRecord],
        latestEntries: [EntryRecord],
        repositoryNotificationScope: SharedUpdateNotificationScope
    ) -> RepositoryUpdateNotification? {
        let effectiveScope = effectiveNotificationScope(for: repositoryNotificationScope)
        let previousByID = Dictionary(uniqueKeysWithValues: previousEntries.map { ($0.id, $0) })
        let latestEntryIDs = Set(latestEntries.map(\.id))
        let changedEntries = latestEntries.filter { entry in
            guard let previousEntry = previousByID[entry.id] else {
                return true
            }

            return previousEntry.updatedAt != entry.updatedAt ||
                previousEntry.title != entry.title ||
                previousEntry.body != entry.body ||
                previousEntry.imageReference != entry.imageReference
        }
        .filter { effectiveScope.includes($0.kind) }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
        let deletedEntryCount = previousEntries.lazy.filter {
            effectiveScope.includes($0.kind) && !latestEntryIDs.contains($0.id)
        }.count
        let totalUpdateCount = changedEntries.count + deletedEntryCount

        guard totalUpdateCount > 0 else {
            return nil
        }

        guard let firstEntry = changedEntries.first else {
            return RepositoryUpdateNotification(
                repositoryID: reference.id,
                entryID: nil,
                title: L10n.format("%@ updated", reference.localizedDisplayName),
                body: deletedEntryCount == 1
                    ? L10n.string("An entry was deleted.")
                    : L10n.format("%lld entries were deleted.", Int64(deletedEntryCount))
            )
        }

        let previewText = firstEntry.displayTitle ??
            firstEntry.summary.trimmed.nilIfEmpty ??
            timelineTitle(for: firstEntry)
        let title: String
        let body: String
        if totalUpdateCount == 1 {
            title = L10n.format("%@ updated", reference.localizedDisplayName)
            body = previewText
        } else {
            title = L10n.format(
                "%@ has %lld updates",
                reference.localizedDisplayName,
                Int64(totalUpdateCount)
            )
            body = L10n.format(
                "%@ and %lld more entries",
                previewText,
                Int64(totalUpdateCount - 1)
            )
        }

        return RepositoryUpdateNotification(
            repositoryID: reference.id,
            entryID: firstEntry.id,
            title: title,
            body: body
        )
    }

    private func scheduleLocalNotification(_ notification: RepositoryUpdateNotification, includeBadge: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        if includeBadge {
            content.badge = 1
        }
        content.userInfo = [
            LocalNotificationPayload.repositoryIDKey: notification.repositoryID
        ]
        if let entryID = notification.entryID {
            content.userInfo[LocalNotificationPayload.entryIDKey] = entryID.uuidString
        }

        let request = UNNotificationRequest(
            identifier: [
                "repository-update",
                notification.repositoryID,
                notification.entryID?.uuidString ?? UUID().uuidString
            ].joined(separator: "-"),
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func clearApplicationBadge() {
        setApplicationBadgeCount(0)
    }

    private func shouldApplySharedUpdateBadge(for trigger: SharedRepositoryRefreshTrigger) -> Bool {
        (trigger == .push || trigger == .backgroundRecovery) && !isApplicationActive
    }

    private func shouldBlockWhenSwitchingRepository(to repositoryID: String) -> Bool {
        let fallbackRepositoryID = repositories.contains(where: { $0.id == repositoryID })
            ? repositoryID
            : RepositoryReference.localRepositoryID
        guard fallbackRepositoryID != RepositoryReference.localRepositoryID else {
            return false
        }

        let repositoryStore = libraryStore.repositoryStore(for: fallbackRepositoryID)
        let descriptor = (try? repositoryStore.loadDescriptor())
            ?? repositoryReference(for: fallbackRepositoryID)?.descriptor
            ?? .local
        guard descriptor.isCloudBacked else {
            return false
        }

        return (try? repositoryStore.loadSnapshot()) == nil
    }

    private static func defaultBlogTag(in tags: [String]) -> String {
        tags.first(where: {
            $0.compare("note", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) ?? tags.first ?? RepositorySnapshot.defaultBlogTags.last ?? "note"
    }

    private static func abbreviatedCount(_ value: Int) -> String {
        guard value >= 1000 else {
            return String(value)
        }

        let abbreviations = [L10n.string("K"), L10n.string("M"), L10n.string("B"), L10n.string("T")]
        let formatter = NumberFormatter()
        formatter.locale = AppLanguage.locale
        formatter.numberStyle = .decimal

        var scaledValue = Double(value) / 1000
        var abbreviationIndex = 0

        while scaledValue >= 1000, abbreviationIndex < abbreviations.count - 1 {
            scaledValue /= 1000
            abbreviationIndex += 1
        }

        while true {
            let fractionDigits: Int
            switch scaledValue {
            case 100...:
                fractionDigits = 0
            case 10...:
                fractionDigits = 1
            default:
                fractionDigits = 2
            }

            let roundingFactor = pow(10.0, Double(fractionDigits))
            let roundedValue = (scaledValue * roundingFactor).rounded() / roundingFactor

            if roundedValue >= 1000, abbreviationIndex < abbreviations.count - 1 {
                scaledValue = roundedValue / 1000
                abbreviationIndex += 1
                continue
            }

            formatter.minimumFractionDigits = fractionDigits
            formatter.maximumFractionDigits = fractionDigits

            let formatted = formatter.string(from: NSNumber(value: roundedValue))
                ?? String(format: "%.\(fractionDigits)f", roundedValue)
            return formatted + abbreviations[abbreviationIndex]
        }
    }

    static func systemAuthenticateBiometrics(reason: String) async throws {
        try await systemAuthenticateBiometrics(reason: reason, context: LAContext())
    }

    static func systemAuthenticateBiometrics(reason: String, context: any AppLocalAuthenticationContext) async throws {
        context.localizedFallbackTitle = L10n.string("Use Passcode")

        var biometricEvaluationError: NSError?
        let canEvaluateBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &biometricEvaluationError
        )
        if !canEvaluateBiometrics,
           !isBiometryLockout(biometricEvaluationError) {
            throw biometricEvaluationError ?? LAError(.biometryNotAvailable)
        }

        var ownerAuthenticationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &ownerAuthenticationError) else {
            if let ownerAuthenticationError {
                throw ownerAuthenticationError
            }
            if let biometricEvaluationError {
                throw biometricEvaluationError
            }
            throw LAError(.passcodeNotSet)
        }

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: error ?? LAError(.authenticationFailed))
                }
            }
        }
    }

    private static func isBiometryLockout(_ error: NSError?) -> Bool {
        guard let error else {
            return false
        }

        return LAError.Code(rawValue: error.code) == .biometryLockout
    }

    static func userFacingMessage(for error: Error) -> String {
        if let cloudKitSchemaMessage = cloudKitProductionSchemaMessage(for: error) {
            return cloudKitSchemaMessage
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.trimmed.nilIfEmpty {
            return description
        }

        let localizedDescription = error.localizedDescription.trimmed
        if !localizedDescription.isEmpty {
            return localizedDescription
        }

        return L10n.string("An unexpected error occurred.")
    }

    private static func cloudKitRetryAfterSeconds(in error: Error) -> TimeInterval? {
        var retryAfterValues: [TimeInterval] = []

        func append(_ value: Any?) {
            switch value {
            case let number as NSNumber where number.doubleValue > 0:
                retryAfterValues.append(number.doubleValue)
            case let double as Double where double > 0:
                retryAfterValues.append(double)
            case let integer as Int where integer > 0:
                retryAfterValues.append(TimeInterval(integer))
            default:
                return
            }
        }

        func collect(from error: Error) {
            if let ckError = error as? CKError {
                append(ckError.retryAfterSeconds)
            }

            let nsError = error as NSError
            append(nsError.userInfo[CKErrorRetryAfterKey])

            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                collect(from: underlyingError)
            }

            if nsError.domain == CKErrorDomain,
               let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                for partialError in partialErrors.values {
                    collect(from: partialError)
                }
            }
        }

        collect(from: error)
        return retryAfterValues.max()
    }

    private static func cloudKitProductionSchemaMessage(for error: Error) -> String? {
        guard let recordType = cloudKitProductionSchemaRecordType(in: error) else {
            return nil
        }

        return L10n.format(
            "The CloudKit production environment has not deployed the %@ record type yet. Deploy the development schema to production in CloudKit Console, then create the share link again.",
            recordType
        )
    }

    private static func cloudKitProductionSchemaRecordType(in error: Error) -> String? {
        cloudKitErrorMessages(in: error)
            .lazy
            .compactMap(productionSchemaRecordType(from:))
            .first
    }

    private static func cloudKitErrorMessages(in error: Error) -> [String] {
        var messages: [String] = []

        func append(_ message: String?) {
            guard let trimmed = message?.trimmed.nilIfEmpty,
                  !messages.contains(trimmed) else {
                return
            }

            messages.append(trimmed)
        }

        func collect(from error: Error) {
            let nsError = error as NSError
            append(error.localizedDescription)
            append(nsError.userInfo[NSLocalizedDescriptionKey] as? String)
            append(nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String)
            append(nsError.userInfo[NSDebugDescriptionErrorKey] as? String)

            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                collect(from: underlyingError)
            }

            if nsError.domain == CKErrorDomain,
               let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                for partialError in partialErrors.values {
                    collect(from: partialError)
                }
            }
        }

        collect(from: error)
        return messages
    }

    private static func productionSchemaRecordType(from message: String) -> String? {
        let marker = "Cannot create new type "
        let suffix = " in production schema"

        guard let start = message.range(of: marker),
              let end = message.range(of: suffix, range: start.upperBound..<message.endIndex) else {
            return nil
        }

        return String(message[start.upperBound..<end.lowerBound]).trimmed.nilIfEmpty
    }

    private func invalidateImageViews() {
        imageRefreshVersion &+= 1
    }
}

struct RepositoryUpdateNotification {
    let repositoryID: String
    let entryID: UUID?
    let title: String
    let body: String
}

@MainActor
private final class ApplicationBackgroundTaskLease {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

private struct PreviewCloudRepositoryService: CloudRepositoryServicing {
    func loadSnapshotMetadata(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshotMetadata {
        RepositorySnapshotMetadata(updatedAt: .distantPast, entryCount: 0)
    }

    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        RepositorySnapshot(entries: [], blogTags: RepositorySnapshot.defaultBlogTags)
    }

    func saveSnapshot(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        expectedRecordChangeTag: String?,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot {
        SavedRepositorySnapshot(
            descriptor: descriptor.role == .local
                ? RepositoryDescriptor(zoneName: "preview-zone", zoneOwnerName: CKCurrentUserDefaultName, shareRecordName: "preview-share", role: .owner)
                : descriptor,
            serverModifiedAt: .now,
            recordChangeTag: "preview-change-tag"
        )
    }

    func recreateSnapshotAfterEncryptedDataReset(
        _ snapshot: RepositorySnapshot,
        using descriptor: RepositoryDescriptor,
        acceptedPredecessorOperationIDs: Set<UUID>
    ) async throws -> SavedRepositorySnapshot {
        try await saveSnapshot(
            snapshot,
            using: descriptor,
            expectedRecordChangeTag: nil,
            acceptedPredecessorOperationIDs: []
        )
    }

    func ensureRepositorySubscription(using descriptor: RepositoryDescriptor) async throws {}

    func pendingRepositoryZoneChanges(
        in scope: CloudDatabaseScope
    ) async throws -> CloudRepositoryDatabaseChanges {
        CloudRepositoryDatabaseChanges()
    }

    func acknowledgeRepositoryZoneChanges(
        _ changes: CloudRepositoryDatabaseChanges,
        in scope: CloudDatabaseScope
    ) async throws {}

    func resetRemoteChangeTracking() async throws {}

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
            snapshot: RepositorySnapshot(entries: [], blogTags: RepositorySnapshot.defaultBlogTags),
            displayName: "Shared Repository"
        )
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        try await acceptShare(from: URL(string: "https://www.icloud.com/share/preview")!)
    }
}
