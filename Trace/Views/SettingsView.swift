import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showWipeConfirmation = false

    var body: some View {
        Form {
            Section("Tracking") {
                Toggle("Enable activity tracking", isOn: .init(
                    get: { appState.isTracking },
                    set: { _ in appState.toggleTracking() }
                ))
            }

            Section("Privacy") {
                LabeledContent("Accessibility") {
                    if appState.hasAccessibilityPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Settings") {
                            appState.requestAccessibility()
                        }
                    }
                }

                Button("Delete All Data", role: .destructive) {
                    showWipeConfirmation = true
                }
                .confirmationDialog(
                    "Delete all Trace data?",
                    isPresented: $showWipeConfirmation
                ) {
                    Button("Delete Everything", role: .destructive) {
                        Task { await appState.wipeAllData() }
                    }
                } message: {
                    Text("This permanently deletes all recorded activity. This cannot be undone.")
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                LabeledContent("Data") {
                    Text("Local only, auto-deleted after 7 days")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .onAppear { appState.checkAccessibility() }
    }
}
