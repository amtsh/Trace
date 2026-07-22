import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SidebarPanelController.shared.configure(appState: appState)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Detects each MenuBarExtra popover presentation and toggles the sidebar panel.
final class SidebarLauncherView: NSView {
    private weak var observedWindow: NSWindow?
    private var keyObserver: NSObjectProtocol?
    private var handledCurrentPresentation = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()

        guard let window else {
            handledCurrentPresentation = false
            return
        }

        observedWindow = window
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.handlePresentation()
        }

        handlePresentation()
    }

    deinit {
        stopObserving()
    }

    func handlePresentationIfNeeded() {
        if window?.isVisible != true {
            handledCurrentPresentation = false
            return
        }
        handlePresentation()
    }

    private func stopObserving() {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
            self.keyObserver = nil
        }
        observedWindow = nil
    }

    private func handlePresentation() {
        guard let window, window.isVisible, !handledCurrentPresentation else { return }
        handledCurrentPresentation = true

        SidebarPanelController.shared.toggle(on: SidebarPanelController.screenAtMouse())
        window.orderOut(nil)

        // Reset once the popover is dismissed so the next click is handled.
        DispatchQueue.main.async { [weak self] in
            self?.handledCurrentPresentation = false
        }
    }
}

struct SidebarLauncher: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarLauncherView {
        SidebarLauncherView(frame: .zero)
    }

    func updateNSView(_ nsView: SidebarLauncherView, context: Context) {
        nsView.handlePresentationIfNeeded()
    }
}
