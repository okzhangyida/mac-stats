import Foundation
import XCTest
@testable import MacStats

final class HistoryBufferTests: XCTestCase {
    func testRemovesPointsOutsideRetentionWindow() {
        let start = Date(timeIntervalSince1970: 1_000)
        var buffer = HistoryBuffer(retentionInterval: 120, maximumPoints: 180)

        buffer.append(1, at: start)
        buffer.append(2, at: start.addingTimeInterval(119))
        buffer.append(3, at: start.addingTimeInterval(121))

        XCTAssertEqual(buffer.points.map(\.value), [2, 3])
    }

    func testLimitsPointCount() {
        let start = Date(timeIntervalSince1970: 2_000)
        var buffer = HistoryBuffer(retentionInterval: 1_000, maximumPoints: 3)

        for value in 0..<5 {
            buffer.append(Double(value), at: start.addingTimeInterval(Double(value)))
        }

        XCTAssertEqual(buffer.points.map(\.value), [2, 3, 4])
    }
}
