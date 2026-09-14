import Foundation
import SwiftUI

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    private(set) var cpuHistory = HistoryBuffer()
    private(set) var memoryHistory = HistoryBuffer()
    private(set) var temperatureHistory = HistoryBuffer()
    private(set) var networkHistory = HistoryBuffer()

    @AppStorage("refreshInterval") var refreshInterval = 2.0
    @AppStorage("includeCachedMemory") var includeCachedMemory = false
    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var generation = 0
    private var isSampling = false

    var diskPercent: Double {
        snapshot.diskTotal == 0 ? 0 : Double(snapshot.diskUsed) / Double(snapshot.diskTotal) * 100
    }

    var diskAvailable: UInt64 {
        snapshot.diskTotal > snapshot.diskUsed ? snapshot.diskTotal - snapshot.diskUsed : 0
    }

    var displayedMemoryUsed: UInt64 {
        let cached = includeCachedMemory ? snapshot.memoryCached : 0
        return min(snapshot.memoryTotal, snapshot.memoryUsed + cached)
    }

    var memoryPercent: Double {
        snapshot.memoryTotal == 0
            ? 0
            : Double(displayedMemoryUsed) / Double(snapshot.memoryTotal) * 100
    }

    func start() {
        guard timer == nil else { return }
        sampleNow()
        installTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        generation += 1
    }

    func restart() {
        stop()
        start()
    }

    func sampleNow() {
        guard !isSampling else { return }
        isSampling = true
        let currentGeneration = generation
        let monitor = monitor

        Task {
            let newSnapshot = await Task.detached(priority: .utility) {
                monitor.sample()
            }.value
            guard currentGeneration == generation else {
                isSampling = false
                return
            }
            record(newSnapshot)
            isSampling = false
        }
    }

    func record(_ newSnapshot: SystemSnapshot) {
        var newCPUHistory = cpuHistory
        var newMemoryHistory = memoryHistory
        var newTemperatureHistory = temperatureHistory
        var newNetworkHistory = networkHistory
        newCPUHistory.append(newSnapshot.cpuPercent, at: newSnapshot.sampledAt)
        newMemoryHistory.append(memoryPercent(for: newSnapshot), at: newSnapshot.sampledAt)
        if let cpuTemperature = newSnapshot.averageTemperature {
            newTemperatureHistory.append(cpuTemperature, at: newSnapshot.sampledAt)
        }
        newNetworkHistory.append(
            newSnapshot.networkDownPerSecond + newSnapshot.networkUpPerSecond,
            at: newSnapshot.sampledAt
        )
        cpuHistory = newCPUHistory
        memoryHistory = newMemoryHistory
        temperatureHistory = newTemperatureHistory
        networkHistory = newNetworkHistory
        snapshot = newSnapshot
    }

    func resetMemoryHistory() {
        var newHistory = HistoryBuffer()
        newHistory.append(memoryPercent, at: snapshot.sampledAt)
        objectWillChange.send()
        memoryHistory = newHistory
    }

    private func memoryPercent(for snapshot: SystemSnapshot) -> Double {
        guard snapshot.memoryTotal > 0 else { return 0 }
        let cached = includeCachedMemory ? snapshot.memoryCached : 0
        let used = min(snapshot.memoryTotal, snapshot.memoryUsed + cached)
        return Double(used) / Double(snapshot.memoryTotal) * 100
    }

    private func installTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: max(1, refreshInterval), repeats: true) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in store.sampleNow() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
