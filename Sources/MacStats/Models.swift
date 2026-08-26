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

    var applicationDisplayName: String {
        applicationName ?? L10n.string("process.background", fallback: "System or background process")
    }

    var displayName: String {
        guard let applicationName,
              applicationName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        else { return name }
        return "\(name)（\(applicationName)）"
    }
}

enum ThermalCondition: String, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    var title: String {
        switch self {
        case .nominal: L10n.string("thermal.nominal", fallback: "Normal")
        case .fair: L10n.string("thermal.fair", fallback: "Warm")
        case .serious: L10n.string("thermal.serious", fallback: "Hot")
        case .critical: L10n.string("thermal.critical", fallback: "Critical")
        case .unknown: L10n.string("thermal.unknown", fallback: "Unknown")
        }
    }
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
        if index == 0 { return L10n.string("fan.left", fallback: "Left fan") }
        if index == 1 { return L10n.string("fan.right", fallback: "Right fan") }
        return L10n.string("fan.numbered", fallback: "Fan %d", index + 1)
    }
}

struct HardwareInfo: Equatable {
    var cpuModel = L10n.string("hardware.processor_unavailable", fallback: "Processor model unavailable")
    var cpuCoreCount = 0
    var gpuCoreCount: Int?

    var compactDescription: String {
        guard cpuCoreCount > 0 else { return cpuModel }
        if let gpuCoreCount, gpuCoreCount > 0 {
            return "\(cpuModel) · \(cpuCoreCount)C CPU / \(gpuCoreCount)C GPU"
        }
        return "\(cpuModel) · \(cpuCoreCount)C CPU"
    }

    var fullDescription: String {
        guard cpuCoreCount > 0 else { return cpuModel }
        if let gpuCoreCount, gpuCoreCount > 0 {
            return L10n.string(
                "hardware.cpu_gpu_cores",
                fallback: "%@ · %d-core CPU / %d-core GPU",
                cpuModel,
                cpuCoreCount,
                gpuCoreCount
            )
        }
        return L10n.string("hardware.cpu_cores", fallback: "%@ · %d-core CPU", cpuModel, cpuCoreCount)
    }
}

struct SystemSnapshot: Equatable {
    var hardware = HardwareInfo()
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
        case .memory: L10n.string("common.memory", fallback: "Memory")
        case .disk: L10n.string("common.disk", fallback: "Disk")
        case .network: L10n.string("common.network", fallback: "Network")
        case .battery: L10n.string("common.battery", fallback: "Battery")
        case .temperature: L10n.string("common.temperature", fallback: "Temperature")
        case .fan: L10n.string("common.fan", fallback: "Fan")
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

    static func memory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(clamping: bytes))
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
