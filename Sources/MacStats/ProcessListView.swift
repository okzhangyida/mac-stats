import SwiftUI

struct ProcessListView: View {
    enum SortOption: String, CaseIterable, Identifiable {
        case cpu
        case memory
        case name
        case application
        case pid

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cpu: L10n.string("process.sort_cpu", fallback: "CPU: High to Low")
            case .memory: L10n.string("process.sort_memory", fallback: "Memory: High to Low")
            case .name: L10n.string("process.sort_name", fallback: "Process Name")
            case .application: L10n.string("process.sort_application", fallback: "Application Name")
            case .pid: "PID"
            }
        }
    }

    @ObservedObject var store: MonitorStore
    @State private var searchText = ""
    @State private var sortOption = SortOption.cpu

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("process.window_title", fallback: "All Processes"))
                        .font(.title2.weight(.semibold))
                    Text(
                        L10n.string(
                            "process.count",
                            fallback: "%d of %d processes",
                            filteredProcesses.count,
                            store.snapshot.allProcesses.count
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(L10n.string("process.search_placeholder", fallback: "Search process, app, PID, or path"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 270)
                Picker(L10n.string("process.sort", fallback: "Sort"), selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Button { store.sampleNow() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.string("common.refresh_now", fallback: "Refresh Now"))
            }
            .padding(16)

            Divider()

            Table(filteredProcesses) {
                TableColumn(L10n.string("process.column_process", fallback: "Process")) { process in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(process.name)
                            .lineLimit(1)
                        Text("PID \(process.pid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 150, ideal: 210)

                TableColumn(L10n.string("process.column_application", fallback: "Application")) { process in
                    Text(process.applicationDisplayName)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 170)

                TableColumn(L10n.string("common.cpu", fallback: "CPU")) { process in
                    Text("\(process.cpuPercent, specifier: "%.1f")%")
                        .monospacedDigit()
                }
                .width(58)

                TableColumn(L10n.string("common.memory", fallback: "Memory")) { process in
                    Text(ByteFormatter.string(process.memoryBytes))
                        .monospacedDigit()
                }
                .width(80)

                TableColumn(L10n.string("process.column_executable", fallback: "Executable")) { process in
                    Text(
                        process.executablePath.isEmpty
                            ? L10n.string("process.inaccessible", fallback: "Inaccessible")
                            : process.executablePath
                    )
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
                        Text(
                            searchText.isEmpty
                                ? L10n.string("process.empty", fallback: "No process data")
                                : L10n.string("process.no_match", fallback: "No matching processes")
                        )
                            .font(.headline)
                        Text(
                            searchText.isEmpty
                                ? L10n.string("process.waiting", fallback: "Waiting for the next system sample")
                                : L10n.string("process.try_another", fallback: "Try another search term")
                        )
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
