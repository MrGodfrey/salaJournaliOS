import Observation
import PhotosUI
import SwiftUI
import UIKit

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore

    let entryID: UUID

    @State private var isEditing: Bool
    @State private var draft: EntryDraft
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importedImageData: Data?
    @State private var isSaving = false
    @State private var isShowingDeleteConfirmation = false

    init(store: AppStore, entry: EntryRecord) {
        self.store = store
        entryID = entry.id
        _isEditing = State(initialValue: false)
        _draft = State(
            initialValue: EntryDraft(
                kind: entry.kind,
                title: entry.title,
                body: entry.body,
                blogTag: entry.blogTag ?? (entry.kind == .blog ? store.defaultBlogTag : nil),
                happenedAt: entry.happenedAt
            )
        )
    }

    var body: some View {
        Group {
            if let entry = store.entry(matching: entryID) {
                content(for: entry)
            } else {
                ContentUnavailableView(
                    "This entry no longer exists",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Go back to continue browsing.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        cancelEditing()
                    }
                    .accessibilityIdentifier("entryDetailCancelButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("entryDetailSaveButton")
                }
            } else if store.canEditRepository,
                      let entry = store.entry(matching: entryID) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        startEditing(with: entry)
                    }
                    .accessibilityIdentifier("entryDetailEditButton")
                }
            }
        }
        .task(id: selectedPhoto) {
            await loadSelectedPhoto()
        }
        .alert(
            "Delete this entry?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteCurrentEntry()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ViewBuilder
    private func content(for entry: EntryRecord) -> some View {
        if isEditing {
            Form {
                EntryFormSections(
                    draft: $draft,
                    selectedPhoto: $selectedPhoto,
                    importedImageData: importedImageData,
                    existingImageURL: store.imageURL(for: entry),
                    imageRefreshVersion: store.imageRefreshVersion,
                    blogTags: store.blogTags
                )

                Section {
                    Button("Delete This Entry", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("entryDetailDeleteButton")
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    readerCover(for: entry)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(entry.title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("entryDetailTitle")

                        HStack(spacing: 8) {
                            Text(entry.cardDateTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let tag = entry.blogTag,
                               entry.kind == .blog {
                                BlogTagChip(tag: tag)
                            }
                        }

                        Text(entry.body)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineSpacing(8)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("entryDetailBody")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func readerCover(for entry: EntryRecord) -> some View {
        if let imageURL = store.imageURL(for: entry) {
            Group {
                if let image = imageURL.repositoryLocalImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 0, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))

                                ProgressView()
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        @unknown default:
                            RoundedRectangle(cornerRadius: 0, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        }
                    }
                }
            }
            .id("detail-cover-\(entry.id.uuidString)-\(store.imageRefreshVersion)")
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipped()
        }
    }

    private func startEditing(with entry: EntryRecord) {
        draft = EntryDraft(
            kind: entry.kind,
            title: entry.title,
            body: entry.body,
            blogTag: entry.blogTag ?? (entry.kind == .blog ? store.defaultBlogTag : nil),
            happenedAt: entry.happenedAt
        )
        importedImageData = nil
        selectedPhoto = nil
        isEditing = true
    }

    private func cancelEditing() {
        if let entry = store.entry(matching: entryID) {
            draft = EntryDraft(
                kind: entry.kind,
                title: entry.title,
                body: entry.body,
                blogTag: entry.blogTag ?? (entry.kind == .blog ? store.defaultBlogTag : nil),
                happenedAt: entry.happenedAt
            )
        }

        importedImageData = nil
        selectedPhoto = nil
        isEditing = false
    }

    private func save() async {
        guard let entry = store.entry(matching: entryID) else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        let didSave = await store.saveEntry(
            draft: draft,
            importedImageData: importedImageData,
            editing: entry
        )

        if didSave {
            importedImageData = nil
            selectedPhoto = nil
            isEditing = false
        }
    }

    private func deleteCurrentEntry() async {
        guard let entry = store.entry(matching: entryID) else {
            return
        }

        await store.deleteEntry(entry)
        dismiss()
    }

    @MainActor
    private func loadSelectedPhoto() async {
        guard let selectedPhoto else {
            return
        }

        do {
            guard let rawData = try await selectedPhoto.loadTransferable(type: Data.self) else {
                importedImageData = nil
                return
            }

            importedImageData = try EntryImageCompressor.compressedData(for: rawData)
        } catch {
            importedImageData = nil
            store.alertMessage = AppStore.userFacingMessage(for: error)
        }
    }
}
