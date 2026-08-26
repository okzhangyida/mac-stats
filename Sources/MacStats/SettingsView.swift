import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    @AppStorage("displayMetrics") private var displayMetrics = "cpu,memory"
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
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
                Picker(L10n.string("settings.refresh_interval", fallback: "Refresh Interval"), selection: $store.refreshInterval) {
                    Text(L10n.string("settings.seconds", fallback: "%d sec", 1)).tag(1.0)
                    Text(L10n.string("settings.seconds", fallback: "%d sec", 2)).tag(2.0)
                    Text(L10n.string("settings.seconds", fallback: "%d sec", 5)).tag(5.0)
                }
                .onChange(of: store.refreshInterval) { _ in store.restart() }
                Toggle(L10n.string("settings.launch_at_login", fallback: "Launch at Login"), isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            Section(L10n.string("settings.memory_section", fallback: "Memory")) {
                Toggle(L10n.string("settings.include_cache", fallback: "Include file cache in memory usage"), isOn: $store.includeCachedMemory)
                    .toggleStyle(.switch)
                    .onChange(of: store.includeCachedMemory) { _ in
                        store.resetMemoryHistory()
                    }
                Text(L10n.string("settings.cache_help", fallback: "When disabled, usage reflects memory used. When enabled, reclaimable file cache is also included."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.privacy_section", fallback: "Privacy")) {
                Label(L10n.string("settings.privacy_notice", fallback: "All monitoring data is processed locally and is never uploaded."), systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            AppAppearance.apply(appAppearance)
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
