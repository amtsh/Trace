import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class ActivityTracker {
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
        try? await database.append(ctx)
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
            windowTitle = axWindowAttribute(axApp, kAXTitleAttribute as String)
            documentURL = axWindowAttribute(axApp, kAXDocumentAttribute as String)

            if windowTitle == nil || windowTitle == appName {
                windowTitle = bestWindowTitle(axApp, appName: appName) ?? windowTitle
            }

            if windowTitle == nil || windowTitle == appName {
                if let contentTitle = webContentTitle(axApp) {
                    windowTitle = contentTitle
                }
            }

            if documentURL == nil, Self.chatBundles.contains(bundleId) {
                documentURL = webContentURL(axApp)
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
        try? await database.append(ctx)
        onSnapshotCaptured?()
    }

    // MARK: - Accessibility helpers

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
        return findWebAreaTitle(windowRef as! AXUIElement, depth: 5)
    }

    private func webContentURL(_ axApp: AXUIElement) -> String? {
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success else { return nil }
        return findWebAreaURL(windowRef as! AXUIElement, depth: 6)
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
