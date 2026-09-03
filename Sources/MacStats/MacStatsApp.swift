import AppKit
import SwiftUI

@main
struct MacStatsApp: App {
    private let didMigratePreferences = PreferencesMigration.run()
    @StateObject private var store = MonitorStore()
    @AppStorage("displayMetrics") private var displayMetrics = "cpu,memory"
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                store: store,
                openSettingsAction: {
                    SettingsWindowCoordinator.shared.show(store: store)
                },
                openProcessesAction: {
                    ProcessWindowCoordinator.shared.show(store: store)
                }
            )
                .frame(width: 390, height: 590)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: menuBarIcon)
                if !menuTitle.isEmpty {
                    Text(menuTitle)
                }
            }
            .onAppear {
                AppAppearance.apply(appAppearance)
                store.start()
                DesktopAppearanceController.shared.start()
                UsageAnalytics.shared.start()
            }
            .onChange(of: appAppearance) { newValue in
                AppAppearance.apply(newValue)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .frame(width: 500, height: 650)
        }

        Window(L10n.string("process.window_title", fallback: "All Processes"), id: "processes") {
            ProcessListView(store: store)
        }
        .defaultSize(width: 920, height: 620)
    }

    private var selectedMetrics: [DisplayMetric] {
        Array(
            displayMetrics
                .split(separator: ",")
                .compactMap { DisplayMetric(rawValue: String($0)) }
                .prefix(2)
        )
    }

    private var menuTitle: String {
        selectedMetrics.map(metricText).joined(separator: " · ")
    }

    private func metricText(_ metric: DisplayMetric) -> String {
        switch metric {
        case .cpu:
            return String(format: "CPU %.0f%%", store.snapshot.cpuPercent)
        case .memory:
            return L10n.string("status.memory_percent", fallback: "Memory %.0f%%", store.memoryPercent)
        case .disk:
            return L10n.string("status.disk_percent", fallback: "Disk %.0f%%", store.diskPercent)
        case .network:
            return "↓\(ByteFormatter.compactRate(store.snapshot.networkDownPerSecond)) ↑\(ByteFormatter.compactRate(store.snapshot.networkUpPerSecond))"
        case .battery:
            return store.snapshot.batteryPercent.map {
                L10n.string("status.battery_percent", fallback: "Battery %.0f%%", $0)
            } ?? "B —"
        case .temperature:
            return store.snapshot.averageTemperature.map { String(format: "%.0f°C", $0) }
                ?? "\(L10n.string("common.temperature", fallback: "Temperature")) \(store.snapshot.thermalCondition.title)"
        case .fan:
            switch store.snapshot.fanAvailability {
            case .available:
                if let fastest = store.snapshot.fans.map(\.rpm).max() {
                    return L10n.string("fan.rpm_value", fallback: "Fan %.0f", fastest)
                }
                return L10n.string("fan.zero", fallback: "Fan 0")
            case .fanless:
                return L10n.string("fan.fanless", fallback: "Fanless design")
            case .unavailable:
                return "\(L10n.string("common.fan", fallback: "Fan")) —"
            }
        }
    }

    private var menuBarIcon: NSImage {
        let image: NSImage
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let bundled = NSImage(contentsOf: url) {
            image = bundled
        } else {
            image = NSImage(systemSymbolName: "gauge.open.with.lines.needle.33percent", accessibilityDescription: "Mac Stats")
                ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: "Mac Stats")
                ?? NSImage(size: NSSize(width: 18, height: 18))
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
