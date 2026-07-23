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

        if BundleRegistry.shared.browsers.contains(app.bundleId) {
            for urlString in app.urls {
                guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { continue }
                // Open URL directly via NSWorkspace into the specific app — no AppleScript, no injection risk.
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                do {
                    try await NSWorkspace.shared.open(
                        [url], withApplicationAt: appURL, configuration: config
                    )
                    restored.append(DisplayURL.format(urlString))
                } catch {
                    failed.append((DisplayURL.format(urlString), error.localizedDescription))
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

            let webURLs = app.urls.compactMap { urlString -> URL? in
                guard urlString.hasPrefix("http") else { return nil }
                return URL(string: urlString)
            }
            for webURL in webURLs.prefix(3) {
                if NSWorkspace.shared.open(webURL) {
                    restored.append(DisplayURL.format(webURL.absoluteString))
                } else {
                    failed.append((DisplayURL.format(webURL.absoluteString), "Couldn't open link"))
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        return RestoreResult(restored: restored, failed: failed)
    }
}
