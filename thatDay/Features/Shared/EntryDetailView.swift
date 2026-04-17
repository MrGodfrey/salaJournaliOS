import Observation
import PhotosUI
import SwiftUI

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
                    "这篇文章已经不存在",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("返回上一页继续浏览其他内容。")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        cancelEditing()
                    }
                    .accessibilityIdentifier("entryDetailCancelButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "保存中..." : "保存") {
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
                    Button("编辑") {
                        startEditing(with: entry)
                    }
                    .accessibilityIdentifier("entryDetailEditButton")
                }
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else {
                return
            }

            importedImageData = try? await selectedPhoto.loadTransferable(type: Data.self)
        }
        .alert(
            "删除这篇文章？",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("删除", role: .destructive) {
                Task {
                    await deleteCurrentEntry()
                }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后将无法恢复。")
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
                    existingImageURL: store.imageURL(for: entry)
                )

                Section {
                    Button("删除这篇文章", role: .destructive) {
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

                        Text(entry.timelineTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

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
}
