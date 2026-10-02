# 首版验证记录

日期：2026-09-22。Xcode 27.0（27A266a），本地分支 `feat/readiness`，未提交或推送。

## 已验证

| 检查 | 结果 | 证据范围 |
|---|---|---|
| Debug 编译 | 通过 | iPhone、Watch、WidgetKit 扩展，arm64 模拟器 |
| Release 编译 | 通过 | 两端与组件；无 Debug 演示入口 |
| 真机 SDK Release 编译 | 通过 | `generic/platform=iOS`，包含 Watch 与组件；未签名、未安装到真实设备 |
| ReadinessCore | 40 项通过 | 评分门槛、基线、缺项、重复、跨夜、补觉、换来源、分档、单调性、跨日隐藏、传输版本 |
| iPhone 数据／缓存 | 15 项通过 | 实际数据归并函数、去重指纹、重算、读取失败、输入删除、清除竞争、缓存失败、演示隔离、后台启动时的缓存发布 |
| iPhone UI | 3 个场景通过 | 评分及三因素详情、建立基线／无数据不出分、年龄确认后启用连接按钮 |
| Watch UI | 2 个场景通过 | 42mm 评分首屏、滚动并进入睡眠详情、无数据不显示 0 分 |
| 代码审查 | 已修复所有行动项 | 三角色交叉审查，覆盖正确性、数据处理效率、界面与复用；另复核后台启动修复 |

UI 测试使用明确标记的演示数据。iPhone 为 iPhone 18 Pro Max 模拟器，Watch 为 Series 12 42mm 模拟器；不是 S9 真机验证。先前失败用例修复后分别定向复测通过，未把失败运行计为通过。

调试过程中修复了：旧来源回包覆盖新来源、清除后重发旧结果、退出演示失败暴露示例分、无关原始样本制造更新时间、后台冷启动缺少待发送缓存、组件入口不能回今日页、Watch 首屏拥挤。UI 自动化改用实际状态等待，并用缓慢短拖动避免越过 Watch 入口；保留功能断言。

## 命令

```sh
swift test --package-path Packages/ReadinessCore
xcodebuild -project yadoR.xcodeproj -scheme yadoR -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' test
xcodebuild -project yadoR.xcodeproj -scheme 'yadoR Watch App' -configuration Debug -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm)' test
```

本次构建使用独立 DerivedData，模拟器关闭签名、只构建 arm64，并关闭索引／显式模块以减少磁盘占用；这些是命令行覆盖，不改变工程默认发布设置。开始时磁盘不足导致构建与安装失败，空间恢复后完成以上验证。测试 Target 出现的 AppIntents 元数据跳过提示不影响本项目功能；App 未提供 App Intents。

## 尚未验证及发行条件

- 未读取个人健康数据；S9 实际睡眠／HRV 覆盖、Apple Watch 来源标识、限定授权窗口需要真机核验。
- 尚未证明真实配对设备上的 WatchConnectivity 投递时延、锁屏下后台查询、组件系统调度及耗电。模型、缓存和视图测试不代替这些条件。
- 评分参数为独立实验规则。腕温、呼吸、血氧与全天静息心率在本版只解释，不影响分数；训练负荷使用活动能量替代，未读取运动耗能评级。见 [算法规格](algorithm.md)。
- 开发者 Team、HealthKit／App Groups 的正式签名、最终商店截图与隐私材料，需在真机和发行准备阶段完成。

真机验证时重点观察：有足够历史能否立即初始化、无新输入是否保持更新时间、断线重连后是否保持同一结果版本、清除及撤回权限后是否仍显示旧分、跨日组件是否隐藏昨天分数。只在这些场景与数据质量核验通过后对外承诺机型支持及刷新体验。
