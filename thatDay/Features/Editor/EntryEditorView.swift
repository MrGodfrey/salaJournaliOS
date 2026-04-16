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
                happenedAt: session.entry?.happenedAt ?? session.defaultDate,
                imageReference: session.entry?.imageReference ?? ""
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("内容") {
                    TextField("标题", text: $draft.title)
                        .accessibilityIdentifier("entryTitleField")

                    DatePicker("日期", selection: $draft.happenedAt, displayedComponents: [.date])
                        .accessibilityIdentifier("entryDatePicker")
                }

                Section("图片") {
                    TextField("图片链接（可选）", text: $draft.imageReference, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("entryImageReferenceField")

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从相册选择图片", systemImage: "photo.on.rectangle")
                    }

                    if let importedImageData,
                       let image = UIImage(data: importedImageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                Section("正文") {
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 220)
                        .accessibilityIdentifier("entryBodyEditor")
                }
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
                guard let selectedPhoto else {
                    return
                }

                importedImageData = try? await selectedPhoto.loadTransferable(type: Data.self)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let didSave = await store.saveEntry(draft: draft, importedImageData: importedImageData)
        if didSave {
            dismiss()
        }
    }
}
