import PhotosUI
import SwiftUI
import UIKit

struct EntryFormSections: View {
    @Binding var draft: EntryDraft
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var isExistingImageRemoved: Bool
    @Binding var importedImageData: Data?

    let existingImageURL: URL?
    let imageRefreshVersion: Int
    let blogTags: [String]

    var body: some View {
        Section("Details") {
            TextField(titlePlaceholder, text: $draft.title)
                .accessibilityIdentifier("entryTitleField")

            DatePicker("Date", selection: $draft.happenedAt, displayedComponents: [.date])
                .accessibilityIdentifier("entryDatePicker")

            if draft.kind == .blog {
                Picker("Tag", selection: Binding(
                    get: { draft.blogTag ?? blogTags.first ?? RepositorySnapshot.defaultBlogTags.first ?? "Reading" },
                    set: { draft.blogTag = $0 }
                )) {
                    ForEach(blogTags, id: \.self) { tag in
                        Text(L10n.blogTag(tag)).tag(tag)
                    }
                }
                .accessibilityIdentifier("entryBlogTagPicker")

                Picker("Image Layout", selection: $draft.blogImageLayout) {
                    ForEach(BlogCardImageLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("entryBlogImageLayoutPicker")
            }
        }

        Section("Content") {
            TextEditor(text: $draft.body)
                .frame(minHeight: 220)
                .accessibilityIdentifier("entryBodyEditor")

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Add Image", systemImage: "photo.on.rectangle")
            }

            Text("Selected images are automatically compressed below \(EntryImageCompressor.sizeLimitDescription).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if hasImagePreview {
                imagePreview

                Button("Delete Image", role: .destructive) {
                    importedImageData = nil
                    selectedPhoto = nil
                    isExistingImageRemoved = true
                }
                .accessibilityIdentifier("entryRemoveImageButton")
            }
        }
    }

    private var titlePlaceholder: String {
        draft.kind == .journal ? L10n.string("Title (Optional)") : L10n.string("Title")
    }

    private var hasImagePreview: Bool {
        importedImageData != nil || (existingImageURL != nil && !isExistingImageRemoved)
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
        } else if let existingImageURL,
                  !isExistingImageRemoved {
            Group {
                if let image = existingImageURL.repositoryLocalImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
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
                }
            }
            .id("editor-image-\(existingImageURL.absoluteString)-\(imageRefreshVersion)")
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
