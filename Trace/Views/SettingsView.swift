import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showWipeConfirmation = false
    @State private var unrecognizedApps: [NSRunningApplication] = []

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

            if !unrecognizedApps.isEmpty {
                Section {
                    ForEach(unrecognizedApps, id: \.bundleIdentifier) { app in
                        LabeledContent(app.localizedName ?? app.bundleIdentifier ?? "Unknown") {
                            Text(app.bundleIdentifier ?? "")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Unrecognized Apps")
                } footer: {
                    Text("These running apps aren't in Trace's known list. URL and session grouping may be limited for them.")
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
        .frame(width: 420, height: 380)
        .onAppear {
            appState.checkAccessibility()
            loadUnrecognizedApps()
        }
    }

    private func loadUnrecognizedApps() {
        let registry = BundleRegistry.shared
        unrecognizedApps = NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleId = app.bundleIdentifier,
                  app.activationPolicy == .regular else { return false }
            return !registry.allKnown.contains(bundleId)
        }
    }
}
