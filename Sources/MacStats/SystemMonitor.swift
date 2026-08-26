import Darwin
import AppKit
import Foundation
import IOKit.ps
import SensorBridge

final class SystemMonitor: @unchecked Sendable {
    private struct SensorReading {
        let averageTemperature: Double?
        let hottestTemperature: Double?
        let gpuTemperature: Double?
        let thermalCondition: ThermalCondition
        let fanAvailability: FanAvailability
        let fans: [FanMetric]
    }

    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?
    private var previousDisk: (read: UInt64, written: UInt64, date: Date)?
    private var previousProcessTimes: [Int32: UInt64] = [:]
    private var applicationNameCache: [String: String] = [:]
    private var cachedSensors: SensorReading?
    private var lastSensorSampleDate: Date?

    func sample(includeProcesses: Bool = true) -> SystemSnapshot {
        let now = Date()
        let memory = memoryUsage()
        let disk = diskUsage()
        let io = diskIO(at: now)
        let network = networkRates(at: now)
        let battery = batteryInfo()
        let sensors = sensorInfo(at: now)

        return SystemSnapshot(
            cpuPercent: cpuUsage(),
            memoryUsed: memory.used,
            memoryCached: memory.cached,
            memoryTotal: memory.total,
            memoryPressure: memory.pressure,
            diskUsed: disk.used,
            diskTotal: disk.total,
            diskReadPerSecond: io.read,
            diskWritePerSecond: io.written,
            networkDownPerSecond: network.down,
            networkUpPerSecond: network.up,
            batteryPercent: battery.percent,
            batteryCharging: battery.charging,
            batteryCycleCount: battery.cycles,
            batteryHealth: battery.health,
            averageTemperature: sensors.averageTemperature,
            hottestTemperature: sensors.hottestTemperature,
            gpuTemperature: sensors.gpuTemperature,
            thermalCondition: sensors.thermalCondition,
            fanAvailability: sensors.fanAvailability,
            fans: sensors.fans,
            uptime: ProcessInfo.processInfo.systemUptime,
            allProcesses: includeProcesses ? processUsage(at: now) : [],
            sampledAt: now
        )
    }

    private func sensorInfo(at date: Date) -> SensorReading {
        if let cachedSensors,
           let lastSensorSampleDate,
           date.timeIntervalSince(lastSensorSampleDate) < 5 {
            return cachedSensors
        }

        var raw = MSCSensorSnapshot()
        _ = MSCReadSensorSnapshot(&raw)

        let thermalCondition: ThermalCondition
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalCondition = .nominal
        case .fair: thermalCondition = .fair
        case .serious: thermalCondition = .serious
        case .critical: thermalCondition = .critical
        @unknown default: thermalCondition = .unknown
        }

        let fanAvailability: FanAvailability
        switch raw.fanStatus {
        case 0: fanAvailability = .fanless
        case 1: fanAvailability = .available
        default: fanAvailability = .unavailable
        }

        let fanCount = max(0, min(Int(raw.fanCount), Int(MSC_MAX_FANS)))
        let fans: [FanMetric] = withUnsafeBytes(of: raw.fanRPM) { buffer in
            let values = buffer.bindMemory(to: Double.self)
            return (0..<fanCount).map { FanMetric(index: $0, rpm: values[$0]) }
        }

