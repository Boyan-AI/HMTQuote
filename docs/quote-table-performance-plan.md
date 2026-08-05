# 实时行情表性能优化方案

## 背景

当前表格组件用于展示期货/期权实时行情，业务特点是：

- 行情数据持续高频推送。
- 单元格内容可能大量、持续变化。
- 用户滑动期间仍需要保持流畅，不能因为行情刷新阻塞手势响应。
- 表格包含中间行权价列，左右两侧分别展示期权相关数据。

现有实现基于嵌套 `List`、每个单元格一个 ArkUI 组件、每行左右各一个横向 `Scroller`。该结构在低频数据和少量行列下可用，但在高频行情和大表格场景下会出现明显性能压力。

## 优化目标

核心目标是滑动不卡顿，优先保证用户交互流畅。

建议验收目标：

- 100 行，每侧 40 列。
- 行情 50Hz。
- 每秒 3000 个 cell 更新。
- 横滑、纵滑、边滑边刷新均无明显卡顿。
- 滑动 FPS 稳定接近 60，低端设备可接受 45+。
- 单帧耗时 P95 小于 16.7ms，至少小于 22ms。
- 单帧耗时 P99 小于 33ms。
- 内存不随行情持续刷新而增长。
- 滑动期间行情刷新不阻塞手势响应。

## 性能测试方案

历史压测结果统一记录在 `docs/quote-table-performance-report.md`。后续每次新增压测数据，都先追加报告，再根据结论调整开发计划。

### entry 压测工程

性能优化必须先有可重复的压测入口。测试代码放在 `entry` 目录，不放在 `t_split_list` 组件库中。

建议新增：

```text
entry/src/main/ets/pages/PerfTest.ets
entry/src/main/ets/perf/MockQuoteFeed.ets
entry/src/main/ets/perf/PerfStats.ets
entry/src/main/ets/perf/PerfScenario.ets
```

职责划分：

- `PerfTest.ets`：压测页面入口，承载测试表格、控制面板和统计展示。
- `MockQuoteFeed.ets`：模拟行情推送，支持不同频率、不同批量大小和不同更新分布。
- `PerfStats.ets`：收集行情输入量、UI 更新量、flush 次数、滚动回调次数、Scroller 同步次数等指标，自带 P95 / P99 计算，并能导出结构化数据。
- `PerfScenario.ets`：定义标准测试场景，保证每次测试参数一致。

### Mock 时钟源

`setTimeout` / `setInterval` 在高频下抖动严重，50Hz 标称往往实际跑成 30-70Hz，导致后续所有基准失真。要求：

- 优先使用平台可用的帧同步能力或高精度 timer；具体 API 需要在阶段 1.0 先验证，不在方案中绑定到单一实现。
- 每次行情触发都记录实际时间戳，事后能反推真实频率。
- 输出报告必须区分「设定频率」和「实测频率」，两者差值过大需要先修 mock，再看业务指标。
- 如果目标频率无法稳定达到，应在报告中标记该场景无效，不能用于证明优化收益。

### 数据分布模式

除了「全表随机 / 可见区域热点 / 固定热点行 / 固定热点列」，还要支持：

- Burst 模式：短时间内大批量更新 + 长尾静默，复现开盘 / 收盘 / 突发行情。
- 同 cell 高频覆盖：单个 cell 在一个 flush 周期内被覆盖 N 次，验证合并策略。
- 跨视窗迁移：热点行随时间在可见区和不可见区之间移动。

### 统计与数据导出

`PerfStats` 必须脱离 DevEco Profiler 也能给出可比较的指标：

- 自行记录 frame timestamp，在端侧计算 P50 / P95 / P99。
- 支持结构化导出：HiLog JSONL 或写入应用 sandbox 文件，字段固定，便于跨版本 diff。
- 每条记录带场景标识、版本标识、时间戳，导出格式作为后续阶段的契约。
- 关键计数器（行情输入量、`updateByItem` 次数、Scroller 同步次数等）的实现归 `PerfStats`，不要散落在各业务文件中。

当前阶段压测页面收敛为固定表格规模，专注验证「拿到数据后逐个复制给单元格」这条 A 版本路径：

- 固定行数：100 行。
- 固定列数：每侧 20 列。
- 行情频率：10Hz / 20Hz / 50Hz / 100Hz。
- 行情变化范围：整表 / 半表 / 1/4 表。
- 整表刷新量：100 行 * 每侧 20 列 * 左右两侧 = 4000 cell / tick。
- 半表刷新量：2000 cell / tick。
- 1/4 表刷新量：1000 cell / tick。
- 数据写入方式：mock 拿到一批数据后，逐个调用 `DataView.updateByItem` 复制到单元格。
- 开始、停止、重置统计。
- 是否在滑动中继续刷新。
- 是否强制整表刷新，用于诊断细粒度 `updateByItem` 是否触发表格刷新；正式压测默认关闭。
- 当前行情输入量。
- 当前 UI 写入量。
- 当前滚动状态。
- 滚动回调次数。
- 阈值告警和 HiLog JSONL 导出。

压测开关命名约定：

- `行情变化范围`：控制 mock 行情每 tick 产生多少变动 cell，是输入压力；取值为 1/4 表、半表、整表。
- `强制整表刷新`：控制 UI 侧是否每次变动后强制重建整份 `DataView`，是诊断开关；正式压测默认关闭。
- `LIVE探针`：额外向少量固定行列写入 `LIVE` 文本，用于肉眼确认可视刷新；正式压测默认关闭。
- `分区配色`：切换 Canvas 四象限背景色，用于验证 Call / Put 上下分区和最新价线视觉；正式性能对比时固定默认配色。

