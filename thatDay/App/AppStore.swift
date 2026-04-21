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
    private let setApplicationBadgeCount: (Int) -> Void
    private let calendar: Calendar

    private var didLoad = false
    private var hasLoadedPreferences = false
    private var isApplicationActive = false
    private var preferences = AppPreferences()
    private var shouldRequireAuthenticationOnNextActive = false
    private var repositoryMutationGenerations: [String: Int] = [:]
    private var repositoryMutationInFlightCounts: [String: Int] = [:]
    private var repositoriesPendingRefreshAfterMutation: Set<String> = []

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
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        authenticateBiometrics: @escaping (String) async throws -> Void = AppStore.systemAuthenticateBiometrics,
        setApplicationBadgeCount: @escaping (Int) -> Void = { badgeCount in
            UNUserNotificationCenter.current().setBadgeCount(badgeCount) { _ in }
        }
    ) {
        self.libraryStore = libraryStore
        self.cloudService = cloudService
        self.calendar = calendar
        self.now = now
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
        repositoryDescriptor.role.canEdit
    }

    var repositoryStatusTitle: String {
        repositoryDescriptor.role.title
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

    var effectiveCurrentRepositoryNotificationScope: SharedUpdateNotificationScope {
        effectiveNotificationScope(for: repositorySharedUpdateNotificationScope)
    }

    var canCreateShareInvite: Bool {
        repositoryDescriptor.role.canCreateShareInvite
    }

    var canManageRepositoryNotificationScope: Bool {
        repositoryDescriptor.role.canManageRepositoryNotificationScope
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
        AppLanguage.monthDayTitle(for: selectedDate)
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
        entries
            .filter { $0.kind == .journal && calendar.isSameMonthDay($0.happenedAt, selectedDate) }
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
        isBusy = true
        defer { isBusy = false }

        do {
            repositories = try libraryStore.loadCatalog()
            preferences = try libraryStore.loadPreferences()
            hasLoadedPreferences = true
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
                entries = []
                blogTags = RepositorySnapshot.defaultBlogTags
                repositorySharedUpdateNotificationScope = .all
            }
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        displayedMonth = calendar.startOfMonth(for: selectedDate)
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
        guard normalized.kind == .journal || !normalized.title.isEmpty else {
            alertMessage = L10n.string("Enter a title.")
            return false
        }
        guard !normalized.body.isEmpty else {
            alertMessage = L10n.string("Enter content.")
            return false
        }

        isBusy = true
        defer { isBusy = false }

        do {
            normalizeRepositoryState()
            let entryID = editingEntry?.id ?? UUID()
            let existingImageReference = editingEntry?.imageReference
            let didChangeImage = importedImageData != nil || (removeExistingImage && existingImageReference != nil)
            let imageReference: String?
            if let importedImageData {
                imageReference = try currentRepositoryStore.storeImage(
                    data: importedImageData,
                    suggestedID: entryID
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

            try await persistEntries()
            if didChangeImage {
                invalidateImageViews()
            }
            editorSession = nil
            return true
        } catch {
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
        selectedBlogTag = matchedBlogTag(for: tag)
        selectedTab = .blog
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
            let snapshot = try currentRepositoryStore.makeSnapshot(
                entries: entries,
                updatedAt: now(),
                embeddingImages: true,
                blogTags: blogTags,
                sharedUpdateNotificationScope: repositorySharedUpdateNotificationScope
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
            alertMessage = L10n.string("Enter a valid iCloud share link.")
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
                alertMessage = L10n.string("Notification permission is disabled, so shared repository updates cannot be delivered.")
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
            alertMessage = L10n.string("The current repository is read-only and cannot import content.")
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

            applySnapshot(importedSnapshot)
            try await persistEntries()
            invalidateImageViews()
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
        isApplicationActive = phase == .active

        if phase == .active {
            clearApplicationBadge()
        }

        guard hasLoadedPreferences else {
            return
        }

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
            try await authenticateBiometricsAction(L10n.string("Unlock thatDay"))
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
        }

        if repositoryDescriptor.isCloudBacked {
            let snapshot = try await cloudService.loadSnapshot(using: repositoryDescriptor)
            applySnapshot(snapshot)
            try repositoryStore.saveCloudSnapshot(snapshot)
            invalidateImageViews()
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
        let repositoryID = currentRepositoryID
        let repositoryStore = libraryStore.repositoryStore(for: repositoryID)
        let repositoryName = currentRepositoryName
        let descriptorAtStart = repositoryDescriptor

        beginRepositoryMutation(for: repositoryID)

        var storedError: Error?

        do {
            normalizeRepositoryState()
            let snapshot = RepositorySnapshot(
                entries: entries,
                updatedAt: now(),
                blogTags: blogTags,
                sharedUpdateNotificationScope: repositorySharedUpdateNotificationScope
            )
            try repositoryStore.saveSnapshot(snapshot)

            let savedDescriptor: RepositoryDescriptor
            if descriptorAtStart.role != .local {
                let cloudSnapshot = try repositoryStore.makeSnapshot(
                    entries: entries,
                    updatedAt: snapshot.updatedAt,
                    embeddingImages: true,
                    blogTags: blogTags,
                    sharedUpdateNotificationScope: repositorySharedUpdateNotificationScope
                )
                savedDescriptor = try await cloudService.saveSnapshot(cloudSnapshot, using: descriptorAtStart)
                try repositoryStore.saveDescriptor(savedDescriptor)
            } else {
                savedDescriptor = .local
                try repositoryStore.saveDescriptor(savedDescriptor)
            }

            if currentRepositoryID == repositoryID {
                repositoryDescriptor = savedDescriptor
            }

            upsertRepositoryReference(
                repositoryID: repositoryID,
                descriptor: savedDescriptor,
                displayName: repositoryName,
                snapshotUpdatedAt: snapshot.updatedAt,
                markAsOpened: true
            )
            try persistRepositoryCatalog()
            await ensureRepositorySubscriptions()
        } catch {
            storedError = error
        }

        let deferredRefreshReference = finishRepositoryMutation(for: repositoryID)
        if let deferredRefreshReference {
            try? await refreshRepository(deferredRefreshReference, trigger: .foreground)
        }

        if let storedError {
            throw storedError
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

    private func effectiveNotificationScope(for repositoryScope: SharedUpdateNotificationScope) -> SharedUpdateNotificationScope {
        repositoryScope == .all ? preferences.sharedUpdateNotificationScope : repositoryScope
    }

    private func refreshRepository(_ reference: RepositoryReference, trigger: SharedRepositoryRefreshTrigger) async throws {
        let repositoryStore = libraryStore.repositoryStore(for: reference.id)
        let mutationGenerationBeforeLoad = repositoryMutationGeneration(for: reference.id)
        let previousSnapshot = try repositoryStore.loadSnapshot()
        let remoteSnapshot = try await cloudService.loadSnapshot(using: reference.descriptor)
        let normalizedRemoteSnapshot = remoteSnapshot.removingEmbeddedImages()
        let latestLocalSnapshot = try repositoryStore.loadSnapshot()

        if isRepositoryMutationInFlight(reference.id) {
            repositoriesPendingRefreshAfterMutation.insert(reference.id)
            return
        }

        if let latestLocalSnapshot {
            if latestLocalSnapshot.updatedAt > normalizedRemoteSnapshot.updatedAt {
                return
            }

            if repositoryMutationGeneration(for: reference.id) != mutationGenerationBeforeLoad,
               latestLocalSnapshot.updatedAt >= normalizedRemoteSnapshot.updatedAt,
               latestLocalSnapshot != normalizedRemoteSnapshot {
                return
            }
        }

        let previousUpdatedAt = [reference.lastKnownSnapshotUpdatedAt, previousSnapshot?.updatedAt]
            .compactMap { $0 }
            .max()
        let shouldNotify = previousUpdatedAt != nil && normalizedRemoteSnapshot.updatedAt > (previousUpdatedAt ?? .distantPast)

        try repositoryStore.saveDescriptor(reference.descriptor)
        try repositoryStore.saveCloudSnapshot(remoteSnapshot)

        upsertRepositoryReference(
            repositoryID: reference.id,
            descriptor: reference.descriptor,
            displayName: reference.displayName,
            snapshotUpdatedAt: normalizedRemoteSnapshot.updatedAt,
            markAsOpened: reference.id == currentRepositoryID
        )
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
            return
        }

        let shouldApplyBadge = shouldApplySharedUpdateBadge(for: trigger)
        if shouldApplyBadge {
            setApplicationBadgeCount(1)
        }

        if trigger != .launch {
            await scheduleLocalNotification(notification, includeBadge: shouldApplyBadge)
        }
    }

    private func makeSharedRepositoryNotification(
        for reference: RepositoryReference,
        previousEntries: [EntryRecord],
        latestEntries: [EntryRecord],
        repositoryNotificationScope: SharedUpdateNotificationScope
    ) -> RepositoryUpdateNotification? {
        let effectiveScope = effectiveNotificationScope(for: repositoryNotificationScope)
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
        .filter { effectiveScope.includes($0.kind) }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }

        guard let firstEntry = changedEntries.first else {
            return nil
        }

        let previewText = firstEntry.displayTitle ?? firstEntry.summary.trimmed.nilIfEmpty ?? firstEntry.timelineTitle
        let title: String
        let body: String
        if changedEntries.count == 1 {
            title = L10n.format("%@ updated", reference.localizedDisplayName)
            body = previewText
        } else {
            title = L10n.format("%@ has %lld updates", reference.localizedDisplayName, Int64(changedEntries.count))
            body = L10n.format("%@ and %lld more entries", previewText, Int64(changedEntries.count - 1))
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

    private func clearApplicationBadge() {
        setApplicationBadgeCount(0)
    }

    private func shouldApplySharedUpdateBadge(for trigger: SharedRepositoryRefreshTrigger) -> Bool {
        trigger == .push && !isApplicationActive
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

    private static func systemAuthenticateBiometrics(reason: String) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = L10n.string("Use Passcode")

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

private struct RepositoryUpdateNotification {
    let repositoryID: String
    let entryID: UUID
    let title: String
    let body: String
}

private struct PreviewCloudRepositoryService: CloudRepositoryServicing {
    func loadSnapshot(using descriptor: RepositoryDescriptor) async throws -> RepositorySnapshot {
        RepositorySnapshot(entries: [], blogTags: RepositorySnapshot.defaultBlogTags)
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
            snapshot: RepositorySnapshot(entries: [], blogTags: RepositorySnapshot.defaultBlogTags),
            displayName: "Shared Repository"
        )
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> AcceptedSharedRepository {
        try await acceptShare(from: URL(string: "https://www.icloud.com/share/preview")!)
    }
}
