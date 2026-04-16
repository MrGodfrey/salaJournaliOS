import Observation
import SwiftUI

struct JournalView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if store.journalSections.isEmpty {
                        ContentUnavailableView(
                            "这一天还没有 Journal",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("换一个日期，或者为今天补一条新的记录。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        ForEach(store.journalSections) { section in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(String(section.year))
                                    .font(.title2.bold())
                                    .padding(.horizontal, 4)

                                ForEach(section.entries) { entry in
                                    EntryCardView(
                                        entry: entry,
                                        imageURL: store.imageURL(for: entry),
                                        canEdit: store.canEditRepository,
                                        showWeekdayBelow: true,
                                        onEdit: { store.showEditor(for: .journal, entry: entry) },
                                        onDelete: { Task { await store.deleteEntry(entry) } }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle(store.selectedDateTitle)
            .navigationBarTitleDisplayMode(.inline)
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
                    Text(store.selectedDateTitle)
                        .font(.headline)
                        .accessibilityIdentifier("journalHeaderDate")
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