测试页默认配置：

```text
渲染：D Canvas
频率：20Hz
行情变化范围：1/4 表
B 调度合并：开
flush：100ms
只刷可见：开
滑动刷新：关
强制整表刷新：关
LIVE 探针：关
```

快捷档位：

- `业务默认`：20Hz + 1/4 表 + D Canvas + 只刷可见 + flush 100ms + 滑动刷新关。
- `偏高压力`：20Hz + 半表 + D Canvas + 只刷可见 + flush 100ms + 滑动刷新关。
- `极限降级`：20Hz + 整表 + D Canvas + 只刷可见 + flush 200ms + 滑动刷新关。

`entry/src/main/resources/base/profile/main_pages.json` 需要注册 `PerfTest` 页面，便于在 DevEco 和真机上直接进入压测。

第一版压测页面不追求视觉完整，重点是：

- 参数可控。
- 结果可重复。
- 各阶段优化前后可以横向比较。
- 不依赖真实行情环境。

### 测试场景矩阵

当前阶段只验证固定 `100 行 / 每侧 20 列` 的刷新压力，避免变量过多导致归因困难：

| 维度 | 测试值 |
| --- | --- |
| 行数 | 固定 100 |
| 每侧列数 | 固定 20 |
| 行情更新频率 | 10Hz / 20Hz / 50Hz / 100Hz |
| 行情变化范围 | 整表 / 半表 / 1/4 表 |
| 每 tick cell 数 | 4000 / 2000 / 1000 |
| 写入方式 | 一批数据逐个复制到单元格 |
| 用户操作 | 静止刷新 / 只纵滑 / 只横滑 / 边滑边刷新 |

重点测试场景：

- `100行 * 每侧20列 * 10Hz * 1/4表`：已出现 P95 超阈值，是阶段 2 的基准失败场景。
- `100行 * 每侧20列 * 10Hz * 半表`：验证 A 版本在中等行情变化范围下的退化。
- `100行 * 每侧20列 * 10Hz * 整表`：验证 A 版本逐 cell 全量写入上限。
- 在同一行情变化范围下提升到 20Hz / 50Hz / 100Hz，观察实测频率是否掉队。
- 分别打开/关闭「强制整表刷新」，判断细粒度 `updateByItem` 是否触发表格刷新。

### 关键指标

必须记录：

- FPS。
- 掉帧率。
- 单帧耗时。
- UI 线程占用。
- ArkTS 执行耗时。
- 每秒行情输入量。
- 每秒实际 UI flush 次数。
- 每次 flush 的 cell 数。
- 每次 flush 的可见 cell 数和不可见 cell 数。
- 内存占用。
- GC 次数和 GC 耗时。
- 首屏渲染耗时。
- 横滑同步耗时。
- 纵滑创建/复用行耗时。
- 实测行情频率和设定频率偏差。
- 统计埋点自身耗时，避免埋点污染被测对象。

最关键指标：

- 滑动期间 FPS。
- 滑动期间最大单帧耗时。
- 行情刷新是否阻塞手势响应。
- 横滑时每帧同步了多少对象。
- 一次行情 flush 实际触发了多少 UI 更新。

### 埋点位置

建议先增加埋点，不直接改渲染架构。

埋点位置：

- 行情推送入口。
- pending 队列入队。
- UI flush 开始和结束。
- `DataView.updateByItem`。
- `TComponent.onScrollFrameBegin`。
- `ScrollController.LeftHorizontal`。
- `ScrollController.RightHorizontal`。
- `ScrollController.V2H`。
- 行组件 build / attach。

需要统计：

- `LeftHorizontal` 每帧同步的 `Scroller` 数量。
- `RightHorizontal` 每帧同步的 `Scroller` 数量。
- `V2H` 每次同步的 `Scroller` 数量。
- 一次行情 flush 改了多少可见 cell。
- 一次行情 flush 改了多少不可见 cell。
- 同一个 cell 在一个 flush 周期内被覆盖了多少次。

### 性能工具

避免不同人用不同工具量出不同结论，明确分工：

- DevEco Profiler 的 Frame 面板：FPS、单帧耗时、UI 线程占用。
- DevEco Profiler 的 Memory 面板：堆内存、GC 次数和耗时。
- SmartPerf-Host：跨进程帧时间、长任务定位。
- 自行埋点 + HiLog：行情输入量、flush 次数、可见/不可见 cell 数、Scroller 同步数量。

代码侧的统计与 Profiler 的帧数据需要时间戳对齐，否则归因不准。

### 对照版本

至少保留以下版本用于比较：

| 版本 | 内容 | 目的 |
| --- | --- | --- |
| A | 当前版本 | 建立基准 |
| A' | 当前版本 + 低风险快速改动 | 排除明显代码层成本 |
| B | 当前结构 + 行情批量 flush | 验证数据调度收益 |
| C | 当前结构 + 只刷新可见行 + 只同步可见 Scroller | 验证可见区域收益；当前 entry 压测先实现只刷新可见行，不可见行保留在缓存 |
| D1 | 行级 Canvas 绘制版本 | 验证 Canvas 上限 |
| D2 | BuilderNode 行版本 | 验证命令式原生节点收益 |
| D | 阶段 4 选定方案完整替换版本 | 验证最终架构收益 |

