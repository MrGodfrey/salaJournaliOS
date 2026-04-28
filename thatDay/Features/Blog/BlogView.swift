import Observation
import SwiftUI
import UIKit

struct BlogView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                BlogTagFilterControl(
                    tags: store.blogTags,
                    selection: $store.selectedBlogTag
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))

                BlogPageView(
                    store: store,
                    selectedTag: store.selectedBlogTag,
                    openEntry: { entryID in
                        navigationPath = [.read(entryID)]
                    },
                    refreshAction: {
                        await store.refreshSharedRepositories(trigger: .manual)
                    },
                    tagSettledAction: { tag in
                        store.selectBlogTag(tag)
                    }
                )
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
            .onChange(of: store.blogTags) { _, _ in
                store.selectBlogTag(store.selectedBlogTag)
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

private struct BlogPageView: UIViewControllerRepresentable {
    let store: AppStore
    let selectedTag: String?
    let openEntry: (UUID) -> Void
    let refreshAction: () async -> Void
    let tagSettledAction: (String?) -> Void

    func makeUIViewController(context: Context) -> BlogPageViewController {
        BlogPageViewController(
            store: store,
            selectedTag: selectedTag,
            openEntry: openEntry,
            refreshAction: refreshAction,
            tagSettledAction: tagSettledAction
        )
    }

    func updateUIViewController(_ uiViewController: BlogPageViewController, context: Context) {
        uiViewController.configure(
            store: store,
            selectedTag: selectedTag,
            openEntry: openEntry,
            refreshAction: refreshAction,
            tagSettledAction: tagSettledAction
        )
    }
}

private final class BlogPageViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    private var store: AppStore
    private var currentTag: String?
    private var openEntry: (UUID) -> Void
    private var refreshAction: () async -> Void
    private var tagSettledAction: (String?) -> Void
    private var isTransitioning = false
    private var pendingTag: String?
    private var hasPendingTag = false

    init(
        store: AppStore,
        selectedTag: String?,
        openEntry: @escaping (UUID) -> Void,
        refreshAction: @escaping () async -> Void,
        tagSettledAction: @escaping (String?) -> Void
    ) {
        self.store = store
        currentTag = store.blogTag(byAdding: 0, to: selectedTag)
        self.openEntry = openEntry
        self.refreshAction = refreshAction
        self.tagSettledAction = tagSettledAction

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "blogPageViewController"
        pageViewController.view.backgroundColor = .systemGroupedBackground
        pageViewController.dataSource = self
        pageViewController.delegate = self

        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)

        pageViewController.setViewControllers(
            [makePage(for: currentTag)],
            direction: .forward,
            animated: false
        )
    }

    func configure(
        store: AppStore,
        selectedTag: String?,
        openEntry: @escaping (UUID) -> Void,
        refreshAction: @escaping () async -> Void,
        tagSettledAction: @escaping (String?) -> Void
    ) {
        self.store = store
        self.openEntry = openEntry
        self.refreshAction = refreshAction
        self.tagSettledAction = tagSettledAction

        let normalizedTag = store.blogTag(byAdding: 0, to: selectedTag)
        guard normalizedTag != currentTag else {
            refreshVisiblePage()
            return
        }

        setCurrentTag(normalizedTag, animated: true)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? BlogTagHostingController else {
            return nil
        }

        let previousTag = store.blogTag(byAdding: -1, to: page.tag)
        guard previousTag != page.tag else {
            return nil
        }

        return makePage(for: previousTag)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? BlogTagHostingController else {
            return nil
        }

        let nextTag = store.blogTag(byAdding: 1, to: page.tag)
        guard nextTag != page.tag else {
            return nil
        }

        return makePage(for: nextTag)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        isTransitioning = true
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        isTransitioning = false

        if completed,
           let visiblePage = pageViewController.viewControllers?.first as? BlogTagHostingController {
            currentTag = store.blogTag(byAdding: 0, to: visiblePage.tag)
            tagSettledAction(currentTag)
        } else {
            refreshVisiblePage()
        }

        applyPendingTagIfNeeded()
    }

    private func setCurrentTag(_ tag: String?, animated: Bool) {
        let normalizedTag = store.blogTag(byAdding: 0, to: tag)
        guard normalizedTag != currentTag else {
            refreshVisiblePage()
            return
        }

        guard !isTransitioning else {
            pendingTag = normalizedTag
            hasPendingTag = true
            return
        }

        isTransitioning = animated
        let direction = store.blogTagPageIndex(for: normalizedTag) > store.blogTagPageIndex(for: currentTag)
            ? UIPageViewController.NavigationDirection.forward
            : UIPageViewController.NavigationDirection.reverse
        let page = makePage(for: normalizedTag)

        pageViewController.setViewControllers(
            [page],
            direction: direction,
            animated: animated
        ) { [weak self] finished in
            guard let self else {
                return
            }

            self.isTransitioning = false
            if !finished {
                self.pageViewController.setViewControllers(
                    [page],
                    direction: direction,
                    animated: false
                )
            }
            self.currentTag = normalizedTag
            self.applyPendingTagIfNeeded()
        }
    }

    private func applyPendingTagIfNeeded() {
        guard hasPendingTag else {
            return
        }

        hasPendingTag = false
        let nextTag = pendingTag
        pendingTag = nil

        guard nextTag != currentTag else {
            return
        }

        setCurrentTag(nextTag, animated: true)
    }

    private func refreshVisiblePage() {
        guard let visiblePage = pageViewController.viewControllers?.first as? BlogTagHostingController else {
            return
        }

        visiblePage.update(
            store: store,
            openEntry: openEntry,
            refreshAction: refreshAction
        )
    }

    private func makePage(for tag: String?) -> BlogTagHostingController {
        BlogTagHostingController(
            tag: store.blogTag(byAdding: 0, to: tag),
            store: store,
            openEntry: openEntry,
            refreshAction: refreshAction
        )
    }
}

