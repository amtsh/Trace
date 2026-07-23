import AppKit
import SwiftUI

final class SidebarPanelController {
    static let shared = SidebarPanelController()

    private var appState: AppState?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SidebarRootView>?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var swipeMonitor: Any?
    private var activeScreen: NSScreen?
    private var isOpen = false
    private var isDismissing = false
    private var swipeAccumulated: CGFloat = 0
    private var panelRestX: CGFloat = 0
    private static let swipeDismissThreshold: CGFloat = 80

    private init() {}

    func configure(appState: AppState) {
        self.appState = appState
    }

    static func screenAtMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func toggle(on screen: NSScreen) {
        isOpen ? hide() : show(on: screen)
    }

    func show(on screen: NSScreen) {
        guard let appState, !isOpen else { return }

        isOpen = true
        activeScreen = screen

        let endFrame = panelFrame(on: screen)
        let visible = screen.visibleFrame
        let startFrame = NSRect(
            x: visible.maxX,
            y: endFrame.minY,
            width: DS.Sidebar.width,
            height: endFrame.height
        )

        if panel == nil {
            let newPanel = NSPanel(
                contentRect: startFrame,
                styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .popUpMenu
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.hidesOnDeactivate = false
            newPanel.isReleasedWhenClosed = false

            let root = SidebarRootView(appState: appState)
            let hv = NSHostingView(rootView: root)
            hv.frame = NSRect(origin: .zero, size: endFrame.size)
            hv.autoresizingMask = [.width, .height]
            newPanel.contentView = hv

            self.panel = newPanel
            self.hostingView = hv
        }

        guard let panel else {
            isOpen = false
            return
        }

        removeEventMonitors()
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()

        panelRestX = endFrame.origin.x

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DS.Animation.panelShow
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + DS.Sidebar.panelShowDelay) {
                guard self?.isOpen == true else { return }
                self?.installEventMonitors()
            }
        }
    }

    func hide() {
        animateDismiss()
    }

    // MARK: - Private

    private func animateDismiss() {
        guard isOpen, !isDismissing, let panel, let screen = activeScreen else { return }

        isOpen = false
        isDismissing = true
        removeClickAndKeyMonitors()

        let offScreenX = screen.visibleFrame.maxX
        let remainingDistance = offScreenX - panel.frame.origin.x
        let fullDistance = offScreenX - panelRestX
        let fraction = fullDistance > 0 ? remainingDistance / fullDistance : 1
        let duration = max(DS.Animation.panelHide * fraction, 0.18)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(
                NSPoint(x: offScreenX, y: panel.frame.minY)
            )
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                panel.orderOut(nil)
                self?.finishDismiss()
            }
        }
    }

    private func animateSnapBack() {
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(NSPoint(
                x: panelRestX,
                y: panel.frame.origin.y
            ))
        } completionHandler: { [weak self] in
            self?.swipeAccumulated = 0
        }
    }

    private func finishDismiss() {
        isDismissing = false
        swipeAccumulated = 0
        removeSwipeMonitor()
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let margin = DS.Sidebar.edgeMargin
        return NSRect(
            x: visible.maxX - DS.Sidebar.width - margin,
            y: visible.minY + margin,
            width: DS.Sidebar.width,
            height: visible.height - margin * 2
        )
    }

    private func installEventMonitors() {
        removeEventMonitors()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isOpen, let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.hide() }
                return nil
            }
            return event
        }

        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if self.isDismissing { return nil }

            guard self.isOpen else { return event }
            guard event.hasPreciseScrollingDeltas else { return event }
            guard panel.frame.contains(NSEvent.mouseLocation) else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let isTracking = self.swipeAccumulated > 0

            if event.phase == .ended || event.phase == .cancelled, isTracking {
                if self.swipeAccumulated >= Self.swipeDismissThreshold {
                    self.animateDismiss()
                } else {
                    self.animateSnapBack()
                }
                return nil
            }

            if !isTracking {
                guard dx > 0, abs(dx) > abs(dy) * 2 else { return event }
            }

            if dx < 0, isTracking {
                self.swipeAccumulated = max(self.swipeAccumulated + dx, 0)
                panel.setFrameOrigin(NSPoint(
                    x: self.panelRestX + self.swipeAccumulated,
                    y: panel.frame.origin.y
                ))
                return nil
            }

            if dx > 0 {
                self.swipeAccumulated += dx
                panel.setFrameOrigin(NSPoint(
                    x: self.panelRestX + self.swipeAccumulated,
                    y: panel.frame.origin.y
                ))
                return nil
            }

            return event
        }
    }

    private func removeClickAndKeyMonitors() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func removeSwipeMonitor() {
        if let swipeMonitor {
            NSEvent.removeMonitor(swipeMonitor)
            self.swipeMonitor = nil
        }
    }

    private func removeEventMonitors() {
        removeClickAndKeyMonitors()
        removeSwipeMonitor()
        swipeAccumulated = 0
        isDismissing = false
    }
}

private struct SidebarRootView: View {
    let appState: AppState

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                TimelineView()
            } else {
                OnboardingView()
                    .background(VisualEffectBackground())
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: DS.Radius.panel,
                            style: .continuous
                        )
                    )
                    .padding(DS.Sidebar.edgeMargin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(appState)
    }
}

extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
