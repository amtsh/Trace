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
