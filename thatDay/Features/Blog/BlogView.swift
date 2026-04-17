import Observation
import SwiftUI

struct BlogView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if store.blogEntries.isEmpty {
                    ContentUnavailableView(
                        "还没有 Blog",
                        systemImage: "square.and.pencil",
                        description: Text("先写下第一篇 Blog。")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 48)
                } else {
                    ForEach(store.blogEntries) { entry in
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
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Blog")
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
            .refreshable {
                await store.refreshSharedRepositories(trigger: .manual)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.presentSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("blogOpenSettingsButton")
                }
            }
            .task(id: store.entryOpenRequest?.id) {
                guard let destination = store.consumeEntryOpenRequest(for: .blog) else {
                    return
                }

                navigationPath = [destination]
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    store.showEditor(for: .blog)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.indigo, in: Circle())
                        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
                }
                .disabled(!store.canEditRepository)
                .padding(.trailing, 24)
                .padding(.bottom, 20)
                .accessibilityIdentifier("addBlogEntryButton")
            }
        }
    }
}
