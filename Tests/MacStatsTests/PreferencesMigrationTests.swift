import Foundation
import XCTest
@testable import MacStats

final class PreferencesMigrationTests: XCTestCase {
    func testMigratesLegacyValuesWithoutOverwritingCurrentPreferences() throws {
        let token = UUID().uuidString
        let currentDomain = "cc.macstats.tests.current.\(token)"
        let newestLegacyDomain = "cc.macstats.tests.newest.\(token)"
        let oldestLegacyDomain = "cc.macstats.tests.oldest.\(token)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: currentDomain))

        defer {
            defaults.removePersistentDomain(forName: currentDomain)
            defaults.removePersistentDomain(forName: newestLegacyDomain)
            defaults.removePersistentDomain(forName: oldestLegacyDomain)
        }

        defaults.setPersistentDomain(
            ["displayMetrics": "cpu,temperature"],
            forName: currentDomain
        )
        defaults.setPersistentDomain(
            ["displayMetrics": "memory,disk", "refreshInterval": 5.0],
            forName: newestLegacyDomain
        )
        defaults.setPersistentDomain(
            ["refreshInterval": 10.0, "includeCachedMemory": true],
            forName: oldestLegacyDomain
        )

        XCTAssertTrue(
            PreferencesMigration.run(
                defaults: defaults,
                currentDomain: currentDomain,
                sourceDomains: [newestLegacyDomain, oldestLegacyDomain]
            )
        )
        XCTAssertEqual(defaults.string(forKey: "displayMetrics"), "cpu,temperature")
        XCTAssertEqual(defaults.double(forKey: "refreshInterval"), 5.0)
        XCTAssertTrue(defaults.bool(forKey: "includeCachedMemory"))
        XCTAssertFalse(
            PreferencesMigration.run(
                defaults: defaults,
                currentDomain: currentDomain,
                sourceDomains: [newestLegacyDomain, oldestLegacyDomain]
            )
        )
    }
}