## 性能瓶颈判断

现有结构的主要性能风险：

1. 每个 cell 是独立 ArkUI 组件，组件数量随行列数线性增加。
2. 每个 cell 使用响应式对象，行情大量变化时会触发大量 UI 更新。
3. 每行左右各一个横向 `List`，可见行多时组件树很重。
4. 横向滑动需要同步多行 `Scroller`，每帧成本较高。
5. 行情数据直接驱动 UI，缺少合并、节流和只刷可见区域的调度层。

最大收益方向不是只做懒加载，而是减少组件数量、减少响应式更新、减少 `Scroller` 同步、减少布局计算。

### 现有代码中的具体问题

除上述架构性风险外，当前代码还有若干无需架构调整即可改进的点（详见阶段 1.5）：

- 中间纵向 `List`（`TComponent.ets` `build()` 内）使用 `ForEach`，应通过实测确认其在当前 ArkUI 版本下的创建/复用行为；如果非可见行也被提前构建，应切换到 `LazyForEach` 或数据源驱动的懒加载。
- per-row 左右 `List` 全部挂了 `.animation({ duration: ANIMATION_DURATION })`，需要确认横滑期间是否参与动画提交；若 Profiler 显示动画管线有额外开销，应移除或仅在展开/收起场景启用。
- `scrollController` 在字段初始化和 `aboutToAppear` 中各 `new` 一次，且 `Update(rows)` 只追加不截断。需要修复初始化时序和数组生命周期，避免行数变化或重复初始化后 `Scroller` 数组膨胀。
- `Head` / `ExpandCallPut` 等 `@Builder` 中以 `new ListItemData(...)` 作为 `ItemComponent` 的入参，每次重建都产生新对象，`@ObjectLink` 重新绑定。

这些问题不影响推荐架构走向，但会让阶段 1 的基准数据偏离实际可达上限。

## 推荐架构

推荐采用：

```text
行情缓存 + 批量调度 + 视口级 Canvas 绘制 + 统一横纵 offset
```

最终推荐方案：

```text
全量行情进缓存
  -> 同一 cell 合并，只保留最新值
  -> 按可配置 flush 策略输出可见范围快照
  -> 视口级 Canvas 只绘制当前可见行列
```

关键结论：

- 渲染层采用视口级 Canvas，不采用整表 Canvas。
- 只刷可见行列，不对不可见区域做 UI flush。
- 真实业务按“部分 cell 变化”设计，不按整表每次全量变化设计。
- 20Hz 是当前业务上限输入频率；50Hz / 100Hz 仅作为压力冗余或破坏性测试。
- 常规验收按 `20Hz + 1/4 表变化`，偏高验收按 `20Hz + 半表变化`，`20Hz + 整表变化` 仅作为极限边界和降级触发测试。
- `flushIntervalMs` 必须作为业务配置项，不写死。
- 默认推荐 `100ms`，即约 10Hz UI 刷新。
- `33ms / 50ms` 作为高实时档，用于重点合约、最新价线附近、买卖价等高关注区域。
- `200ms` 作为降级档或滑动中低优先级档，不作为默认主路径；200ms 约等于 5Hz，用户可能感知到行情跳变。
- 滑动中刷新作为配置项：可选择继续刷新、降频刷新或暂停 flush，暂停时行情仍写缓存，滑动结束后立即 flush 最新值。
- 配置需要支持线上灰度和远程调整，便于不同设备、不同合约活跃度、不同行情频率下调参。

建议配置模型：

```text
QuoteTablePerfConfig
  renderMode: viewportCanvas
  defaultFlushIntervalMs: 100
  highPriorityFlushIntervalMs: 33 | 50
  degradedFlushIntervalMs: 200
  visibleOnly: true
  refreshWhileScrolling: true | false
  scrollingFlushIntervalMs: 100 | 200
  maxFlushCellsPerFrame
  visibleRowBuffer
  visibleColBuffer
  enablePerfStats
  enableAutoDegrade
```

目标结构：

```text
TComponent
  ViewportCanvas
    draw visible rows
    draw visible columns
    map pointer -> row/col
  Floating line indicator
```

核心变化：

- 行情数据不直接修改 UI 绑定对象。
- 行情回调只提交真实变动 cell，不构造整表快照，不做整表 UI 刷新。
- 每行不再渲染大量 `Text`、`Row`、`ListItem`。
- 使用固定视口大小的 `Canvas` 绘制当前可见行列。
- 横向和纵向滚动都不再依赖大量 `Scroller`，由统一 offset 驱动。
- 点击、长按通过坐标换算 row/col。

## 数据层方案

新增非响应式行情缓存，例如 `QuoteTableStore`。

职责：

- 保存全量最新行情。
- 保存行列结构。
- 保存左侧、右侧、中间列数据。
- 保存颜色、涨跌、高亮等绘制状态。
- 维护脏行集合。
- 合并同一 cell 的重复更新。

建议模型：

```text
QuoteTableStore
  rows
  leftCols
  rightCols
  centerValues
  leftValues
  rightValues
  leftColors
  rightColors
  dirtyRows
  pendingUpdates
```

数据格式约束：

