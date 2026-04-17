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
    @State private var isSaving = false

    init(store: AppStore, session: EntryEditorSession) {
        self.store = store
        self.session = session
        _draft = State(
            initialValue: EntryDraft(
                kind: session.kind,
                title: session.entry?.title ?? "",
                body: session.entry?.body ?? "",
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
                    importedImageData: importedImageData,
                    existingImageURL: session.entry.flatMap { store.imageURL(for: $0) }
                )
            }
            .navigationTitle(session.mode == .create ? "新建 \(session.kind.title)" : "编辑 \(session.kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        store.dismissEditor()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "保存中..." : "保存") {
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
        } catch {
            importedImageData = nil
            store.alertMessage = AppStore.userFacingMessage(for: error)
        }
    }
}
