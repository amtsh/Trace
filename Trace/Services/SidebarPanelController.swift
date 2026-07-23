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
    private var panelRestX: CGFloat = 0
    private var frameAnimationTimer: Timer?

    private enum PanelEasing {
        case easeIn
        case easeOut

        func value(at progress: Double) -> CGFloat {
            let t = max(0, min(progress, 1))
            switch self {
            case .easeIn:
                return CGFloat(t * t * t)
            case .easeOut:
                let u = 1 - t
                return CGFloat(1 - u * u * u)
            }
        }
    }

    private static let swipeDismissThreshold: CGFloat = 80
    private static let velocityDismissThreshold: CGFloat = 300

    private enum SwipePhase {
        case idle
        case undecided(totalDx: CGFloat, totalDy: CGFloat)
        case tracking(accumulated: CGFloat)
        case passthrough
    }

    private var swipePhase: SwipePhase = .idle

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
        isDismissing = false
        activeScreen = screen
        appState.panelDidPresent()

        let endFrame = panelFrame(on: screen)
        let startFrame = offScreenFrame(for: endFrame, on: screen)

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
        panel.setFrame(startFrame, display: true)
        panel.orderFrontRegardless()

        panelRestX = endFrame.origin.x

        DispatchQueue.main.async { [weak self] in
            self?.animatePanelFrame(
                to: endFrame,
                duration: DS.Animation.panelShow,
                easing: .easeOut
            ) { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + DS.Sidebar.panelShowDelay) {
                    guard self?.isOpen == true else { return }
                    self?.installEventMonitors()
                    self?.hideScrollbars()
                }
            }
        }
    }

    func hide() {
        animateDismiss()
    }

    // MARK: - Private

    private func offScreenFrame(for restFrame: NSRect, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.visibleFrame.maxX,
            y: restFrame.minY,
            width: restFrame.width,
            height: restFrame.height
        )
    }

    private func animatePanelFrame(
        to targetFrame: NSRect,
        duration: TimeInterval,
        easing: PanelEasing,
        completion: (() -> Void)? = nil
    ) {
        guard let panel, duration > 0 else {
            panel?.setFrame(targetFrame, display: true)
            completion?()
            return
        }

        stopFrameAnimation()

        let startFrame = panel.frame
        let startTime = CFAbsoluteTimeGetCurrent()

        frameAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let panel = self.panel else {
                timer.invalidate()
                return
            }

            let progress = min((CFAbsoluteTimeGetCurrent() - startTime) / duration, 1)
            let t = easing.value(at: progress)

            panel.setFrame(
                NSRect(
                    x: startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * t,
                    y: startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * t,
                    width: startFrame.width + (targetFrame.width - startFrame.width) * t,
                    height: startFrame.height + (targetFrame.height - startFrame.height) * t
                ),
                display: true
            )

            guard progress >= 1 else { return }

            timer.invalidate()
            self.frameAnimationTimer = nil
            panel.setFrame(targetFrame, display: true)
            completion?()
        }

        if let frameAnimationTimer {
            RunLoop.main.add(frameAnimationTimer, forMode: .common)
        }
    }

    private func stopFrameAnimation() {
        frameAnimationTimer?.invalidate()
        frameAnimationTimer = nil
    }

    private func animateDismiss() {
        guard isOpen, !isDismissing, let panel, let screen = activeScreen else { return }

        isOpen = false
        isDismissing = true
        removeClickAndKeyMonitors()

        let endFrame = offScreenFrame(for: panel.frame, on: screen)
        let remainingDistance = endFrame.origin.x - panel.frame.origin.x
        let fullDistance = endFrame.origin.x - panelRestX
        let fraction = fullDistance > 0 ? remainingDistance / fullDistance : 1
        let duration = max(DS.Animation.panelHide * fraction, 0.18)

        animatePanelFrame(to: endFrame, duration: duration, easing: .easeIn) { [weak self] in
            panel.orderOut(nil)
            self?.finishDismiss()
        }
    }

    private func animateSnapBack() {
        guard let panel else { return }
        var restFrame = panel.frame
        restFrame.origin.x = panelRestX
        animatePanelFrame(to: restFrame, duration: 0.2, easing: .easeOut)
    }

    private func finishDismiss() {
        stopFrameAnimation()
        isDismissing = false
        swipePhase = .idle
        removeSwipeMonitor()
    }

    private func hideScrollbars() {
        guard let panel else { return }
        for case let scrollView as NSScrollView in panel.contentView?.descendants ?? [] {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
        }
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - DS.Sidebar.width,
            y: visible.minY,
            width: DS.Sidebar.width,
            height: visible.height
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
            guard let self else { return event }
            return self.handleScrollEvent(event)
        }
    }

    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard let panel, isOpen, !isDismissing else { return event }
        guard event.hasPreciseScrollingDeltas else { return event }
        guard panel.frame.contains(NSEvent.mouseLocation) else { return event }

        // Ignore momentum events entirely — only track finger-on-trackpad
        guard event.momentumPhase == [] else {
            switch swipePhase {
            case .tracking:
                return nil
            default:
                return event
            }
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        switch swipePhase {
        case .idle:
            if event.phase == .began {
                swipePhase = .undecided(totalDx: dx, totalDy: dy)
                return event
            }
            return event

        case .undecided(let totalDx, let totalDy):
            let newDx = totalDx + dx
            let newDy = totalDy + dy

            if abs(newDx) + abs(newDy) < 4 {
                swipePhase = .undecided(totalDx: newDx, totalDy: newDy)
                return event
            }

            if newDx > 0, abs(newDx) > abs(newDy) * 1.5 {
                swipePhase = .tracking(accumulated: newDx)
                panel.setFrameOrigin(NSPoint(
                    x: panelRestX + max(newDx, 0),
                    y: panel.frame.origin.y
                ))
                return nil
            } else {
                swipePhase = .passthrough
                return event
            }

        case .tracking(let accumulated):
            if event.phase == .ended || event.phase == .cancelled {
                let velocity = dx / 0.016
                if accumulated >= Self.swipeDismissThreshold || velocity >= Self.velocityDismissThreshold {
                    animateDismiss()
                } else {
                    animateSnapBack()
                }
                swipePhase = .idle
                return nil
            }

            let newAccumulated = accumulated + dx
            swipePhase = .tracking(accumulated: newAccumulated)
            panel.setFrameOrigin(NSPoint(
                x: panelRestX + max(newAccumulated, 0),
                y: panel.frame.origin.y
            ))
            return nil

        case .passthrough:
            if event.phase == .ended || event.phase == .cancelled {
                swipePhase = .idle
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
        stopFrameAnimation()
        removeClickAndKeyMonitors()
        removeSwipeMonitor()
        swipePhase = .idle
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