- cellKey 使用稳定结构，不使用临时字符串拼接作为核心存储键；可用 `{ side, row, col }` 或编码后的整数 key。
- Worker / PerfStats / 渲染层使用同一套 side 枚举，避免左/右/中间列映射重复实现。
- 颜色在数据层保存为可序列化 token 或 ARGB 数值，渲染层再转换为 ArkUI 可用颜色；不要在 Worker delta 中传 `ResourceColor` 资源对象。
- 文本值统一存储为 string，数字格式化在行情入库或专门 formatter 层完成，避免绘制时重复格式化。
- 所有批次带 `version` 或单调递增序号，用于丢弃过期 flush 结果。

行情入口只做：

```text
写入 cache
标记 dirty row
合并同 cell 多次更新
请求下一次 flush
```

不要在行情回调里直接调用 `DataView.updateByItem` 或直接修改 `@Observed` cell 对象。

### 涨跌闪烁色状态

行情变化通常需要短暂高亮，但不能为每个 cell 起独立定时器。建议在 `QuoteTableStore` 中维护：

```text
flashUntil: Map<cellKey, timestamp>
flashColor: Map<cellKey, ResourceColor>
```

调度层每次 flush 时：

- 把 `now >= flashUntil` 的 cell 从高亮集合移除并标记对应行 dirty。
- 渲染层根据当前是否在 flash 窗口内决定 cell 文本颜色或背景。

这样定时器只剩一个 flush tick，flash 状态变成纯数据，不需要在 UI 层挂动画。

## 调度层方案

新增 `QuoteUpdateScheduler`。

职责：

- 接收行情更新。
- 合并同一 cell 的多次变化。
- 按固定节奏 flush 到 UI。
- 滑动中降低刷新优先级。
- 只刷新可见行和可见列。

推荐策略：

- 默认 flush 间隔 100ms（≈10Hz），作为当前实测下实时感和 UI 负载之间的起始折中值。
- 重点可见区域可使用 33ms / 50ms 高实时档，但必须由配置控制并独立压测。
- 200ms 仅作为降级档、滑动中低优先级档或低端设备兜底档；不建议作为默认值。
- 滑动中以手势响应优先，只保留最新行情值，可配置为继续刷新、降频刷新或暂停 flush。
- 压力探测：连续 N 帧超阈值则自动退到 200ms 或暂停滑动中刷新，恢复后逐步回到默认档。
- flush 间隔必须可配置，不作为硬编码常量写死。

### flush 触发与排序

- 触发时机优先用 VSync / `requestAnimationFrame` 锁帧，退化到高精度 timer；不要直接用 `setTimeout`。
- 同一次 flush 内多个 dirty row 的处理顺序：先可见后不可见，可见区按从上到下，避免视觉跳动和无意义的不可见绘制。
- 不可见 dirty row 在本次 flush 不绘制，只标记 cache 已变；滚入视窗时由可见区域更新触发重绘。
- flush 入口和出口都要在 `PerfStats` 打点，便于事后分析单次 flush 的 cell 数、可见率和耗时分位数。

### 线程模型

3000 cell/s 的行情合并、`dirtyRows` 维护、flash 状态扫描如果全放 UI 线程，会和渲染抢同一个时间预算。需要在阶段 2 设计时就定下来：

- 基础方案：先把行情合并、dirty 标记和 flash 状态计算封装到纯数据接口中，不直接访问 `@Observed` 对象，不依赖 UI 线程 API。
- Worker 方案：当阶段 1 数据显示合并和扫描耗时会明显抢占单帧预算时，再把纯数据合并迁移到 Worker，例如 `ets/workers/QuoteWorker.ets`。
- Worker 与 UI 线程之间只传递纯数据 delta，例如 row/side/col/value/color/token/version；不要传 `Resource`、`PixelMap`、`Scroller`、ArkUI 组件对象或函数。
- UI 线程只接收 flush 结果、更新可见快照版本并触发重绘。
- 如果阶段 1 数据显示合并耗时 < 单帧预算 20%，可以暂缓 Worker 化，但接口设计要保留可迁移性。

这个决策点必须在阶段 2 启动前确认。之后再切线程模型成本很高，尤其是数据结构如果已经耦合到 UI 对象，会导致返工。

示意流程：

```text
行情推送
  -> QuoteTableStore 写缓存
  -> QuoteUpdateScheduler 合并 pending
  -> 到达 flush 时机
  -> 计算可见行/列
  -> 只刷新可见脏行
```

## 可见区域模型

组件需要维护：

```text
visibleStartRow
visibleEndRow
leftVisibleStartCol
leftVisibleEndCol
rightVisibleStartCol
rightVisibleEndCol
horizontalOffset
verticalOffset
```

刷新原则：

- 可见 cell：允许触发 UI 重绘。
- 不可见 cell：只更新缓存，不触发 UI。
- 滚动到新区域时：从缓存读取最新值绘制。
- 同一 flush 周期内同一 cell 多次变化：只绘制最后值。

注意：在当前 per-row `Scroller` 架构下，"只同步可见 Scroller" 可以作为过渡优化，但必须维护一个权威的横向 offset，并在行 attach / 进入视窗时立即对齐，否则新进入视窗的行会出现 offset 错位。该方案能减少一部分横滑同步成本，但仍保留大量 per-row `Scroller` 和嵌套 `List`，收益上限有限。横滑成本的根治需要统一 offset（阶段 4-5）。

## Canvas 绘制方案

### RowCanvas

每个可见行使用一个 `RowCanvas`。

输入：

