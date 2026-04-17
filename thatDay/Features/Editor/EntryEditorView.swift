import Observation
import PhotosUI
import SwiftUI

struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore

    let session: EntryEditorSession

    @State private var draft: EntryDraft
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importedImageData: Data?
    @State private var isExistingImageRemoved = false
    @State private var isSaving = false

    init(store: AppStore, session: EntryEditorSession) {
        self.store = store
        self.session = session
        _draft = State(
            initialValue: EntryDraft(
                kind: session.kind,
                title: session.entry?.title ?? "",
                body: session.entry?.body ?? "",
                blogTag: session.entry?.blogTag ?? (session.kind == .blog ? store.defaultBlogTag : nil),
                blogImageLayout: session.entry?.blogImageLayout ?? .landscape,
                happenedAt: session.entry?.happenedAt ?? session.defaultDate
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                EntryFormSections(
                    draft: $draft,
                    selectedPhoto: $selectedPhoto,
                    isExistingImageRemoved: $isExistingImageRemoved,
                    importedImageData: $importedImageData,
                    existingImageURL: session.entry.flatMap { store.imageURL(for: $0) },
                    imageRefreshVersion: store.imageRefreshVersion,
                    blogTags: store.blogTags
                )
            }
            .navigationTitle(session.mode == .create ? "New \(session.kind.title)" : "Edit \(session.kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        store.dismissEditor()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("saveEntryButton")
                }
            }
            .task(id: selectedPhoto) {
                await loadSelectedPhoto()
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let didSave = await store.saveEntry(
            draft: draft,
            importedImageData: importedImageData,
            removeExistingImage: isExistingImageRemoved,
            editing: session.entry
        )
        if didSave {
            dismiss()
        }
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
            isExistingImageRemoved = false
        } catch {
            importedImageData = nil
            store.alertMessage = AppStore.userFacingMessage(for: error)
        }
    }
}
