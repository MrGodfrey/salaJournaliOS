import SwiftUI

struct EntryCardView: View {
    let entry: EntryRecord
    let imageURL: URL?
    let canEdit: Bool
    let showWeekdayBelow: Bool
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(entry.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(alignment: .center) {
                        Text(showWeekdayBelow ? entry.timelineTitle : entry.weekdayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if canEdit {
                            Menu {
                                Button("编辑", action: onEdit ?? {})
                                Button("删除", role: .destructive, action: onDelete ?? {})
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                            }
                            .accessibilityIdentifier("entryMenu-\(entry.id.uuidString)")
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .accessibilityIdentifier("entryCard-\(entry.id.uuidString)")

            if showWeekdayBelow {
                Text(entry.weekdayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
        } else {
            placeholder
                .frame(height: 140)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: entry.kind == .journal
                    ? [Color.teal.opacity(0.9), Color.blue.opacity(0.6)]
                    : [Color.orange.opacity(0.85), Color.pink.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: entry.kind.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
