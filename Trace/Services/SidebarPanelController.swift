import AppKit
import SwiftUI

final class SidebarPanelController {
    static let shared = SidebarPanelController()

    private var appState: AppState?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SidebarRootView>?
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
        guard isOpen, let panel, let screen = activeScreen else { return }

        isOpen = false
        removeEventMonitors()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DS.Animation.panelHide
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
