import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Applies desktop effects to a derived copy of the current wallpaper. Keeping
/// the black strip in the wallpaper lets macOS choose native light menu content.
@MainActor
final class DesktopAppearanceController: ObservableObject {
    static let shared = DesktopAppearanceController()

    enum Status: Equatable {
        case idle
        case waiting
        case processing
        case active
        case unsupported(String)
        case failed(String)
    }

    @Published private(set) var hideNotch: Bool
    @Published private(set) var roundedCorners: Bool
    @Published private(set) var cornerRadius: Double
    @Published private(set) var includeExternalDisplays: Bool
    @Published private(set) var hasDisplayNotch: Bool
    @Published private(set) var status: Status = .idle

    private enum DefaultsKey {
        static let hideNotch = "desktopAppearance.hideNotch"
        static let roundedCorners = "desktopAppearance.roundedCorners"
        static let cornerRadius = "desktopAppearance.cornerRadius"
        static let includeExternalDisplays = "desktopAppearance.includeExternalDisplays"
        static let wallpaperRecords = "desktopAppearance.wallpaperRecords.v2"
    }

    private struct WallpaperRecord {
        var sourceURL: URL
        var processedURL: URL?
        var sourceFingerprint: String
        var options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    private struct PersistedRecord: Codable {
        let sourcePath: String
        let processedPath: String?
    }

    private struct SourceCandidate {
        let url: URL
        let fingerprint: String
    }

    private struct ProviderSnapshot {
        let name: String
        let fingerprint: String
        let sourceURL: URL?
        let solidColorComponents: [CGFloat]?
        let isDynamicDesktop: Bool
    }

    struct ProcessingRequest: Sendable {
        let sourceURL: URL
        let outputURL: URL
        let pixelWidth: Int
        let pixelHeight: Int
        let menuBarHeight: Int
        let hideNotch: Bool
        let roundedCorners: Bool
        let cornerRadius: Int
    }

    private enum ControllerError: LocalizedError {
        case unsupportedVideo
        case invalidImage
        case cannotCreateOutput
        case cannotFinalizeOutput

        var errorDescription: String? {
            switch self {
            case .unsupportedVideo:
                return "This live or video wallpaper cannot be processed without stopping its animation."
            case .invalidImage:
                return "The wallpaper image could not be decoded."
            case .cannotCreateOutput:
                return "A processed wallpaper file could not be created."
            case .cannotFinalizeOutput:
                return "The processed wallpaper file could not be saved."
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let workspace = NSWorkspace.shared
    private var records: [CGDirectDisplayID: WallpaperRecord] = [:]
    /// Keyed by processed path, so different Spaces on the same display never
    /// overwrite one another's restoration source.
    private var persistedRecords: [String: PersistedRecord] = [:]
    private var observerTokens: [NSObjectProtocol] = []
    private var storeWatchers: [DispatchSourceFileSystemObject] = []
    private var pollingTimer: Timer?
    private var reconcileTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var generation = 0
    private var selectionObservations: [CGDirectDisplayID: (fingerprint: String, firstSeen: Date)] = [:]
    private var hasStarted = false
    private var isCommittingWallpaper = false
    private var isProcessingWallpaper = false

    private init() {
        hideNotch = defaults.bool(forKey: DefaultsKey.hideNotch)
        roundedCorners = defaults.bool(forKey: DefaultsKey.roundedCorners)
        cornerRadius = defaults.object(forKey: DefaultsKey.cornerRadius) as? Double ?? 18
        includeExternalDisplays = defaults.bool(forKey: DefaultsKey.includeExternalDisplays)
        hasDisplayNotch = Self.detectDisplayNotch()
        loadPersistedRecords()
    }

    var isEnabled: Bool { hideNotch || roundedCorners }

    func start() {
        guard !hasStarted else {
            scheduleReconcile(delay: 0)
            return
        }
        hasStarted = true

        let center = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.didUnhideNotification] {
            observerTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let controller = self else { return }
                Task { @MainActor in controller.scheduleReconcile(delay: 0.1, cancelProcessing: true) }
            })
        }

