import Observation
import SwiftUI

struct SearchView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []
    @State private var pendingDeletion: EntryRecord?

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
                                        showWeekdayBelow: false
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if store.canEditRepository {
                                        Button("删除", role: .destructive) {
                                            pendingDeletion = entry
                                        }

                                        Button("编辑") {
                                            navigationPath.append(.edit(entry.id))
                                        }
                                        .tint(.indigo)
                                    }
                                }
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
            .navigationDestination(for: EntryDestination.self) { destination in
                if let entry = store.entry(matching: destination.entryID) {
                    EntryDetailView(
                        store: store,
                        entry: entry,
                        startsInEditMode: destination.startsInEditMode
                    )
                } else {
                    ContentUnavailableView(
                        "这篇文章已经不存在",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .alert(
                "删除这篇文章？",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { value in
                        if !value {
                            pendingDeletion = nil
                        }
                    }
                )
            ) {
                Button("删除", role: .destructive) {
                    guard let entry = pendingDeletion else {
                        return
                    }

                    Task {
                        await store.deleteEntry(entry)
                        pendingDeletion = nil
                    }
                }

                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("删除后将无法恢复。")
            }
        }
    }
}
