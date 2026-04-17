import Observation
import SwiftUI
import UIKit

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

private struct BlogTagFilterControl: UIViewRepresentable {
    let tags: [String]
    @Binding var selection: String?

    private var options: [String] {
        ["All"] + tags
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.accessibilityIdentifier = "blogTagFilterControl"

        let segmentedControl = UISegmentedControl(items: options)
        segmentedControl.apportionsSegmentWidthsByContent = true
        segmentedControl.selectedSegmentTintColor = UIColor(Color.indigo)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        segmentedControl.addTarget(context.coordinator, action: #selector(Coordinator.selectionChanged(_:)), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.accessibilityIdentifier = "blogTagFilterSegments"

        scrollView.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            segmentedControl.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            segmentedControl.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.segmentedControl = segmentedControl
        update(segmentedControl: segmentedControl, coordinator: context.coordinator)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let segmentedControl = context.coordinator.segmentedControl else {
            return
        }

        context.coordinator.parent = self
        update(segmentedControl: segmentedControl, coordinator: context.coordinator)
    }

    private func update(segmentedControl: UISegmentedControl, coordinator: Coordinator) {
        if coordinator.options != options {
            segmentedControl.removeAllSegments()
            for (index, title) in options.enumerated() {
                segmentedControl.insertSegment(withTitle: title, at: index, animated: false)
            }
            coordinator.options = options
        }

        let selectedIndex = selection.flatMap { tag in
            options.firstIndex(of: tag)
        } ?? 0

        segmentedControl.selectedSegmentIndex = selectedIndex
        coordinator.scrollSelectedSegmentIfNeeded()
    }

    final class Coordinator: NSObject {
        var parent: BlogTagFilterControl
        weak var scrollView: UIScrollView?
        weak var segmentedControl: UISegmentedControl?
        var options: [String] = []

        init(parent: BlogTagFilterControl) {
            self.parent = parent
        }

        @objc
        func selectionChanged(_ sender: UISegmentedControl) {
            let selectedIndex = sender.selectedSegmentIndex
            if selectedIndex <= 0 {
                parent.selection = nil
            } else {
                parent.selection = options[selectedIndex]
            }

            scrollSelectedSegmentIfNeeded()
        }

        func scrollSelectedSegmentIfNeeded() {
            guard let scrollView,
                  let segmentedControl,
                  segmentedControl.selectedSegmentIndex >= 0,
                  segmentedControl.numberOfSegments > segmentedControl.selectedSegmentIndex else {
                return
            }

            let orderedSegments = segmentedControl.subviews.sorted { lhs, rhs in
                lhs.frame.minX < rhs.frame.minX
            }
            guard orderedSegments.count > segmentedControl.selectedSegmentIndex else {
                return
            }

            let selectedFrame = orderedSegments[segmentedControl.selectedSegmentIndex].frame
            let targetFrame = selectedFrame.insetBy(dx: -24, dy: 0)
            scrollView.scrollRectToVisible(targetFrame, animated: true)
        }
    }
}
