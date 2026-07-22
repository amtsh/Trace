import AppKit

final class RestoreService {
    func restore(_ session: Session) async -> RestoreResult {
        var restored: [String] = []
        var failed: [(item: String, reason: String)] = []

        for app in session.apps {
            let result = await restore(app: app)
            restored.append(contentsOf: result.restored)
            failed.append(contentsOf: result.failed)
        }

        return RestoreResult(restored: restored, failed: failed)
    }

    func restore(app: SessionApp) async -> RestoreResult {
        var restored: [String] = []
        var failed: [(item: String, reason: String)] = []

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: app.bundleId
        ) else {
            return RestoreResult(restored: [], failed: [(app.appName, "App not found")])
        }

        do {
            try await NSWorkspace.shared.openApplication(
                at: appURL, configuration: .init()
            )
            restored.append(app.appName)
        } catch {
            return RestoreResult(restored: [], failed: [(app.appName, error.localizedDescription)])
        }

        try? await Task.sleep(for: .milliseconds(300))

        if Self.browserBundles.contains(app.bundleId) {
            for url in app.urls {
                if openBrowserTab(bundleId: app.bundleId, url: url) {
                    restored.append(DisplayURL.format(url))
                } else {
                    failed.append((DisplayURL.format(url), "Couldn't open tab"))
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        } else {
            let fileURLs = app.urls.compactMap { urlString -> URL? in
                guard urlString.hasPrefix("file://") else { return nil }
                return URL(string: urlString)
            }
            for fileURL in fileURLs.prefix(5) {
                do {
                    let config = NSWorkspace.OpenConfiguration()
                    try await NSWorkspace.shared.open(
                        [fileURL], withApplicationAt: appURL, configuration: config
                    )
                    restored.append(fileURL.lastPathComponent)
                } catch {
                    failed.append((fileURL.lastPathComponent, error.localizedDescription))
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        return RestoreResult(restored: restored, failed: failed)
    }

    // MARK: - Private

    private static let browserBundles: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    private func openBrowserTab(bundleId: String, url: String) -> Bool {
        let escaped = url
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        switch bundleId {
        case "com.apple.Safari":
            script = """
                tell application "Safari"
                    activate
                    if (count of windows) is 0 then
                        make new document with properties {URL:"\(escaped)"}
                    else
                        tell front window to set current tab to (make new tab with properties {URL:"\(escaped)"})
                    end if
                end tell
            """
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac":
            let name = switch bundleId {
                case "com.google.Chrome": "Google Chrome"
                case "com.brave.Browser": "Brave Browser"
                default: "Microsoft Edge"
            }
            script = """
                tell application "\(name)"
                    activate
                    if (count of windows) is 0 then
                        make new window
                        set URL of active tab of front window to "\(escaped)"
                    else
                        tell front window to make new tab with properties {URL:"\(escaped)"}
                    end if
                end tell
            """
        default:
            return false
        }

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }
}
