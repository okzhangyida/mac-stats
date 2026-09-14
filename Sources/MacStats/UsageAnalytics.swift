import Combine
import Foundation

@MainActor
final class UsageAnalytics: ObservableObject {
    static let shared = UsageAnalytics()

    @Published private(set) var isEnabled: Bool

    private enum DefaultsKey {
        static let enabled = "analytics.enabled"
        static let installSent = "analytics.installSent"
        static let lastActiveDay = "analytics.lastActiveDay"
        static let lastReportedVersion = "analytics.lastReportedVersion"
    }

    private enum Event: String, Encodable {
        case install
        case dailyActive = "daily_active"
        case versionChanged = "version_changed"
    }

    private struct Payload: Encodable {
        let schemaVersion = 1
        let event: Event
        let appVersion: String
        let build: String
        let osMajor: Int
        let architecture: String
        let language: String
        let channel = "direct"
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private var hasStarted = false
    private var isSending = false

    private init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [DefaultsKey.enabled: true])
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: DefaultsKey.enabled)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        session = URLSession(configuration: configuration)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        sendPendingEventsIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.enabled)
        if enabled {
            sendPendingEventsIfNeeded()
        }
    }

    private func sendPendingEventsIfNeeded() {
        guard isEnabled, endpoint != nil, !isSending else { return }
        isSending = true
        Task {
            await sendPendingEvents()
            isSending = false
        }
    }

    private func sendPendingEvents() async {
        guard isEnabled else { return }

        let currentVersion = versionKey
        if !defaults.bool(forKey: DefaultsKey.installSent) {
            if await send(.install) {
                defaults.set(true, forKey: DefaultsKey.installSent)
                defaults.set(currentVersion, forKey: DefaultsKey.lastReportedVersion)
            }
        } else if defaults.string(forKey: DefaultsKey.lastReportedVersion) != currentVersion {
            if await send(.versionChanged) {
                defaults.set(currentVersion, forKey: DefaultsKey.lastReportedVersion)
            }
        }

        let today = Self.utcDayFormatter.string(from: Date())
        if defaults.string(forKey: DefaultsKey.lastActiveDay) != today,
           await send(.dailyActive) {
            defaults.set(today, forKey: DefaultsKey.lastActiveDay)
        }
    }

    private func send(_ event: Event) async -> Bool {
        guard isEnabled, let endpoint else { return false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("MacStats/\(appVersion)", forHTTPHeaderField: "User-Agent")

        let payload = Payload(
            event: event,
            appVersion: appVersion,
            build: buildNumber,
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            architecture: Self.architecture,
            language: Self.coarseLanguage
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MacStatsAnalyticsEndpoint") as? String,
              !value.isEmpty,
              let url = URL(string: value),
              url.scheme == "https" else {
            return nil
        }
        return url
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildNumber: String {
        if let displayBuild = Bundle.main.object(forInfoDictionaryKey: "MacStatsBuildNumber") as? String,
           !displayBuild.isEmpty {
            return displayBuild
        }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private var versionKey: String { "\(appVersion) (\(buildNumber))" }

    private static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "other"
        #endif
    }

    private static var coarseLanguage: String {
        guard let language = Locale.preferredLanguages.first?.lowercased() else { return "other" }
        if language.hasPrefix("zh") { return "zh-Hans" }
        if language.hasPrefix("en") { return "en" }
        return "other"
    }
}
