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
