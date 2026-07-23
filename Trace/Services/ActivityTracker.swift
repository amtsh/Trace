import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog

final class ActivityTracker: ActivityTracking {
    private let database: SnapshotDatabase
    private let ownBundleId: String

    private var appSwitchObserver: (any NSObjectProtocol)?
    private var sleepObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    private var periodicTimer: Timer?
    private var lastContext: CapturedContext?
    private var pendingActivationCapture: Task<Void, Never>?
    private(set) var isRunning = false

    private static let activationDwellSeconds: Double = 10
    private static let idleThresholdSeconds: Double = 60

    init(database: SnapshotDatabase) {
        self.database = database
        self.ownBundleId = Bundle.main.bundleIdentifier ?? ""
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleAppSwitch()
        }

        startPeriodicTimer()

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.periodicTimer?.invalidate()
            self?.periodicTimer = nil
            self?.pendingActivationCapture?.cancel()
            self?.pendingActivationCapture = nil
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.lastContext = nil
            self?.startPeriodicTimer()
            Task { @MainActor in await self?.captureSnapshot() }
        }

        Task { await captureSnapshot() }
    }

    func stop() {
        isRunning = false
        periodicTimer?.invalidate()
        periodicTimer = nil
        pendingActivationCapture?.cancel()
        pendingActivationCapture = nil
        [appSwitchObserver, sleepObserver, wakeObserver]
            .compactMap { $0 }
            .forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appSwitchObserver = nil
        sleepObserver = nil
        wakeObserver = nil
    }

    var onSnapshotCaptured: (() -> Void)?
    var onPollCompleted: (() -> Void)?

    // MARK: - Private

    /// On every app switch: immediately record a lightweight snapshot (no AX),
    /// then schedule the full-context dwell capture after activationDwellSeconds.
    private func handleAppSwitch() {
        Task { @MainActor in await captureAppSwitchSnapshot() }
        scheduleActivationCapture()
    }

    /// Lightweight snapshot: captures app identity only, no AX calls.
    /// Ensures every app switch is logged even if the user switches away quickly.
    private func captureAppSwitchSnapshot() async {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              bundleId != ownBundleId,
              !Self.ignoredBundles.contains(bundleId)
        else { return }

        let appName = frontApp.localizedName ?? bundleId
        let ctx = CapturedContext(
            appName: appName,
            appBundle: bundleId,
            windowTitle: nil,
            documentURL: nil,
            isIdle: false
        )

        if let last = lastContext, last.appBundle == ctx.appBundle { return }

        lastContext = ctx
        do {
            try await database.save(ctx)
        } catch {
            Logger.tracking.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
        }
        onSnapshotCaptured?()
    }

    private func scheduleActivationCapture() {
        pendingActivationCapture?.cancel()
        pendingActivationCapture = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.activationDwellSeconds))
            guard !Task.isCancelled else { return }
            await self?.captureSnapshot()
        }
    }

    private func startPeriodicTimer() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.captureSnapshot() }
        }
    }

    private func captureSnapshot() async {
        if IsSecureEventInputEnabled() { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              bundleId != ownBundleId,
              !Self.ignoredBundles.contains(bundleId)
        else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled { return }

        let appName = frontApp.localizedName ?? bundleId
        let idleSeconds = min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
        )
        if idleSeconds > Self.idleThresholdSeconds { return }

        var windowTitle: String?
        var documentURL: String?

        if PermissionManager.hasAccessibilityPermission {
            let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
            windowTitle = sanitized(axWindowAttribute(axApp, kAXTitleAttribute as String))
            documentURL = sanitized(axWindowAttribute(axApp, kAXDocumentAttribute as String))

            if !isMeaningfulTitle(windowTitle, appName: appName) {
                windowTitle = sanitized(bestWindowTitle(axApp, appName: appName)) ?? windowTitle
            }

            if !isMeaningfulTitle(windowTitle, appName: appName) {
                windowTitle = sanitized(webContentTitle(axApp)) ?? sanitized(webContentTitleFromAllWindows(axApp))
            }

            if documentURL == nil, Self.isChatBundle(bundleId) {
                documentURL = sanitized(webContentURL(axApp)) ?? sanitized(webContentURLFromAllWindows(axApp))
            }

            if !isMeaningfulTitle(windowTitle, appName: appName),
               let url = documentURL,
               let derived = titleFromChatURL(url) {
                windowTitle = derived
            }

            if bundleId == Self.githubDesktopBundle {
                if documentURL == nil {
                    documentURL = sanitized(githubDesktopRepositoryPath(axApp))
                }
                if !isMeaningfulTitle(windowTitle, appName: appName) {
                    windowTitle = sanitized(githubDesktopContext(axApp, appName: appName))
                        ?? titleFromRepositoryPath(documentURL)
                }
            }
        }

        if documentURL == nil, Self.browserBundles.contains(bundleId) {
            documentURL = browserURL(bundleId: bundleId)
        }

        let ctx = CapturedContext(
            appName: appName,
            appBundle: bundleId,
            windowTitle: windowTitle,
            documentURL: documentURL,
            isIdle: false
        )

        onPollCompleted?()

        if let last = lastContext,
           last.appBundle == ctx.appBundle,
           last.windowTitle == ctx.windowTitle,
           last.documentURL == ctx.documentURL {
            return
        }

        lastContext = ctx
        do {
            try await database.save(ctx)
        } catch {
            Logger.tracking.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
        }
        onSnapshotCaptured?()
    }

    // MARK: - Accessibility helpers

    private func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isMeaningfulTitle(_ title: String?, appName: String) -> Bool {
        guard let title = sanitized(title) else { return false }
        return title.caseInsensitiveCompare(appName) != .orderedSame
    }

    static func isChatBundle(_ bundleId: String) -> Bool {
        chatBundles.contains(bundleId) || bundleId.hasPrefix("ai.perplexity")
    }

    private static let githubDesktopBundle = "com.github.GitHubClient"

    private func githubDesktopContext(_ axApp: AXUIElement, appName: String) -> String? {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        var candidates: [String] = []
        for window in windows.prefix(2) {
            collectAccessibilityTexts(from: window, depth: 6, appName: appName, into: &candidates)
        }

        return pickGitHubDesktopCandidate(from: candidates)
    }

    private func githubDesktopRepositoryPath(_ axApp: AXUIElement) -> String? {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows.prefix(2) {
            if let path = findRepositoryPath(in: window, depth: 6) {
                return path
            }
        }
        return nil
    }

    private func findRepositoryPath(in element: AXUIElement, depth: Int) -> String? {
        guard depth > 0 else { return nil }

        if let url = sanitized(axStringAttribute(element, "AXURL")),
           url.hasPrefix("file://") {
            return url
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success, let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children.prefix(10) {
            if let path = findRepositoryPath(in: child, depth: depth - 1) {
                return path
            }
        }
        return nil
    }

    private func collectAccessibilityTexts(
        from element: AXUIElement,
        depth: Int,
        appName: String,
        into candidates: inout [String]
    ) {
        guard depth > 0 else { return }

        if let title = sanitized(axStringAttribute(element, kAXTitleAttribute as String)),
           isMeaningfulTitle(title, appName: appName) {
            candidates.append(title)
        }

        if let value = sanitized(axStringAttribute(element, kAXValueAttribute as String)),
           isMeaningfulTitle(value, appName: appName) {
            candidates.append(value)
        }

        if let description = sanitized(axStringAttribute(element, kAXDescriptionAttribute as String)),
           isMeaningfulTitle(description, appName: appName) {
            candidates.append(description)
        }

        var roleRef: AnyObject?
        let role = (AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleRef
        ) == .success) ? roleRef as? String : nil

        if role == "AXStaticText",
           let value = sanitized(axStringAttribute(element, kAXValueAttribute as String)),
           isMeaningfulTitle(value, appName: appName) {
            candidates.append(value)
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success, let children = childrenRef as? [AXUIElement] else { return }

        for child in children.prefix(10) {
            collectAccessibilityTexts(from: child, depth: depth - 1, appName: appName, into: &candidates)
        }
    }

    private func axStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func pickGitHubDesktopCandidate(from candidates: [String]) -> String? {
        let blocked = [
            "changes", "history", "repository", "branch", "fetch origin", "pull origin",
            "push origin", "open in", "show in finder", "view on github", "current branch",
            "publish repository", "create pull request", "stash all changes",
        ]

        let scored = candidates.compactMap { raw -> (String, Int)? in
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2, text.count <= 64 else { return nil }
            let lower = text.lowercased()
            if blocked.contains(where: { lower == $0 || lower.hasPrefix($0) }) { return nil }
            if lower == "github desktop" { return nil }

            var score = 0
            if text.contains("/") { score += 1 }
            if text.contains(" — ") || text.contains(" - ") { score += 4 }
            if text.split(separator: " ").count == 1 { score += 3 }
            if text.first?.isLowercase == false { score += 1 }
            return (text, score)
        }

        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    private func titleFromRepositoryPath(_ urlString: String?) -> String? {
        guard let urlString, urlString.hasPrefix("file://") else { return nil }
        return SessionBuilder.projectFromURL(urlString)
    }

    private func axWindowAttribute(_ app: AXUIElement, _ attr: String) -> String? {
        var window: AnyObject?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &window
        ) == .success else { return nil }

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement, attr as CFString, &value
        ) == .success else { return nil }

        return value as? String
    }

    private func bestWindowTitle(_ axApp: AXUIElement, appName: String) -> String? {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows {
            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(
                window, kAXTitleAttribute as CFString, &titleRef
            ) == .success, let title = titleRef as? String,
               !title.isEmpty, title != appName {
                return title
            }
        }
        return nil
    }

    private func webContentTitle(_ axApp: AXUIElement) -> String? {
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success else { return nil }
        return findWebAreaTitle(windowRef as! AXUIElement, depth: 8)
    }

    private func webContentURL(_ axApp: AXUIElement) -> String? {
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success else { return nil }
        return findWebAreaURL(windowRef as! AXUIElement, depth: 8)
    }

    private func webContentTitleFromAllWindows(_ axApp: AXUIElement) -> String? {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows.prefix(4) {
            if let title = findWebAreaTitle(window, depth: 8) {
                return title
            }
        }
        return nil
    }

    private func webContentURLFromAllWindows(_ axApp: AXUIElement) -> String? {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows.prefix(4) {
            if let url = findWebAreaURL(window, depth: 8) {
                return url
            }
        }
        return nil
    }

    private func titleFromChatURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }

        if host.contains("perplexity") {
            let parts = url.path.split(separator: "/").map(String.init)
            if let slug = parts.last, !slug.isEmpty, parts.contains(where: { $0 == "search" || $0 == "thread" }) {
                return humanizeURLSlug(slug)
            }
        }

        if host.contains("claude.ai") || host.contains("chatgpt.com") || host.contains("openai.com") {
            return nil
        }

        return nil
    }

    private func humanizeURLSlug(_ slug: String) -> String {
        slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findWebAreaURL(_ element: AXUIElement, depth: Int) -> String? {
        guard depth > 0 else { return nil }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success, let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children.prefix(8) {
            var roleRef: AnyObject?
            if AXUIElementCopyAttributeValue(
                child, kAXRoleAttribute as CFString, &roleRef
            ) == .success, (roleRef as? String) == "AXWebArea" {
                var urlRef: AnyObject?
                if AXUIElementCopyAttributeValue(
                    child, "AXURL" as CFString, &urlRef
                ) == .success {
                    if let url = urlRef as? NSURL, let absolute = url.absoluteString,
                       absolute.hasPrefix("http") {
                        return absolute
                    }
                    if let string = urlRef as? String, string.hasPrefix("http") {
                        return string
                    }
                }
            }
            if let found = findWebAreaURL(child, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    private func findWebAreaTitle(_ element: AXUIElement, depth: Int) -> String? {
        guard depth > 0 else { return nil }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success, let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children.prefix(8) {
            var roleRef: AnyObject?
            if AXUIElementCopyAttributeValue(
                child, kAXRoleAttribute as CFString, &roleRef
            ) == .success, (roleRef as? String) == "AXWebArea" {
                var titleRef: AnyObject?
                if AXUIElementCopyAttributeValue(
                    child, kAXTitleAttribute as CFString, &titleRef
                ) == .success, let title = titleRef as? String, !title.isEmpty {
                    return title
                }
            }
            if let found = findWebAreaTitle(child, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - Bundle lists

    static let ignoredBundles: Set<String> = [
        "com.apple.UserNotificationCenter",
        "com.apple.universalAccessAuthWarn",
        "com.apple.SecurityAgent",
        "com.apple.loginwindow",
        "com.apple.screencaptureui",
        "com.apple.ScreenSaver.Engine",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.ScreenContinuity",
        "app.glaze.macos.main",
    ]

    static let browserBundles: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    static let chatBundles: Set<String> = [
        "com.anthropic.claude",
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
        "ai.perplexity.mac",
        "ai.perplexity.macv3",
    ]

    private func browserURL(bundleId: String) -> String? {
        let script: String
        switch bundleId {
        case "com.apple.Safari":
            script = """
                tell application "Safari"
                    if (count of windows) > 0 then return URL of current tab of front window
                end tell
            """
        case "com.google.Chrome":
            script = "tell application \"Google Chrome\" to return URL of active tab of front window"
        case "com.brave.Browser":
            script = "tell application \"Brave Browser\" to return URL of active tab of front window"
        case "com.microsoft.edgemac":
            script = "tell application \"Microsoft Edge\" to return URL of active tab of front window"
        case "company.thebrowser.Browser":
            script = "tell application \"Arc\" to return URL of active tab of front window"
        case "company.thebrowser.dia":
            script = "tell application \"Dia\" to return URL of active tab of front window"
        default:
            return nil
        }
        var error: NSDictionary?
        return NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
    }
}
