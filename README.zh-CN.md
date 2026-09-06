# Mac Stats

轻量原生的 macOS 菜单栏工具：隐藏刘海、显示系统状态，让菜单栏与桌面更协调。

[官网](https://macstats.justbro.ai) · [下载](https://github.com/okzhangyida/mac-stats/releases/latest) · [English](README.md)

## 菜单栏与桌面美化

通过深色菜单栏弱化 MacBook 刘海的视觉存在感，并为桌面添加可调圆角。无刘海屏幕也可以使用深色菜单栏。

![深色菜单栏与桌面圆角（英文界面）](docs/images/mac-stats-menubar-live-en.png)

## 系统状态，一目了然

集中查看 CPU、内存、磁盘容量、网络、电池、温度和风扇状态；菜单栏最多显示两个指标，支持近期趋势和高占用进程查看。

![系统状态监测面板（英文界面）](docs/images/mac-stats-dashboard-en.png)

- 中英文原生界面，支持浅色、深色及跟随系统外观。
- 可调刷新间隔，可选择登录时启动。
- 支持 Apple silicon 与 Intel；传感器可用性因机型而异。
- 支持静态、传统动态桌面壁纸与多显示器；不支持航拍或视频壁纸。

## 下载与安装

需要 **macOS 13 或更新版本**。从官网或 GitHub Releases 下载通用版 DMG，打开后将 Mac Stats 拖入 Applications。

官方安装包已使用 Developer ID 签名，并通过 Apple 公证。

## 隐私

系统读数、进程与壁纸数据仅在本机处理。无需账号、无广告、无个人追踪。默认开启不含设备标识的基础使用统计，可在设置中关闭。详见 [隐私政策](PRIVACY.md)。

## 开发与支持

源代码构建说明见 [开发文档](docs/DEVELOPMENT.md)。问题反馈可通过 Issues，支持与安全问题请联系 [support@justbro.ai](mailto:support@justbro.ai)。

## 许可与致谢

开发者：Zhang Yida。源代码采用 [GNU GPL v3.0 或更新版本](LICENSE)。

**本产品使用 OpenAI Codex 进行开发。**
