import XCTest
@testable import MacStats

final class ProcessCPUAccountingTests: XCTestCase {
    func testFallbackParsesSystemServiceAndNamesWithSpaces() throws {
        let reading = try XCTUnwrap(ProcessFallbackReading(line: " 166 20:22.97 227904 WindowServer"))
        XCTAssertEqual(reading.pid, 166)
        XCTAssertEqual(reading.seconds, 1222.97, accuracy: 0.001)
        XCTAssertEqual(reading.memory, 227904 * 1024)
        let helper = try XCTUnwrap(ProcessFallbackReading(line: "42 1-02:03:04.50 100 App Helper"))
        XCTAssertEqual(helper.name, "App Helper")
        XCTAssertEqual(helper.seconds, 93784.5, accuracy: 0.001)
        XCTAssertNil(ProcessFallbackReading(line: "42 invalid 100 App"))
        XCTAssertNil(ProcessFallbackReading(line: "PID TIME RSS COMMAND"))
    }

    func testAppleSiliconOneBusyCoreUsesOneEighteenthOfMachine() {
        let accounting = ProcessCPUAccounting(numerator: 125, denominator: 3)
        // Two seconds at 24 MHz: one busy core should use 5.56%, not 0.13%.
        XCTAssertEqual(accounting.percent(previous: 100, current: 48_000_100,
                                          elapsedTicks: 48_000_000, logicalCPUs: 18),
                       100.0 / 18, accuracy: 0.000001)
    }

    func testIntelAndAppleSiliconGiveSameMulticorePercentage() {
        for (numerator, denominator, ticks) in [(UInt32(125), UInt32(3), UInt64(48_000_000)),
                                               (UInt32(1), UInt32(1), UInt64(2_000_000_000))] {
            let accounting = ProcessCPUAccounting(numerator: numerator, denominator: denominator)
            XCTAssertEqual(accounting.percent(previous: 0, current: ticks * 3,
                                              elapsedTicks: ticks, logicalCPUs: 18),
                           100.0 / 6, accuracy: 0.000001)
            XCTAssertEqual(accounting.percent(previous: 0, current: ticks * 18,
                                              elapsedTicks: ticks, logicalCPUs: 18), 100)
        }
    }

    func testMissingBaselineResetAndZeroIntervalDoNotProduceSpikes() {
        let accounting = ProcessCPUAccounting(numerator: 125, denominator: 3)
        XCTAssertEqual(accounting.percent(previous: nil, current: 999, elapsedTicks: 10, logicalCPUs: 18), 0)
        XCTAssertEqual(accounting.percent(previous: 999, current: 10, elapsedTicks: 10, logicalCPUs: 18), 0)
        XCTAssertEqual(accounting.percent(previous: 0, current: 999, elapsedTicks: 0, logicalCPUs: 18), 0)
    }
}
