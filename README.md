# yadoR

iPhone + Apple Watch 准备度 App，最低 iOS 27 / watchOS 27。实现当前评分、四档状态、睡眠／生命体征／活动解释、历史基线初始化、日间数据更新，以及表盘复杂功能和智能叠放组件。

当前算法版本为 `0.1-experimental`。这是可供开发和实机验证的独立规则实现，不是苹果算法，也尚未完成 S9 数据校准。模拟器测试不证明健康评估准确性。

## 运行

1. 使用 Xcode 27 打开 `yadoR.xcodeproj`，选择 `yadoR`（iPhone）或 `yadoR Watch App`。
2. 模拟器可在“说明与设置 → 开发演示”查看评分、基线和无数据状态。演示有明确标记，不写入正式缓存或发送到另一端；Release 不提供此入口。
3. 真机运行前，为 iPhone、Watch、Widget 三个 Target 选择自己的开发者 Team，并注册／启用 `group.com.yado.yadoR`。iPhone 需要 HealthKit 及其后台投递权限。
4. 在 iPhone 完成年龄确认及健康授权。已有历史可用于初始化；核心记录不足时不会产生默认分数。

只读 HealthKit，不申请写入权限，不创建账号或健康数据服务器。iPhone 负责计算；Watch 显示同步结果，手机离线时保留带时间的当天缓存。系统决定后台投递和组件刷新时机。

## 代码

- `Packages/ReadinessCore`：模型、确定性规则、睡眠归并及纯 Swift 测试。
- `yadoR/HealthKitClient.swift`：健康授权、同源数据读取与后台观察。
- `AppRuntime`：应用状态、刷新合并、WatchConnectivity 传输。
- `Shared`：保护文件的共享缓存及隐私声明。
- `SharedUI`：两端今日页、因素页、设置和无数据状态。
- `yadoRWidgets`：四种表盘复杂功能尺寸，包括用于智能叠放的矩形组件。
- `Design/AppIcon.svg`：独立 R 字形图标的矢量源文件。

## 规则及验证

- [算法规格](docs/algorithm.md)：公式、数据门槛、时间窗口、缺失处理及限制。
- [健康数据处理](docs/health-data.md)：来源选择、去重及实际设备的验证事项。
- [实现决定](docs/implementation.md)：功能范围、计算与同步方式。
- [验证记录](docs/verification.md)：已通过的检查与真机验证边界。

纯逻辑测试：`swift test --package-path Packages/ReadinessCore`。

Xcode 的 iPhone Test 操作覆盖缓存、删除输入、刷新失败、清除期间的竞争以及 UI 流程。Watch UI 测试验证今日页与因素入口。测试中的健康输入为合成数据，不读取个人健康记录。

发行前仍需在 S9 及声明支持的其他型号上验证：真实样本覆盖、跨设备来源标识、后台唤醒、锁屏、跨日、断线重连、组件刷新和耗电；再校准参数并完善商店材料。
