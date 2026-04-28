import Observation
import SwiftUI
import UIKit

struct JournalView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            JournalPageView(
                store: store,
                selectedDate: store.selectedDate,
                openEntry: { entryID in
                    navigationPath = [.read(entryID)]
                },
                refreshAction: {
                    await store.refreshSharedRepositories(trigger: .manual)
                },
                dateSettledAction: { date in
                    store.selectDate(date)
                }
            )
            .background(Color(.systemGroupedBackground))
            .accessibilityIdentifier("journalScreen")
            .navigationTitle(store.selectedDateTitle)
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
            .task(id: store.entryOpenRequest?.id) {
                guard let destination = store.consumeEntryOpenRequest(for: .journal) else {
                    return
                }

                navigationPath = [destination]
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.goToCalendar()
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityIdentifier("openCalendarButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.presentSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("openSettingsButton")
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Button {
                            store.moveSelectedDate(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("journalPreviousDayButton")

                        Button {
                            store.returnToToday()
                        } label: {
                            Text(store.selectedDateTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .accessibilityIdentifier("journalHeaderDate")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("journalHeaderDateButton")

                        Button {
                            store.moveSelectedDate(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("journalNextDayButton")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if store.canEditRepository {
                    Button {
                        store.showEditor(for: .journal)
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
                    .accessibilityIdentifier("addJournalEntryButton")
                }
            }
        }
    }
}

private struct JournalPageView: UIViewControllerRepresentable {
    let store: AppStore
    let selectedDate: Date
    let openEntry: (UUID) -> Void
    let refreshAction: () async -> Void
    let dateSettledAction: (Date) -> Void

    func makeUIViewController(context: Context) -> JournalPageViewController {
        JournalPageViewController(
            store: store,
            selectedDate: selectedDate,
            openEntry: openEntry,
            refreshAction: refreshAction,
            dateSettledAction: dateSettledAction
        )
    }

    func updateUIViewController(_ uiViewController: JournalPageViewController, context: Context) {
        uiViewController.configure(
            store: store,
            selectedDate: selectedDate,
            openEntry: openEntry,
            refreshAction: refreshAction,
            dateSettledAction: dateSettledAction
        )
    }
}

private final class JournalPageViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )

    private var store: AppStore
    private var currentDate: Date
    private var openEntry: (UUID) -> Void
    private var refreshAction: () async -> Void
    private var dateSettledAction: (Date) -> Void
    private var isTransitioning = false
    private var pendingDate: Date?

    init(
        store: AppStore,
        selectedDate: Date,
        openEntry: @escaping (UUID) -> Void,
        refreshAction: @escaping () async -> Void,
        dateSettledAction: @escaping (Date) -> Void
    ) {
        self.store = store
        currentDate = store.startOfJournalDay(for: selectedDate)
        self.openEntry = openEntry
        self.refreshAction = refreshAction
        self.dateSettledAction = dateSettledAction

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "journalPageViewController"
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
            [makePage(for: currentDate)],
            direction: .forward,
            animated: false
        )
    }

    func configure(
        store: AppStore,
        selectedDate: Date,
        openEntry: @escaping (UUID) -> Void,
        refreshAction: @escaping () async -> Void,
        dateSettledAction: @escaping (Date) -> Void
    ) {
        self.store = store
        self.openEntry = openEntry
        self.refreshAction = refreshAction
        self.dateSettledAction = dateSettledAction

        let normalizedDate = store.startOfJournalDay(for: selectedDate)
        guard normalizedDate != currentDate else {
            refreshVisiblePage()
            return
        }

        setCurrentDate(normalizedDate, animated: true)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? JournalDayHostingController else {
            return nil
        }

        return makePage(for: store.journalDate(byAdding: -1, to: page.date))
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? JournalDayHostingController else {
            return nil
        }

        return makePage(for: store.journalDate(byAdding: 1, to: page.date))
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
           let visiblePage = pageViewController.viewControllers?.first as? JournalDayHostingController {
            currentDate = store.startOfJournalDay(for: visiblePage.date)
            dateSettledAction(currentDate)
        } else {
            refreshVisiblePage()
        }

        applyPendingDateIfNeeded()
    }

    private func setCurrentDate(_ date: Date, animated: Bool) {
        guard date != currentDate else {
            refreshVisiblePage()
            return
        }

        guard !isTransitioning else {
            pendingDate = date
            return
        }

        isTransitioning = animated
        let direction = date > currentDate
            ? UIPageViewController.NavigationDirection.forward
            : UIPageViewController.NavigationDirection.reverse
        let page = makePage(for: date)

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
            self.currentDate = date
            self.applyPendingDateIfNeeded()
        }
    }

    private func applyPendingDateIfNeeded() {
        guard let pendingDate else {
            return
        }

        self.pendingDate = nil
        setCurrentDate(pendingDate, animated: true)
    }

    private func refreshVisiblePage() {
        guard let visiblePage = pageViewController.viewControllers?.first as? JournalDayHostingController else {
            return
        }

        visiblePage.update(
            store: store,
            openEntry: openEntry,
            refreshAction: refreshAction
        )
    }

    private func makePage(for date: Date) -> JournalDayHostingController {
        JournalDayHostingController(
            date: store.startOfJournalDay(for: date),
            store: store,
            openEntry: openEntry,
            refreshAction: refreshAction
        )
    }
}

private final class JournalDayHostingController: UIHostingController<JournalDayPageView> {
    let date: Date

    init(
        date: Date,
        store: AppStore,
        openEntry: @escaping (UUID) -> Void,
        refreshAction: @escaping () async -> Void
    ) {
        self.date = date
        super.init(
            rootView: JournalDayPageView(
                store: store,
                date: date,
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
        rootView = JournalDayPageView(
            store: store,
            date: date,
            openEntry: openEntry,
            refreshAction: refreshAction
        )
    }
}

private struct JournalDayPageView: View {
    @Bindable var store: AppStore

    let date: Date
    let openEntry: (UUID) -> Void
    let refreshAction: () async -> Void

    private var entries: [EntryRecord] {
        store.journalEntries(for: date)
    }

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No journal entries on this day",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Try another date, or add a new entry for today.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(entries) { entry in
                    Button {
                        openEntry(entry.id)
                    } label: {
                        EntryCardView(
                            entry: entry,
                            imageURL: store.imageURL(for: entry),
                            imageRefreshVersion: store.imageRefreshVersion,
                            dateText: entry.journalCardDateTitle
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .contentShape(Rectangle())
        .accessibilityIdentifier("journalDayPage-\(Calendar.current.dayIdentifier(for: date))")
        .refreshable {
            await refreshAction()
        }
    }
}
