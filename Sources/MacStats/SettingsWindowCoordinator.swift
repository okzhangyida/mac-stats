import AppKit
import SwiftUI

@MainActor
final class SettingsWindowCoordinator {
    static let shared = SettingsWindowCoordinator()

    private var windowController: NSWindowController?

    private init() {}

    func show(store: MonitorStore) {
        if windowController == nil {
            let hostingController = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: hostingController)
            window.title = L10n.string("settings.window_title", fallback: "Mac Stats Settings")
            window.setContentSize(NSSize(width: 500, height: 650))
            window.minSize = NSSize(width: 500, height: 560)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        windowController?.window?.orderFrontRegardless()
    }
}
