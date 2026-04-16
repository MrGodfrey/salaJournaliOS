import Observation
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            JournalView(store: store)
                .tabItem {
                    Label("Journal", systemImage: "book.closed")
                }
                .tag(AppTab.journal)

            CalendarView(store: store)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(AppTab.calendar)

            SearchView(store: store)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)

            BlogView(store: store)
                .tabItem {
                    Label("Blog", systemImage: "doc.text.image")
                }
                .tag(AppTab.blog)
        }
        .tint(Color.indigo)
        .task {
            await store.loadIfNeeded()
        }
        .overlay(alignment: .center) {
            if store.isBusy {
                ProgressView("处理中...")
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sheet(item: $store.editorSession) { session in
            EntryEditorView(
                store: store,
                session: session
            )
        }
        .sheet(isPresented: $store.isShowingSettings) {
            SettingsView(store: store)
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { value in
                    if !value {
                        store.alertMessage = nil
                    }
                }
            )
        ) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

#Preview {
    ContentView(
        store: AppStore.preview()
    )
}
