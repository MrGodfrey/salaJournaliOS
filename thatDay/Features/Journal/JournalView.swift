import Observation
import SwiftUI

struct JournalView: View {
    @Bindable var store: AppStore

    @State private var navigationPath: [EntryDestination] = []

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
                                        imageURL: store.imageURL(for: entry)
                                    )
                                }
                                .navigationLinkIndicatorVisibility(.hidden)
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
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
                        entry: entry
                    )
                } else {
                    ContentUnavailableView(
                        "这篇文章已经不存在",
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
        }
    }
}
