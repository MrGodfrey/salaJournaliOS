import Observation
import SwiftUI
import UIKit

struct SearchView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []

    private var hasQuery: Bool {
        !store.searchText.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
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
                        Text("\(store.searchResults.count) Results")
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Start typing to search",
                            systemImage: "magnifyingglass",
                            description: Text("Journal and Blog entries are searched together.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityIdentifier("searchIdleState")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchBar(
                    text: $store.searchText,
                    placeholder: "Search titles or content"
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(Color(uiColor: .systemGroupedBackground))
            }
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
                    .accessibilityIdentifier("searchOpenSettingsButton")
                }
            }
        }
    }
}

private struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = placeholder
        searchBar.returnKeyType = .search
        searchBar.autocorrectionType = .default
        searchBar.autocapitalizationType = .none
        searchBar.enablesReturnKeyAutomatically = false
        searchBar.accessibilityIdentifier = "searchField"
        searchBar.searchTextField.accessibilityIdentifier = "searchField"
        searchBar.searchTextField.clearButtonMode = .whileEditing
        searchBar.searchTextField.autocapitalizationType = .none
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }
    }
}