        let workspaceCenter = workspace.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            observerTokens.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let controller = self else { return }
                Task { @MainActor in controller.scheduleReconcile(delay: 0.1, cancelProcessing: true) }
            })
        }

        installWallpaperStoreWatchers()
        cleanupWallpaperCache()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.scheduleReconcile(delay: 0.05) }
        }
        scheduleReconcile(delay: 0)
    }

    func setHideNotch(_ enabled: Bool) {
        guard hideNotch != enabled else { return }
        hideNotch = enabled
        defaults.set(enabled, forKey: DefaultsKey.hideNotch)
        settingsDidChange(restoreBeforeApplying: true)
    }

    func setRoundedCorners(_ enabled: Bool) {
        guard roundedCorners != enabled else { return }
        roundedCorners = enabled
        defaults.set(enabled, forKey: DefaultsKey.roundedCorners)
        settingsDidChange(restoreBeforeApplying: true)
    }

    func setCornerRadius(_ radius: Double) {
        let clamped = min(max(radius, 8), 40)
        guard cornerRadius != clamped else { return }
        cornerRadius = clamped
        defaults.set(clamped, forKey: DefaultsKey.cornerRadius)
        settingsDidChange(delay: 0.15, restoreBeforeApplying: false)
    }

    func setIncludeExternalDisplays(_ enabled: Bool) {
        guard includeExternalDisplays != enabled else { return }
        includeExternalDisplays = enabled
        defaults.set(enabled, forKey: DefaultsKey.includeExternalDisplays)
        if !enabled {
            let externalScreens = NSScreen.screens.filter { screen in
                guard let displayID = screen.displayID else { return false }
                return CGDisplayIsBuiltin(displayID) == 0
            }
            _ = restoreVisibleWallpapers(on: externalScreens)
        }
        settingsDidChange(restoreBeforeApplying: false)
    }

    func applyNow() {
        generation += 1
        processingTask?.cancel()
        isProcessingWallpaper = false
        records = records.mapValues { record in
            var copy = record
            copy.processedURL = nil
            return copy
        }
        scheduleReconcile(delay: 0)
    }

    func disableEffects() {
        hideNotch = false
        roundedCorners = false
        defaults.set(false, forKey: DefaultsKey.hideNotch)
        defaults.set(false, forKey: DefaultsKey.roundedCorners)
        restoreCurrentWallpapers()
    }

    private func settingsDidChange(
        delay: TimeInterval = 0,
        restoreBeforeApplying: Bool
    ) {
        generation += 1
        processingTask?.cancel()
        isProcessingWallpaper = false
        guard isEnabled else {
            restoreCurrentWallpapers()
            return
        }

        if restoreBeforeApplying {
            // A menu-bar or corner-mode change moves the desktop boundary.
            // Restore the trusted source first, then derive the new effect from
            // that source instead of stacking it on the previous output.
            restoreCurrentWallpapers()
            scheduleReconcile(delay: max(delay, 0.1))
        } else {
            // Radius drags and display-scope changes can reuse the recorded
            // source without visibly restoring the desktop on every step.
            records = records.mapValues { record in
                var copy = record
                copy.processedURL = nil
                return copy
            }
            scheduleReconcile(delay: delay)
        }
    }

    private func scheduleReconcile(delay: TimeInterval, cancelProcessing: Bool = false) {
        guard hasStarted, !isCommittingWallpaper else { return }
        if isProcessingWallpaper {
            guard cancelProcessing else { return }
            generation += 1
            processingTask?.cancel()
            isProcessingWallpaper = false
        }
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    private func reconcile() {
        let detectedNotch = Self.detectDisplayNotch()
        if hasDisplayNotch != detectedNotch {
            hasDisplayNotch = detectedNotch
        }
        guard isEnabled else {
            if restoreVisibleWallpapers() { status = .idle }
            return
        }

        let screens = selectedScreens()
        guard !screens.isEmpty else {
            status = .failed("No compatible display was found.")
            return
        }

        var requests: [(screen: NSScreen, displayID: CGDirectDisplayID, source: SourceCandidate)] = []
        for screen in screens {
            guard let displayID = screen.displayID else { continue }
            let provider = providerSnapshot(for: screen)
            let currentURL = effectiveWallpaperURL(for: screen, provider: provider)

            if let currentURL, isGeneratedWallpaper(currentURL) {
                if let record = records[displayID], record.processedURL?.standardizedFileURL == currentURL.standardizedFileURL {
                    continue
                }
                if let persisted = persistedRecords[currentURL.standardizedFileURL.path],
                   FileManager.default.fileExists(atPath: persisted.sourcePath) {
                    let sourceURL = URL(fileURLWithPath: persisted.sourcePath)
                    let candidate = SourceCandidate(url: sourceURL, fingerprint: sourceFingerprint(for: sourceURL, extra: "persisted"))
                    if records[displayID] == nil,
                       FileManager.default.fileExists(atPath: currentURL.path) {
                        records[displayID] = WallpaperRecord(
                            sourceURL: sourceURL,
                            processedURL: currentURL,
                            sourceFingerprint: candidate.fingerprint,
                            options: workspace.desktopImageOptions(for: screen) ?? [:]
                        )
                        status = .active
                        continue
                    }
                    requests.append((screen, displayID, candidate))
                    continue
                }
            }

            guard let source = wallpaperSource(for: screen, provider: provider) else {
                if case .unsupported = status {
                    // Keep the specific compatibility explanation.
                } else {
                    status = .waiting
                }
                continue
            }

            guard isStableSelection(source.fingerprint, on: displayID) else {
                status = .waiting
                scheduleReconcile(delay: 0.25)
                continue
            }

            if let existing = records[displayID],
               existing.sourceFingerprint == source.fingerprint,
               let processedURL = existing.processedURL,
               currentURL?.standardizedFileURL == processedURL.standardizedFileURL {
                continue
            }
            requests.append((screen, displayID, source))
        }

        if requests.isEmpty {
            if screens.allSatisfy({ screen in
                guard let url = effectiveWallpaperURL(for: screen) else { return false }
                return isGeneratedWallpaper(url)
            }) {
                status = .active
            }
            return
        }
        beginProcessing(requests)
    }

    private func isStableSelection(_ fingerprint: String, on displayID: CGDirectDisplayID) -> Bool {
        let now = Date()
        if let observation = selectionObservations[displayID], observation.fingerprint == fingerprint {
            return now.timeIntervalSince(observation.firstSeen) >= 0.2
        }
        selectionObservations[displayID] = (fingerprint, now)
        return false
    }

    private func beginProcessing(_ items: [(screen: NSScreen, displayID: CGDirectDisplayID, source: SourceCandidate)]) {
        generation += 1
        let currentGeneration = generation
        processingTask?.cancel()
        isProcessingWallpaper = true
        status = .processing

        var prepared: [(displayID: CGDirectDisplayID, source: SourceCandidate, request: ProcessingRequest, options: [NSWorkspace.DesktopImageOptionKey: Any])] = []
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            for item in items {
                let size = pixelSize(for: item.screen)
                let menuHeight = Int((menuBarHeight(for: item.screen) * item.screen.backingScaleFactor).rounded())
                let radius = Int((CGFloat(cornerRadius) * item.screen.backingScaleFactor).rounded())
                let signature = [
                    "renderer:4",
                    item.source.fingerprint,
                    "\(size.width)x\(size.height)",
                    "menu:\(menuHeight):\(hideNotch)",
                    "corners:\(radius):\(roundedCorners)"
                ].joined(separator: "|")
                let outputURL = outputDirectory.appendingPathComponent("mac-stats-\(Self.stableHash(signature)).wallpaper")
                let request = ProcessingRequest(
                    sourceURL: item.source.url,
                    outputURL: outputURL,
                    pixelWidth: size.width,
                    pixelHeight: size.height,
                    menuBarHeight: menuHeight,
                    hideNotch: hideNotch,
                    roundedCorners: roundedCorners,
                    cornerRadius: radius
                )
                prepared.append((item.displayID, item.source, request, workspace.desktopImageOptions(for: item.screen) ?? [:]))
            }
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                var results: [(CGDirectDisplayID, SourceCandidate, URL, [NSWorkspace.DesktopImageOptionKey: Any])] = []
                for item in prepared {
                    try Task.checkCancellation()
                    let request = item.request
                    let outputURL = try await Task.detached(priority: .userInitiated) {
                        try Self.renderWallpaper(request)
                    }.value
                    results.append((item.displayID, item.source, outputURL, item.options))
                }
                try Task.checkCancellation()
                guard currentGeneration == self.generation else { return }
                self.isProcessingWallpaper = false
                self.commit(results)
            } catch is CancellationError {
                if currentGeneration == self.generation { self.isProcessingWallpaper = false }
                return
            } catch ControllerError.unsupportedVideo {
                guard currentGeneration == self.generation else { return }
                self.isProcessingWallpaper = false
                self.status = .unsupported(
                    L10n.string(
                        "settings.wallpaper_provider_reason",
                        fallback: "Its source frames are managed by a live wallpaper provider and cannot be rewritten safely."
                    )
                )
            } catch {
                guard currentGeneration == self.generation else { return }
                self.isProcessingWallpaper = false
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    private func commit(_ results: [(CGDirectDisplayID, SourceCandidate, URL, [NSWorkspace.DesktopImageOptionKey: Any])]) {
        isCommittingWallpaper = true
        defer { isCommittingWallpaper = false }

        do {
            for result in results {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == result.0 }) else { continue }
                var options = result.3
                options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
                options[.allowClipping] = true
                options[.fillColor] = NSColor.black
                try workspace.setDesktopImageURL(result.2, for: screen, options: options)
                records[result.0] = WallpaperRecord(
                    sourceURL: result.1.url,
                    processedURL: result.2,
                    sourceFingerprint: result.1.fingerprint,
                    options: result.3
                )
                persistedRecords[result.2.standardizedFileURL.path] = PersistedRecord(
                    sourcePath: result.1.url.path,
                    processedPath: result.2.path
                )
            }
            persistRecords()
            status = .active
            cleanupWallpaperCache()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func restoreCurrentWallpapers() {
        generation += 1
        processingTask?.cancel()
        isProcessingWallpaper = false
        reconcileTask?.cancel()
        if restoreVisibleWallpapers() { status = .idle }
    }

    @discardableResult
    private func restoreVisibleWallpapers(on screens: [NSScreen] = NSScreen.screens) -> Bool {
        isCommittingWallpaper = true
        defer { isCommittingWallpaper = false }
        var succeeded = true

        for screen in screens {
            guard let displayID = screen.displayID,
                  let currentURL = currentGeneratedWallpaperURL(for: screen),
                  isGeneratedWallpaper(currentURL) else { continue }

            let path = currentURL.standardizedFileURL.path
            let runtimeRecord = records[displayID]
            let sourceURL: URL?
            let options: [NSWorkspace.DesktopImageOptionKey: Any]
            if runtimeRecord?.processedURL?.standardizedFileURL.path == path {
                sourceURL = runtimeRecord?.sourceURL
                options = runtimeRecord?.options ?? workspace.desktopImageOptions(for: screen) ?? [:]
            } else if let persisted = persistedRecords[path] {
                sourceURL = URL(fileURLWithPath: persisted.sourcePath)
                options = workspace.desktopImageOptions(for: screen) ?? [:]
            } else {
                sourceURL = nil
                options = [:]
            }

            guard let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            do {
                try workspace.setDesktopImageURL(sourceURL, for: screen, options: options)
                persistedRecords.removeValue(forKey: path)
                records.removeValue(forKey: displayID)
            } catch {
                succeeded = false
                status = .failed(error.localizedDescription)
            }
        }
        persistRecords()
        return succeeded
    }

    /// Provider metadata may continue to point at the source wallpaper after
    /// NSWorkspace has applied our derived file. Restoration must therefore
    /// prefer the actual desktop URL whenever it identifies generated output.
    private func currentGeneratedWallpaperURL(for screen: NSScreen) -> URL? {
        if let workspaceURL = workspace.desktopImageURL(for: screen),
           isGeneratedWallpaper(workspaceURL) {
            return workspaceURL
        }
        if let effectiveURL = effectiveWallpaperURL(for: screen),
           isGeneratedWallpaper(effectiveURL) {
            return effectiveURL
        }
        return nil
    }

    private func wallpaperSource(for screen: NSScreen, provider suppliedProvider: ProviderSnapshot?) -> SourceCandidate? {
        if let provider = suppliedProvider, provider.name.lowercased() != "default" {
            guard let providerURL = resolveProviderSource(provider) else {
                setUnavailableProviderStatus(provider)
                return nil
            }
            return SourceCandidate(
                url: providerURL,
                fingerprint: sourceFingerprint(for: providerURL, extra: provider.fingerprint)
            )
        }

        if let url = workspace.desktopImageURL(for: screen),
           !isGeneratedWallpaper(url),
           !url.standardizedFileURL.path.hasPrefix("/var/db/Wallpapers/"),
           url.isFileURL {
            guard url.lastPathComponent != "DefaultDesktop.heic" else {
                status = .waiting
                return nil
            }
            return SourceCandidate(url: url, fingerprint: sourceFingerprint(for: url, extra: "workspace"))
        }
        guard let provider = suppliedProvider else { return nil }
        guard let sourceURL = resolveProviderSource(provider) else {
            setUnavailableProviderStatus(provider)
            return nil
        }
        return SourceCandidate(url: sourceURL, fingerprint: sourceFingerprint(for: sourceURL, extra: provider.fingerprint))
    }

    private func setUnsupportedProviderStatus() {
        status = .unsupported(
            L10n.string(
                "settings.wallpaper_provider_reason",
                fallback: "Its source frames are managed by a live wallpaper provider and cannot be rewritten safely."
            )
        )
    }

    private func setUnavailableProviderStatus(_ provider: ProviderSnapshot) {
        let name = provider.name.lowercased()
        if provider.isDynamicDesktop {
            setUnsupportedProviderStatus()
        } else if name == "default" || name.contains("choice.image") || name.contains("color") {
            status = .waiting
        } else {
            setUnsupportedProviderStatus()
        }
    }

    private func resolveProviderSource(_ provider: ProviderSnapshot) -> URL? {
        if let sourceURL = provider.sourceURL,
           sourceURL.isFileURL,
           !isGeneratedWallpaper(sourceURL),
           FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }
        if let components = provider.solidColorComponents {
            return solidColorSourceURL(components: components, fingerprint: provider.fingerprint)
        }

        let lowercased = provider.name.lowercased()
        let candidates: [URL]
        if lowercased.contains("sonoma") {
            candidates = [URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")]
        } else if lowercased.contains("ventura") {
            candidates = [URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/Ventura Graphic.heic")]
        } else if lowercased.contains("monterey") {
            candidates = [URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/Monterey Graphic.heic")]
        } else {
            candidates = []
        }
        if let exact = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return exact
        }
        return nil
    }

    /// `NSWorkspace.desktopImageURL` returns DefaultDesktop.heic for provider-
    /// backed wallpapers. The per-user Store is the authoritative readable
    /// source for the provider selected on the current display.
    private func providerSnapshot(for screen: NSScreen) -> ProviderSnapshot? {
        userStoreProviderSnapshot(for: screen) ?? newestProviderSnapshot()
    }

    private func effectiveWallpaperURL(for screen: NSScreen) -> URL? {
        effectiveWallpaperURL(for: screen, provider: providerSnapshot(for: screen))
    }

    private func effectiveWallpaperURL(for screen: NSScreen, provider: ProviderSnapshot?) -> URL? {
        if let provider {
            if let sourceURL = provider.sourceURL { return sourceURL }
            if provider.name.lowercased() != "default" { return nil }
        }
        return workspace.desktopImageURL(for: screen)
    }

    private func userStoreProviderSnapshot(for screen: NSScreen) -> ProviderSnapshot? {
        let storeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: storeURL),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let displayUUID = screen.displayID.flatMap(Self.displayUUIDString)
        var desktops: [[String: Any]] = []

        if let displayUUID,
           let displays = root["Displays"] as? [String: Any],
           let display = displays[displayUUID] as? [String: Any],
           let desktop = display["Desktop"] as? [String: Any] {
            desktops.append(desktop)
        }
        if let spaces = root["Spaces"] as? [String: Any],
           let currentSpace = spaces[""] as? [String: Any] {
            if let displayUUID,
               let displays = currentSpace["Displays"] as? [String: Any],
               let display = displays[displayUUID] as? [String: Any],
               let desktop = display["Desktop"] as? [String: Any] {
                desktops.append(desktop)
            }
            if let defaultDisplay = currentSpace["Default"] as? [String: Any],
               let desktop = defaultDisplay["Desktop"] as? [String: Any] {
                desktops.append(desktop)
            }
        }
        if let systemDefault = root["SystemDefault"] as? [String: Any],
           let desktop = systemDefault["Desktop"] as? [String: Any] {
            desktops.append(desktop)
        }

        desktops.sort {
            ($0["LastSet"] as? Date ?? .distantPast) > ($1["LastSet"] as? Date ?? .distantPast)
        }

        for desktop in desktops {
            guard let content = desktop["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]],
                  let choice = choices.first,
                  let provider = choice["Provider"] as? String else { continue }
            var fingerprintData = Data(provider.utf8)
            var sourceURL: URL?
            var solidColorComponents: [CGFloat]?
            var isDynamicDesktop = false
            if let configuration = choice["Configuration"] as? Data {
                fingerprintData.append(configuration)
                sourceURL = Self.sourceURL(fromConfiguration: configuration)
                isDynamicDesktop = Self.isDynamicDesktopConfiguration(configuration)
            }
            if sourceURL == nil {
                sourceURL = Self.sourceURL(fromFiles: choice["Files"])
            }
            let encodedOptions = (choice["EncodedOptionValues"] as? Data)
                ?? (content["EncodedOptionValues"] as? Data)
            if let encodedOptions {
                fingerprintData.append(encodedOptions)
                if provider.lowercased().contains("color"),
                   let decoded = try? PropertyListSerialization.propertyList(from: encodedOptions, format: nil) {
                    solidColorComponents = Self.findColorComponents(in: decoded)
                }
            }
            if solidColorComponents == nil,
               provider.lowercased().contains("color"),
               let optionValues = content["OptionValues"] {
                solidColorComponents = Self.findColorComponents(in: optionValues)
            }
            return ProviderSnapshot(
                name: provider,
                fingerprint: Self.stableHash(fingerprintData),
                sourceURL: sourceURL,
                solidColorComponents: solidColorComponents,
                isDynamicDesktop: isDynamicDesktop
            )
        }
        return nil
    }

    private func newestProviderSnapshot() -> ProviderSnapshot? {
        let root = URL(fileURLWithPath: "/var/db/Wallpapers", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let metadataURLs = directories.map { $0.appendingPathComponent("Metadata.plist") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }

        for url in metadataURLs {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let content = plist["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]],
                  let provider = choices.first?["Provider"] as? String else { continue }
            return ProviderSnapshot(
                name: provider,
                fingerprint: Self.stableHash(data),
                sourceURL: nil,
                solidColorComponents: nil,
                isDynamicDesktop: false
            )
        }
        return nil
    }

    private nonisolated static func displayUUIDString(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private nonisolated static func sourceURL(fromConfiguration data: Data) -> URL? {
        guard let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        if let urlValue = configuration["url"] as? [String: Any],
           let relative = urlValue["relative"] as? String,
           let url = URL(string: relative),
           url.isFileURL {
            if url.pathExtension.lowercased() == "madesktop" {
                return resolveMadeDesktopSource(at: url)
            }
            return url.standardizedFileURL
        }

        if configuration["type"] as? String == "systemColor",
           let systemColor = configuration["systemColor"] as? [String: Any],
           let colorName = systemColor.keys.first {
            let directory = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Solid Colors", isDirectory: true)
            let normalizedColorName = normalizeColorName(colorName)
            if let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ), let match = files.first(where: {
                normalizeColorName($0.deletingPathExtension().lastPathComponent) == normalizedColorName
            }) {
                return match.standardizedFileURL
            }
        }
        return nil
    }

    private nonisolated static func isDynamicDesktopConfiguration(_ data: Data) -> Bool {
        guard let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlValue = configuration["url"] as? [String: Any],
              let relative = urlValue["relative"] as? String,
              let url = URL(string: relative),
              url.pathExtension.lowercased() == "madesktop",
              let descriptor = madeDesktopDescriptor(at: url) else { return false }
        return descriptor.isDynamic || descriptor.isSolar
    }

    private nonisolated static func resolveMadeDesktopSource(at descriptorURL: URL) -> URL? {
        guard let descriptor = madeDesktopDescriptor(at: descriptorURL),
              !descriptor.isDynamic,
              !descriptor.isSolar else { return nil }

        let fileName = descriptor.mobileAssetID.lowercased().hasSuffix(".heic")
            ? descriptor.mobileAssetID
            : descriptor.mobileAssetID + ".heic"
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)
                .appendingPathComponent(fileName),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)
                .appendingPathComponent(fileName)
        ]
        if let fullResolution = candidates.first(where: { validImageSource($0) }) {
            return fullResolution.standardizedFileURL
        }
        if let thumbnailURL = descriptor.thumbnailURL,
           validImageSource(thumbnailURL, minimumDimension: 1_920) {
            return thumbnailURL.standardizedFileURL
        }
        return nil
    }

    private nonisolated static func madeDesktopDescriptor(
        at url: URL
    ) -> (mobileAssetID: String, thumbnailURL: URL?, isDynamic: Bool, isSolar: Bool)? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let mobileAssetID = plist["mobileAssetID"] as? String else { return nil }
        let thumbnailURL = (plist["thumbnailPath"] as? String).map { URL(fileURLWithPath: $0) }
        return (
            mobileAssetID,
            thumbnailURL,
            plist["isDynamic"] as? Bool ?? false,
            plist["isSolar"] as? Bool ?? false
        )
    }

    private nonisolated static func validImageSource(_ url: URL, minimumDimension: Int = 1) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        return min(width.intValue, height.intValue) >= minimumDimension
    }

    private nonisolated static func normalizeColorName(_ value: String) -> String {
        value.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }

    private nonisolated static func sourceURL(fromFiles value: Any?) -> URL? {
        guard let files = value as? [Any] else { return nil }
        for file in files {
            if let path = file as? String {
                if let url = URL(string: path), url.isFileURL { return url.standardizedFileURL }
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            if let dictionary = file as? [String: Any] {
                for key in ["relative", "url", "path"] {
                    guard let path = dictionary[key] as? String else { continue }
                    if let url = URL(string: path), url.isFileURL { return url.standardizedFileURL }
                    return URL(fileURLWithPath: path).standardizedFileURL
                }
            }
        }
        return nil
    }

    private nonisolated static func findColorComponents(in value: Any) -> [CGFloat]? {
        if let dictionary = value as? [String: Any] {
            if let values = dictionary["components"] as? [NSNumber], values.count >= 3 {
                return values.prefix(4).map { CGFloat(truncating: $0) }
            }
            for child in dictionary.values {
                if let components = findColorComponents(in: child) { return components }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let components = findColorComponents(in: child) { return components }
            }
        }
        return nil
    }

    private func solidColorSourceURL(components: [CGFloat], fingerprint: String) -> URL? {
        let directory = outputDirectory.appendingPathComponent("Sources", isDirectory: true)
        let url = directory.appendingPathComponent("solid-\(fingerprint).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: 2,
                    height: 2,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let destination = CGImageDestinationCreateWithURL(
                    url as CFURL,
                    UTType.png.identifier as CFString,
                    1,
                    nil
                  ) else { return nil }
            let red = components.indices.contains(0) ? components[0] : 0
            let green = components.indices.contains(1) ? components[1] : 0
            let blue = components.indices.contains(2) ? components[2] : 0
            let alpha = components.indices.contains(3) ? components[3] : 1
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha]) ?? .black)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            guard let image = context.makeImage() else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    nonisolated static func renderWallpaper(_ request: ProcessingRequest) throws -> URL {
        if ["mov", "mp4", "m4v"].contains(request.sourceURL.pathExtension.lowercased()) {
            throw ControllerError.unsupportedVideo
        }
        guard let source = CGImageSourceCreateWithURL(request.sourceURL as CFURL, nil) else {
            throw ControllerError.invalidImage
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw ControllerError.invalidImage }

        let sourceType = CGImageSourceGetType(source) ?? UTType.png.identifier as CFString
        let dynamic = count > 1
        let sourceExtension = request.sourceURL.pathExtension.lowercased()
        let preservesHEIF = ["heic", "heif"].contains(sourceExtension)
            || UTType(sourceType as String)?.conforms(to: .heic) == true
        let outputType = (dynamic || preservesHEIF) ? sourceType : UTType.png.identifier as CFString
        let outputExtension: String
        if preservesHEIF {
            outputExtension = sourceExtension == "heif" ? "heif" : "heic"
        } else if dynamic {
            outputExtension = UTType(sourceType as String)?.preferredFilenameExtension ?? "heic"
        } else {
            outputExtension = "png"
        }
        let finalURL = request.outputURL.appendingPathExtension(outputExtension)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: finalURL.path)
            return finalURL
        }
        let temporaryURL = finalURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-\(finalURL.lastPathComponent)")

        guard let destination = CGImageDestinationCreateWithURL(temporaryURL as CFURL, outputType, count, nil) else {
            throw ControllerError.cannotCreateOutput
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        if let containerProperties = CGImageSourceCopyProperties(source, nil) {
            CGImageDestinationSetProperties(destination, containerProperties)
        }
        for index in 0..<count {
            try Task.checkCancellation()
            guard let sourceImage = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let rendered = renderFrame(sourceImage, request: request) else {
                throw ControllerError.invalidImage
            }
            var properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            properties[kCGImageDestinationLossyCompressionQuality] = 0.94
            CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ControllerError.cannotFinalizeOutput
        }
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        return finalURL
    }

    nonisolated private static func renderFrame(_ image: CGImage, request: ProcessingRequest) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: request.pixelWidth,
            height: request.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: request.pixelWidth, height: request.pixelHeight))

        let target = CGSize(width: request.pixelWidth, height: request.pixelHeight)
        let source = CGSize(width: image.width, height: image.height)
        let scale = max(target.width / source.width, target.height / source.height)
        let drawnSize = CGSize(width: source.width * scale, height: source.height * scale)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: (target.width - drawnSize.width) / 2,
            y: (target.height - drawnSize.height) / 2,
            width: drawnSize.width,
            height: drawnSize.height
        ))

        let desktopTop = CGFloat(request.pixelHeight - (request.hideNotch ? request.menuBarHeight : 0))
        if request.hideNotch, request.menuBarHeight > 0 {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(
                x: 0,
                y: request.pixelHeight - request.menuBarHeight,
                width: request.pixelWidth,
                height: request.menuBarHeight
            ))
        }

        if request.roundedCorners, request.cornerRadius > 0 {
            let radius = CGFloat(min(request.cornerRadius, request.pixelWidth / 2))
            context.setFillColor(CGColor(gray: 0, alpha: 1))

            let left = CGMutablePath()
            left.move(to: CGPoint(x: 0, y: desktopTop - radius))
            left.addLine(to: CGPoint(x: 0, y: desktopTop))
            left.addLine(to: CGPoint(x: radius, y: desktopTop))
            left.addArc(center: CGPoint(x: radius, y: desktopTop - radius), radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            left.closeSubpath()
            context.addPath(left)
            context.fillPath()

            let right = CGMutablePath()
            let width = CGFloat(request.pixelWidth)
            right.move(to: CGPoint(x: width, y: desktopTop - radius))
            right.addLine(to: CGPoint(x: width, y: desktopTop))
            right.addLine(to: CGPoint(x: width - radius, y: desktopTop))
            right.addArc(center: CGPoint(x: width - radius, y: desktopTop - radius), radius: radius, startAngle: .pi / 2, endAngle: 0, clockwise: true)
            right.closeSubpath()
            context.addPath(right)
            context.fillPath()

            let bottomLeft = CGMutablePath()
            bottomLeft.move(to: CGPoint(x: 0, y: radius))
            bottomLeft.addLine(to: CGPoint(x: 0, y: 0))
            bottomLeft.addLine(to: CGPoint(x: radius, y: 0))
            bottomLeft.addArc(
                center: CGPoint(x: radius, y: radius),
                radius: radius,
                startAngle: .pi * 3 / 2,
                endAngle: .pi,
                clockwise: true
            )
            bottomLeft.closeSubpath()
            context.addPath(bottomLeft)
            context.fillPath()

            let bottomRight = CGMutablePath()
            bottomRight.move(to: CGPoint(x: width, y: radius))
            bottomRight.addLine(to: CGPoint(x: width, y: 0))
            bottomRight.addLine(to: CGPoint(x: width - radius, y: 0))
            bottomRight.addArc(
                center: CGPoint(x: width - radius, y: radius),
                radius: radius,
                startAngle: .pi * 3 / 2,
                endAngle: 0,
                clockwise: false
            )
            bottomRight.closeSubpath()
            context.addPath(bottomRight)
            context.fillPath()
        }
        return context.makeImage()
    }

    private func installWallpaperStoreWatchers() {
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true).path,
            "/var/db/Wallpapers"
        ]
        for path in paths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.scheduleReconcile(delay: 0.2, cancelProcessing: true) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            storeWatchers.append(source)
        }
    }

    private func selectedScreens() -> [NSScreen] {
        if includeExternalDisplays { return NSScreen.screens }
        let builtIn = NSScreen.screens.filter { screen in
            guard let displayID = screen.displayID else { return false }
            return CGDisplayIsBuiltin(displayID) != 0
        }
        return builtIn.isEmpty ? (NSScreen.main.map { [$0] } ?? []) : builtIn
    }

    private func pixelSize(for screen: NSScreen) -> (width: Int, height: Int) {
        (
            max(1, Int((screen.frame.width * screen.backingScaleFactor).rounded())),
            max(1, Int((screen.frame.height * screen.backingScaleFactor).rounded()))
        )
    }

    private func menuBarHeight(for screen: NSScreen) -> CGFloat {
        max(screen.safeAreaInsets.top, max(0, screen.frame.maxY - screen.visibleFrame.maxY))
    }

    private var outputDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Mac Stats/Wallpapers", isDirectory: true)
    }

    /// Bounds disk usage without deleting a wallpaper that is visible now.
    /// Persisted source mappings are intentionally retained so an evicted
    /// wallpaper used by another Space can be regenerated when visited.
    private func cleanupWallpaperCache() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let protectedPaths = Set(NSScreen.screens.compactMap { screen -> String? in
            guard let url = effectiveWallpaperURL(for: screen), isGeneratedWallpaper(url) else { return nil }
            return url.standardizedFileURL.path
        })

        struct CacheEntry {
            let url: URL
            let size: Int
            let modified: Date
            let isProtected: Bool
        }

        let entries = urls.compactMap { url -> CacheEntry? in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { return nil }
            return CacheEntry(
                url: url,
                size: max(0, values.fileSize ?? 0),
                modified: values.contentModificationDate ?? .distantPast,
                isProtected: protectedPaths.contains(url.standardizedFileURL.path)
            )
        }.sorted { $0.modified > $1.modified }

        let maximumCount = 20
        let maximumBytes = 500 * 1_024 * 1_024
        var retainedCount = entries.filter(\.isProtected).count
        var retainedBytes = entries.filter(\.isProtected).reduce(0) { $0 + $1.size }

        for entry in entries where !entry.isProtected {
            if retainedCount < maximumCount, retainedBytes + entry.size <= maximumBytes {
                retainedCount += 1
                retainedBytes += entry.size
            } else {
                try? fileManager.removeItem(at: entry.url)
            }
        }

        // Interrupted ImageIO writes are hidden files and therefore handled
        // separately from the normal least-recently-used cache entries.
        if let allURLs = try? fileManager.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil) {
            for url in allURLs where url.lastPathComponent.hasPrefix(".") {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func isGeneratedWallpaper(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(outputDirectory.standardizedFileURL.path + "/")
    }

    private func sourceFingerprint(for url: URL, extra: String) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Self.stableHash([
            url.standardizedFileURL.path,
            String(values?.fileSize ?? 0),
            String(values?.contentModificationDate?.timeIntervalSince1970 ?? 0),
            extra
        ].joined(separator: "|"))
    }

    private static func stableHash(_ string: String) -> String { stableHash(Data(string.utf8)) }

    private static func stableHash(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func loadPersistedRecords() {
        guard let data = defaults.data(forKey: DefaultsKey.wallpaperRecords),
              let decoded = try? JSONDecoder().decode([String: PersistedRecord].self, from: data) else { return }
        persistedRecords = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            if let processedPath = value.processedPath { return (URL(fileURLWithPath: processedPath).standardizedFileURL.path, value) }
            return key.hasPrefix("/") ? (key, value) : nil
        })
    }

    private func persistRecords() {
        if let data = try? JSONEncoder().encode(persistedRecords) {
            defaults.set(data, forKey: DefaultsKey.wallpaperRecords)
        }
    }

    private static func detectDisplayNotch() -> Bool {
        NSScreen.screens.contains { screen in
            guard let displayID = screen.displayID, CGDisplayIsBuiltin(displayID) != 0 else { return false }
            return screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
            CGDirectDisplayID($0.uint32Value)
        }
    }
}
