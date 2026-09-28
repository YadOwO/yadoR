# 原生准备度界面

参考日期：2026-09-28。

## Apple 官方参考

- [watchOS 27 准备指数使用手册](https://support.apple.com/zh-cn/guide/watch/flx4gnzby346/watchos)
- [使用手册中的界面截图](https://ipcdn-web.apple.com/assets/v2/web/8fd62263-5cb8-4246-bde8-bea3d1b53437)
- [准备指数 App Store 官方截图集](https://apps.apple.com/cn/app/%E5%87%86%E5%A4%87%E6%8C%87%E6%95%B0/id6764448634)：9 分青绿色首页、3 分紫色首页、状态说明、影响因素卡片，共四张。
- [生命体征官方说明](https://support.apple.com/en-ae/120142)：Watch 夜间生命体征和 iPhone 健康详情页面。
- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos/)

已查看上述四张 App Store 截图及两张生命体征原图。准备指数首页以分数和状态为中心，背景和仪表随状态变色，下滑后显示解释与因素卡片。生命体征页面用大号状态、数据区域及简洁卡片区分信息层级。Apple HIG 强调抬腕即读、减少导航层级、通过数码表冠纵向浏览，并让背景颜色承载状态。

本次借鉴信息层级和布局，不使用 Apple 的图标素材，也不改动独立评分算法、分档文案或数据处理。没有历史序列的页面不添加趋势图或时间切换控件。

## 本次调整

- 四档状态使用粉、紫、蓝、青绿配色，统一仪表、状态文案、背景及设置中的分档说明。紫色低分和青绿色高分来自已查看的官方截图，其余配色是本 App 的设计选择；浅色模式使用更深的文字颜色。
- 半圆轨道增加当前位置附近的高亮弧段，保留小圆点；分数使用系统字体。
- Watch 保留首屏仪表与三个因素入口，下滑依次展示状态说明、三个因素摘要卡片、同步信息和设置。卡片与快捷入口共用活动、生命体征、睡眠的顺序。当前模型没有因素异常等级或明确的正负贡献字段，因此不伪造勾选、感叹号或升降分组。
- iPhone 使用系统大标题、轻微状态色评分卡和独立因素卡片。每个因素展示真实摘要及首项关键指标，详情页按摘要、记录、解释、未计入项和来源排序。此处是原生风格适配，不声称复刻 Apple 的 iPhone 准备指数页面。
- 保留演示标记、无数据不出分、基线进度、年龄确认与设置入口。评分继续提供完整 VoiceOver 描述；从 XXXL 字体开始，将分数文字移到仪表下方，避免重叠，并提供四档评分预览。

## 验证

本轮按用户要求不运行构建、测试或模拟器，仅检查代码差异。以下是上一版的验证记录，不代表本轮布局已完成运行验收。

- iPhone 18 Pro Max / iOS 27：3 项 UI 测试通过，覆盖评分与三个因素详情、基线／缺少数据、年龄确认；已检查评分页与基线页截图。
- Watch Series 12 42mm / watchOS 27：复核首屏仪表、三个因素入口和演示标记，并检查无数据不出分。
- 初次构建遇到磁盘不足，关闭显式模块和索引后完成编译。首次截图发现 Watch 演示标记不在首屏，随后补充首屏边界断言并调整间距。

模拟器只使用明确标记的演示数据，不代表真实健康数据或配对同步验收。无障碍大字体提供独立布局预览，深色外观跟随系统；这两种变体尚未完成模拟器截图验收。

上一版验证使用的构建参数为 `CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO SWIFT_ENABLE_EXPLICIT_MODULES=NO CLANG_ENABLE_EXPLICIT_MODULES=NO`，仅影响命令行验证，不修改工程配置。UI 测试使用现有 `yadoR` 和 `yadoR Watch App` scheme，`-parallel-testing-enabled NO`。
