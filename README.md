# Mac Stats

一款轻量、原生、隐私友好的 macOS 菜单栏状态监测应用。

## 功能

- 菜单栏可选择显示最多两个状态指标，也可仅显示图标
- CPU、内存、磁盘、网络和电池概览，显示具体芯片档位与内存总容量
- CPU、内存与 CPU 温度的最近两分钟趋势，带系统时间轴和网格
- Apple Silicon HID / Intel SMC 温度读取与系统热状态
- 自动识别风扇数量并显示实时 RPM；无风扇机型明确标识
- CPU/内存高占用进程排行
- 自动识别进程所属应用，并提供可搜索、排序的全部进程详情窗口
- 可调整刷新频率
- 支持登录时自动启动
- 界面可跟随系统外观，也可手动选择浅色或深色
- 支持简体中文和英文界面，并自动跟随 macOS 系统语言
- 数据只在本机处理
- 带有原生 macOS 应用图标

## 系统要求

- macOS 13 或更高版本
- Xcode 15 或兼容的 Swift 6 工具链

## 开发运行

```bash
swift run MacStats
```

## 构建应用

```bash
./Scripts/build-app.sh
open "dist/Mac Stats.app"
```

脚本会生成并临时签名 `dist/Mac Stats.app`。首次本机构建不包含 Developer ID
签名和公证，仅适合开发与本机使用。

## 发布准备

生成带 Hardened Runtime 的 Universal 2 测试应用及明确标注为未公证的 DMG：

```bash
./Scripts/build-universal.sh
./Scripts/package-dmg.sh
```

测试包只用于内部验证，不应公开分发。正式发布前需要确定永久 Bundle ID、加入
Apple Developer Program，并创建 Developer ID Application 证书及 `notarytool`
钥匙串配置。随后通过环境变量运行：

```bash
MAC_STATS_BUNDLE_ID="你的永久Bundle ID" \
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \
NOTARY_PROFILE="你的notarytool配置名" \
./Scripts/release-notarized.sh
```

正式脚本会生成 Universal 2 应用，启用 Hardened Runtime，签名 DMG，提交 Apple
公证，装订公证票据，并执行 Gatekeeper 与 SHA-256 验证。隐私、安全说明与闭源免费
使用许可分别见 `PRIVACY.md`、`SECURITY.md` 与 `LICENSE`。

## 当前限制

- 磁盘容量来自公开系统 API；磁盘实时读写吞吐暂时保留为兼容占位。
- 活动进程的 CPU 百分比需要至少两次采样才能计算。
- 受系统权限保护的进程可能无法显示可执行文件路径或所属应用。
- 摄氏温度和风扇 RPM 使用只读的机型相关硬件接口；接口不可用时会安全降级为系统热状态。
