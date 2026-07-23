import SwiftUI

// MARK: - Design System
// Single source of truth for all visual constants in Trace.
// Import this file and reference tokens instead of hardcoding values.

enum DS {

    // MARK: Spacing
    enum Spacing {
        /// 4pt — tight inline gap (icon rows, badge clusters)
        static let xxs: CGFloat = 4
        /// 6pt — small gap (HStack icons, caption rows)
        static let xs: CGFloat = 6
        /// 8pt — standard component gap
        static let sm: CGFloat = 8
        /// 10pt — section inner padding, divider leading inset base
        static let md: CGFloat = 10
        /// 12pt — card outer margin, panel edge margin
        static let lg: CGFloat = 12
        /// 14pt — card inner padding
        static let xl: CGFloat = 14
        /// 16pt — list bottom padding
        static let xxl: CGFloat = 16
        /// 24pt — onboarding section padding
        static let xxxl: CGFloat = 24
    }

    // MARK: Corner radius
    enum Radius {
        /// Capsule-style tags and pills
        static let pill: CGFloat = 999
        /// Small chips (accessibility banner)
        static let sm: CGFloat = 8
        /// Session cards and content areas
        static let card: CGFloat = 16
        /// Sidebar panel / onboarding sheet
        static let panel: CGFloat = 22
        /// App icon badge: multiply by icon size (0.22)
        static let iconBadgeFactor: CGFloat = 0.22
        /// Onboarding hero icon
        static let hero: CGFloat = 16
    }

    // MARK: Icon sizes
    enum IconSize {
        /// Secondary app icons in collapsed card row
        static let secondary: CGFloat = 18
        /// App detail row icon
        static let detail: CGFloat = 24
        /// Primary app icon in collapsed card header
        static let primary: CGFloat = 40
        /// Onboarding hero icon container
        static let hero: CGFloat = 64
        /// Menu/overflow icon glyph inside button
        static let glyphSm: CGFloat = 8
        /// Restore action chevron glyph
        static let glyphMd: CGFloat = 11
        /// Chevron disclosure glyph in card header
        static let chevron: CGFloat = 9
        /// Poll countdown ring
        static let ring: CGFloat = 10
    }

    // MARK: Opacity
    enum Opacity {
        /// Card shadow
        static let shadowCard: Double = 0.35
        /// Day label / header text shadow
        static let shadowText: Double = 0.4
        /// Accessibility banner background tint
        static let accessoryBannerBg: Double = 0.12
        /// Section label in expanded card
        static let sectionLabel: Double = 0.55
        /// Context lines (non-path) in detail rows
        static let contextLine: Double = 0.6
        /// Menu button label
        static let menuLabel: Double = 0.75
        /// Menu button background
        static let menuBg: Double = 0.55
        /// Onboarding icon shadow
        static let heroShadow: Double = 0.3
    }

    // MARK: Animation
    enum Animation {
        /// Card expand / collapse
        static let cardExpand: SwiftUI.Animation = .smooth(duration: 0.25)
        /// Hover state fade
        static let hover: SwiftUI.Animation = .smooth(duration: 0.15)
        /// Hide-button appear/disappear
        static let hideButton: SwiftUI.Animation = .smooth(duration: 0.2)
        /// Sidebar slide-in
        static let panelShow: Double = 0.25
        /// Sidebar slide-out
        static let panelHide: Double = 0.2
    }

    // MARK: Shadow
    enum Shadow {
        static let cardRadius: CGFloat = 8
        static let cardY: CGFloat = 4
        static let textRadius: CGFloat = 3
        static let textY: CGFloat = 1
        static let heroRadius: CGFloat = 10
        static let heroY: CGFloat = 4
    }

    // MARK: Sidebar
    enum Sidebar {
        static let width: CGFloat = 380
        static let edgeMargin: CGFloat = 12
        static let panelShowDelay: TimeInterval = 0.1
    }

    // MARK: Polling
    enum Poll {
        static let intervalSeconds: TimeInterval = 30
        static let ringLineWidth: CGFloat = 1.5
        static let timelineRefreshSeconds: TimeInterval = 30
    }

    // MARK: Settings
    enum Settings {
        static let windowWidth: CGFloat = 420
        static let windowHeight: CGFloat = 380
    }

    // MARK: Card limits
    enum Card {
        /// Max secondary app icons shown in collapsed card row
        static let maxSecondaryIcons: Int = 5
        /// Max context lines shown per app in detail row
        static let maxContextLines: Int = 3
        /// Max file URLs restored per non-browser app
        static let maxFileRestores: Int = 5
        /// Max web URLs restored per non-browser app
        static let maxWebRestores: Int = 3
    }
}