private final class BlogTagHostingController: UIHostingController<BlogTagPageView> {
    let tag: String?

    init(
        tag: String?,
        store: AppStore,
        openEntry: @escaping (UUID) -> Void,
        refreshAction: @escaping () async -> Void
    ) {
        self.tag = tag
        super.init(
            rootView: BlogTagPageView(
                store: store,
                tag: tag,
                openEntry: openEntry,
                refreshAction: refreshAction
            )
        )
        view.backgroundColor = .systemGroupedBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        store: AppStore,
        openEntry: @escaping (UUID) -> Void,
        refreshAction: @escaping () async -> Void
    ) {
        rootView = BlogTagPageView(
            store: store,
            tag: tag,
            openEntry: openEntry,
            refreshAction: refreshAction
        )
    }
}

private struct BlogTagPageView: View {
    @Bindable var store: AppStore

    let tag: String?
    let openEntry: (UUID) -> Void
    let refreshAction: () async -> Void

    private var filteredEntries: [EntryRecord] {
        store.blogEntries(for: tag)
    }

    var body: some View {
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
                    L10n.format("No posts in %@", L10n.blogTag(tag ?? L10n.string("this tag"))),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Choose another tag or add a new blog post.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 48)
            } else {
                ForEach(filteredEntries) { entry in
                    Button {
                        openEntry(entry.id)
                    } label: {
                        EntryCardView(
                            entry: entry,
                            imageURL: store.imageURL(for: entry),
                            imageRefreshVersion: store.imageRefreshVersion
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("blogTagPage-\(BlogTagFilterOption.accessibilityID(for: tag))")
        .refreshable {
            await refreshAction()
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
                        .accessibilityValue(isSelected(option) ? L10n.string("Selected") : L10n.string("Not selected"))
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

    nonisolated static var all: BlogTagFilterOption {
        BlogTagFilterOption(
            id: "all",
            title: L10n.string("All"),
            tag: nil,
            accessibilityID: "All"
        )
    }

    nonisolated static func tag(_ value: String) -> BlogTagFilterOption {
        BlogTagFilterOption(
            id: value,
            title: L10n.blogTag(value),
            tag: value,
            accessibilityID: value
        )
    }

    nonisolated static func accessibilityID(for tag: String?) -> String {
        tag ?? all.accessibilityID
    }
}
