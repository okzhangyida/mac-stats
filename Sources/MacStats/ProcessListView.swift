import SwiftUI

struct ProcessListView: View {
    enum SortOption: String, CaseIterable, Identifiable {
        case cpu = "CPU 从高到低"
        case memory = "内存从高到低"
        case name = "进程名称"
        case application = "应用名称"
        case pid = "PID"

        var id: String { rawValue }
    }

    @ObservedObject var store: MonitorStore
    @State private var searchText = ""
    @State private var sortOption = SortOption.cpu

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("所有进程")
                        .font(.title2.weight(.semibold))
                    Text("当前共 \(filteredProcesses.count) / \(store.snapshot.allProcesses.count) 个进程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("搜索进程、应用、PID 或路径", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 270)
                Picker("排序", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Button { store.sampleNow() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("立即刷新")
            }
            .padding(16)

            Divider()

            Table(filteredProcesses) {
                TableColumn("进程") { process in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(process.name)
                            .lineLimit(1)
                        Text("PID \(process.pid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 150, ideal: 210)

                TableColumn("所属应用") { process in
                    Text(process.applicationDisplayName)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 170)

                TableColumn("CPU") { process in
                    Text("\(process.cpuPercent, specifier: "%.1f")%")
                        .monospacedDigit()
                }
                .width(58)

                TableColumn("内存") { process in
                    Text(ByteFormatter.string(process.memoryBytes))
                        .monospacedDigit()
                }
                .width(80)

                TableColumn("可执行文件") { process in
                    Text(process.executablePath.isEmpty ? "不可访问" : process.executablePath)
                        .lineLimit(1)
                        .foregroundStyle(process.executablePath.isEmpty ? .secondary : .primary)
                        .help(process.executablePath)
                }
                .width(min: 180, ideal: 320)
            }
            .overlay {
                if filteredProcesses.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: searchText.isEmpty ? "list.bullet.rectangle" : "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "暂无进程数据" : "没有匹配的进程")
                            .font(.headline)
                        Text(searchText.isEmpty ? "等待下一次系统采样" : "请尝试其他关键词")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { store.start() }
    }

    private var filteredProcesses: [ProcessMetric] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = store.snapshot.allProcesses.filter { process in
            guard !query.isEmpty else { return true }
            return process.name.lowercased().contains(query)
                || process.applicationDisplayName.lowercased().contains(query)
                || String(process.pid).contains(query)
                || process.executablePath.lowercased().contains(query)
        }

        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .cpu:
                if abs(lhs.cpuPercent - rhs.cpuPercent) > 0.01 { return lhs.cpuPercent > rhs.cpuPercent }
                return lhs.memoryBytes > rhs.memoryBytes
            case .memory:
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.cpuPercent > rhs.cpuPercent
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .application:
                return lhs.applicationDisplayName.localizedStandardCompare(rhs.applicationDisplayName) == .orderedAscending
            case .pid:
                return lhs.pid < rhs.pid
            }
        }
    }
}
