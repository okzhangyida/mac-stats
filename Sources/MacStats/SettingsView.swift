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
            Section("外观") {
                Picker("界面外观", selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appAppearance) { newValue in
                    AppAppearance.apply(newValue)
                }
                Text("选择“跟随系统”时，会随 macOS 浅色或深色外观自动切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("菜单栏") {
                Text("显示指标（最多两个）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(DisplayMetric.allCases) { metric in
                    Toggle(isOn: selectionBinding(for: metric)) {
                        Label(metric.title, systemImage: metric.systemImage)
                    }
                    .disabled(!selectedMetrics.contains(metric) && selectedMetrics.count >= 2)
                }
                if selectedMetrics.isEmpty {
                    Text("当前仅显示菜单栏图标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("显示顺序：\(selectedMetrics.map(\.title).joined(separator: " → "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("刷新间隔", selection: $store.refreshInterval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }
                .onChange(of: store.refreshInterval) { _ in store.restart() }
                Toggle("登录时自动启动", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("内存") {
                Toggle("内存占用包含缓存文件", isOn: $store.includeCachedMemory)
                    .toggleStyle(.switch)
                    .onChange(of: store.includeCachedMemory) { _ in
                        store.resetMemoryHistory()
                    }
                Text("关闭时按已使用内存计算；开启后会把可回收的文件缓存计入占用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("隐私") {
                Label("所有监测数据仅在本机处理，不会上传。", systemImage: "hand.raised.fill")
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
            launchError = "无法更新登录项：\(error.localizedDescription)"
        }
    }
}
