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
  "variantId": "A_current",
  "elapsedMs": 43219,
  "quoteUpdatesPerSecond": 9972,
  "uiAppliedPerSecond": 10270,
  "uiPaintedPerSecond": 10270,
  "flushPerSecond": 10,
  "flushedCellsPerSecond": 9972,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 12.06119149688225,
  "maxFlushCostMs": 32.853271484375,
  "lastFlushCostMs": 13.88525390625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.323494002223015,
  "frameP99Ms": 46.33345400169492,
  "maxFrameMs": 77.20011500269175,
  "scrollCallbacks": 1076,
  "scrollerSyncCount": 0
}
```

结论：

- A_current 每秒 flush 约 9972 cell，平均 flush 耗时约 12.1ms，最大 flush 耗时约 32.9ms。
- P95 仍为 46.3ms，说明单次 flush 最大耗时已经足以压缩帧预算。

### 2. B_scheduler，flush 200ms

原始结果：

```json
{
  "level": "异常",
  "reason": "P95帧间隔61.7ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 1087,
  "quoteUpdatesPerSecond": 9200,
  "uiAppliedPerSecond": 9200,
  "uiPaintedPerSecond": 4876,
  "flushPerSecond": 5,
  "flushedCellsPerSecond": 4600,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 13.533642578125,
  "maxFlushCostMs": 16.851806640625,
  "lastFlushCostMs": 11.40673828125,
  "measuredFrequencyHz": 9,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 10,
  "frameP95Ms": 61.748756002634764,
  "frameP99Ms": 77.18994199857116,
  "maxFrameMs": 77.18994199857116,
  "scrollCallbacks": 8,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 2090,
  "quoteUpdatesPerSecond": 9570,
  "uiAppliedPerSecond": 9570,
  "uiPaintedPerSecond": 5072,
  "flushPerSecond": 5,
  "flushedCellsPerSecond": 4785,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 12.7260009765625,
  "maxFlushCostMs": 16.851806640625,
  "lastFlushCostMs": 12.902587890625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.33159899711609,
  "frameP99Ms": 77.18994199857116,
  "maxFrameMs": 77.21613299846649,
  "scrollCallbacks": 38,
  "scrollerSyncCount": 0
}
```

结论：

- B_scheduler 把 flush 频率降到约 5 次/秒，`UI绘制/s` 降到约 5000。
- 单次最大 flush 耗时约 16.9ms，已经接近一帧预算。
- P95 仍为 46.3ms，说明降低 flush 频率仍不足以解决长帧。

### 3. C_visible_scheduler，flush 200ms

原始结果：

```json
{
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "C_visible_scheduler",
  "timestamp": 1779289647432,
  "elapsedMs": 25284,
  "quoteUpdatesPerSecond": 10006,
  "uiAppliedPerSecond": 10007,
  "uiPaintedPerSecond": 0,
  "flushPerSecond": 0,
  "flushedCellsPerSecond": 0,
  "maxFlushCells": 0,
  "lastFlushCells": 0,
  "avgFlushCostMs": 0,
  "maxFlushCostMs": 0,
  "lastFlushCostMs": 0,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "quoteUpdates": 253000,
  "uiAppliedUpdates": 253004,
  "uiPaintedCells": 4,
  "scrollCallbacks": 893,
  "scrollerSyncCount": 0,
  "frameCount": 1636,
  "frameP50Ms": 15.442796997725964,
  "frameP95Ms": 15.45040499791503,
  "frameP99Ms": 15.451319999992847,
  "maxFrameMs": 15.45167500153184,
  "health": "正常",
  "healthReason": ""
}
```

结论：

- 该结果不能作为 C 性能收益结论。
- `flushPerSecond=0`、`uiPaintedPerSecond=0` 表示 C 实际没有刷新可见表格。
- 根因：旧版 `QuarterTable` mock 按 index 顺序刷新前 25 行；组件启动后会滚到中间行附近，可见行与 pending 行没有交集。
- 已修正 mock：`FullTable` / `HalfTable` / `QuarterTable` 改为按全表行列均匀分布，避免 1/4 表只落在前 25 行。

下一步：

- 重新跑 A / B / C 三组。
- 重点确认 C 的 `flushPerSecond` 和 `uiPaintedPerSecond` 必须大于 0；否则仍然不是有效测试。

## 2026-05-20 阶段 3：修正 mock 后 A/B/C 对照

固定参数：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- mock 分布：`QuarterTable` 已修正为全表均匀分布。
- 视觉探针：关闭。
- 整表刷新：关闭。

### 1. A_current

原始结果：

```json
{
  "level": "异常",
  "reason": "P95帧间隔92.6ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 6575,
  "quoteUpdatesPerSecond": 9734,
  "uiAppliedPerSecond": 10318,
  "uiPaintedPerSecond": 10318,
  "flushPerSecond": 10,
  "flushedCellsPerSecond": 9734,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 12.08392333984375,
  "maxFlushCostMs": 29.246337890625,
  "lastFlushCostMs": 10.23095703125,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 92.6394210010767,
  "frameP99Ms": 123.53730399906635,
  "maxFrameMs": 138.96890700235963,
  "scrollCallbacks": 3,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "异常",
  "reason": "P95帧间隔123.5ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 11802,
  "quoteUpdatesPerSecond": 9829,
  "uiAppliedPerSecond": 10418,
  "uiPaintedPerSecond": 10418,
  "flushPerSecond": 10,
  "flushedCellsPerSecond": 9829,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 13.297817887931034,
  "maxFlushCostMs": 29.246337890625,
  "lastFlushCostMs": 10.3671875,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 123.51673999801278,
  "frameP99Ms": 138.96890700235963,
  "maxFrameMs": 138.97090500220656,
  "scrollCallbacks": 3,
  "scrollerSyncCount": 0
}
```

结论：

- A_current 在修正 mock 后退化为异常，P95 最高达到 123.5ms。
- 单次 flush 最大耗时约 29.2ms，已经超过 16.7ms 一帧预算。

### 2. B_scheduler

原始结果：

```json
{
  "level": "异常",
  "reason": "P95帧间隔123.5ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 12266,
  "quoteUpdatesPerSecond": 9865,
  "uiAppliedPerSecond": 9865,
  "uiPaintedPerSecond": 7950,
  "flushPerSecond": 8,
  "flushedCellsPerSecond": 7500,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 13.058779509171195,
  "maxFlushCostMs": 30.5361328125,
  "lastFlushCostMs": 16.38916015625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 123.5271669998765,
  "frameP99Ms": 138.96231000125408,
  "maxFrameMs": 185.29100200161338,
  "scrollCallbacks": 55,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "异常",
  "reason": "P95帧间隔123.5ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "B_scheduler",
  "elapsedMs": 17449,
  "quoteUpdatesPerSecond": 9915,
  "uiAppliedPerSecond": 9915,
  "uiPaintedPerSecond": 7351,
  "flushPerSecond": 7,
  "flushedCellsPerSecond": 6935,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 13.371146209969009,
  "maxFlushCostMs": 33.274658203125,
  "lastFlushCostMs": 11.162109375,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 123.52217599749565,
  "frameP99Ms": 138.958107996732,
  "maxFrameMs": 185.29100200161338,
  "scrollCallbacks": 109,
  "scrollerSyncCount": 0
}
```

结论：

- B_scheduler 相比 A 降低了部分 `UI绘制/s`，但 P95 仍为 123.5ms。
- 单次最大 flush 耗时约 33.3ms，仍超过 2 帧预算。
- 当前 B 的批量合并不足以改善帧稳定性。

### 3. C_visible_scheduler

原始结果：

```json
{
  "level": "异常",
  "reason": "P95帧间隔123.5ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "C_visible_scheduler",
  "elapsedMs": 11909,
  "quoteUpdatesPerSecond": 9909,
  "uiAppliedPerSecond": 9909,
  "uiPaintedPerSecond": 1324,
  "flushPerSecond": 7,
  "flushedCellsPerSecond": 876,
  "maxFlushCells": 120,
  "lastFlushCells": 120,
  "avgFlushCostMs": 11.133004520716293,
  "maxFlushCostMs": 26.858154296875,
  "lastFlushCostMs": 12.358642578125,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 123.534907002002,
  "frameP99Ms": 138.9690800011158,
  "maxFrameMs": 154.39085299894214,
  "scrollCallbacks": 35,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "异常",
  "reason": "P95帧间隔123.5ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "C_visible_scheduler",
  "elapsedMs": 17200,
  "quoteUpdatesPerSecond": 9884,
  "uiAppliedPerSecond": 9884,
  "uiPaintedPerSecond": 1390,
  "flushPerSecond": 8,
  "flushedCellsPerSecond": 915,
  "maxFlushCells": 120,
  "lastFlushCells": 120,
  "avgFlushCostMs": 10.943003934972426,
  "maxFlushCostMs": 26.858154296875,
  "lastFlushCostMs": 9.02978515625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 123.53440199792385,
  "frameP99Ms": 138.9690800011158,
  "maxFrameMs": 154.39085299894214,
  "scrollCallbacks": 67,
  "scrollerSyncCount": 0
}
```

结论：

- C_visible_scheduler 已经有效刷新：`flushPerSecond > 0`，`uiPaintedPerSecond > 0`。
- C 将 `UI绘制/s` 从 A 的约 10400 降到约 1400，降幅约 86%。
- C 将单次 flush cell 数从 1000 降到 120。
- 但 C 的 P95 仍为 123.5ms，说明仅减少可见写入量仍不能解决当前长帧。
- C 单次最大 flush 耗时仍达 26.9ms，120 个 cell 写入仍可能超过一帧预算。

### 阶段 3 当前判断

- 数据层优化已经证明有效：B/C 都能显著降低 UI 写入量。
- 帧稳定性没有改善，说明瓶颈已经转移或主要存在于渲染结构、布局重算、组件响应式传播、滚动同步或 `updateByItem` setter 触发链路。
- 下一步不建议继续扩大 scheduler 参数调优。应进入结构验证：
  - 先做 `C_chunked_visible_scheduler`：把一次可见 flush 的 120 cell 拆成多帧小批量，验证单帧写入预算。
  - 同时准备 RowCanvas / BuilderNode 原型，验证减少 cell 组件数量后的性能上限。

## 2026-05-20 阶段 4：D_canvas 原型入口

本次代码更新新增 `D_canvas`：

- 新增 `CanvasQuoteTable`。
- 新增 `CanvasQuoteGridData`，用普通数组保存左右两侧 cell 文本和颜色。
- D 模式下不再使用每个 cell 一个 ArkUI 组件，而是由 Canvas 绘制表格。
- D 模式仍复用 `MockQuoteFeed`、`QuoteTableStore`、`QuoteUpdateScheduler` 和 `PerfStats`。
- Canvas flush 时批量写数组，整批只递增一次 `canvasRevision`，避免每个 cell 触发一次 Canvas 重绘。

当前原型边界：

- 这是 D1 性能上限原型，不是最终业务组件。
- 当前绘制整张 100 行表格，未做行级 Canvas 拆分、可见列裁剪、点击坐标换算、主题/字号完整适配。
- 用于验证“去掉 per-cell ArkUI 组件后，P95 和 flush cost 是否显著下降”。

下一轮测试：

1. A_current，10Hz，1/4 表，组件渲染。
2. C_visible_scheduler，10Hz，1/4 表，组件渲染，只刷可见开。
3. D_canvas，10Hz，1/4 表，Canvas 渲染。

重点观察：

- `variantId` 应为 `D_canvas`。
- `uiPaintedPerSecond` 是否与 B/C 同一量级。
- `maxFlushCostMs` 是否明显低于 C 的 26.9ms。
- `frameP95Ms` 是否从 123ms 降回 16-33ms 区间。

判断标准：

- 如果 D_canvas 的 P95 明显下降，说明主瓶颈是 per-cell 组件结构和响应式 setter 链路。
- 如果 D_canvas 的 P95 仍高，需要继续拆分 Canvas 绘制范围，检查整表 Canvas 重绘成本、Scroll 嵌套和 VSync 采样。

## 2026-05-20 阶段 4：D_canvas 首轮验证

固定参数：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- 视觉探针：关闭。
- 整表刷新：关闭。

### 1. A_current，组件渲染

原始结果：

```json
{
  "level": "异常",
  "reason": "P95帧间隔77.2ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 1972,
  "quoteUpdatesPerSecond": 9636,
  "uiAppliedPerSecond": 10214,
  "uiPaintedPerSecond": 10214,
  "flushPerSecond": 10,
  "flushedCellsPerSecond": 9636,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 15.003122430098685,
  "maxFlushCostMs": 39.736328125,
  "lastFlushCostMs": 18.873046875,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 77.18467900156975,
  "frameP99Ms": 123.53010099753737,
  "maxFrameMs": 123.53010099753737,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "异常",
  "reason": "P95帧间隔61.8ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 6996,
  "quoteUpdatesPerSecond": 9863,
  "uiAppliedPerSecond": 10454,
  "uiPaintedPerSecond": 10454,
  "flushPerSecond": 10,
  "flushedCellsPerSecond": 9863,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 13.21636520606884,
  "maxFlushCostMs": 39.736328125,
  "lastFlushCostMs": 10.729736328125,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 61.76946100220084,
  "frameP99Ms": 92.64565600082278,
  "maxFrameMs": 123.53010099753737,
  "scrollCallbacks": 71,
  "scrollerSyncCount": 0
}
```

结论：

- A_current 仍为异常，P95 在 61-77ms 区间。
- 组件渲染下平均 flush 耗时约 13-15ms，最大 flush 耗时约 39.7ms。

### 2. 复测记录，variantId 仍为 A_current

原始结果：

```json
{
  "level": "异常",
  "reason": "P95帧间隔61.8ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 16969,
  "quoteUpdatesPerSecond": 8604,
  "uiAppliedPerSecond": 9120,
  "uiPaintedPerSecond": 9120,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 8604,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 13.243821235552225,
  "maxFlushCostMs": 27.516357421875,
  "lastFlushCostMs": 11.486328125,
  "measuredFrequencyHz": 9,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 10,
  "frameP95Ms": 61.769393999129534,
  "frameP99Ms": 77.20899500325322,
  "maxFrameMs": 77.21277099847794,
  "scrollCallbacks": 71,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "异常",
  "reason": "P95帧间隔61.7ms>=50ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "A_current",
  "elapsedMs": 21973,
  "quoteUpdatesPerSecond": 6644,
  "uiAppliedPerSecond": 7043,
  "uiPaintedPerSecond": 7043,
  "flushPerSecond": 7,
  "flushedCellsPerSecond": 6644,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 13.243821235552225,
  "maxFlushCostMs": 27.516357421875,
  "lastFlushCostMs": 11.486328125,
  "measuredFrequencyHz": 7,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 30,
  "frameP95Ms": 61.73844600096345,
  "frameP99Ms": 77.20139499753714,
  "maxFrameMs": 77.20984200015664,
  "scrollCallbacks": 71,
  "scrollerSyncCount": 0
}
```

结论：

- 该组 `variantId` 仍为 `A_current`，不能作为 C_visible_scheduler 对照。
- 后续 C 对照需要确认页面当前文本显示 `C_visible_scheduler`，且导出 JSON 中 `variantId` 一致。

### 3. D_canvas

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "elapsedMs": 7551,
  "quoteUpdatesPerSecond": 9933,
  "uiAppliedPerSecond": 9933,
  "uiPaintedPerSecond": 8873,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 8873,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 0.9309810809235075,
  "maxFlushCostMs": 1.774658203125,
  "lastFlushCostMs": 0.89697265625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.31716100126505,
  "frameP99Ms": 61.756166998296976,
  "maxFrameMs": 61.77208999916911,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "elapsedMs": 12614,
  "quoteUpdatesPerSecond": 9989,
  "uiAppliedPerSecond": 9989,
  "uiPaintedPerSecond": 8879,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 8879,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 0.9345049176897321,
  "maxFlushCostMs": 1.77880859375,
  "lastFlushCostMs": 0.906494140625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.328348997980356,
  "frameP99Ms": 61.76223699748516,
  "maxFrameMs": 77.21148600056767,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0
}
```

