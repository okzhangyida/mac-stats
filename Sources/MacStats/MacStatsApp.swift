import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MonitorStore()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PreferencesMigration.run()
        AppAppearance.apply(UserDefaults.standard.string(forKey: "appAppearance") ?? AppAppearance.system.rawValue)

        installApplicationMenu()
        statusBarController = StatusBarController(store: store)
        store.start()
        DesktopAppearanceController.shared.start()
        UsageAnalytics.shared.start()
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Mac Stats")
        let settings = NSMenuItem(
            title: L10n.string("common.settings", fallback: "Settings"),
            action: #selector(showSettingsWindow(_:)), keyEquivalent: ","
        )
        settings.target = self
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(NSMenuItem(
            title: L10n.string("common.quit", fallback: "Quit"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApplication.shared.mainMenu = menu
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        SettingsWindowCoordinator.shared.show(store: store)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}

// All windows are explicitly owned by their coordinators. Registering an empty
// SwiftUI Settings scene creates a second, blank window that macOS can reopen.
@main
enum MacStatsApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
