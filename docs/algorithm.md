# yadoR 独立评分规则 v0.1

算法标识：`0.1-experimental`。实现：`Packages/ReadinessCore/Sources/ReadinessCore/ReadinessEngine.swift`。

这是一组为首版数据流程编写的、可复现的实验规则。没有复制 GitHub 算法代码，也没有使用苹果未公开的公式。当前参数尚未经过 S9 实际夜间数据校准或人群有效性验证；单元测试只验证规则行为。功能范围按产品方案执行，分数不与苹果准备指数逐分等同。

## 输入、归属及出分条件

输入是数据读取层已经归并的睡眠会话和每日活动摘要；本模块不访问 HealthKit、网络、磁盘或真实时钟。调用方传入 `now` 和 `calendar`，默认值只方便正常调用。日期按当前日历和时区分组，跨午夜睡眠归属于结束日期。

- 睡眠按记录 ID 去重；同 ID 但内容冲突时排除，避免随机选一版。每个结束日期选实际睡眠最长的已完成会话作为主要睡眠。同样长时按结束时间、来源 ID、记录 ID 确定顺序。
- 今天必须有已完成的主要睡眠；选中后再判断夜间心率和 HRV 质量，不能用较短补觉替代缺失核心体征的主要睡眠。
- 有效主要睡眠至少 3 小时；至少 3 次夜间心率，首尾覆盖至少 1 小时，覆盖不得超过会话长度。心率必须有限且在 20–250 次/分；这只是排除明显坏输入的宽界限，不是健康正常范围。
- 必须有本次主要睡眠的 SDNN：至少 1 次、有限、`0 < SDNN ≤ 500 ms`。没有记录时不沿用旧 HRV，不转换或混入 RMSSD。
- 过去 49 个日历日期（今天加之前 48 天）至少有 7 个同时满足睡眠、心率和 SDNN 要求的夜晚，包括今天。真正用于比较的历史不含今天，因此至少 6 晚。
- 以今天主要睡眠的 `sourceID` 筛选历史，再按日期选主要睡眠。其他来源不补齐夜晚计数；换表来源后重新检查和建立基线。
- 今天必须有实际读到的活动能量，过去 28 天至少有 6 个不同日期的活动能量记录。`nil` 表示不可用，不转换成 0；明确读到的 0 可以使用。活动能量须有限且在 0–30,000 千卡，宽上限只拦截坏输入。
- 同一天存在内容不同的多个活动摘要时，该天排除；读取层应当提供完成去重后的唯一摘要，不能把冲突项直接相加。

当日主要睡眠、核心体征或当日活动缺失时是 `missingData`；历史不足是 `buildingBaseline`。两者都没有分数。`validNights` 是同时通过心率和 SDNN 门槛的夜晚数量，因此不会在 HRV 尚不够时显示已经完成初始化。

睡眠会话中的时间必须有限且有正长度，长度不超过 24 小时，睡眠和清醒总时长不得超过会话范围（容许 1 秒舍入差）。未结束或未来会话不参与当前评估。非法可选体征只被忽略，不伪造成零值或正常值。

## 计算

所有中间量只在内部使用。用户只看到一个 0–10 整数及三类因素，不展示第二套睡眠、生命体征、活动分数。

```text
raw = 8 − sleepPenalty + vitalsAdjustment − activityPenalty
score = round(clamp(raw, 0, 10))
```

0–1、2–4、5–7、8–10 对应四档。`round` 为最接近整数、正好半分时远离零。8 分起点和下面所有系数均为实验参数，不意味着某个分数具有医学上的安全含义。

### 睡眠

使用之前有效主要睡眠的时长中位数作为个人参考，并限制到 7–9 小时。它是本算法的比较刻度，不是对所有年龄、所有人的睡眠需求建议。

```text
referenceHours = clamp(median(previousMainSleepHours), 7, 9)
deficitHours = max(referenceHours − currentMainSleepHours, 0)
napOffsetHours = min(deficitHours, napHours × 0.5, 1)
durationPenalty = min((deficitHours − napOffsetHours) × 1.25, 4)

bedtimeShiftMinutes = abs(circularDifference(currentBedtime, historicalBedtime))
regularityPenalty = min(max(bedtimeShiftMinutes − 30, 0) / 60 × 0.5, 1.2)

awakeFraction = recordedAwakeSeconds / (asleepSeconds + recordedAwakeSeconds)
awakePenalty = min(max(awakeFraction − 0.1, 0) × 5, 1.2)
sleepPenalty = durationPenalty + regularityPenalty + awakePenalty
```

入睡时间在 24 小时圆环上比较；先选总圆周距离最小的历史时刻作为锚点，再求偏移中位数，避免 23:50 和 00:10 被平均成中午。重复锚点选择有稳定排序。

补觉只使用同一来源、今天结束、开始不早于主要睡眠结束、睡眠至少 10 分钟且不足 3 小时的已完成会话。重叠补觉按时间分段取最高睡眠比例，不重复累加。补觉最多抵扣原有缺口的 1 小时等效时长，且只按记录时长的 50% 抵扣；主要睡眠没有时长缺口就没有额外奖励。

“记录到的清醒”仅代表已有清醒分段。当前输入模型不能区分完全没有清醒记录和确实没有被记录的清醒，不能据此声称测量了全部觉醒事件。这是实机校准时必须核验的数据限制。

