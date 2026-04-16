import Observation
import SwiftUI

struct JournalView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []
    @State private var pendingDeletion: EntryRecord?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if store.journalSections.isEmpty {
                    ContentUnavailableView(
                        "这一天还没有 Journal",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("换一个日期，或者为今天补一条新的记录。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.journalSections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                NavigationLink(value: EntryDestination.read(entry.id)) {
                                    EntryCardView(
                                        entry: entry,
                                        imageURL: store.imageURL(for: entry),
                                        showWeekdayBelow: true
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
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
                        } header: {
                            Text(String(section.year))
                                .font(.title2.bold())
                                .textCase(nil)
                                .padding(.leading, 4)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .contentShape(Rectangle())
            .accessibilityIdentifier("journalScreen")
            .navigationTitle(store.selectedDateTitle)
            .navigationBarTitleDisplayMode(.inline)
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
                }
            }
            .overlay(alignment: .bottomTrailing) {
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
                .disabled(!store.canEditRepository)
                .padding(.trailing, 24)
                .padding(.bottom, 20)
                .accessibilityIdentifier("addJournalEntryButton")
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 32)
                    .onEnded(handleJournalSwipe(_:))
            )
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

    private func handleJournalSwipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        let vertical = value.translation.height

        guard abs(horizontal) > max(64, abs(vertical) * 1.3) else {
            return
        }

        store.moveSelectedDate(by: horizontal < 0 ? 1 : -1)
    }
}