        let reading = SensorReading(
            averageTemperature: raw.temperatureAvailable ? raw.averageTemperature : nil,
            hottestTemperature: raw.temperatureAvailable ? raw.hottestTemperature : nil,
            gpuTemperature: raw.gpuTemperature > 0 ? raw.gpuTemperature : nil,
            thermalCondition: thermalCondition,
            fanAvailability: fanAvailability,
            fans: fans
        )
        cachedSensors = reading
        lastSensorSampleDate = date
        return reading
    }

    private func cpuUsage() -> Double {
        var count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        var cpuCount: natural_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &count
        )
        guard result == KERN_SUCCESS, let info else { return 0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)
            )
        }

        var ticks = (user: UInt64(0), system: UInt64(0), idle: UInt64(0), nice: UInt64(0))
        for index in 0..<Int(cpuCount) {
            let offset = Int(CPU_STATE_MAX) * index
            ticks.user += UInt64(info[offset + Int(CPU_STATE_USER)])
            ticks.system += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            ticks.idle += UInt64(info[offset + Int(CPU_STATE_IDLE)])
            ticks.nice += UInt64(info[offset + Int(CPU_STATE_NICE)])
        }

        defer { previousCPUTicks = ticks }
        guard let old = previousCPUTicks else { return 0 }
        let busy = delta(ticks.user, old.user) + delta(ticks.system, old.system) + delta(ticks.nice, old.nice)
        let idle = delta(ticks.idle, old.idle)
        let total = busy + idle
        return total == 0 ? 0 : min(100, Double(busy) / Double(total) * 100)
    }

    private func memoryUsage() -> (used: UInt64, cached: UInt64, total: UInt64, pressure: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, physicalMemory(), 0) }

        let page = UInt64(getpagesize())
        let total = physicalMemory()
        let internalMemory = UInt64(stats.internal_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let externalMemory = UInt64(stats.external_page_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page

        // Activity Monitor presents file cache separately from Memory Used.
        // Public VM statistics do not expose its private formula, but internal
        // non-purgeable + wired + compressed is the closest public equivalent.
        let appAndSystemMemory = internalMemory > purgeable ? internalMemory - purgeable : internalMemory
        let used = min(total, appAndSystemMemory + wired + compressed)
        let availableForCache = total > used ? total - used : 0
        let cached = min(availableForCache, externalMemory + purgeable)
        let pressure = total == 0 ? 0 : Double(used) / Double(total) * 100
        return (used, cached, total, pressure)
    }

    private func physicalMemory() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    private func diskUsage() -> (used: UInt64, total: UInt64) {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let available = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            return (total > available ? total - available : 0, total)
        } catch {
            return (0, 0)
        }
    }

    private func diskIO(at date: Date) -> (read: Double, written: Double) {
        // Public macOS APIs do not expose reliable per-device throughput without
        // traversing the I/O Registry. Capacity is always available; throughput
        // remains zero if a supported counter cannot be sampled.
        let counters = (read: UInt64(0), written: UInt64(0))
        defer { previousDisk = (counters.read, counters.written, date) }
        guard let old = previousDisk else { return (0, 0) }
        let interval = max(0.1, date.timeIntervalSince(old.date))
        return (
            Double(delta(counters.read, old.read)) / interval,
            Double(delta(counters.written, old.written)) / interval
        )
    }

    private func networkRates(at date: Date) -> (down: Double, up: Double) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               (interface.ifa_flags & UInt32(IFF_UP)) != 0,
               let rawData = interface.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            cursor = interface.ifa_next
        }

        defer { previousNetwork = (received, sent, date) }
        guard let old = previousNetwork else { return (0, 0) }
        let interval = max(0.1, date.timeIntervalSince(old.date))
        return (
            Double(delta(received, old.received)) / interval,
            Double(delta(sent, old.sent)) / interval
        )
    }

    private func batteryInfo() -> (percent: Double?, charging: Bool, cycles: Int?, health: String?) {
        let hardware = batteryHardwareDetails()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, false, hardware.cycles, hardware.health) }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = description[kIOPSMaxCapacityKey] as? Double,
                  maximum > 0
            else { continue }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true || state == kIOPSACPowerValue
            return (current / maximum * 100, charging, hardware.cycles, hardware.health)
        }
        return (nil, false, hardware.cycles, hardware.health)
    }

    private func batteryHardwareDetails() -> (cycles: Int?, health: String?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any]
        else { return (nil, nil) }

        let cycles = values["CycleCount"] as? Int
        let condition = values["BatteryHealth"] as? String
        return (cycles, condition)
    }

    private func processUsage(at date: Date) -> [ProcessMetric] {
        let capacity = max(1, Int(proc_listallpids(nil, 0)))
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteCount = Int32(capacity * MemoryLayout<pid_t>.stride)
        let count = Int(proc_listallpids(&pids, byteCount))
        guard count > 0 else { return [] }

        var currentTimes: [Int32: UInt64] = [:]
        var results: [ProcessMetric] = []
        let logicalCPUs = max(1, ProcessInfo.processInfo.processorCount)

        for pid in pids.prefix(count) where pid > 0 {
            var task = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            let read = withUnsafeMutablePointer(to: &task) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, size)
            }
            guard read == size else { continue }

            let totalTime = task.pti_total_user + task.pti_total_system
            currentTimes[pid] = totalTime
            let elapsed = max(0.1, date.timeIntervalSince1970 - (lastProcessSampleDate ?? date).timeIntervalSince1970)
            let oldTime = previousProcessTimes[pid] ?? totalTime
            let cpu = min(100, Double(delta(totalTime, oldTime)) / 1_000_000_000 / elapsed / Double(logicalCPUs) * 100)

            var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let nameBytes = nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let name = String(decoding: nameBytes, as: UTF8.self)
            guard !name.isEmpty else { continue }

            var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let executablePath: String
            if pathLength > 0 {
                let bytes = pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                executablePath = String(decoding: bytes, as: UTF8.self)
            } else {
                executablePath = ""
            }

            results.append(ProcessMetric(
                pid: pid,
                name: name,
                applicationName: resolveApplicationName(
                    pid: pid,
                    processName: name,
                    executablePath: executablePath
                ),
                executablePath: executablePath,
                cpuPercent: cpu,
                memoryBytes: task.pti_resident_size
            ))
        }

        previousProcessTimes = currentTimes
        lastProcessSampleDate = date
        return results.sorted {
            if abs($0.cpuPercent - $1.cpuPercent) > 0.1 { return $0.cpuPercent > $1.cpuPercent }
            return $0.memoryBytes > $1.memoryBytes
        }
    }

    private func resolveApplicationName(pid: pid_t, processName: String, executablePath: String) -> String? {
        if let bundlePath = outermostApplicationBundle(in: executablePath) {
            if let cached = applicationNameCache[bundlePath] { return cached }
            if let bundle = Bundle(path: bundlePath) {
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
                applicationNameCache[bundlePath] = name
                return name
            }
        }

        if let runningName = NSRunningApplication(processIdentifier: pid)?.localizedName,
           !runningName.isEmpty {
            return runningName
        }

        return presetApplicationName(for: processName)
    }

    private func outermostApplicationBundle(in executablePath: String) -> String? {
        guard executablePath.hasPrefix("/") else { return nil }
        let components = executablePath.split(separator: "/")
        guard let appIndex = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else {
            return nil
        }
        return "/" + components[...appIndex].joined(separator: "/")
    }

    private func presetApplicationName(for processName: String) -> String? {
        let key = processName.lowercased()
        let exact: [String: String] = [
            "kernel_task": "macOS 内核",
            "launchd": "macOS 服务管理",
            "windowserver": "macOS 窗口服务",
            "mds": "Spotlight",
            "corespotlightd": "Spotlight",
            "bird": "iCloud 云盘",
            "cloudd": "iCloud",
            "backupd": "时间机器",
            "photoanalysisd": "照片",
            "photolibraryd": "照片",
            "trustd": "macOS 安全服务",
            "securityd": "macOS 安全服务",
            "distnoted": "macOS 通知服务",
            "runningboardd": "macOS 应用管理",
            "controlcenter": "控制中心",
            "dock": "程序坞",
            "finder": "访达"
        ]
        if let match = exact[key] { return match }
        if key.hasPrefix("mdworker") { return "Spotlight" }
        if key.hasPrefix("com.apple.webkit") || key.contains("safari web content") { return "Safari" }
        if key.contains("google chrome helper") { return "Google Chrome" }
        if key.contains("microsoft edge helper") { return "Microsoft Edge" }
        if key.contains("code helper") { return "Visual Studio Code" }
        if key.contains("codex") && key.contains("renderer") { return "Codex" }
        return nil
    }

    private var lastProcessSampleDate: Date?

    private func delta(_ new: UInt64, _ old: UInt64) -> UInt64 {
        new >= old ? new - old : 0
    }
}
