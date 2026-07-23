import AppKit
import SwiftUI

final class SidebarPanelController {
    static let shared = SidebarPanelController()

    static let width: CGFloat = 380

    private var appState: AppState?
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var activeScreen: NSScreen?
    private var isOpen = false

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
            width: Self.width,
            height: endFrame.height
        )

        if panel == nil {
            let panel = NSPanel(
                contentRect: startFrame,
                styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false

            let hostingView = NSHostingView(rootView: SidebarRootView(appState: appState))
            hostingView.frame = NSRect(origin: .zero, size: endFrame.size)
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            self.panel = panel
        } else {
            (panel!.contentView as? NSHostingView<SidebarRootView>)?.rootView =
                SidebarRootView(appState: appState)
        }

        guard let panel else {
            isOpen = false
            return
        }

        removeEventMonitors()
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self?.isOpen == true else { return }
                self?.installEventMonitors()
            }
        }
    }

    func hide() {
        guard isOpen, let panel, let screen = activeScreen else { return }

        isOpen = false
        removeEventMonitors()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(
                NSPoint(x: screen.visibleFrame.maxX, y: panel.frame.minY)
            )
        } completionHandler: {
            DispatchQueue.main.async {
                panel.orderOut(nil)
            }
        }
    }

    // MARK: - Private

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let margin: CGFloat = 12
        return NSRect(
            x: visible.maxX - Self.width - margin,
            y: visible.minY + margin,
            width: Self.width,
            height: visible.height - margin * 2
        )
    }

    private func installEventMonitors() {
        removeEventMonitors()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
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
    }

    private func removeEventMonitors() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private struct SidebarRootView: View {
    let appState: AppState

    private static let cornerRadius: CGFloat = 22

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                TimelineView()
            } else {
                OnboardingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        )
        .environment(appState)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
