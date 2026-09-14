import Combine
import XCTest
@testable import MacStats

final class MonitorStoreTests: XCTestCase {
    @MainActor
    func testRecordingPublishesOnceAndKeepsTheLatestTwoMinutes() {
        let store = MonitorStore()
        let start = Date(timeIntervalSince1970: 10_000)
        var notifications = 0
        let subscription = store.objectWillChange.sink { notifications += 1 }

        for offset in 0...180 {
            var snapshot = SystemSnapshot()
            snapshot.cpuPercent = Double(offset)
            snapshot.memoryUsed = 50
            snapshot.memoryTotal = 100
            snapshot.averageTemperature = 40 + Double(offset % 10)
            snapshot.sampledAt = start.addingTimeInterval(Double(offset))
            store.record(snapshot)
        }

        XCTAssertEqual(notifications, 181)
        XCTAssertEqual(store.cpuHistory.points.count, 121)
        XCTAssertEqual(store.memoryHistory.points.count, 121)
        XCTAssertEqual(store.temperatureHistory.points.count, 121)
        XCTAssertEqual(store.cpuHistory.points.first?.date, start.addingTimeInterval(60))
        XCTAssertEqual(store.cpuHistory.points.last?.date, start.addingTimeInterval(180))
        XCTAssertEqual(store.cpuHistory.points.last?.value, 180)
        withExtendedLifetime(subscription) {}
    }
}
