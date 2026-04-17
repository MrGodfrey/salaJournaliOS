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
    @State private var reassigningBlogTag: String?
    @State private var unusedBlogTagToDelete: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository Status") {
                    LabeledContent("Current Repository", value: store.currentRepositoryName)
                    LabeledContent("Current Access", value: store.repositoryStatusTitle)
                    Text(store.repositorySummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.canEditRepository {
                    Section("CloudKit Sharing") {
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
                }

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

                Section("Notifications") {
                    Toggle("Shared Repository Update Alerts", isOn: Binding(
                        get: { store.isSharedUpdateNotificationEnabled },
                        set: { isEnabled in
                            Task {
                                await store.updateSharedUpdateNotificationEnabled(isEnabled)
                            }
                        }
                    ))

                    Text("Send a tappable system notification when a shared repository you joined adds or updates entries.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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

                Section("Blog Tags") {
                    ForEach(store.blogTags, id: \.self) { tag in
                        HStack(spacing: 12) {
                            Text(tag)

                            Spacer()

                            Text("\(store.blogTagUsageCounts[tag, default: 0])")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if store.canEditRepository && store.blogTags.count > 1 {
                                Button(role: .destructive) {
                                    prepareBlogTagDeletion(tag)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        Task {
                            await store.moveBlogTags(fromOffsets: source, toOffset: destination)
                        }
                    }

                    if store.canEditRepository {
                        HStack(spacing: 12) {
                            TextField("New Tag", text: $newBlogTagName)
                                .textInputAutocapitalization(.words)
                                .accessibilityIdentifier("newBlogTagField")

                            Button("Add") {
                                let tagName = newBlogTagName.trimmed
                                guard !tagName.isEmpty else {
                                    return
                                }

                                newBlogTagName = ""
                                Task {
                                    await store.addBlogTag(named: tagName)
                                }
                            }
                            .disabled(
                                newBlogTagName.trimmed.isEmpty ||
                                    store.blogTags.contains(where: {
                                        $0.compare(newBlogTagName.trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                                    })
                            )
                        }
                    }

                    Text(store.canEditRepository
                         ? "Tags belong to the current repository. Reorder them with Edit, add new ones here, and deleting a used tag will first ask where its blog posts should move."
                         : "The current repository is read-only, so blog tags can be viewed here but cannot be changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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

                Section("Advanced") {
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
                            Text(repository.displayName).tag(repository.id)
                        }
                    }

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
                            Text(repository.displayName).tag(repository.id)
                        }
                    }

                    Button("Clear Current Repository", role: .destructive) {
                        isShowingClearRepositoryConfirmation = true
                    }
                    .disabled(!store.canEditRepository)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.canEditRepository {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }

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
            .confirmationDialog(
                reassigningBlogTag.map { "Delete \($0)?" } ?? "Delete Tag?",
                isPresented: Binding(
                    get: { reassigningBlogTag != nil },
                    set: { isPresented in
                        if !isPresented {
                            reassigningBlogTag = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let tag = reassigningBlogTag {
                    ForEach(store.blogTags.filter { $0 != tag }, id: \.self) { replacementTag in
                        Button("Move posts to \(replacementTag)") {
                            let sourceTag = tag
                            reassigningBlogTag = nil
                            Task {
                                await store.deleteBlogTag(sourceTag, reassigningEntriesTo: replacementTag)
                            }
                        }
                    }
                }

                Button("Cancel", role: .cancel) {
                    reassigningBlogTag = nil
                }
            } message: {
                if let tag = reassigningBlogTag {
                    Text("Choose where existing blog posts tagged \(tag) should go before this tag is removed.")
                }
            }
            .alert(
                unusedBlogTagToDelete.map { "Delete \($0)?" } ?? "Delete Tag?",
                isPresented: Binding(
                    get: { unusedBlogTagToDelete != nil },
                    set: { isPresented in
                        if !isPresented {
                            unusedBlogTagToDelete = nil
                        }
                    }
                )
            ) {
                if let tag = unusedBlogTagToDelete {
                    Button("Delete", role: .destructive) {
                        let sourceTag = tag
                        unusedBlogTagToDelete = nil
                        Task {
                            await store.deleteBlogTag(sourceTag, reassigningEntriesTo: nil)
                        }
                    }
                }

                Button("Cancel", role: .cancel) {
                    unusedBlogTagToDelete = nil
                }
            } message: {
                Text("This tag is not used by any blog posts and will be removed from the current repository.")
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

    private func prepareBlogTagDeletion(_ tag: String) {
        if store.blogTagUsageCounts[tag, default: 0] > 0 {
            reassigningBlogTag = tag
        } else {
            unusedBlogTagToDelete = tag
        }
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
