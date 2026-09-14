# Development

Build requirements: macOS, Xcode Command Line Tools, and a compatible Swift 6 toolchain.

## 开发运行

```bash
swift run MacStats
```

## 构建应用

首次开始一个新的交付批次时，先按北京时间分配构建号；同一批次的重新构建不要重复分配：

```bash
./Scripts/allocate-build-number.swift 1.0.0 "本批次用途"
```

构建号以 `Build/build-numbers.json` 为唯一记录。对外使用 `YYYYMMDD.NN`，构建脚本会自动
写入兼容 macOS 的 `CFBundleVersion` 映射。

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
`ai.justbro.macstats`。发布前需要 Apple Developer Program、Developer ID
Application 证书及 `notarytool` 钥匙串配置。随后运行：

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \
NOTARY_PROFILE="你的notarytool配置名" \
./Scripts/release-notarized.sh
```

正式脚本会生成 Universal 2 应用，启用 Hardened Runtime，签名 DMG，提交 Apple
公证，装订公证票据，并执行 Gatekeeper 与 SHA-256 验证。