```text
rowIndex
rowHeight
columnWidth
centerWidth
horizontalOffset
rowVersion
selectedState
highlightState
```

绘制内容：

- 行背景。
- 象限背景色。
- 单元格边框和分割线。
- 左侧可见 cell 文本。
- 中间行权价。
- 右侧可见 cell 文本。
- 涨跌颜色。
- 高亮态、选中态。

绘制时只计算可见列：

```text
startCol = floor(horizontalOffset / columnWidth)
endCol = ceil((horizontalOffset + viewportWidth) / columnWidth)
```

### HeaderCanvas

表头也建议 Canvas 化。

原因：

- 表头需要和内容横向 offset 完全同步。
- 当前表头也会创建多个 item 组件。
- Canvas 表头可以减少构建和布局成本。

绘制内容：

- 左侧表头。
- 中间行权价标题。
- 右侧表头。
- 分割线和背景。

### Canvas 绘制注意事项

Canvas 方案需要重点验证以下细节，避免性能收益被文本绘制成本抵消：

- 文本测量、截断、居中、最小字号策略。
- 中文、数字、符号混排时的字体回退和基线一致性。
- 高 DPI 设备下的线宽、半像素边框和文本清晰度。
- 单行绘制是否能只重绘脏行，避免因父组件状态变化导致全屏重绘。
- 当前价格线、选中态、涨跌闪烁是否独立绘制，避免污染所有行的 dirty 状态。

## 备选渲染方案：BuilderNode

HarmonyOS 提供 `BuilderNode` / `NodeController` 等命令式节点 API，可以降低 `@Observed` / `@ObjectLink` 的响应式开销，同时保留原生 `Text` 渲染。对文本密集的行情表，相比 Canvas 主要差异：

| 维度 | Canvas | BuilderNode |
| --- | --- | --- |
| 文本质量 | 自己处理度量、截断、对齐 | 复用 ArkUI 文本管线 |
| 中文 / 字体回退 | 容易踩坑 | 与原生一致 |
| 无障碍 | 需自行实现 | 复用原生节点 |
| 单帧成本 | 取决于绘制内容量 | 取决于节点创建 / 复用成本 |
| 开发量 | 高 | 中 |

ArkUI Canvas 的文本绘制在文本密集场景下并不总是优于原生 `Text`。建议阶段 4 同时做 D1（RowCanvas）和 D2（BuilderNode 行）两个原型，用数据决定方向，不要默认 Canvas 一定更快。

选型标准：

- 如果瓶颈主要是组件数量、布局和响应式 diff，Canvas 优先。
- 如果瓶颈主要是文本测量和绘制，BuilderNode 或复用原生 `Text` 管线可能更稳。
- 如果无障碍、字体一致性、文本截断质量优先级高，BuilderNode 风险较低。
- 如果横滑必须极致稳定，统一 offset + Canvas 的上限更高。

## 滚动方案

### 横向滚动

不再每行维护横向 `Scroller`。

改为维护统一 offset：

```text
leftHorizontalOffset
rightHorizontalOffset
```

横滑时：

```text
更新 offset
请求 HeaderCanvas 重绘
请求可见 RowCanvas 重绘
```

收益：

- 去掉每帧同步多行 `Scroller`。
- 去掉每行左右横向 `List`。
- 横滑成本从多对象同步变成统一状态更新和可见行绘制。

### 纵向滚动

纵向仍可使用 `List` 或 `LazyForEach`。

每行只包含一个 `RowCanvas`，行高固定。

收益：

- 仍然利用 ArkUI 的纵向虚拟化能力。
- 大幅减少单行组件数量。
- 纵滑时创建和复用成本降低。

## 交互方案

由于 cell 不再是独立组件，交互需要坐标换算。

点击换算：

```text
x -> side + col
y -> row
```

长按、选中、高亮同理。

需要支持：

- 单元格点击。
- 单元格长按。
- 行高亮。
- 单元格高亮。
- 当前价格线点击穿透或忽略。

坐标换算必须基于：

- 中间列宽度。
- 左右区域宽度。
- 每列宽度。
- 当前横向 offset。
- 当前行号。

## 脏行刷新方案

行情更新后不要全表 repaint。

维护：

```text
dirtyRows: Set<number>
rowVersions: number[]
```

flush 时：

```text
for row in dirtyRows:
  if row is visible:
    rowVersions[row]++
```

`RowCanvas` 监听自己的 `rowVersion`，只在对应行版本变化时重绘。

如果 ArkUI Canvas 不能直接做细粒度 invalidate，则通过行级 version 驱动对应行重建或重绘，避免全表刷新。

## 开发计划

### 阶段 1.0：entry 压测工程

目标：先建立可重复运行的本地压测入口，作为后续所有优化的对照基线。

任务：

- 新增 `entry/src/main/ets/pages/PerfTest.ets`。
- 新增 `entry/src/main/ets/perf/MockQuoteFeed.ets`。
- 新增 `entry/src/main/ets/perf/PerfStats.ets`。
- 新增 `entry/src/main/ets/perf/PerfScenario.ets`。
- 在 `main_pages.json` 注册压测页面。
- 压测页面接入当前 `TComponent`。
- 固定 100 行、每侧 20 列。
- 支持行情频率配置：10Hz / 20Hz / 50Hz / 100Hz。
- 支持刷新范围配置：整表 / 半表 / 1/4 表。
- mock 拿到一批数据后，逐个调用 `DataView.updateByItem` 复制到单元格。
- 支持开始、停止、重置统计。
- 支持一键运行标准场景。
- 支持输出每秒行情输入量、UI 更新量、滚动回调次数和 Scroller 同步次数。
- 支持实测频率统计，区分设定频率和实际触发频率。
- 支持结构化导出，优先 JSONL，每条记录包含 scenarioId、variantId、timestamp、metrics。
- 验证 Mock 时钟源稳定性；若实测频率偏差超过阈值，标记场景无效。
- 支持阈值告警：P95 / P99 / max 帧间隔、实测频率偏差、行情输入但 UI 无写入。

