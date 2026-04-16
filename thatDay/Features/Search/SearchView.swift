import Observation
import SwiftUI

struct SearchView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索标题或正文", text: $store.searchText)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("searchField")
                }

                Section {
                    if store.searchResults.isEmpty {
                        ContentUnavailableView.search(text: store.searchText)
                    } else {
                        ForEach(store.searchResults) { entry in
                            EntryCardView(
                                entry: entry,
                                imageURL: store.imageURL(for: entry),
                                canEdit: store.canEditRepository,
                                showWeekdayBelow: false,
                                onEdit: {
                                    store.showEditor(for: entry.kind, entry: entry)
                                },
                                onDelete: {
                                    Task { await store.deleteEntry(entry) }
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }
                } header: {
                    Text("共 \(store.searchResults.count) 条结果")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
        }
    }
}