结论：

- D_canvas 将平均 flush 耗时从 A 的约 13-15ms 降到约 0.93ms。
- D_canvas 将最大 flush 耗时从 A 的 27-39ms 降到约 1.78ms。
- D_canvas 的 P95 从 A 的 61-77ms 降到 46.3ms，已从异常降为警告，但仍未达到 33ms 以下。
- 该结果确认主瓶颈之一是 per-cell ArkUI 组件和响应式 setter 链路。
- D_canvas 仍有 46ms 长帧，下一步应优化 Canvas 绘制提交本身：避免整表重绘，改为行级 Canvas 或可见行/可见列裁剪。

### 阶段 4 当前判断

- Canvas 路线成立，数据写入和 flush 成本已大幅下降。
- 当前 D_canvas 仍绘制整张 100 行表格，且每批行情触发整表 Canvas redraw。
- 下一步优先级：
  1. D1.1：Canvas 只绘制可见行，降低每次 redraw 的实际绘制面积。
  2. D1.2：按行 Canvas 拆分，只 invalidate 脏行。
  3. 补充 Canvas draw 耗时指标，把数组写入耗时和 Canvas redraw 耗时拆开。

## 2026-05-20 阶段 4：D1.1 可见行 Canvas 绘制

本次代码更新：

- `CanvasQuoteTable` 不再每次 redraw 绘制整张 100 行表。
- 根据纵向滚动 offset 和 viewport 高度，只绘制当前可见行，并额外绘制 4 行 buffer。
- 新增 Canvas redraw 耗时统计：
  - `canvasDrawPerSecond`
  - `avgCanvasDrawCostMs`
  - `maxCanvasDrawCostMs`
  - `lastCanvasDrawCostMs`
