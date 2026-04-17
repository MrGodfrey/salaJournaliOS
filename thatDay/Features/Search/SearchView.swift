import Observation
import SwiftUI

struct SearchView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []

    private var hasQuery: Bool {
        !store.searchText.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    TextField("搜索标题或正文", text: $store.searchText)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("searchField")
                }

                if hasQuery {
                    Section {
                        if store.searchResults.isEmpty {
                            ContentUnavailableView.search(text: store.searchText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(store.searchResults) { entry in
                                NavigationLink(value: EntryDestination.read(entry.id)) {
                                    EntryCardView(
                                        entry: entry,
                                        imageURL: store.imageURL(for: entry),
                                        imageRefreshVersion: store.imageRefreshVersion
                                    )
                                }
                                .navigationLinkIndicatorVisibility(.hidden)
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    } header: {
                        Text("共 \(store.searchResults.count) 条结果")
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "输入关键词开始搜索",
                            systemImage: "magnifyingglass",
                            description: Text("Journal 和 Blog 会一起参与检索。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityIdentifier("searchIdleState")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EntryDestination.self) { destination in
                if let entry = store.entry(matching: destination.entryID) {
                    EntryDetailView(
                        store: store,
                        entry: entry
                    )
                } else {
                    ContentUnavailableView(
                        "这篇文章已经不存在",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.presentSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("searchOpenSettingsButton")
                }
            }
        }
    }
}
