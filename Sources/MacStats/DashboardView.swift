import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: MonitorStore
    let openSettingsAction: (() -> Void)?
    let openProcessesAction: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    init(
        store: MonitorStore,
        openSettingsAction: (() -> Void)? = nil,
        openProcessesAction: (() -> Void)? = nil
    ) {
        self.store = store
        self.openSettingsAction = openSettingsAction
        self.openProcessesAction = openProcessesAction
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    primaryGrid
                    HistoryCard(
                        cpu: store.cpuHistory.points,
                        memory: store.memoryHistory.points,
                        temperature: store.temperatureHistory.points
                    )
                    processesCard
                    systemFooter
                }
                .padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mac Stats").font(.headline)
                Text(
                    L10n.string(
                        "dashboard.updated_at",
                        fallback: "Updated %@",
                        store.snapshot.sampledAt.formatted(.dateTime.hour().minute().second())
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            headerNetworkStatus
            Spacer(minLength: 4)
            Button { store.sampleNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(L10n.string("common.refresh_now", fallback: "Refresh Now"))
            settingsButton
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help(L10n.string("dashboard.quit", fallback: "Quit Mac Stats"))
        }
        .padding(14)
    }

    private var headerNetworkStatus: some View {
        HStack(spacing: 6) {
            headerNetworkRate(
                store.snapshot.networkDownPerSecond,
                systemImage: "arrow.down.circle.fill",
                color: .cyan
            )
            headerNetworkRate(
                store.snapshot.networkUpPerSecond,
                systemImage: "arrow.up.circle.fill",
                color: .green
            )
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: 108)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func headerNetworkRate(
        _ bytesPerSecond: Double,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 12, alignment: .center)
            Text(ByteFormatter.compactRate(bytesPerSecond))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .frame(width: 30, alignment: .leading)
        }
        .frame(width: 44)
    }

    @ViewBuilder
    private var settingsButton: some View {
        if let openSettingsAction {
            Button {
                dismiss()
                DispatchQueue.main.async {
                    openSettingsAction()
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help(L10n.string("common.settings", fallback: "Settings"))
        } else if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help(L10n.string("common.settings", fallback: "Settings"))
        } else {
            Button {
                NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help(L10n.string("common.settings", fallback: "Settings"))
        }
    }

    private var primaryGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                MetricCard(
                    title: L10n.string("common.cpu", fallback: "CPU"),
                    value: percent(store.snapshot.cpuPercent),
                    detail: store.snapshot.hardware.compactDescription,
                    detailHelp: store.snapshot.hardware.fullDescription,
                    icon: "cpu",
                    color: .blue,
                    progress: store.snapshot.cpuPercent / 100
                )
                MetricCard(
                    title: L10n.string("common.memory", fallback: "Memory"),
                    value: percent(store.memoryPercent),
                    detail: memoryDetail,
                    icon: "memorychip",
                    color: .purple,
                    progress: store.memoryPercent / 100
                )
            }
            GridRow {
                MetricCard(
                    title: L10n.string("common.disk", fallback: "Disk"),
                    value: percent(store.diskPercent),
                    detail: L10n.string(
                        "dashboard.disk_detail",
                        fallback: "Used %@ / Total %@",
                        ByteFormatter.string(store.snapshot.diskUsed),
                        ByteFormatter.string(store.snapshot.diskTotal)
                    ),
                    icon: "internaldrive",
                    color: .orange,
                    progress: store.diskPercent / 100
                )
                MetricCard(
                    title: L10n.string("common.battery", fallback: "Battery"),
                    value: store.snapshot.batteryPercent.map(percent)
                        ?? L10n.string("dashboard.desktop_device", fallback: "Desktop Mac"),
                    detail: batteryDetail,
                    icon: store.snapshot.batteryCharging ? CompatibleSymbol.batteryCharging : CompatibleSymbol.battery,
                    color: .green,
                    progress: (store.snapshot.batteryPercent ?? 0) / 100
                )
            }
            GridRow {
                MetricCard(
                    title: L10n.string("common.temperature", fallback: "Temperature"),
                    value: temperatureValue,
                    detail: temperatureDetail,
                    icon: "thermometer.medium",
                    color: .red,
                    progress: (store.snapshot.averageTemperature ?? 0) / 100
                )
                FanCard(
                    availability: store.snapshot.fanAvailability,
                    fans: store.snapshot.fans
                )
            }
        }
    }

    private var processesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.string("dashboard.top_processes", fallback: "Top Processes"), systemImage: "list.number")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(L10n.string("common.cpu", fallback: "CPU"))
                    .frame(width: ProcessColumnLayout.cpuWidth, alignment: .trailing)
                Text(L10n.string("common.memory", fallback: "Memory"))
                    .frame(width: ProcessColumnLayout.memoryWidth, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if store.snapshot.topProcesses.isEmpty {
                Text(L10n.string("dashboard.waiting_sample", fallback: "Waiting for the next sample…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.snapshot.topProcesses) { process in
                    HStack {
                        Text(process.displayName).lineLimit(1)
                        Spacer()
                        Text("\(process.cpuPercent, specifier: "%.1f")%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: ProcessColumnLayout.cpuWidth, alignment: .trailing)
                        Text(ByteFormatter.string(process.memoryBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: ProcessColumnLayout.memoryWidth, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
            HStack {
                Spacer()
                Button(L10n.string("dashboard.view_all", fallback: "View All")) {
                    dismiss()
                    DispatchQueue.main.async {
                        if let openProcessesAction {
                            openProcessesAction()
                        } else {
                            openWindow(id: "processes")
                        }
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .cardStyle()
    }

    private var systemFooter: some View {
        HStack {
            Label(L10n.string("dashboard.uptime", fallback: "Up %@", uptimeText), systemImage: "clock")
            Spacer()
            Text(ProcessInfo.processInfo.operatingSystemVersionString)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var uptimeText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: store.snapshot.uptime) ?? "—"
    }

    private var batteryDetail: String {
        guard store.snapshot.batteryPercent != nil else {
            return L10n.string("dashboard.no_battery", fallback: "No battery detected")
        }
        var parts = [
            store.snapshot.batteryCharging
                ? L10n.string("dashboard.power_connected", fallback: "Power connected")
                : L10n.string("dashboard.on_battery", fallback: "On battery")
        ]
        if let cycles = store.snapshot.batteryCycleCount {
            parts.append(L10n.string("dashboard.battery_cycles", fallback: "%d cycles", cycles))
        }
        if let health = store.snapshot.batteryHealth, !health.isEmpty { parts.append(health) }
        return parts.joined(separator: " · ")
    }

    private var temperatureValue: String {
        store.snapshot.averageTemperature.map { String(format: "%.0f°C", $0) }
            ?? store.snapshot.thermalCondition.title
    }

    private var temperatureDetail: String {
        if let hottest = store.snapshot.hottestTemperature {
            return L10n.string(
                "dashboard.temp_highest",
                fallback: "Peak %@ · Thermal state: %@",
                String(format: "%.0f°C", hottest),
                store.snapshot.thermalCondition.title
            )
        }
        return L10n.string(
            "dashboard.temp_unavailable",
            fallback: "Temperature unavailable · Thermal state: %@",
            store.snapshot.thermalCondition.title
        )
    }

    private var memoryDetail: String {
        let used = ByteFormatter.memory(store.displayedMemoryUsed)
        let cached = ByteFormatter.memory(store.snapshot.memoryCached)
        let total = ByteFormatter.memory(store.snapshot.memoryTotal)
        return store.includeCachedMemory
            ? L10n.string("dashboard.memory_with_cache", fallback: "With cache %@ / %@", used, total)
            : L10n.string("dashboard.memory_detail", fallback: "Used %@ / Total %@ · Cache %@", used, total, cached)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}

private enum ProcessColumnLayout {
    static let cpuWidth: CGFloat = 42
    static let memoryWidth: CGFloat = 64
}

private struct FanCard: View {
    let availability: FanAvailability
    let fans: [FanMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.string("common.fan", fallback: "Fan"), systemImage: CompatibleSymbol.fan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("RPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            content
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: MetricCardLayout.contentHeight,
            maxHeight: MetricCardLayout.contentHeight,
            alignment: .topLeading
        )
        .cardStyle()
    }

    @ViewBuilder
    private var content: some View {
        switch availability {
        case .available where !fans.isEmpty:
            HStack(spacing: 6) {
                ForEach(Array(fans.prefix(2).enumerated()), id: \.element.id) { position, fan in
                    if position > 0 {
                        Divider()
                            .frame(height: 34)
                    }
                    fanReading(fan, label: fans.count > 1 ? sideLabel(for: position) : nil)
                }
            }
        case .fanless:
            Label(L10n.string("fan.fanless", fallback: "Fanless design"), systemImage: CompatibleSymbol.fan)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        default:
            Label(L10n.string("common.unavailable", fallback: "Unavailable"), systemImage: CompatibleSymbol.fan)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func fanReading(_ fan: FanMetric, label: String?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: CompatibleSymbol.fan)
                    .font(.caption)
                    .foregroundStyle(.cyan)
                if let label {
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(format: "%.0f", fan.rpm))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func sideLabel(for position: Int) -> String {
        position == 0 ? "L" : "R"
    }

}

private enum MetricCardLayout {
    static let contentHeight: CGFloat = 58
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    var detailHelp: String? = nil
    let icon: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
            ProgressView(value: min(1, max(0, progress)))
                .tint(color)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)
                .help(detailHelp ?? detail)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: MetricCardLayout.contentHeight,
            maxHeight: MetricCardLayout.contentHeight,
            alignment: .topLeading
        )
        .cardStyle()
    }
}

private struct HistoryCard: View {
    let cpu: [MetricPoint]
    let memory: [MetricPoint]
    let temperature: [MetricPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(durationTitle, systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 10) {
                    legend(L10n.string("common.cpu", fallback: "CPU"), .blue)
                    legend(L10n.string("common.memory", fallback: "Memory"), .purple)
                    legend(L10n.string("dashboard.cpu_temperature", fallback: "CPU Temp"), .orange)
                }
            }
            Chart {
                ForEach(cpu) { point in
                    LineMark(
                        x: .value(L10n.string("dashboard.chart_time", fallback: "Time"), point.date),
                        y: .value(L10n.string("dashboard.chart_value", fallback: "Value"), point.value),
                        series: .value(L10n.string("dashboard.chart_metric", fallback: "Metric"), L10n.string("common.cpu", fallback: "CPU"))
                    )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(memory) { point in
                    LineMark(
                        x: .value(L10n.string("dashboard.chart_time", fallback: "Time"), point.date),
                        y: .value(L10n.string("dashboard.chart_value", fallback: "Value"), point.value),
                        series: .value(L10n.string("dashboard.chart_metric", fallback: "Metric"), L10n.string("common.memory", fallback: "Memory"))
                    )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(temperature) { point in
                    LineMark(
                        x: .value(L10n.string("dashboard.chart_time", fallback: "Time"), point.date),
                        y: .value(L10n.string("dashboard.chart_temperature", fallback: "Temperature"), point.value),
                        series: .value(L10n.string("dashboard.chart_metric", fallback: "Metric"), L10n.string("dashboard.cpu_temperature", fallback: "CPU Temp"))
                    )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(0.16))
                    AxisTick()
                        .foregroundStyle(.secondary.opacity(0.35))
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisTick().foregroundStyle(.secondary.opacity(0.35))
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text("\(number)°")
                        }
                    }
                }
                AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.20))
                    AxisTick().foregroundStyle(.secondary.opacity(0.35))
                    AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } }
                }
            }
            .frame(height: 112)
        }
        .cardStyle()
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var durationTitle: String {
        L10n.string("dashboard.last_two_minutes", fallback: "Last 2 Minutes")
    }

    private var chartDomain: ClosedRange<Date> {
        let end = Date()
        return end.addingTimeInterval(-120)...end
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(11)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.primary.opacity(0.06))
            }
    }
}
