import AppKit
import SwiftUI

@main
struct MacStatsApp: App {
    @StateObject private var store = MonitorStore()
    @AppStorage("displayMetrics") private var displayMetrics = "cpu,memory"

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
            .onAppear { store.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .frame(width: 470, height: 500)
        }

        Window("所有进程", id: "processes") {
            ProcessListView(store: store)
        }
        .defaultSize(width: 920, height: 620)
    }

    private var menuTitle: String {
        selectedMetrics.map(metricText).joined(separator: " · ")
    }

    private var selectedMetrics: [DisplayMetric] {
        Array(
            displayMetrics
                .split(separator: ",")
                .compactMap { DisplayMetric(rawValue: String($0)) }
                .prefix(2)
        )
    }

    private func metricText(_ metric: DisplayMetric) -> String {
        switch metric {
        case .cpu:
            return String(format: "CPU %.0f%%", store.snapshot.cpuPercent)
        case .memory:
            return String(format: "内存 %.0f%%", store.memoryPercent)
        case .disk:
            return String(format: "磁盘 %.0f%%", store.diskPercent)
        case .network:
            return "↓\(ByteFormatter.compactRate(store.snapshot.networkDownPerSecond)) ↑\(ByteFormatter.compactRate(store.snapshot.networkUpPerSecond))"
        case .battery:
            return store.snapshot.batteryPercent.map { String(format: "电池 %.0f%%", $0) } ?? "电池 —"
        case .temperature:
            return store.snapshot.averageTemperature.map { String(format: "%.0f°C", $0) }
                ?? "温度 \(store.snapshot.thermalCondition.rawValue)"
        case .fan:
            switch store.snapshot.fanAvailability {
            case .available:
                if let fastest = store.snapshot.fans.map(\.rpm).max() {
                    return String(format: "风扇 %.0f", fastest)
                }
                return "风扇 0"
            case .fanless:
                return "无风扇"
            case .unavailable:
                return "风扇 —"
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
                ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: "Mac Stats")!
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
