import SwiftUI
import UIKit

struct EntryCardView: View {
    let entry: EntryRecord
    let imageURL: URL?
    let imageRefreshVersion: Int
    let dateText: String?

    init(
        entry: EntryRecord,
        imageURL: URL?,
        imageRefreshVersion: Int,
        dateText: String? = nil
    ) {
        self.entry = entry
        self.imageURL = imageURL
        self.imageRefreshVersion = imageRefreshVersion
        self.dateText = dateText
    }

    var body: some View {
        Group {
            if let imageURL {
                VStack(alignment: .leading, spacing: 0) {
                    coverImage(for: imageURL)
                        .id("cover-\(entry.id.uuidString)-\(imageRefreshVersion)")
                    cardText
                        .padding(16)
                }
            } else {
                cardText
                    .padding(16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .accessibilityIdentifier("entryCard-\(entry.id.uuidString)")
    }

    private var cardText: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = entry.displayTitle {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(dateText ?? entry.cardDateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let tag = entry.blogTag,
                   entry.kind == .blog {
                    BlogTagChip(tag: tag)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func coverImage(for imageURL: URL) -> some View {
        Group {
            if let image = imageURL.repositoryLocalImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        Color(.tertiarySystemGroupedBackground)
                            .overlay {
                                ProgressView()
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color(.tertiarySystemGroupedBackground)
                    @unknown default:
                        Color(.tertiarySystemGroupedBackground)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 204)
        .clipped()
    }
}

struct BlogTagChip: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.indigo)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.indigo.opacity(0.12), in: Capsule())
    }
}
