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
                ProgressView("Processing...")
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .overlay {
            if store.isAuthenticationRequired {
                AppLockOverlay(
                    isAuthenticating: store.isAuthenticating
                ) {
                    Task {
                        await store.unlockIfNeeded()
                    }
                }
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
            "Notice",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { value in
                    if !value {
                        store.alertMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
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

private struct AppLockOverlay: View {
    let isAuthenticating: Bool
    let unlockAction: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    Text("Biometric lock is enabled")
                        .font(.title3.bold())

                    Text("Authenticate to view the current repository.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Button(isAuthenticating ? L10n.string("Authenticating...") : L10n.string("Try Again")) {
                    unlockAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
            .padding(24)
        }
        .transition(.opacity)
    }
}
