import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let store: MonitorStore
    @ObservedObject private var desktopAppearance = DesktopAppearanceController.shared
    @ObservedObject private var usageAnalytics = UsageAnalytics.shared
    @AppStorage("displayMetrics") private var displayMetrics = "cpu,memory"
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @AppStorage("refreshInterval") private var refreshInterval = 2.0
    @AppStorage("includeCachedMemory") private var includeCachedMemory = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section(L10n.string("settings.appearance_section", fallback: "Appearance")) {
                Picker(L10n.string("settings.appearance_picker", fallback: "App Appearance"), selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appAppearance) { newValue in
                    AppAppearance.apply(newValue)
                }
                Text(L10n.string("settings.appearance_help", fallback: "When set to System, the app follows the macOS light or dark appearance."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.desktop_appearance_section", fallback: "Desktop Appearance")) {
                Toggle(isOn: desktopHideNotchBinding) {
                    Label(
                        desktopAppearance.hasDisplayNotch
                            ? L10n.string("settings.hide_notch", fallback: "Hide Screen Notch")
                            : L10n.string("settings.dark_menu_bar", fallback: "Dark Menu Bar"),
                        systemImage: "rectangle.topthird.inset.filled"
                    )
                }
                .toggleStyle(.switch)

                Text(
                    desktopAppearance.hasDisplayNotch
                        ? L10n.string("settings.hide_notch_help", fallback: "Makes the menu bar black so the display notch blends naturally into the top edge.")
                        : L10n.string("settings.dark_menu_bar_help", fallback: "Makes the menu bar black so its contents stay clear against the wallpaper.")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: desktopRoundedCornersBinding) {
                    Label(
                        L10n.string("settings.rounded_desktop", fallback: "Rounded desktop corners"),
                        systemImage: "rectangle.roundedtop"
                    )
                }
                .toggleStyle(.switch)

                HStack {
                    Text(L10n.string("settings.corner_radius", fallback: "Corner Radius"))
                    Slider(value: desktopCornerRadiusBinding, in: 8...40, step: 1)
                        .disabled(!desktopAppearance.roundedCorners)
                    Text(L10n.string("settings.points", fallback: "%.0f pt", desktopAppearance.cornerRadius))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Toggle(
                    L10n.string("settings.external_displays", fallback: "Apply to external displays"),
                    isOn: desktopExternalDisplaysBinding
                )
                .toggleStyle(.switch)

                desktopAppearanceStatus

                HStack {
                    Button(L10n.string("settings.apply_appearance", fallback: "Refresh Effect")) {
                        desktopAppearance.applyNow()
                    }
                    .disabled(!desktopAppearance.isEnabled)

                    Button(L10n.string("settings.disable_appearance", fallback: "Turn Off Effects")) {
                        desktopAppearance.disableEffects()
                    }
                    .disabled(!desktopAppearance.isEnabled)
                }

                Text(L10n.string(
                    "settings.desktop_overlay_help",
                    fallback: "Supports image and solid-color wallpapers. Dynamic, Aerial, and video wallpapers remain unchanged."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.menu_bar_section", fallback: "Menu Bar")) {
                Text(L10n.string("settings.metrics_limit", fallback: "Display metrics (up to two)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(DisplayMetric.allCases) { metric in
                    Toggle(isOn: selectionBinding(for: metric)) {
                        Label(metric.title, systemImage: metric.systemImage)
                    }
                    .disabled(!selectedMetrics.contains(metric) && selectedMetrics.count >= 2)
                }
                if selectedMetrics.isEmpty {
                    Text(L10n.string("settings.icon_only", fallback: "Only the menu bar icon is shown"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        L10n.string(
                            "settings.display_order",
                            fallback: "Display order: %@",
                            selectedMetrics.map(\.title).joined(separator: " → ")
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker(L10n.string("settings.refresh_interval", fallback: "Refresh Interval"), selection: $refreshInterval) {
                    Text(L10n.string("settings.seconds", fallback: "%d sec", 1)).tag(1.0)
                    Text(L10n.string("settings.seconds", fallback: "%d sec", 2)).tag(2.0)
                    Text(L10n.string("settings.seconds", fallback: "%d sec", 5)).tag(5.0)
                }
                .onChange(of: refreshInterval) { newValue in
                    store.refreshInterval = newValue
                    store.restart()
                }
                Toggle(L10n.string("settings.launch_at_login", fallback: "Launch at Login"), isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            Section(L10n.string("settings.memory_section", fallback: "Memory")) {
                Toggle(L10n.string("settings.include_cache", fallback: "Include file cache in memory usage"), isOn: $includeCachedMemory)
                    .toggleStyle(.switch)
                    .onChange(of: includeCachedMemory) { newValue in
                        store.includeCachedMemory = newValue
                        store.resetMemoryHistory()
                    }
                Text(L10n.string("settings.cache_help", fallback: "When disabled, usage reflects memory used. When enabled, reclaimable file cache is also included."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.privacy_section", fallback: "Privacy")) {
                Toggle(isOn: anonymousUsageBinding) {
                    Label(
                        L10n.string("settings.analytics_toggle", fallback: "Help Improve Mac Stats"),
                        systemImage: "chart.bar.xaxis"
                    )
                }
                .toggleStyle(.switch)

                Text(L10n.string(
                    "settings.analytics_help",
                    fallback: "Sends basic usage statistics without a device identifier to help us understand version adoption. System status, processes, sensors, network speeds, and wallpaper data are never sent. You can turn this off at any time."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(L10n.string("settings.privacy_notice", fallback: "CPU, memory, temperature, process, network, and wallpaper data always stay on this Mac."), systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            AppAppearance.apply(appAppearance)
            launchAtLogin = SMAppService.mainApp.status == .enabled
            desktopAppearance.start()
        }
    }

    private var selectedMetrics: [DisplayMetric] {
        displayMetrics.split(separator: ",").compactMap { DisplayMetric(rawValue: String($0)) }
    }

    private func selectionBinding(for metric: DisplayMetric) -> Binding<Bool> {
        Binding(
            get: { selectedMetrics.contains(metric) },
            set: { enabled in
                var selection = selectedMetrics
                if enabled {
                    guard selection.count < 2, !selection.contains(metric) else { return }
                    selection.append(metric)
                } else {
                    selection.removeAll { $0 == metric }
                }
                displayMetrics = selection.map(\.rawValue).joined(separator: ",")
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { updateLaunchAtLogin($0) }
        )
    }

    private var anonymousUsageBinding: Binding<Bool> {
        Binding(
            get: { usageAnalytics.isEnabled },
            set: { usageAnalytics.setEnabled($0) }
        )
    }

    private var desktopHideNotchBinding: Binding<Bool> {
        Binding(
            get: { desktopAppearance.hideNotch },
            set: { desktopAppearance.setHideNotch($0) }
        )
    }

    private var desktopRoundedCornersBinding: Binding<Bool> {
        Binding(
            get: { desktopAppearance.roundedCorners },
            set: { desktopAppearance.setRoundedCorners($0) }
        )
    }

    private var desktopCornerRadiusBinding: Binding<Double> {
        Binding(
            get: { desktopAppearance.cornerRadius },
            set: { desktopAppearance.setCornerRadius($0) }
        )
    }

    private var desktopExternalDisplaysBinding: Binding<Bool> {
        Binding(
            get: { desktopAppearance.includeExternalDisplays },
            set: { desktopAppearance.setIncludeExternalDisplays($0) }
        )
    }

    @ViewBuilder
    private var desktopAppearanceStatus: some View {
        switch desktopAppearance.status {
        case .idle:
            Label(
                L10n.string("settings.overlay_idle", fallback: "Desktop appearance effects are off."),
                systemImage: "rectangle.on.rectangle.slash"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .waiting:
            Label(
                L10n.string("settings.wallpaper_waiting", fallback: "Waiting for macOS to finish changing the wallpaper…"),
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("settings.wallpaper_processing", fallback: "Optimizing desktop wallpaper…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .active:
            Label(
                L10n.string("settings.overlay_active", fallback: "Desktop appearance effects are active."),
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        case let .unsupported(message):
            Label(
                L10n.string("settings.wallpaper_video_unsupported", fallback: "The current dynamic or video wallpaper was left unchanged: %@", message),
                systemImage: "film"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .failed(message):
            Label(
                L10n.string("settings.overlay_error", fallback: "Couldn’t apply desktop appearance: %@", message),
                systemImage: "xmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = L10n.string(
                "settings.login_item_error",
                fallback: "Couldn’t update the login item: %@",
                error.localizedDescription
            )
        }
    }
}
