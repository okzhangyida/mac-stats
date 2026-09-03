# Mac Stats 测试说明

## 本机回归

运行以下命令会以 macOS 13.0 为最低部署目标执行单元测试和 release 构建：

```sh
./Scripts/check-macos13.sh
```

当前测试覆盖：

- 最近两分钟历史数据的保留时长和最大采样数
- 网络速率、硬件信息和进程名称格式
- 高占用进程数量限制
- 壁纸四个圆角的像素级渲染
- 主面板与设置页的浅色、深色界面渲染

设置 `MAC_STATS_SNAPSHOT_DIR` 后，界面渲染测试会把四张 PNG 截图写入指定目录。

## macOS 13 Ventura 虚拟机

测试环境使用 Tart 和 Apple Virtualization.framework：

- 基准虚拟机：`mac-stats-ventura-base`
- 日常测试虚拟机：`mac-stats-ventura`
- 处理器：6 vCPU
- 内存：8 GB
- 磁盘：120 GB（镜像配置，APFS 克隆共享未修改数据）
- 账户：镜像内置的隔离测试账户，不登录 Apple ID 或个人账户

完整回归命令：

```sh
./Scripts/tart-ventura-test.sh
```

脚本会启动虚拟机、共享并同步当前源码、在 Ventura 中原生运行测试和构建、验证 App 首次启动与退出后重新启动、保存日志和界面截图，然后关闭虚拟机。结果保存在 `TestReports/ventura/`，该目录不会提交到 Git。

## 必须使用真机验证的项目

虚拟机没有真实 Mac 的全部硬件，以下功能仍需在受支持的真机上测试：

- 刘海检测、菜单栏着色与不同实体屏幕形态
- 动态墙纸和系统墙纸提供器的完整行为
- CPU 温度、SMC 风扇和无风扇机型识别
- 电池电量、充电状态和循环次数
- Intel Mac 以及不同 Apple 芯片的传感器差异

虚拟机主要用于发现旧系统 API、资源、本地化、构建、启动和普通 SwiftUI 布局问题，不能代替上述硬件覆盖。
