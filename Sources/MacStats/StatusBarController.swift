import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private static let logger = Logger(subsystem: "ai.justbro.macstats", category: "StatusBar")

    private let store: MonitorStore
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var usesIconOnlyFallback = false

    init(store: MonitorStore) {
        self.store = store
        super.init()

        configurePopover()
        observeChanges()
        ensureStatusItem()
    }

    func ensureStatusItem() {
        if let statusItem, statusItem.button != nil {
            statusItem.isVisible = true
            updateStatusItem()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else {
            Self.logger.error("NSStatusBar did not provide a status item button")
            return
        }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.image = menuBarIcon
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        item.isVisible = true
        updateStatusItem()

        Self.logger.notice("Installed status item with width \(item.length, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak button] in
            self?.verifyVisibility(of: button)
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 390, height: 590)
        popover.delegate = self
    }

    private func preparePopoverContent() {
        guard popover.contentViewController == nil else { return }
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                store: store,
                openSettingsAction: { [weak self] in self?.showSettings() },
                openProcessesAction: { [weak self] in self?.showProcesses() }
            )
            .frame(width: 390, height: 590)
        )
    }

    private func observeChanges() {
        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        releaseHiddenPopoverContent()
        guard let statusItem, let button = statusItem.button else { return }
        let title = selectedMetrics.map(metricText).joined(separator: " · ")
        button.attributedTitle = NSAttributedString(string: "")
        button.title = usesIconOnlyFallback || title.isEmpty ? "" : " \(title)"
        button.setAccessibilityLabel(accessibilityMenuLabel)

        // NSStatusItem.variableLength occasionally remains at zero after a
        // login-item launch. An explicit, content-derived width is reliable.
        if usesIconOnlyFallback {
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.squareLength
        } else {
            button.imagePosition = .imageLeading
            let contentWidth = button.intrinsicContentSize.width
            let preferredWidth = contentWidth.isFinite && contentWidth > 0
                ? ceil(contentWidth + 6)
                : 28
            statusItem.length = min(max(preferredWidth, 28), 240)
        }
        statusItem.isVisible = true
    }

    private func releaseHiddenPopoverContent() {
        guard !popover.isShown, popover.contentViewController != nil else { return }
        popover.contentViewController = nil
    }

    private func verifyVisibility(of button: NSStatusBarButton?) {
        guard let statusItem, let button else { return }
        let hasUsableWidth = button.frame.width >= 20
        let attachedToWindow = button.window != nil

        Self.logger.notice(
            "Status item check: itemWidth=\(statusItem.length, privacy: .public), buttonWidth=\(button.frame.width, privacy: .public), attached=\(attachedToWindow, privacy: .public), visible=\(statusItem.isVisible, privacy: .public)"
        )

        guard !hasUsableWidth || !attachedToWindow else { return }
        usesIconOnlyFallback = true
        button.title = ""
        statusItem.length = NSStatusItem.squareLength
        statusItem.isVisible = true
        Self.logger.error("Status item was not laid out; switched to icon-only fallback")
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else {
            ensureStatusItem()
            return
        }
        preparePopoverContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        // MonitorStore continues sampling and retaining the last two minutes.
        // Only the hidden SwiftUI/Charts hierarchy is discarded here.
        releaseHiddenPopoverContent()
    }

    private func showSettings() {
        popover.performClose(nil)
        SettingsWindowCoordinator.shared.show(store: store)
    }

    private func showProcesses() {
        popover.performClose(nil)
        ProcessWindowCoordinator.shared.show(store: store)
    }

    private var selectedMetrics: [DisplayMetric] {
        Array(
            (UserDefaults.standard.string(forKey: "displayMetrics") ?? "cpu,memory")
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

    private var accessibilityMenuLabel: String {
        let metrics = selectedMetrics.map(accessibilityMetricText).joined(separator: ", ")
        return metrics.isEmpty ? "Mac Stats" : "Mac Stats, \(metrics)"
    }

    private func accessibilityMetricText(_ metric: DisplayMetric) -> String {
        switch metric {
        case .cpu:
            return String(format: "CPU %.0f%%", store.snapshot.cpuPercent)
        case .memory:
            return L10n.string("status.memory_percent", fallback: "Memory %.0f%%", store.memoryPercent)
        case .disk:
            return L10n.string("status.disk_percent", fallback: "Disk %.0f%%", store.diskPercent)
        case .network:
            return L10n.string(
                "status.network_rates",
                fallback: "Download %@, Upload %@",
                ByteFormatter.compactRate(store.snapshot.networkDownPerSecond),
                ByteFormatter.compactRate(store.snapshot.networkUpPerSecond)
            )
        case .battery:
            return store.snapshot.batteryPercent.map {
                L10n.string("status.battery_percent", fallback: "Battery %.0f%%", $0)
            } ?? L10n.string("dashboard.no_battery", fallback: "No battery detected")
        case .temperature:
            return store.snapshot.averageTemperature.map {
                L10n.string("status.temperature_value", fallback: "Temperature %.0f degrees Celsius", $0)
            } ?? L10n.string("status.temperature_unavailable", fallback: "Temperature unavailable")
        case .fan:
            if let fastest = store.snapshot.fans.map(\.rpm).max() {
                return L10n.string("fan.rpm_accessibility", fallback: "Fan %.0f RPM", fastest)
            }
            return store.snapshot.fanAvailability == .fanless
                ? L10n.string("fan.fanless", fallback: "Fanless design")
                : L10n.string("fan.unreadable", fallback: "Fan unavailable")
        }
    }

    private var menuBarIcon: NSImage {
        let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "gauge.open.with.lines.needle.33percent", accessibilityDescription: "Mac Stats")
            ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: "Mac Stats")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