- `flush cost` 继续表示数据写入数组或组件的耗时，`canvas draw cost` 单独表示 Canvas 清屏和绘制耗时。

下一轮测试：

1. D_canvas，10Hz，1/4 表，静止刷新 30 秒。
2. D_canvas，10Hz，1/4 表，纵向滑动 30 秒。
3. D_canvas，10Hz，1/4 表，横向滑动 30 秒。

重点观察：

- `maxFlushCostMs` 是否仍约 1-2ms。
- `maxCanvasDrawCostMs` 是否明显低于上一轮整表绘制的隐性成本。
- `frameP95Ms` 是否从 46ms 降到 33ms 以下。
- 滑动时是否出现空白行或可见区域不刷新。

判断标准：

- 如果 `canvasDrawCostMs` 很低但 P95 仍 46ms，下一步排查 Scroll/Canvas 提交链路和统计采样方式。
- 如果 `canvasDrawCostMs` 偏高，继续进入 D1.2：按行 Canvas 拆分，只重绘脏行。

## 2026-05-20 阶段 4：D1.1 静止刷新验证

场景：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- 渲染：`D_canvas`。
- 操作：静止刷新。

原始结果：

```json
{
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "timestamp": 1779291350954,
  "elapsedMs": 59277,
  "quoteUpdatesPerSecond": 9987,
  "uiAppliedPerSecond": 9987,
  "uiPaintedPerSecond": 9666,
  "flushPerSecond": 10,
  "flushedCellsPerSecond": 9666,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 0.9168388007198953,
  "maxFlushCostMs": 2.318603515625,
  "lastFlushCostMs": 0.90625,
  "canvasDrawPerSecond": 13,
  "avgCanvasDrawCostMs": 1.5931006044563842,
  "maxCanvasDrawCostMs": 21.529296875,
  "lastCanvasDrawCostMs": 1.75634765625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "quoteUpdates": 592000,
  "uiAppliedUpdates": 592002,
  "uiPaintedCells": 573002,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0,
  "frameCount": 3825,
  "frameP50Ms": 15.442963998764753,
  "frameP95Ms": 15.44896200299263,
  "frameP99Ms": 15.450800001621246,
  "maxFrameMs": 30.887008000165224,
  "health": "正常",
  "healthReason": ""
}
```

