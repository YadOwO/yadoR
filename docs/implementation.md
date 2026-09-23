# yadoR 首版实现

依据：[产品方案](product-plan.md)。产品范围维持 R1–R8，不修改原方案。

## 技术决定

- iOS 27 / watchOS 27，SwiftUI；iPhone 负责只读 HealthKit、计算及发布结果，Watch 负责展示、请求同步与缓存；手机不可用时不声称生成新的评估。
- `ReadinessCore` 本地 Swift Package 存放可测试的纯数据模型、睡眠归并及独立确定性算法；不引入第三方算法或依赖。
- 用 WatchConnectivity application context 发送当前结果。Watch App 与 WidgetKit 扩展通过 App Group 共享当前结果。只保存派生结果，不长期复制原始健康数据，不上传服务器。
- 所有自动产生的结果来自授权后的真实输入；开发演示仅在 Debug 显式启用并标记，不写入正式缓存或同步。
- 当前参数为实验规则，单独记录在 `algorithm.md`。测试验证规则正确性，不代表准确性或医学有效性；实机校准是发行前条件。

## 实现单元

| 单元 | 文件归属 | 目标与验证 |
|---|---|---|
| 核心算法 | `Packages/ReadinessCore/Sources/ReadinessCore/ReadinessEngine.swift`、对应 Tests、`docs/algorithm.md` | R1/R2/R4/R5/R8；个人基线、同指标比较、无核心输入不出分、三因素解释、重复/缺失/边界/单调性测试 |
| 健康数据 | `yadoR/HealthKitClient.swift`、`Packages/ReadinessCore/Sources/ReadinessCore/SleepNormalizer.swift`、对应 Tests | R2/R4/R5；公开只读 API、同源处理、去重、跨夜/午睡归属、指纹，错误与空数据分开 |
| 页面 | `SharedUI/`、两端 `ContentView.swift` | R1–R4/R7/R8；原生导航、独立刻度图形、三因素详情、权限引导、设置与无数据状态、辅助功能 |
| 集成与组件 | `Shared/`、两端 App 入口、`yadoRWidgets/`、工程配置、集成测试 | R5–R8；单一计算来源、过期结果隐藏、同步重试、缓存清除、组件刷新、编译及模拟器验证 |

所有单元共享 `Models.swift` 接口。并行实现仅修改各自归属文件；不提交、不运行整个工程测试，由集成阶段统一验证。

## 发行前实机检查

- 开发者 Team 与 HealthKit / App Groups 签名配置。
- S9 授权历史、夜间心率与 SDNN 数量、睡眠记录来源及数据覆盖。
- 配对设备离线 / 重连 / 换表、数据删除 / 权限收回、锁屏、跨日、后台投递和组件耗电。
- 独立算法参数校准、最终视觉及商店隐私材料。编译和合成数据测试不能替代这些检查。