产出：

- 可独立运行的 `entry` 压测页面。
- 标准场景参数配置。
- 后续阶段统一使用的 mock 行情源。
- 固定字段的结构化指标导出格式。

**Kill criteria**：如果压测页面无法稳定复现卡顿或无法输出可比较指标，不进入阶段 1；先补齐测试能力。

### 阶段 1：性能基准和埋点

目标：使用阶段 1.0 的压测能力跑标准场景，确认主要瓶颈。

任务：

- 使用阶段 1.0 的压测页面运行标准场景矩阵。
- 在业务代码侧（`DataView.updateByItem`、`ScrollController.LeftHorizontal/RightHorizontal/V2H`、`TComponent.onScrollFrameBegin`、行组件 build/attach）增加调用计数和耗时埋点，结果统一回流到 `PerfStats`。
- 跑通后导出各场景的结构化报告（FPS、P95/P99 单帧、flush 次数、Scroller 同步次数、可见/不可见 cell 数、内存、GC）。
- 与 DevEco Profiler 截图对齐时间戳，校验端侧统计准确性。

任务边界：`PerfStats` 的指标计算和导出能力归阶段 1.0，本阶段只做埋点接入和报告产出，不在业务代码里散落各自的计数逻辑。

产出：

- 当前版本性能报告。
- 不同行列规模下的瓶颈数据。
- 是否优先改数据调度或渲染结构的判断依据。

**Kill criteria**：埋点数据要能回答"横滑慢是 Scroller 同步、组件重建还是数据更新"。无法定位则不进入下一阶段。

### 阶段 1.5：低风险快速改动

目标：在不动整体架构的前提下，先消化代码层显而易见的成本，避免后续阶段的基准被这些问题拉低。

任务：

- 通过 Profiler 确认 `ForEach` 在当前 `List` 中的实际创建/复用行为；如非可见行构建成本明显，再切换为 `LazyForEach` 并配合稳定 key。
- 通过 Profiler 确认 per-row 左右 `List` 上的 `.animation({ duration: ANIMATION_DURATION })` 是否参与横滑成本；如有明显开销，移除或限定到展开/收起场景。
- 修复 `scrollController` 字段初始化 + `aboutToAppear` 双重初始化风险，并让 `Update(rows)` 按目标行数补齐/截断。
- `Head` / `ExpandCallPut` 等 `@Builder` 中不再每次 `new ListItemData(...)`，改为成员缓存或常量。
- 复测一次基准。

产出：

- 不依赖架构改动的性能改进版本，作为新的基准 A'。
- 估算这些改动占整体目标的比例（经验值常在 30-50%）。

**Kill criteria**：如果 A' 已满足验收目标，可暂停阶段 2 以后的工作。

### 阶段 2：行情缓存与批量调度

目标：行情不再直接驱动 UI。

任务：

- 新增 `QuoteTableStore`。
- 新增 `QuoteUpdateScheduler`，支持 33ms / 100ms / 200ms flush 对照；当前阶段默认先用 100ms 验证合并收益。
- 定义统一 cellKey、side 枚举、颜色 token、批次 version。
- 行情入口改为写缓存和 pending 队列。
- 同一 cell 多次更新只保留最后值。
- flush 时按行聚合，对每个 dirty row 做一次批处理而非 cell 逐个触发响应式更新。
- 支持滑动中降频或延后 flush；若关闭"滑动中刷新"，滑动期间只继续写缓存，不取出 pending，滑动结束后 flush 最新值。
- 压测页面提供 A / B 模式切换，A 为逐个 `updateByItem`，B 为缓存合并后按 flush 间隔写 UI。
- `UI写入/s` 统计合并前进入调度层的有效 cell 数，`UI绘制/s` 统计合并后实际写入表格的 cell 数。B 是否有效优先看 `UI绘制/s` 是否显著低于 `UI写入/s`，再看 P95 / P99 是否下降。
- 视觉探针只用于确认表格可见变化，正式压测默认关闭，避免额外 UI 写入污染性能数据。
- 完成线程模型决策：继续 UI 线程纯数据合并，或迁移到 Worker；无论是否 Worker 化，接口都保持纯数据输入输出。

产出：

- 当前组件结构下的调度优化版本。
- 对照测试版本 B。

**Kill criteria**：B 相对 A' 在"行情持续刷新中横滑"场景下 P95 单帧 ≤ 22ms **且**相对改善 ≥ 20%。改善不达标则瓶颈不在数据层，跳过阶段 3 直接进入阶段 4-5 评估。

### 阶段 3：可见区域刷新

目标：减少不可见区域的 UI 更新，并评估当前 per-row `Scroller` 架构下横滑可见同步的收益上限。

任务：

