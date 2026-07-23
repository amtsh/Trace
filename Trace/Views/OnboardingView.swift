import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var hasRequested = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: .blue.opacity(0.3), radius: 10, y: 4)

            VStack(spacing: 6) {
                Text("\"What was I doing?\"")
                    .font(.title2.weight(.bold))
                Text("Trace remembers, so you don't have to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                valueRow("arrow.counterclockwise", .blue,
                         "Remembers your context",
                         "Apps, windows, and tabs you had open")
                valueRow("arrow.uturn.backward", .indigo,
                         "Takes you back",
                         "Reopen everything with one click")
                valueRow("hand.raised.fill", .teal,
                         "Private by design",
                         "No screenshots, keystrokes, or content")
                valueRow("internaldrive", .gray,
                         "Fully offline",
                         "Stays on this Mac, auto-deletes after 7 days")
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(spacing: 12) {
                if appState.hasAccessibilityPermission {
                    Button { appState.completeOnboarding() } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
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
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    if hasRequested {
                        Button("I've granted it — check again") {
                            appState.checkAccessibility()
                        }
                        .buttonStyle(.glass)
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

    private func valueRow(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