结论：

- D1.1 静止刷新已达成目标：P95 15.45ms，P99 15.45ms，max 30.9ms。
- 数据写入成本稳定：平均 flush 0.92ms，最大 flush 2.32ms。
- Canvas 绘制成本可接受：平均 draw 1.59ms，最大 draw 21.53ms。
- 可见行 Canvas 绘制方向成立，性能瓶颈已从 per-cell 组件响应式链路显著下降。
- 但交互存在问题：用户反馈“基本滑不动”。因此当前 D1.1 不能作为可交互方案，需要先修 Scroll 事件处理。

修正方向：

- 不在 Canvas 外层 Scroll 的 `onScrollFrameBegin` 中拦截滚动消费。
- 改为通过 `Scroller.currentOffset()` 在滚动后读取 offset，再触发可见行 redraw。
- 修复后继续跑纵向滑动和横向滑动测试。

## 2026-05-20 阶段 4：D1.1 滑动/交互验证

场景：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- 渲染：`D_canvas`。
- 操作：滑动/交互过程中刷新。

原始结果：

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "elapsedMs": 28301,
  "quoteUpdatesPerSecond": 9964,
  "uiAppliedPerSecond": 9964,
  "uiPaintedPerSecond": 9116,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 9116,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 1.072117058805717,
  "maxFlushCostMs": 13.4697265625,
  "lastFlushCostMs": 0.976318359375,
  "canvasDrawPerSecond": 33,
  "avgCanvasDrawCostMs": 2.011186223199838,
  "maxCanvasDrawCostMs": 83.109130859375,
  "lastCanvasDrawCostMs": 1.444580078125,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.34920600056648,
  "frameP99Ms": 61.775342002511024,
  "maxFrameMs": 77.18107600137591,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0
}
```

```json
{
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "timestamp": 1779291483508,
  "elapsedMs": 30882,
  "quoteUpdatesPerSecond": 9974,
  "uiAppliedPerSecond": 9974,
  "uiPaintedPerSecond": 9164,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 9164,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 1.062625089719523,
  "maxFlushCostMs": 13.4697265625,
  "lastFlushCostMs": 0.897705078125,
  "canvasDrawPerSecond": 31,
  "avgCanvasDrawCostMs": 1.994718825829617,
  "maxCanvasDrawCostMs": 83.109130859375,
  "lastCanvasDrawCostMs": 1.3564453125,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "quoteUpdates": 308000,
  "uiAppliedUpdates": 308002,
  "uiPaintedCells": 283002,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0,
  "frameCount": 1885,
  "frameP50Ms": 15.442805998027325,
  "frameP95Ms": 30.885296002030373,
  "frameP99Ms": 61.774921000003815,
  "maxFrameMs": 61.79710899665952,
  "health": "正常",
  "healthReason": ""
}
```

```json
{
  "level": "警告",
  "reason": "P95帧间隔46.3ms>=33ms",
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "elapsedMs": 32301,
  "quoteUpdatesPerSecond": 9969,
  "uiAppliedPerSecond": 9969,
  "uiPaintedPerSecond": 9071,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 9071,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 1.059072032316553,
  "maxFlushCostMs": 13.4697265625,
  "lastFlushCostMs": 0.954345703125,
  "canvasDrawPerSecond": 30,
  "avgCanvasDrawCostMs": 1.9894735587843977,
  "maxCanvasDrawCostMs": 83.109130859375,
  "lastCanvasDrawCostMs": 1.472900390625,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "frameP95Ms": 46.34920600056648,
  "frameP99Ms": 61.774921000003815,
  "maxFrameMs": 61.79710899665952,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0
}
```

结论：

- D_canvas 交互场景仍明显优于组件表格：平均 flush 约 1.06ms，平均 Canvas draw 约 2.0ms。
- P95 在 30.9ms 到 46.3ms 之间波动，较 A/C 的 60-123ms 已明显改善，但仍可能触发警告。
- `maxCanvasDrawCostMs=83.1ms` 是当前最大风险点。
- `canvasDrawPerSecond=30+`，说明滚动和行情刷新会频繁触发 redraw，存在同一帧附近重复绘制的可能。

下一步：

- 对 Canvas redraw 做合并调度：同一帧内多次 revision/scroll 只绘制一次。
- 继续观察 `canvasDrawPerSecond`、`maxCanvasDrawCostMs` 和 P95 是否下降。

## 2026-05-20 阶段 4：D1.1 redraw 合并调度

本次代码更新：

- `CanvasQuoteTable` 的 `revision`、布局变化、滚动变化不再直接调用 `redraw()`。
- 新增 `requestRedraw()`，按 16ms 最小间隔合并 Canvas redraw。
- 同一时间窗口内多次行情刷新/滚动事件只触发一次实际绘制。
- 目标是降低 `canvasDrawPerSecond` 和 `maxCanvasDrawCostMs`，减少滑动时的偶发长帧。

下一轮测试：

- 复测 `D_canvas` 滑动/交互场景。
- 重点比较更新前后的：
  - `canvasDrawPerSecond`：期望从 30+ 降低或稳定。
  - `maxCanvasDrawCostMs`：期望不再出现 80ms 级别。
  - `frameP95Ms`：期望稳定在 33ms 以下。

## 2026-05-20 阶段 4：D1.1 redraw 合并后复测

场景：

- 行数：100。
- 每侧列数：20。
- 频率：10Hz。
- 刷新范围：1/4 表。
- 渲染：`D_canvas`。
- redraw 策略：16ms 合并调度。

原始结果：

```json
{
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "timestamp": 1779291619047,
  "elapsedMs": 22044,
  "quoteUpdatesPerSecond": 9980,
  "uiAppliedPerSecond": 9980,
  "uiPaintedPerSecond": 9436,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 9436,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 0.9688309889573318,
  "maxFlushCostMs": 6.115966796875,
  "lastFlushCostMs": 0.9794921875,
  "canvasDrawPerSecond": 25,
  "avgCanvasDrawCostMs": 1.7785675048828125,
  "maxCanvasDrawCostMs": 3.34619140625,
  "lastCanvasDrawCostMs": 1.98974609375,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "quoteUpdates": 220000,
  "uiAppliedUpdates": 220002,
  "uiPaintedCells": 208002,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0,
  "frameCount": 1363,
  "frameP50Ms": 15.442609000951052,
  "frameP95Ms": 15.44895600154996,
  "frameP99Ms": 15.449843998998404,
  "maxFrameMs": 15.450303003191948,
  "health": "正常",
  "healthReason": ""
}
```

```json
{
  "scenarioId": "rows100_cols20_10hz_quartertable",
  "variantId": "D_canvas",
  "timestamp": 1779291656382,
  "elapsedMs": 59378,
  "quoteUpdatesPerSecond": 9987,
  "uiAppliedPerSecond": 9987,
  "uiPaintedPerSecond": 9414,
  "flushPerSecond": 9,
  "flushedCellsPerSecond": 9414,
  "maxFlushCells": 1000,
  "lastFlushCells": 1000,
  "avgFlushCostMs": 0.9698885950078264,
  "maxFlushCostMs": 8.9443359375,
  "lastFlushCostMs": 0.897216796875,
  "canvasDrawPerSecond": 25,
  "avgCanvasDrawCostMs": 1.7378204752604167,
  "maxCanvasDrawCostMs": 3.44482421875,
  "lastCanvasDrawCostMs": 1.78662109375,
  "measuredFrequencyHz": 10,
  "targetFrequencyHz": 10,
  "frequencyDriftPercent": 0,
  "quoteUpdates": 593000,
  "uiAppliedUpdates": 593004,
  "uiPaintedCells": 559004,
  "scrollCallbacks": 0,
  "scrollerSyncCount": 0,
  "frameCount": 3781,
  "frameP50Ms": 15.442074999213219,
  "frameP95Ms": 15.449260000139475,
  "frameP99Ms": 15.4501519985497,
  "maxFrameMs": 15.450676001608372,
  "health": "正常",
  "healthReason": ""
}
```

结论：

- redraw 合并调度有效。
- `maxCanvasDrawCostMs` 从上一轮 83.1ms 降到 3.45ms。
- `avgCanvasDrawCostMs` 稳定在 1.7-1.8ms。
- `frameP95Ms` 稳定在 15.45ms，`frameP99Ms` 也稳定在 15.45ms。
- D1.1 在 `100行 * 每侧20列 * 10Hz * 1/4表` 场景下已达到流畅目标。

阶段结论：

- 当前性能收益最大方案已经明确：行情缓存 + Canvas 可见行绘制 + Canvas redraw 合并调度。
- 继续优化组件表格路径意义不大，应把后续开发重心转向 Canvas 方案的业务能力补齐。
- 下一步应验证更高压力场景：20Hz / 50Hz、半表 / 整表，以及滑动中的横向滚动手感。

## 2026-05-20 阶段 4：D1.2 视口级 Canvas

用户反馈滑动体验优先，决定从“大 Canvas + Scroll 嵌套”切换到视口级 Canvas。

本次代码更新：

- `D_canvas` 改为单个固定视口大小的 Canvas。
- 不再创建整表宽高的大 Canvas surface。
- 移除外层纵向 Scroll + 内层横向 Scroll 嵌套。
- 使用 `PanGesture` 自己维护 `horizontalOffset` 和 `verticalOffset`。
- 每次 redraw 只 `clearRect(0, 0, viewportWidth, viewportHeight)`。
- 绘制时按 offset 映射当前可见行和可见列。
- 保留 16ms redraw 合并调度，避免行情刷新和滑动事件重复绘制。

验证目标：

- 解决上一版“大 Canvas + Scroll 合成”导致的滑动手感差。
- 保持 D1.1 的低 flush / draw 成本。
- 横向和纵向滑动都能操作。
- 滑动中可见区域持续刷新。

下一轮测试：

1. D_canvas，10Hz，1/4 表，静止刷新。
2. D_canvas，10Hz，1/4 表，纵向拖动。
3. D_canvas，10Hz，1/4 表，横向拖动。
4. D_canvas，20Hz，1/4 表，滑动中刷新。

重点观察：

- 主观滑动手感是否明显改善。
- `frameP95Ms` 是否稳定低于 33ms。
- `maxCanvasDrawCostMs` 是否继续保持低位。
- 是否出现拖动边界异常、空白区域、文字残影或横纵 offset 错乱。

## 2026-05-20 阶段 4：D1.2 视口级 Canvas 验证

用户反馈：滑动流畅。

### 场景 1：10Hz，1/4 表

原始结果：