- 维护可见行范围。
- 行情 flush 只更新可见 cell；不可见数据只进入缓存，滚入视窗时再读最新值。
- 维护横向可见列范围，flush 时只触发可见列的更新。
- 可选实验：横滑只同步可见行 `Scroller`，同时维护权威横向 offset，并在行 attach / 进入视窗时立即对齐。
- 若可见行同步引入 offset 错位、边界回弹不一致或 fling 行为异常，则回退横滑同步实验，把统一 offset 留到阶段 4-5。

产出：

- 对照测试版本 C。
- 明确当前架构能达到的性能上限。

**Kill criteria**：C 相对 B 在大表场景（300+ 行 × 40+ 列）P95 单帧仍 > 22ms，或横滑期间仍有明显长帧，则必须进入阶段 4-5；如果已达验收目标，可冻结当前架构并转入阶段 6。

### 阶段 4：视口级 Canvas 原型与选型

目标：验证渲染层重构收益，并确定最终高性能渲染路线。

当前结论：选定 `D_canvas` 视口级 Canvas，不继续推进 RowCanvas / BuilderNode 双原型。原因是当前原型已经在业务默认和偏高压力档下达标，且滑动体验明显优于 per-cell 组件结构。

任务：

- 完成 `D_canvas` 视口级 Canvas：
  - 固定视口大小 Canvas。
  - 统一横纵 offset。
  - 只绘制当前可见行列和少量 buffer。
  - 当前行权价列固定。
  - 左右 Call / Put 横向联动。
  - 展开 / 收起。
  - 最新价线。
  - 点击命中。
  - 惯性滑动。
  - 滑动中刷新策略。
- 接入 `QuoteTableStore` 和 `QuoteUpdateScheduler`。
- 完成业务默认、偏高压力、极限降级三档压测。

适配清单（两个原型都要验收，避免坑留到阶段 6 才发现）：

- 主题切换：当前已有黑白版适配（FUHM-404），Canvas / BuilderNode 不能依赖 `$r('app.color...')` 自动重绘，必须订阅主题变化并主动 invalidate 所有可见行。
- 系统大字号：当前 `ItemComponent` 用 `minFontSize` / `maxFontSize` 自适应；Canvas 需自行二分测量，BuilderNode 需确认 `Text` 在 `BuilderNode` 内仍能响应系统字号。
- 横屏 / 折叠屏 / 平板：可见列从 10 涨到 30，单行绘制内容约 3 倍，性能预算必须重新跑一次而不是只跑竖屏。
- 屏幕旋转 / 窗口尺寸变化：原型要能正确重算列宽和可见区，并在切换瞬间不留残影。

选型报告产出维度：

- 各场景 FPS / P95 / P99。
- 文本质量主观评分（含中英文混排、字号自适应、截断对齐）。
- 内存占用（含每个 RowCanvas 的位图开销估算）。
- 主题 / 字号 / 旋转适配的完成度和实现复杂度。
- 开发与维护成本评估。

产出：

- `D_canvas` 视口级 Canvas 原型。
- 渲染方案选型报告。
- 默认压测档位和推荐配置。

**阶段结论**：业务默认档位 `20Hz + 1/4 表 + 100ms flush + 只刷可见 + 滑动刷新关` 达标；偏高压力档 `20Hz + 半表 + 100ms flush` 达标；极限降级档仅作为边界测试，不作为默认业务目标。

### 阶段 5：业务组件化接入

目标：将 entry 压测原型抽象为可接入真实业务的行情表组件，并保留压测页作为回归入口。

任务：

- 从 `entry/src/main/ets/perf/CanvasQuoteTable.ets` 提取业务组件接口。
- 定义真实业务数据输入模型：
  - 行权价数组。
  - Call / Put 列配置。
  - 最新价。
  - 变动 cell delta。
  - 颜色 / 闪烁 / 主题 token。
- 定义 `QuoteTablePerfConfig`：
  - 默认 flush 100ms。
  - 高实时档 33 / 50ms。
  - 降级档 200ms。
  - 只刷可见。
  - 滑动中刷新策略。
  - buffer 行列数。
  - 自动降级阈值。
- 将 mock 的 1 基指标列序替换为真实业务列定义。
- 将最新价线从测试行号索引替换为真实行权价映射。
- 将点击 `Info` 测试页替换为业务回调，例如 `onCellClick(row, side, col, value, rowData)`。
- 保留 `PerfTest` 页面作为回归测试入口，不直接混入业务页面。
- 接入 feature flag，新旧渲染路径可在运行时切换。

接口约束：

- 不修改现有 `TComponent`、`DataView`、`GestureMonitor` 的对外签名。
- 高性能路径通过新增 `TCanvasComponent` 并行提供。
- 配置通过新增 `QuoteTablePerfConfig` 提供。
- 旧业务可继续使用 `TComponent`；新业务可按需切换到 `TCanvasComponent`。
- 新增类和新增方法必须写中文注释。
- 命名采用业界常见含义：
  - `Config` 表示配置。
  - `Component` 表示 ArkUI 组件。
  - `viewportCanvas` 表示视口级 Canvas 渲染。

灰度与回滚策略：

- 默认走旧渲染，feature flag 控制开启新渲染，按版本 / 用户分组灰度。
- 旧渲染路径在阶段 5 完成后保留至少两个发布版本，不立即删除。
- 灰度期间 `PerfStats` 双路径采集，便于线上对比。
- 回滚条件提前定义：例如关键场景 P95 / 崩溃率 / 用户投诉超过阈值，自动或一键回退到旧路径。

