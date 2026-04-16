import PhotosUI
import SwiftUI
import UIKit

struct EntryFormSections: View {
    @Binding var draft: EntryDraft
    @Binding var selectedPhoto: PhotosPickerItem?

    let importedImageData: Data?
    let existingImageURL: URL?

    var body: some View {
        Section("内容") {
            TextField("标题", text: $draft.title)
                .accessibilityIdentifier("entryTitleField")

            DatePicker("日期", selection: $draft.happenedAt, displayedComponents: [.date])
                .accessibilityIdentifier("entryDatePicker")
        }

        Section("图片") {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("从相册选择图片", systemImage: "photo.on.rectangle")
            }

            imagePreview
        }

        Section("正文") {
            TextEditor(text: $draft.body)
                .frame(minHeight: 220)
                .accessibilityIdentifier("entryBodyEditor")
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let importedImageData,
           let image = UIImage(data: importedImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let existingImageURL {
            AsyncImage(url: existingImageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
