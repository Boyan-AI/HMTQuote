# 实时行情表性能测试报告

本文档用于持续记录实时行情表压测结果、结论和后续验证动作。后续每次更新压测数据，都追加到本文档，避免性能结论只保留在聊天记录中。

## 记录规则

- 每次记录必须包含：日期、测试版本、场景、关键参数、原始结果、结论、下一步动作。
- 原始结果优先保留 HiLog JSON，便于后续复算和横向比较。
- 报告中的 `UI写入/s` 表示调度层接收并处理的有效 cell 更新数。
- 报告中的 `UI绘制/s` 表示最终实际写入表格并触发 UI 更新的 cell 数。
- `P95帧间隔` 表示最近采样窗口内 95% 的帧间隔不超过该值。该值越高，越容易出现用户可感知卡顿。
- `P95 >= 33ms` 标记为警告，表示已经明显低于 60FPS 目标。
- `P95 >= 50ms` 标记为异常，表示滑动体验大概率不可接受。

## 当前测试入口

- 页面：`entry/src/main/ets/pages/PerfTest.ets`
- 固定规模：100 行，每侧 20 列。
- 频率选项：10Hz / 20Hz / 50Hz / 100Hz。
- 行情变化范围：整表 / 半表 / 1/4 表，用于控制 mock 行情输入压力。
- A 模式：行情批次到达后，逐个调用 `DataView.updateByItem`。
- B 模式：行情先进入 `QuoteTableStore`，按 `QuoteUpdateScheduler` 的 flush 间隔批量写 UI。
- C 模式：在 B 的基础上只 flush 当前可见行，不可见行继续留在缓存，滚入视窗后再写最新值。
- B flush 选项：33ms / 100ms / 200ms。
- 强制整表刷新：UI 侧诊断开关，用于确认细粒度更新是否触发表格刷新；正式压测应关闭。
- LIVE探针：仅用于确认可视刷新，会额外写少量 cell；正式压测应关闭。
- 分区配色：Canvas 四象限背景色预设切换，用于视觉验证；正式性能对比时固定默认配色。

## 2026-05-20 阶段 1：基准测试

### 场景：300 行、每侧 40 列、10Hz、可见区域批量 1000

原始结果：

```json
{
  "scenarioId": "rows300_cols40_10hz_b1000_visible",
  "variantId": "A_current",
  "elapsedMs": 57715,
  "quoteUpdatesPerSecond": 9166,
  "uiAppliedPerSecond": 9166,
  "uiPaintedPerSecond": 9166,
  "flushPerSecond": 9,
  "measuredFrequencyHz": 9,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 10,
  "quoteUpdates": 529000,
  "uiAppliedUpdates": 529014,
  "uiPaintedCells": 529014,
  "scrollCallbacks": 1757,
  "scrollerSyncCount": 0,
  "frameCount": 3424,
  "frameP50Ms": 15.443378999829292,
  "frameP95Ms": 30.867224000394344,
  "frameP99Ms": 46.312118999660015,
  "maxFrameMs": 46.33072800002992,
  "health": "正常",
  "healthReason": ""
}
```

结论：

- 实测频率为 9Hz，较目标 10Hz 偏差 10%，mock 时钟基本可用。
- P95 为 30.9ms，接近 33ms 警告线，P99 已到 46.3ms。
- 即使 health 为正常，长尾帧已经说明当前结构在高行列规模下存在明显卡顿风险。

### 场景：100 行、每侧 40 列、10Hz、可见区域批量 200

原始结果：

```json
{
  "scenarioId": "rows100_cols40_10hz_b200_visible",
  "variantId": "A_current",
  "elapsedMs": 19320,
  "quoteUpdatesPerSecond": 1998,
  "uiAppliedPerSecond": 2018,
  "uiPaintedPerSecond": 2018,
  "flushPerSecond": 10,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "quoteUpdates": 38600,
  "uiAppliedUpdates": 38988,
  "uiPaintedCells": 38988,
  "scrollCallbacks": 554,
  "scrollerSyncCount": 0,
  "frameCount": 1250,
  "frameP50Ms": 15.443847000598907,
  "frameP95Ms": 15.449602998793125,
  "frameP99Ms": 15.451086999848485,
  "maxFrameMs": 15.451398998498917,
  "health": "正常",
  "healthReason": ""
}
```

