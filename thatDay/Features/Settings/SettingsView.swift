import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore

    @State private var isShowingFileImporter = false
    @State private var isShowingClearRepositoryConfirmation = false
    @State private var newBlogTagName = ""
    @State private var pendingBlogTagDeletion: BlogTagDeletionRequest?
    @State private var pendingPersonalNotificationScopeConfirmation: SharedUpdateNotificationScope?
    @State private var pendingRepositoryNotificationScopeConfirmation: SharedUpdateNotificationScope?

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository Status") {
                    Picker(
                        "Current Repository",
                        selection: Binding(
                            get: { store.currentRepositoryID },
                            set: { repositoryID in
                                Task {
                                    await store.switchRepository(to: repositoryID)
                                }
                            }
                        )
                    ) {
                        ForEach(store.sortedRepositories) { repository in
                            Text(repository.localizedDisplayName).tag(repository.id)
                        }
                    }
                    .accessibilityIdentifier("currentRepositoryPicker")

                    LabeledContent("Current Access", value: store.repositoryStatusTitle)
                }

                blogTagsSection

                cloudKitSharingSection

                openSharedRepositorySection

                notificationsSection

                Section("Security") {
                    Toggle("Biometric Unlock", isOn: Binding(
                        get: { store.isBiometricLockEnabled },
                        set: { isEnabled in
                            Task {
                                await store.updateBiometricLockEnabled(isEnabled)
                            }
                        }
                    ))

                    Text("When enabled, authentication is required every time the app launches or returns to the foreground.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                importExportSection

                advancedSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Clear the current repository?",
                isPresented: $isShowingClearRepositoryConfirmation
            ) {
                Button("Clear", role: .destructive) {
                    Task {
                        await store.clearCurrentRepository()
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All entries and images in the current repository will be deleted. This action cannot be undone.")
            }
            .alert(
                "Change personal push updates?",
                isPresented: Binding(
                    get: { pendingPersonalNotificationScopeConfirmation != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingPersonalNotificationScopeConfirmation = nil
                        }
                    }
                ),
                presenting: pendingPersonalNotificationScopeConfirmation
            ) {
                scope in
                Button(L10n.format("Change to %@", scope.title)) {
                    store.setSharedUpdateNotificationScope(scope)
                }

                Button("Cancel", role: .cancel) {
                    pendingPersonalNotificationScopeConfirmation = nil
                }
            } message: {
                scope in
                Text(
                    L10n.format(
                        "%@ will be saved as your personal default. Repositories whose owner selects Journal or Blog will ignore this setting.",
                        scope.summary
                    )
                )
            }
            .alert(
                "Change repository push updates?",
                isPresented: Binding(
                    get: { pendingRepositoryNotificationScopeConfirmation != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingRepositoryNotificationScopeConfirmation = nil
                        }
                    }
                ),
                presenting: pendingRepositoryNotificationScopeConfirmation
            ) {
                scope in
                Button(L10n.format("Change to %@", scope.title)) {
                    Task {
                        await store.updateRepositorySharedUpdateNotificationScope(scope)
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingRepositoryNotificationScopeConfirmation = nil
                }
            } message: {
                scope in
                Text(repositoryNotificationScopeChangeMessage(for: scope))
            }
            .alert(
                pendingBlogTagDeletion?.title ?? L10n.string("Delete Tag?"),
                isPresented: Binding(
                    get: { pendingBlogTagDeletion != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingBlogTagDeletion = nil
                        }
                    }
                ),
                presenting: pendingBlogTagDeletion
            ) {
                request in
                if request.requiresReassignment {
                    ForEach(request.replacementTags, id: \.self) { replacementTag in
                        Button(L10n.format("Move posts to %@", L10n.blogTag(replacementTag))) {
                            confirmBlogTagDeletion(
                                request.tag,
                                replacementTag: replacementTag
                            )
                        }
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        confirmBlogTagDeletion(request.tag, replacementTag: nil)
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingBlogTagDeletion = nil
                }
            } message: { request in
                Text(request.message)
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result,
                      let url = urls.first else {
                    return
                }

                Task {
                    await store.importRepositoryArchive(from: url)
                }
            }
            .sheet(item: $store.sharingControllerItem) { item in
                CloudSharingControllerContainer(controller: item.controller)
            }
            .sheet(item: $store.exportedArchiveItem) { item in
                ActivityViewController(activityItems: [item.url])
            }
        }
    }

    private var cloudKitSharingSection: some View {
        Section("CloudKit Sharing") {
            if store.canCreateShareInvite {
                Picker("Invite Access", selection: $store.shareAccessOption) {
                    ForEach(ShareAccessOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.shareAccessOption.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await store.presentSharingController()
                    }
                } label: {
                    Label("Create Share Link", systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("presentShareControllerButton")
            }

            if store.canManageRepositoryNotificationScope {
                Picker("Repository Push Updates", selection: Binding(
                    get: { store.repositorySharedUpdateNotificationScope },
                    set: { scope in
                        guard scope != store.repositorySharedUpdateNotificationScope else {
                            return
                        }

                        pendingRepositoryNotificationScopeConfirmation = scope
                    }
                )) {
                    ForEach(SharedUpdateNotificationScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .accessibilityIdentifier("repositorySharedUpdateNotificationScopePicker")
            } else {
                LabeledContent("Repository Push Updates", value: store.repositorySharedUpdateNotificationScope.title)
            }

            Text(store.repositoryNotificationScopeDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var blogTagsSection: some View {
        Section("Blog Tags") {
            ForEach(store.blogTags, id: \.self) { tag in
                blogTagRow(for: tag)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if store.canEditRepository && store.blogTags.count > 1 {
                            Button {
                                prepareBlogTagDeletion(tag)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
            }
            .onMove(perform: moveBlogTags)

            if store.canEditRepository {
                HStack(spacing: 12) {
                    TextField("New Tag", text: $newBlogTagName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("newBlogTagField")

                    Button("Add") {
                        addBlogTag()
                    }
                    .disabled(isAddBlogTagDisabled)
                }
            }

            Text(blogTagsDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var openSharedRepositorySection: some View {
        Section("Open Shared Repository") {
            TextField("https://www.icloud.com/share/...", text: $store.incomingShareLink, axis: .vertical)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .accessibilityIdentifier("shareLinkTextField")

            Button {
                Task {
                    await store.acceptIncomingShareLink()
                }
            } label: {
                Label("Open Shared Repository", systemImage: "link")
            }
            .accessibilityIdentifier("acceptShareLinkButton")
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Shared Repository Update Alerts", isOn: Binding(
                get: { store.isSharedUpdateNotificationEnabled },
                set: { isEnabled in
                    Task {
                        await store.updateSharedUpdateNotificationEnabled(isEnabled)
                    }
                }
            ))

            Picker("Personal Push Updates", selection: Binding(
                get: { store.sharedUpdateNotificationScope },
                set: { scope in
                    guard scope != store.sharedUpdateNotificationScope else {
                        return
                    }

                    pendingPersonalNotificationScopeConfirmation = scope
                }
            )) {
                ForEach(SharedUpdateNotificationScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .accessibilityIdentifier("sharedUpdateNotificationScopePicker")

            LabeledContent("Effective in This Repository", value: store.effectiveCurrentRepositoryNotificationScope.title)

            Text(store.personalNotificationScopeDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var importExportSection: some View {
        Section("Import / Export") {
            Button {
                Task {
                    await store.exportCurrentRepository()
                }
            } label: {
                Label("Export Current Repository as ZIP", systemImage: "square.and.arrow.up")
            }

            Button {
                isShowingFileImporter = true
            } label: {
                Label("Import ZIP into Current Repository", systemImage: "square.and.arrow.down")
            }

            Text("Import replaces the current repository contents. Export creates a ZIP file and can continue in the background.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let transferProgress = store.transferProgress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: transferProgress.fractionCompleted)
                    Text(transferProgress.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Picker(
                "Default on Launch",
                selection: Binding(
                    get: { store.defaultRepositoryID },
                    set: { repositoryID in
                        store.setDefaultRepository(repositoryID)
                    }
                )
            ) {
                ForEach(store.sortedRepositories) { repository in
                    Text(repository.localizedDisplayName).tag(repository.id)
                }
            }

            Button("Clear Current Repository", role: .destructive) {
                isShowingClearRepositoryConfirmation = true
            }
            .disabled(!store.canEditRepository)
        }
    }

    private func repositoryNotificationScopeChangeMessage(for scope: SharedUpdateNotificationScope) -> String {
        if scope == .all {
            return L10n.string("Everyone in this repository can use their own personal Push Updates setting again.")
        }

        return L10n.format(
            "Everyone in this repository will be limited to %@. Personal Push Updates settings will be ignored here until you switch back to All.",
            scope.summary.lowercased(with: AppLanguage.locale)
        )
    }

    private var isAddBlogTagDisabled: Bool {
        let normalizedName = newBlogTagName.trimmed
        return normalizedName.isEmpty || store.blogTags.contains(where: {
            $0.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
    }

    private var blogTagsDescription: String {
        store.canEditRepository
            ? L10n.string("Tags belong to the current repository. Drag a tag to reorder it, add new ones here, and deleting a used tag will first ask where its blog posts should move.")
            : L10n.string("The current repository is read-only, so blog tags can be viewed here but cannot be changed.")
    }

    private func addBlogTag() {
        let tagName = newBlogTagName.trimmed
        guard !tagName.isEmpty else {
            return
        }

        newBlogTagName = ""
        Task {
            await store.addBlogTag(named: tagName)
        }
    }

    @ViewBuilder
    private func blogTagRow(for tag: String) -> some View {
        let row = HStack(spacing: 12) {
            Text(L10n.blogTag(tag))

            Spacer()

            Text("\(store.blogTagUsageCounts[tag, default: 0])")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if store.canEditRepository {
                Image(systemName: "line.3.horizontal")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .moveDisabled(!store.canEditRepository)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(blogTagRowAccessibilityIdentifier(for: tag))

        row
    }

    private func prepareBlogTagDeletion(_ tag: String) {
        pendingBlogTagDeletion = BlogTagDeletionRequest(
            tag: tag,
            replacementTags: store.blogTags.filter { $0 != tag },
            usageCount: store.blogTagUsageCounts[tag, default: 0]
        )
    }

    private func moveBlogTags(from source: IndexSet, to destination: Int) {
        guard store.canEditRepository else {
            return
        }

        Task {
            await store.moveBlogTags(fromOffsets: source, toOffset: destination)
        }
    }

    private func confirmBlogTagDeletion(_ tag: String, replacementTag: String?) {
        pendingBlogTagDeletion = nil
        Task {
            await store.deleteBlogTag(tag, reassigningEntriesTo: replacementTag)
        }
    }
}

private struct BlogTagDeletionRequest: Identifiable {
    let tag: String
    let replacementTags: [String]
    let usageCount: Int

    var id: String {
        tag
    }

    var title: String {
        L10n.format("Delete %@?", L10n.blogTag(tag))
    }

    var requiresReassignment: Bool {
        usageCount > 0
    }

    var message: String {
        if requiresReassignment {
            return L10n.format("Choose where existing blog posts tagged %@ should go before this tag is removed.", L10n.blogTag(tag))
        }

        return L10n.string("This tag is not used by any blog posts and will be removed from the current repository.")
    }
}

private struct CloudSharingControllerContainer: UIViewControllerRepresentable {
    let controller: UICloudSharingController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private func blogTagRowAccessibilityIdentifier(for tag: String) -> String {
    "settingsBlogTagRow-\(tag.replacingOccurrences(of: " ", with: "-"))"
}