产出：

- 可复用业务组件。
- 真实行情 delta 接入适配层。
- 大表格和高频行情下的回归报告。
- feature flag 切换机制与灰度方案文档。

**Kill criteria**：业务组件在真实 20Hz 部分变动行情下，业务默认和偏高压力档 P95 ≤ 16.7ms；横纵滑动 P95 ≤ 22ms；极限场景触发降级后不出现连续异常。

### 阶段 6：交互和视觉补齐

目标：补齐生产可用能力。

任务：

- 单元格点击。
- 单元格长按。
- 行/单元格点击后默认不高亮；如业务需要，作为可配置项。
- 涨跌色闪烁或短暂高亮。
- 当前价格线。
- 左右区域展开/收起。
- 表头同步。
- 边界滚动处理。

产出：

- 功能完整的 Canvas 行情表。

### 阶段 7：压测调参和降级策略

目标：稳定生产性能，固化回归基线。

任务：

- 根据压测结果调整 flush 间隔。
- 根据滑动状态调整刷新优先级。
- 数据量过大时降低视觉效果。
- 建立低端设备参数。
- 记录最终推荐配置。
- 建立自动化回归基线：mock 行情驱动 + 帧统计脚本，CI 或日常构建中输出 FPS / P95 / P99，阈值告警。
- 固化报告格式和阈值，确保 A/A'/B/C/D1/D2/D 的报告可以直接 diff。
- 增加低端设备、横屏/折叠屏/平板场景的固定回归用例。

产出：

- 最终性能报告。
- 推荐参数。
- 可重复执行的回归基线脚本和阈值。

## 风险和取舍

### Canvas 方案收益

- 显著减少 ArkUI 组件数量。
- 显著减少响应式对象更新。
- 去掉大量横向 `Scroller` 同步。
- 横滑和行情刷新更稳定。
- 更适合高频行情表。
- 视口级 Canvas 可自行控制固定表头、行权价固定列、左右反向联动横滑、展开收起动画和滑动期间暂停刷新。

### Canvas 方案成本

- 点击、长按需要自己做坐标换算。
- 文本绘制、截断、对齐需要自己处理。
- 可访问性不如原生组件。
- 单元格级动画需要自行实现。
- 展开收起、惯性、方向锁、命中测试、最新价线、固定表头等交互都需要维护自定义坐标系统。
- 开发量高于懒加载或局部优化。
- 主题切换、系统大字号、屏幕旋转需要自己重绘和重新测量，原有声明式适配链路不再适用。
- 每个 RowCanvas 各持位图，纵向可见行多时内存占用需要监控。

### BuilderNode 方案收益

- 复用 ArkUI 文本管线，中文 / 字体回退 / 系统字号天然一致。
- 命令式更新跳过响应式 diff，适合高频点更新。
- 无障碍、文本截断等能力可继承原生节点。

### BuilderNode 方案成本

- `BuilderNode` / `NodeController` API 相对较新，需要确认目标 HarmonyOS 版本范围下的兼容性和稳定性。
- 命令式更新写多了维护成本接近手写 DOM，需要约束更新入口集中在调度层。
- 公开文档和社区案例少于声明式，踩坑需要自己定位。
- 与现有声明式组件的混用边界（事件、布局、动画）需要专门梳理。

## 推荐决策

推荐分阶段验证、按 Kill criteria 决定是否继续，而不是默认走完所有阶段。

推荐路线：

```text
阶段 1.0 ：entry 压测工程（先让性能问题可重复）
阶段 1   ：埋点和基准
阶段 1.5 ：低风险快速改动（先吃掉代码层成本）
阶段 2   ：行情缓存与批量调度（33ms / 100ms / 200ms flush 对照）
阶段 3   ：可见区域刷新（数据只刷可见）
阶段 4   ：视口级 Canvas 方案验证并确认主路线
阶段 5   ：落地 t_split_list，新增 TCanvasComponent，不破坏旧接口
阶段 6   ：真实业务接入、交互补齐和主题配置
阶段 7   ：压测调参、自动降级和回归基线固化
```

阶段 4 已用数据确认视口级 Canvas 是当前收益最大的路线。后续不再优先推进 RowCanvas / BuilderNode，除非真实业务接入后出现 Canvas 无法覆盖的能力缺口。

不建议只做懒加载。懒加载能减少首屏和屏幕外构建压力，但无法根治高频行情下的 cell 组件更新、横向 `Scroller` 同步和布局成本问题。

## 当前业务组件开发约束

`t_split_list` 是真实业务组件目录，后续开发遵守以下约束：

- 保留 `TComponent`、`DataView`、`GestureMonitor`、`TController` 等现有对外能力。
- 新能力优先新增导出，不直接破坏旧接口。
- 高性能路线使用 `TCanvasComponent`。
- 性能参数集中在 `QuoteTablePerfConfig`，后续实际业务可把 flush 间隔、可见刷新、滑动中暂停刷新作为配置项下发。
- 文件保持职责单一：
  - 组件生命周期和手势在 `TCanvasComponent`。
  - 绘制逻辑在 `TCanvasRenderer`。
  - 数据适配在 `TCanvasDataAdapter`。
  - 常量在 `TCanvasConstants`。
- 新增类和新增方法必须写中文注释。
- 示例和接入说明维护在 `t_split_list/README.md` 与 `entry/src/main/ets/pages/QuoteTableExample.ets`。
