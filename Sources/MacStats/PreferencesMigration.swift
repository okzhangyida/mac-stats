import Foundation

enum PreferencesMigration {
    static let permanentDomain = "ai.justbro.macstats"

    private static let migrationMarker = "preferences.migratedToPermanentBundleID.v1"
    private static let legacyDomains = [
        "cc.macstats.app",
        "com.local.MacStats.rollback03",
        "com.local.MacStats"
    ]

    @discardableResult
    static func run(
        defaults: UserDefaults = .standard,
        currentDomain: String = permanentDomain,
        sourceDomains: [String] = legacyDomains
    ) -> Bool {
        let currentValues = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard currentValues[migrationMarker] == nil else { return false }

        var migratedValues = currentValues
        for sourceDomain in sourceDomains {
            guard let legacyValues = defaults.persistentDomain(forName: sourceDomain) else { continue }
            for (key, value) in legacyValues where migratedValues[key] == nil {
                migratedValues[key] = value
            }
        }

        let didMigrate = migratedValues.keys.contains { currentValues[$0] == nil }
        for (key, value) in migratedValues where currentValues[key] == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: migrationMarker)
        return didMigrate
    }
}
