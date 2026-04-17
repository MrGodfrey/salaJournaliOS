import Observation
import SwiftUI

struct BlogView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []
    @State private var selectedTag: String?

    private var filteredEntries: [EntryRecord] {
        guard let selectedTag else {
            return store.blogEntries
        }

        return store.blogEntries.filter { $0.blogTag == selectedTag }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                BlogTagFilterControl(
                    tags: store.blogTags,
                    selection: $selectedTag
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))

                List {
                    if store.blogEntries.isEmpty {
                        ContentUnavailableView(
                            "No blog posts yet",
                            systemImage: "square.and.pencil",
                            description: Text("Write your first blog post.")
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 48)
                    } else if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            "No posts in \(selectedTag ?? "this tag")",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Choose another tag or add a new blog post.")
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 48)
                    } else {
                        ForEach(filteredEntries) { entry in
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
                .refreshable {
                    await store.refreshSharedRepositories(trigger: .manual)
                }
            }
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
                        "This entry no longer exists",
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
                    .accessibilityIdentifier("blogOpenSettingsButton")
                }
            }
            .task(id: store.entryOpenRequest?.id) {
                guard let destination = store.consumeEntryOpenRequest(for: .blog) else {
                    return
                }

                navigationPath = [destination]
            }
            .onChange(of: store.blogTags) { _, newTags in
                if let selectedTag,
                   !newTags.contains(selectedTag) {
                    self.selectedTag = nil
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if store.canEditRepository {
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
                    .padding(.trailing, 24)
                    .padding(.bottom, 20)
                    .accessibilityIdentifier("addBlogEntryButton")
                }
            }
        }
    }
}

private struct BlogTagFilterControl: View {
    let tags: [String]
    @Binding var selection: String?

    private var options: [BlogTagFilterOption] {
        [.all] + tags.map(BlogTagFilterOption.tag)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(options) { option in
                        Button {
                            selection = option.tag
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected(option) ? Color.white : Color.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected(option) ? Color.indigo : Color(.secondarySystemGroupedBackground))
                                )
                                .overlay {
                                    if !isSelected(option) {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(option.id)
                        .accessibilityIdentifier("blogTagFilter-\(option.accessibilityID)")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("blogTagFilterControl")
            .onAppear {
                scrollToSelection(using: proxy, animated: false)
            }
            .onChange(of: selection) { _, _ in
                scrollToSelection(using: proxy, animated: true)
            }
            .onChange(of: tags) { _, _ in
                scrollToSelection(using: proxy, animated: false)
            }
        }
    }

    private func isSelected(_ option: BlogTagFilterOption) -> Bool {
        selection == option.tag
    }

    private func scrollToSelection(using proxy: ScrollViewProxy, animated: Bool) {
        let selectedID = options.first(where: isSelected)?.id ?? BlogTagFilterOption.all.id

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            } else {
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
    }
}

private struct BlogTagFilterOption: Identifiable, Hashable {
    let id: String
    let title: String
    let tag: String?
    let accessibilityID: String

    nonisolated static let all = BlogTagFilterOption(
        id: "all",
        title: "All",
        tag: nil,
        accessibilityID: "All"
    )

    nonisolated static func tag(_ value: String) -> BlogTagFilterOption {
        BlogTagFilterOption(
            id: value,
            title: value,
            tag: value,
            accessibilityID: value
        )
    }
}
