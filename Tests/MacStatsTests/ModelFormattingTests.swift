import AppKit
import Foundation
import XCTest
@testable import MacStats

final class ModelFormattingTests: XCTestCase {
    func testCompactRatesUseStableUnits() {
        XCTAssertEqual(ByteFormatter.compactRate(-1), "0B")
        XCTAssertEqual(ByteFormatter.compactRate(999), "999B")
        XCTAssertEqual(ByteFormatter.compactRate(1_000), "1K")
        XCTAssertEqual(ByteFormatter.compactRate(1_500_000), "1.5M")
        XCTAssertEqual(ByteFormatter.compactRate(2_250_000_000), "2.2G")
    }

    func testProcessNameAddsApplicationOnlyWhenDifferent() {
        let same = ProcessMetric(
            pid: 1,
            name: "Finder",
            applicationName: "Finder",
            executablePath: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            cpuPercent: 1,
            memoryBytes: 1
        )
        let helper = ProcessMetric(
            pid: 2,
            name: "Microsoft Edge Helper",
            applicationName: "Microsoft Edge",
            executablePath: "/Applications/Microsoft Edge.app/Contents/Frameworks/Helper",
            cpuPercent: 1,
            memoryBytes: 1
        )

        XCTAssertEqual(same.displayName, "Finder")
        XCTAssertEqual(helper.displayName, "Microsoft Edge Helper（Microsoft Edge）")
    }

    func testHardwareDescriptionIncludesCpuAndGpuCores() {
        let hardware = HardwareInfo(cpuModel: "Apple M5 Pro", cpuCoreCount: 18, gpuCoreCount: 20)
        XCTAssertEqual(hardware.compactDescription, "Apple M5 Pro · 18C CPU / 20C GPU")
    }

    func testTopProcessesAreLimitedToFive() {
        var snapshot = SystemSnapshot()
        snapshot.allProcesses = (0..<8).map { index in
            ProcessMetric(
                pid: Int32(index),
                name: "Process \(index)",
                applicationName: nil,
                executablePath: "",
                cpuPercent: Double(index),
                memoryBytes: UInt64(index)
            )
        }
        XCTAssertEqual(snapshot.topProcesses.count, 5)
    }

    func testCompatibilitySymbolsAreAvailable() {
        XCTAssertNotNil(NSImage(systemSymbolName: CompatibleSymbol.battery, accessibilityDescription: nil))
        XCTAssertNotNil(NSImage(systemSymbolName: CompatibleSymbol.batteryCharging, accessibilityDescription: nil))
        XCTAssertNotNil(NSImage(systemSymbolName: CompatibleSymbol.fan, accessibilityDescription: nil))
    }
}
