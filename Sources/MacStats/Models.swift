import Foundation

struct MetricPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct ProcessMetric: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let applicationName: String?
    let executablePath: String
    let cpuPercent: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }

    var applicationDisplayName: String { applicationName ?? "系统或后台进程" }

    var displayName: String {
        guard let applicationName,
              applicationName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        else { return name }
        return "\(name)（\(applicationName)）"
    }
}

enum ThermalCondition: String, Equatable {
    case nominal = "正常"
    case fair = "偏热"
    case serious = "较热"
    case critical = "严重"
    case unknown = "未知"
}

enum FanAvailability: Equatable {
    case available
    case fanless
    case unavailable
}

struct FanMetric: Identifiable, Equatable {
    let index: Int
    let rpm: Double

    var id: Int { index }

    var name: String {
        if index == 0 { return "左侧风扇" }
        if index == 1 { return "右侧风扇" }
        return "风扇 \(index + 1)"
    }
}

struct SystemSnapshot: Equatable {
    var cpuPercent = 0.0
    var memoryUsed: UInt64 = 0
    var memoryCached: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var memoryPressure = 0.0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var diskReadPerSecond = 0.0
    var diskWritePerSecond = 0.0
    var networkDownPerSecond = 0.0
    var networkUpPerSecond = 0.0
    var batteryPercent: Double?
    var batteryCharging = false
    var batteryCycleCount: Int?
    var batteryHealth: String?
    var averageTemperature: Double?
    var hottestTemperature: Double?
    var gpuTemperature: Double?
    var thermalCondition = ThermalCondition.unknown
    var fanAvailability = FanAvailability.unavailable
    var fans: [FanMetric] = []
    var uptime: TimeInterval = 0
    var allProcesses: [ProcessMetric] = []
    var sampledAt = Date()

    var topProcesses: [ProcessMetric] {
        Array(allProcesses.prefix(5))
    }
}

enum DisplayMetric: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case disk
    case network
    case battery
    case temperature
    case fan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        case .disk: "磁盘"
        case .network: "网络"
        case .battery: "电池"
        case .temperature: "温度"
        case .fan: "风扇"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .battery: "battery.75percent"
        case .temperature: "thermometer.medium"
        case .fan: "fan"
        }
    }
}

enum ByteFormatter {
    private static func formatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        return formatter
    }

    static func string(_ bytes: UInt64) -> String {
        formatter().string(fromByteCount: Int64(clamping: bytes))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1 else { return "0 B/s" }
        return "\(formatter().string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    static func compactRate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fG", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", value / 1_000)
        default:
            return String(format: "%.0fB", value)
        }
    }
}
