import Foundation
import SwiftUI

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var cpuHistory = HistoryBuffer()
    @Published private(set) var memoryHistory = HistoryBuffer()
    @Published private(set) var temperatureHistory = HistoryBuffer()
    @Published private(set) var networkHistory = HistoryBuffer()
    @Published private(set) var isSampling = false

    @AppStorage("refreshInterval") var refreshInterval = 2.0
    @AppStorage("includeCachedMemory") var includeCachedMemory = false
    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var generation = 0

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
            snapshot = newSnapshot
            cpuHistory.append(newSnapshot.cpuPercent, at: newSnapshot.sampledAt)
            memoryHistory.append(memoryPercent, at: newSnapshot.sampledAt)
            if let cpuTemperature = newSnapshot.averageTemperature {
                temperatureHistory.append(cpuTemperature, at: newSnapshot.sampledAt)
            }
            networkHistory.append(
                newSnapshot.networkDownPerSecond + newSnapshot.networkUpPerSecond,
                at: newSnapshot.sampledAt
            )
            isSampling = false
        }
    }

    func resetMemoryHistory() {
        memoryHistory = HistoryBuffer()
        memoryHistory.append(memoryPercent, at: snapshot.sampledAt)
    }

    private func installTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: max(1, refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleNow() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