结论：

- 在 200 cell/tick、10Hz 场景下，帧间隔稳定在 15.45ms 左右。
- 小批量更新不是当前主要瓶颈，问题主要出现在单 tick 大量 cell 复制和表格结构刷新时。

## 2026-05-20 阶段 1：固定 100 行、每侧 20 列压测

### 场景：A_current，10Hz，1/4 表刷新

原始告警：

```json
{
  "level": "异常",
  "reason": "P95帧间隔61.8ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 32468,
  "quoteUpdatesPerSecond": 9979,
  "uiAppliedPerSecond": 10578,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 61.75066200084984,
  "frameP99Ms": 77.19554699957371,
  "maxFrameMs": 123.52819399908185,
  "scrollCallbacks": 692,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 33470,
  "quoteUpdatesPerSecond": 9979,
  "uiAppliedPerSecond": 10578,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.33528799936175,
  "frameP99Ms": 61.77311199903488,
  "maxFrameMs": 92.64221099950373,
  "scrollCallbacks": 721,
  "scrollerSyncCount": 0
}
```

结论：

- 固定 100 行、每侧 20 列、10Hz、1/4 表刷新已经稳定触发警告或异常。
- 该场景适合作为阶段 2 的基准失败场景。
- 1/4 表约 1000 cell/tick，10Hz 下约 10000 cell/s；当前 A 版本逐个写 UI 的成本已经明显影响帧稳定性。

## 2026-05-20 阶段 2：A/B 初测

### 场景：A_current，10Hz，1/4 表刷新

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 18897,
  "quoteUpdatesPerSecond": 9948,
  "uiAppliedPerSecond": 10545,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.31333100050688,
  "frameP99Ms": 46.3321139998734,
  "maxFrameMs": 92.63601899892092,
  "scrollCallbacks": 580,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 28983,
  "quoteUpdatesPerSecond": 9971,
  "uiAppliedPerSecond": 10570,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.32741900160909,
  "frameP99Ms": 61.74641400203109,
  "maxFrameMs": 61.770256001502275,
  "scrollCallbacks": 581,
  "scrollerSyncCount": 0
}
```

结论：

- A 版本 P95 稳定在 46ms 左右。
- 该场景下用户滑动会有明显卡顿风险。

### 场景：B_scheduler，10Hz，1/4 表刷新，33ms flush

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 46318,
  "quoteUpdatesPerSecond": 9975,
  "uiAppliedPerSecond": 9975,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.3005810007453,
  "frameP99Ms": 46.328759998083115,
  "maxFrameMs": 61.768984999507666,
  "scrollCallbacks": 1405,
  "scrollerSyncCount": 0
}
```

```json
{
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "timestamp": 1779288047328,
  "elapsedMs": 53046,
  "quoteUpdatesPerSecond": 9991,
  "uiAppliedPerSecond": 9991,
  "uiPaintedPerSecond": 10591,
  "flushPerSecond": 10,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "quoteUpdates": 530000,
  "uiAppliedUpdates": 530002,
  "uiPaintedCells": 561802,
  "scrollCallbacks": 1495,
  "scrollerSyncCount": 0,
  "frameCount": 2907,
  "frameP50Ms": 15.444199997931719,
  "frameP95Ms": 46.31718999892473,
  "frameP99Ms": 46.331300999969244,
  "maxFrameMs": 61.768984999507666,
  "health": "警告",
  "healthReason": "P95帧间隔46.3ms>=33ms"
}
```

结论：

