import SwiftUI

struct EntryCardView: View {
    let entry: EntryRecord
    let imageURL: URL?

    var body: some View {
        Group {
            if let imageURL {
                VStack(alignment: .leading, spacing: 0) {
                    coverImage(for: imageURL)
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
            Text(entry.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(entry.cardDateTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func coverImage(for imageURL: URL) -> some View {
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
        .frame(maxWidth: .infinity)
        .frame(height: 204)
        .clipped()
    }
}
