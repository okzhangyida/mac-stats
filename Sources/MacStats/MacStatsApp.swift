import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MonitorStore()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PreferencesMigration.run()
        AppAppearance.apply(UserDefaults.standard.string(forKey: "appAppearance") ?? AppAppearance.system.rawValue)

        statusBarController = StatusBarController(store: store)
        store.start()
        DesktopAppearanceController.shared.start()
        UsageAnalytics.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}

@main
struct MacStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // All live monitoring windows are mounted on demand by the status-bar
        // controller, so hidden SwiftUI scene graphs do not rebuild forever.
        Settings {
            EmptyView()
        }
    }
}
