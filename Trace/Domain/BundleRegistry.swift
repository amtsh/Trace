import Foundation

/// Central registry for all known bundle ID categories.
/// Loaded once from BundleConfig.plist; falls back to hardcoded defaults.
struct BundleRegistry {
    let browsers: Set<String>
    let terminals: Set<String>
    let chatApps: Set<String>
    let ignored: Set<String>

    static let shared: BundleRegistry = {
        if let url = Bundle.main.url(forResource: "BundleConfig", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] {
            return BundleRegistry(
                browsers: Set(dict["browsers"] ?? []),
                terminals: Set(dict["terminals"] ?? []),
                chatApps: Set(dict["chatApps"] ?? []),
                ignored: Set(dict["ignored"] ?? [])
            )
        }
        return .defaults
    }()

    static let defaults = BundleRegistry(
        browsers: [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "company.thebrowser.dia",
            "org.mozilla.firefox",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
            "com.kagi.orion",
        ],
        terminals: [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "io.alacritty",
            "net.kovidgoyal.kitty",
            "com.mitchellh.ghostty",
            "io.tabbyml.tabby",
        ],
        chatApps: [
            "com.anthropic.claude",
            "com.anthropic.claudefordesktop",
            "com.openai.chat",
            "ai.perplexity.mac",
        ],
        ignored: [
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
    )

    var allKnown: Set<String> {
        browsers.union(terminals).union(chatApps).union(ignored)
    }
}
