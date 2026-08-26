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
                Text("更新于 \(store.snapshot.sampledAt, format: .dateTime.hour().minute().second())")
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
            .help("立即刷新")
            settingsButton
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("退出 Mac Stats")
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
            .help("设置")
        } else if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
        } else {
            Button {
                NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    private var primaryGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                MetricCard(
                    title: "CPU",
                    value: percent(store.snapshot.cpuPercent),
                    detail: "总处理器负载",
                    icon: "cpu",
                    color: .blue,
                    progress: store.snapshot.cpuPercent / 100
                )
                MetricCard(
                    title: "内存",
                    value: percent(store.memoryPercent),
                    detail: memoryDetail,
                    icon: "memorychip",
                    color: .purple,
                    progress: store.memoryPercent / 100
                )
            }
            GridRow {
                MetricCard(
                    title: "磁盘",
                    value: percent(store.diskPercent),
                    detail: "已用 \(ByteFormatter.string(store.snapshot.diskUsed)) / 总计 \(ByteFormatter.string(store.snapshot.diskTotal))",
                    icon: "internaldrive",
                    color: .orange,
                    progress: store.diskPercent / 100
                )
                MetricCard(
                    title: "电池",
                    value: store.snapshot.batteryPercent.map(percent) ?? "台式设备",
                    detail: batteryDetail,
                    icon: store.snapshot.batteryCharging ? "battery.100percent.bolt" : "battery.75percent",
                    color: .green,
                    progress: (store.snapshot.batteryPercent ?? 0) / 100
                )
            }
            GridRow {
                MetricCard(
                    title: "温度",
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
                Label("高占用进程", systemImage: "list.number")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("CPU / 内存").font(.caption2).foregroundStyle(.secondary)
            }
            if store.snapshot.topProcesses.isEmpty {
                Text("等待下一次采样…")
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
                        Text(ByteFormatter.string(process.memoryBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("查看全部") {
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
            Label("运行 \(uptimeText)", systemImage: "clock")
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
        guard store.snapshot.batteryPercent != nil else { return "未检测到电池" }
        var parts = [store.snapshot.batteryCharging ? "已接入电源" : "正在使用电池"]
        if let cycles = store.snapshot.batteryCycleCount { parts.append("\(cycles) 次循环") }
        if let health = store.snapshot.batteryHealth, !health.isEmpty { parts.append(health) }
        return parts.joined(separator: " · ")
    }

    private var temperatureValue: String {
        store.snapshot.averageTemperature.map { String(format: "%.0f°C", $0) }
            ?? store.snapshot.thermalCondition.rawValue
    }

    private var temperatureDetail: String {
        if let hottest = store.snapshot.hottestTemperature {
            return "最高 \(String(format: "%.0f°C", hottest)) · 热状态\(store.snapshot.thermalCondition.rawValue)"
        }
        return "无法读取摄氏温度 · 热状态\(store.snapshot.thermalCondition.rawValue)"
    }

    private var memoryDetail: String {
        let used = ByteFormatter.string(store.displayedMemoryUsed)
        let cached = ByteFormatter.string(store.snapshot.memoryCached)
        let total = ByteFormatter.string(store.snapshot.memoryTotal)
        return store.includeCachedMemory
            ? "含缓存 \(used) / \(total)"
            : "已用 \(used) · 缓存 \(cached)"
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}

private struct FanCard: View {
    let availability: FanAvailability
    let fans: [FanMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("风扇", systemImage: "fan")
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
            Label("无风扇设计", systemImage: "fan")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        default:
            Label("不可读取", systemImage: "fan")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func fanReading(_ fan: FanMetric, label: String?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "fan")
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
                    legend("CPU", .blue)
                    legend("内存", .purple)
                    legend("CPU 温度", .orange)
                }
            }
            Chart {
                ForEach(cpu) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("数值", point.value),
                        series: .value("指标", "CPU")
                    )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(memory) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("数值", point.value),
                        series: .value("指标", "内存")
                    )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(temperature) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("温度", point.value),
                        series: .value("指标", "CPU 温度")
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
                    AxisTick().foregroundStyle(.orange.opacity(0.40))
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text("\(number)°")
                                .foregroundStyle(.orange)
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

    private var durationTitle: String { "最近 2 分钟" }

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
