import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore

    @State private var isShowingFileImporter = false
    @State private var isShowingClearRepositoryConfirmation = false

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
