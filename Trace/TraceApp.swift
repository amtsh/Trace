import SwiftUI

@main
struct TraceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SidebarLauncher()
                .frame(width: 1, height: 1)
        } label: {
            Label("Trace", systemImage: "inset.filled.rectangle.badge.record")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }
}

/// Root alert for unrecoverable database errors.
struct DatabaseErrorAlert: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        @Bindable var appState = appState
        content
            .alert(
                "Database Error",
                isPresented: .init(
                    get: { appState.databaseError != nil },
                    set: { if !$0 { appState.databaseError = nil } }
                )
            ) {
                Button("Reset Database", role: .destructive) {
                    appState.resetDatabase()
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            } message: {
                Text(appState.databaseError ?? "An unknown error occurred.")
            }
    }
}
