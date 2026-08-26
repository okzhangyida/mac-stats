import AppKit
import SwiftUI

@MainActor
final class ProcessWindowCoordinator {
    static let shared = ProcessWindowCoordinator()

    private var windowController: NSWindowController?

    private init() {}

    func show(store: MonitorStore) {
        if windowController == nil {
            let hostingController = NSHostingController(rootView: ProcessListView(store: store))
            let window = NSWindow(contentViewController: hostingController)
            window.title = L10n.string("process.window_title", fallback: "All Processes")
            window.setContentSize(NSSize(width: 920, height: 620))
            window.minSize = NSSize(width: 760, height: 480)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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