- B_scheduler 在 33ms flush 下没有改善 P95，仍约 46ms。
- 原因是行情输入为 10Hz，每 100ms 才来一批数据；33ms flush 基本等不到第二批数据，无法形成跨 tick 合并。
- 当刷新范围是 1/4 表且每批更新多为不同 cell 时，单批内部去重收益也有限。
- 该数据不能证明 B 方案无效，只能证明 `10Hz + 33ms flush` 不是有效合并参数。
- 当时 `UI绘制/s` 高于 `UI写入/s`，主要受视觉探针额外写入影响。正式压测需要关闭视觉探针。

## 当前阶段结论

- A 版本在 `100行 * 每侧20列 * 10Hz * 1/4表` 下已经达到 P95 46ms 级别，属于明确可复现的性能问题。
- B 方案需要调整 flush 周期后再测，不能只用 33ms 判断收益。
- 下一步重点不是继续扩大数据规模，而是在同一失败场景下比较：
  - A_current。
  - B_scheduler + 100ms flush。
  - B_scheduler + 200ms flush。
- 判断 B 是否有效的核心指标：
  - `UI绘制/s` 是否明显低于 `UI写入/s`。
  - `P95 / P99 / max` 是否下降。
  - 滑动过程中是否仍触发 33ms 或 50ms 阈值告警。

## 下一轮测试计划

固定参数：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- 视觉探针：关闭。
- 整表刷新：关闭。
- 每个场景至少运行 30 秒，建议 60 秒。

测试顺序：

1. A_current，记录完整 JSON。
2. B_scheduler，flush 100ms，记录完整 JSON。
3. B_scheduler，flush 200ms，记录完整 JSON。
4. 若 B 的 `UI绘制/s` 明显下降但 P95 不降，说明瓶颈更可能在表格结构、布局或滚动同步。
5. 若 B 的 `UI绘制/s` 和 P95 均下降，继续测试 20Hz / 50Hz。

## 2026-05-20 阶段 2：A/B flush 对照

固定参数：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- 场景 ID：`rows100_cols20_10hz_quartertable`。

### 1. A_current

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 10273,
  "quoteUpdatesPerSecond": 9929,
  "uiAppliedPerSecond": 10525,
  "uiPaintedPerSecond": 10525,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.3233080022037,
  "frameP99Ms": 46.333000998944044,
  "maxFrameMs": 61.775609999895096,
  "scrollCallbacks": 173,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 15281,
  "quoteUpdatesPerSecond": 9947,
  "uiAppliedPerSecond": 10544,
  "uiPaintedPerSecond": 10544,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.325109999626875,
  "frameP99Ms": 46.3333659991622,
  "maxFrameMs": 61.775609999895096,
  "scrollCallbacks": 430,
  "scrollerSyncCount": 0
}
```

结论：

- A_current 继续稳定触发 46ms 级 P95 警告。
- `UI写入/s` 与 `UI绘制/s` 基本一致，说明 A 版本没有合并收益，行情更新直接落到 UI。

### 2. B_scheduler，推定 flush 100ms

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 76253,
  "quoteUpdatesPerSecond": 9993,
  "uiAppliedPerSecond": 9993,
  "uiPaintedPerSecond": 9919,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.30860900133848,
  "frameP99Ms": 46.33077400177717,
  "maxFrameMs": 61.774916000664234,
  "scrollCallbacks": 1801,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 81318,
  "quoteUpdatesPerSecond": 9986,
  "uiAppliedPerSecond": 9986,
  "uiPaintedPerSecond": 9914,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.30539299920201,
  "frameP99Ms": 46.33206199854612,
  "maxFrameMs": 61.774916000664234,
  "scrollCallbacks": 1866,
  "scrollerSyncCount": 0
}
```

结论：

- `UI绘制/s` 仅从约 9990 降到约 9910，合并幅度不足 1%。
- P95 仍约 46.3ms，和 A_current 基本一致。
- 在 10Hz 输入下，100ms flush 仍基本是一批行情对应一次 UI flush，无法显著跨 tick 合并。

