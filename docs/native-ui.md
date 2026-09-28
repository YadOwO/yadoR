# 原生准备度界面

参考日期：2026-09-28。

## Apple 官方参考

- [watchOS 27 准备指数使用手册](https://support.apple.com/zh-cn/guide/watch/flx4gnzby346/watchos)
- [使用手册中的界面截图](https://ipcdn-web.apple.com/assets/v2/web/8fd62263-5cb8-4246-bde8-bea3d1b53437)
- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos/)

官方截图采用深色背景、青绿色半圆轨道与位置圆点，分数和状态居中，下方是活动、生命体征、睡眠三个入口。本次借鉴这套信息层级；不使用 Apple 的图标素材，也不改动独立评分算法、分档文案或数据处理。

## 本次调整

- Watch 首屏直接展示仪表与三个因素入口，说明、同步信息和设置放在后续滚动区域。入口显示因素名称，不根据缺失的数据推断“正常”勾选状态。
- iPhone 使用系统大标题、随浅色／深色外观变化的背景与强调色、统一仪表，以及带分隔线的因素分组。此处是原生风格适配，不声称复刻 Apple 的 iPhone 页面。
- 因素详情按类别区分图标颜色，将相关指标收拢为一组。
- 保留演示标记、无数据不出分、基线进度、年龄确认与设置入口。评分继续提供完整 VoiceOver 描述；无障碍大字体下，分数文字移到仪表下方，避免重叠。

## 验证

- iPhone 18 Pro Max / iOS 27：3 项 UI 测试通过，覆盖评分与三个因素详情、基线／缺少数据、年龄确认；已检查评分页与基线页截图。
- Watch Series 12 42mm / watchOS 27：复核首屏仪表、三个因素入口和演示标记，并检查无数据不出分。
- 初次构建遇到磁盘不足，关闭显式模块和索引后完成编译。首次截图发现 Watch 演示标记不在首屏，随后补充首屏边界断言并调整间距。

模拟器只使用明确标记的演示数据，不代表真实健康数据或配对同步验收。无障碍大字体提供独立布局预览，深色外观跟随系统；这两种变体尚未完成模拟器截图验收。

本次使用的构建参数为 `CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO SWIFT_ENABLE_EXPLICIT_MODULES=NO CLANG_ENABLE_EXPLICIT_MODULES=NO`，仅影响命令行验证，不修改工程配置。UI 测试使用现有 `yadoR` 和 `yadoR Watch App` scheme，`-parallel-testing-enabled NO`。
