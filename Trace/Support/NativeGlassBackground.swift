import AppKit
import SwiftUI

/// AppKit liquid glass surface — renders correctly in borderless panels where
/// SwiftUI's `.glassEffect()` falls back to a flat tint.
struct NativeGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tintOpacity: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSGlassEffectView) {
        view.cornerRadius = cornerRadius
        view.style = .regular
        view.tintColor = NSColor.black.withAlphaComponent(tintOpacity)
        view.clipsToBounds = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
