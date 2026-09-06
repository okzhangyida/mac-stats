# Mac Stats

一款优雅的 macOS 菜单栏美化工具。

Mac Stats 以轻量、简洁、无视觉干扰的方式呈现实时系统状态，并让菜单栏与桌面看起来更统一。保留真正有用的功能，不堆叠冗余设计。

## 下载

从 [GitHub Releases](https://github.com/okzhangyida/mac-stats/releases/latest) 下载经过 Developer ID 签名和 Apple 公证的安装包。支持 macOS 13 及以上版本。

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
- 可使用“隐藏屏幕刘海”将菜单栏背景处理为黑色，并为桌面壁纸添加可调圆角
- 支持静态及随时间变化的动态桌面壁纸、多显示器及桌面空间切换后重应用
- 可在带刘海的屏幕上显示“隐藏屏幕刘海”，无刘海屏幕自动显示“深色菜单栏”
- 快速识别系统墙纸变化，先保存可信原图再重新应用桌面效果，不会把系统过渡图写回桌面
- 支持简体中文和英文界面，并自动跟随 macOS 系统语言
- 系统监测与墙纸数据只在本机处理；基础使用统计不含设备标识并可随时关闭
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

公开构建可通过 `MAC_STATS_ANALYTICS_ENDPOINT` 注入自有统计服务地址；未设置时应用
不会发送任何统计请求。正式服务地址为 `https://macstats-api.justbro.ai/v1/events`，接收服务与部署说明位于 `analytics-worker/`。

## 发布准备

生成带 Hardened Runtime 的 Universal 2 测试应用及明确标注为未公证的 DMG：

```bash
./Scripts/build-universal.sh
./Scripts/package-dmg.sh
```

测试包只用于内部验证，不应公开分发。正式 Bundle ID 为
`cc.macstats.app`。发布前需要 Apple Developer Program、Developer ID
Application 证书及 `notarytool` 钥匙串配置。随后运行：

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \
NOTARY_PROFILE="你的notarytool配置名" \
./Scripts/release-notarized.sh
```

正式脚本会生成 Universal 2 应用，启用 Hardened Runtime，签名 DMG，提交 Apple
公证，装订公证票据，并执行 Gatekeeper 与 SHA-256 验证。

## 开发者与许可

- 开发者：Zhang Yida
- 官网：[macstats.justbro.ai](https://macstats.justbro.ai)
- 使用支持：[support@justbro.ai](mailto:support@justbro.ai)
- 安全问题：[support@justbro.ai](mailto:support@justbro.ai)
- 源代码采用 [GNU General Public License v3.0 or later](LICENSE) 发布（SPDX：`GPL-3.0-or-later`）

隐私与安全说明分别见 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)。

## 当前限制

- 磁盘容量来自公开系统 API；磁盘实时读写吞吐暂时保留为兼容占位。
- 活动进程的 CPU 百分比需要至少两次采样才能计算。
- 受系统权限保护的进程可能无法显示可执行文件路径或所属应用。
- 摄氏温度和风扇 RPM 使用只读的机型相关硬件接口；接口不可用时会安全降级为系统热状态。
- 桌面外观功能暂不处理 macOS 航拍或视频壁纸；关闭功能后，其他桌面空间会在切换到它们时恢复原壁纸。