### 3. B_scheduler，推定 flush 200ms

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 22238,
  "quoteUpdatesPerSecond": 9938,
  "uiAppliedPerSecond": 9938,
  "uiPaintedPerSecond": 5243,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.306007999926805,
  "frameP99Ms": 61.75296600162983,
  "maxFrameMs": 77.20455500110984,
  "scrollCallbacks": 321,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 27249,
  "quoteUpdatesPerSecond": 9982,
  "uiAppliedPerSecond": 9982,
  "uiPaintedPerSecond": 5252,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.30368600040674,
  "frameP99Ms": 61.75296600162983,
  "maxFrameMs": 77.20455500110984,
  "scrollCallbacks": 346,
  "scrollerSyncCount": 0
}
```

结论：

- `UI绘制/s` 从 A 的约 10500 降到约 5250，降幅约 50%。
- P95 仍保持约 46.3ms，P99 和 max 反而高于 A 的部分采样。
- 这说明阶段 2 的数据合并已经生效，但没有解决当前 P95 长帧。
- 当前瓶颈更可能在表格组件结构、布局/重建成本、滚动链路或测试页统计采样方式，而不是单纯的 cell 写入数量。

### 阶段 2 当前判断

- B_scheduler 的 200ms flush 能显著降低 `UI绘制/s`，证明缓存合并逻辑有效。
- P95 未下降，说明继续只调 flush 间隔的收益有限。
- 下一步应进入阶段 3 验证“只刷可见区域 / 不可见只入缓存”，同时补充更细粒度的 flush 耗时指标：
  - 每次 flush 的 snapshots 数。
  - 每次 flush 的实际 `updateByItem` 耗时。
  - 每次强制整表刷新耗时。
  - flush 发生时是否正在滚动。
  - flush 周期内是否出现 46ms 固定倍数长帧。

## 2026-05-20 阶段 3：只刷可见行测试入口

本次代码更新新增 `C_visible_scheduler`：

- C 在 B_scheduler 基础上启用“只刷可见”。
- scheduler 只从 `QuoteTableStore` drain 当前可见行范围。
- 不可见行 pending 不丢弃，继续保留在缓存中。
- 当不可见行滚入可见范围后，再 flush 该行最新值。

新增统计字段：

- `flushedCellsPerSecond`：每秒进入 flush 的 snapshot 数。
- `maxFlushCells`：单次 flush 最大 snapshot 数。
- `lastFlushCells`：最近一次 flush snapshot 数。
- `avgFlushCostMs`：平均 flush 耗时。
- `maxFlushCostMs`：最大 flush 耗时。
- `lastFlushCostMs`：最近一次 flush 耗时。

下一轮固定测试：

1. A_current，10Hz，1/4 表，视觉探针关，整表刷新关。
2. B_scheduler，flush 200ms，10Hz，1/4 表，视觉探针关，整表刷新关。
3. C_visible_scheduler，flush 200ms，10Hz，1/4 表，视觉探针关，整表刷新关。
4. 重点比较 `uiPaintedPerSecond`、`flushedCellsPerSecond`、`maxFlushCells`、`maxFlushCostMs` 和 P95。

判断标准：

- 如果 C 的 `flushedCellsPerSecond` 和 `uiPaintedPerSecond` 明显下降，且 P95 下降，说明不可见 cell 写入是主要瓶颈。
- 如果 C 的写入量下降但 P95 仍约 46ms，说明长帧更可能来自表格结构、滚动同步、布局或 VSync 采样窗口。
- 如果 `maxFlushCostMs` 接近或超过 16ms，应继续拆 flush 或进入行级 Canvas / BuilderNode 验证。

## 2026-05-20 阶段 3：首轮 C_visible_scheduler 验证

固定参数：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- 视觉探针：关闭。
- 整表刷新：关闭。

### 1. A_current

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