### 核心生命体征

SDNN 与夜间心率分别建立基线。HRV 使用自然对数，夜间心率保持次/分。两者都只使用同一来源、相同主要睡眠场景的历史记录。

```text
center = median(previousValues)
MAD = median(abs(previousValues − center))
scale = max(MAD × 1.4826, floor)
z = clamp((currentValue − center) / scale, −3, 3)
```

HRV 的 `floor = 0.15`（对数单位），夜间心率的 `floor = 3` 次/分。固定下限防止相同历史数据造成除零或微小变化被无限放大；偏离上限避免异常单次值无限加减分。

```text
hrvPenalty = min(max(−hrvZ − 0.5, 0) × 0.9, 2)
heartPenalty = min(max(heartZ − 0.5, 0) × 0.8, 2)
hrvBenefit = min(max(hrvZ − 0.5, 0) × 0.6, 1.5)
heartBenefit = min(max(−heartZ − 0.5, 0) × 0.2, 0.5)
vitalsAdjustment = hrvBenefit + heartBenefit − hrvPenalty − heartPenalty
```

此处“高 HRV / 低夜间心率”的有限正向作用只是模型方向约定，不代表这些变化在所有身体状态下都是有益变化。对异常高 HRV、疾病、药物、心律及传感器误差的处理尚需验证。

呼吸、腕温、血氧和全天静息心率在 v0.1 **只展示、不参与评分**。有至少 6 条对应历史时显示本指标历史中位数，否则明确历史不足；静息心率只比较其每日静息心率历史，绝不拿它替代夜间心率。合法显示范围为呼吸 5–60 次/分、腕温 25–45 °C、血氧 0.5–1 的比例、静息心率 20–250 次/分；这些仍是坏输入防护界限。

可选指标缺失时显示未读到或未计入，分数不受是否存在可选指标影响。因此不会通过缺项后重新归一化权重让分数升高，也不能声称这些可选指标已经影响了首版分数。

### 活动

首版统一使用活动能量作为粗略负荷输入。体能训练时长和运动耗能评级只作说明；体能训练能量已经包含在活动能量中，不再单独扣一遍。不同训练的生理负荷未必与能量成比例，因此这不是苹果训练负荷或完整训练科学模型。

```text
dailyReference = median(observedPriorDailyEnergyWithin28Days)
todayRatio = observedTodayEnergy / max(dailyReference, 100 kcal)
todayPenalty = min(max(todayRatio − 0.5, 0) × 0.75, 2)
```

历史少于 21 个有记录日期，或前 7 天少于 5 天有记录时，明确使用临时日参考，不声称已有完整 28 天基线，不计算额外的近期负荷扣减。读取不到的日期不填零。

覆盖满足后，只比较截至昨天的两个窗口，避免今天负荷同时改变分子、基线及当天扣减。

```text
recentMean = mean(observedEnergyFromPrior7Days)
longMean = mean(observedEnergyFromPrior28Days)
historyRatio = recentMean / max(longMean, 100 kcal)
historyPenalty = min(max(historyRatio − 1.2, 0) × 1.5, 1.5)
activityPenalty = todayPenalty + historyPenalty
```

100 千卡是防止低活动参考导致比值爆炸的数值下限，不用于生成缺失活动数据。没有训练不等同于没有活动能量；没有评级也不构造评级。当前模型若有 `effortLoad`，含义是已经读取到的评级乘训练分钟，只显示该记录汇总，不宣称未评级训练已经纳入。

## 更新和稳定性

- 相同有效输入、评估日期、时区和算法版本得到相同分数与因素。集合排序、重复记录和传入顺序不改变结果。
- 增加今天活动能量不会单独提高分数；仅追加训练分钟或评级不会重复扣能量。
- 固定其他输入时，增加睡眠时长不会增加睡眠扣减；补觉不固定加分，不重复累计。
- 不以“距上次运动多久”“现在几点”为恢复奖励。没有新有效数据时，当天重算的分数和因素不变；生成时间只表示调用时间。应用层用输入指纹避免把重复查询当作新结果发布。
- `dataThrough` 使用读取层提供的真实样本截止时间；没有该元数据时退回已完成同来源睡眠的最新结束时间。它与 `generatedAt` 分开保存。读取层负责提供涵盖活动等全部有效输入的真实截止时间。
- 昨日快照通过 `visible(at:calendar:)` 转为无当日结果，隐藏旧分数和因素；不能把昨日结果当作今天。
- 算法版本变更后重新评估；新来源从其自身历史重建，不能继承另一块表的 HRV 基线。

## 验证边界

测试覆盖首个 7 晚、49 天窗口、当日核心缺失、心率覆盖、源切换、重复与冲突记录、跨午夜、补觉重叠、未来记录、固定输入随时间稳定、负荷方向、零值与缺失、临时活动参考、可选指标、NaN/无穷/异常值、防除零、分档边界和昨日结果隐藏。

发行前还需要 S9 真实数据验证以下事项：夜间 SDNN 是否常能达到门槛、3 次心率与 1 小时覆盖是否合理、源标识能否稳定区分设备、清醒分段覆盖、活动能量历史完整性、低运动用户的参考刻度、7 晚短基线稳定性、年龄与作息差异、评分分布和日内变化幅度。通过合成输入测试或编译，均不能替代这些结果。
