import PhotosUI
import SwiftUI
import UIKit

struct EntryFormSections: View {
    @Binding var draft: EntryDraft
    @Binding var selectedPhoto: PhotosPickerItem?

    let importedImageData: Data?
    let existingImageURL: URL?

    var body: some View {
        Section("信息") {
            TextField("标题", text: $draft.title)
                .accessibilityIdentifier("entryTitleField")

            DatePicker("日期", selection: $draft.happenedAt, displayedComponents: [.date])
                .accessibilityIdentifier("entryDatePicker")
        }

        Section("正文") {
            TextEditor(text: $draft.body)
                .frame(minHeight: 220)
                .accessibilityIdentifier("entryBodyEditor")

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("插入图片", systemImage: "photo.on.rectangle")
            }

            Text("选图后会自动压缩到 \(EntryImageCompressor.sizeLimitDescription) 以内。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            imagePreview
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
