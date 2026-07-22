import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var hasRequested = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.primary)

            VStack(spacing: 6) {
                Text("\"What was I doing?\"")
                    .font(.title2.weight(.semibold))
                Text("Trace remembers, so you don't have to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                valueRow("arrow.counterclockwise", "Remembers your context", "Apps, windows, and tabs you had open")
                valueRow("arrow.uturn.backward", "Takes you back", "Reopen everything with one click")
                valueRow("eye.slash", "Private by design", "No screenshots, keystrokes, or content")
                valueRow("internaldrive", "Fully offline", "Stays on this Mac, auto-deletes after 7 days")
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 12) {
                if appState.hasAccessibilityPermission {
                    Button { appState.completeOnboarding() } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Needed to read window titles — without it, only app names are recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        appState.requestAccessibility()
                        hasRequested = true
                    } label: {
                        Text("Grant Accessibility Access")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if hasRequested {
                        Button("I've granted it — check again") {
                            appState.checkAccessibility()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("Continue without (app names only)") {
                        appState.completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
    }

    private func valueRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
