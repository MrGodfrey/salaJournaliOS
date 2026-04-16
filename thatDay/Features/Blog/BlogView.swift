import Observation
import SwiftUI

struct BlogView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                if store.blogEntries.isEmpty {
                    ContentUnavailableView(
                        "还没有 Blog",
                        systemImage: "square.and.pencil",
                        description: Text("先写下第一篇 Blog。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.blogEntries) { entry in
                        EntryCardView(
                            entry: entry,
                            imageURL: store.imageURL(for: entry),
                            canEdit: store.canEditRepository,
                            showWeekdayBelow: false,
                            onEdit: {
                                store.showEditor(for: .blog, entry: entry)
                            },
                            onDelete: {
                                Task { await store.deleteEntry(entry) }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Blog")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.showEditor(for: .blog)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!store.canEditRepository)
                    .accessibilityIdentifier("addBlogEntryButton")
                }
            }
        }
    }
}
