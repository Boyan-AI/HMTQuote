# T 型行情表开发方案

## 目标

本文档面向后续开发、测试和业务接入人员，作为当前 T 型期权/期货行情表的开发总方案入口。详细性能数据、历史方案和接入细节分别见：

- `docs/quote-table-performance-plan.md`：性能优化方案和压测设计。
- `docs/quote-table-performance-report.md`：历史压测原始结果和阶段结论。
- `docs/quote-table-performance-summary.md`：当前性能优化汇报。
- `docs/tcanvas-business-integration-guide.md`：业务侧接入修改说明。
- `common_sideslipview/README.md`：组件对外能力和快速接入说明。

当前核心目标是稳定交付高频行情表：

- 高频行情刷新不阻塞横纵滑动。
- 普通行情刷新不导致最新价线反复居中。
- 业务接入有明确初始化、刷新、合约切换和测试规范。
- 后续功能开发能在同一套性能基准下验证，避免回退到逐 cell 组件刷新路径。

## 当前结论

当前主线是 `TCanvasComponent`，后续不再支持原 `TComponent` 作为业务路径。

历史验证结论：

- 原 `TComponent` 使用嵌套 `List` 和 per-cell ArkUI 组件，高频刷新下 P95 帧间隔可稳定达到 46ms 以上，存在明确卡顿风险。
- A/B/C 过渡方案证明数据合并、只刷可见区域有收益，但不能根治 per-cell 组件结构带来的长帧。
- 视口级 Canvas 方案已把核心场景 P95 拉回接近 16.7ms 帧预算内。
- 当前默认工作点建议为 `20Hz + 部分变动 + 100ms flush + 只刷可见 + 滚动中暂停或节流 UI flush`。
- `20Hz + 整表刷新` 属于压力边界，只用于降级触发和极限测试，不作为业务默认目标。

## 模块边界

### common_sideslipview

组件库负责提供稳定对外能力：

- `TCanvasComponent`：视口级 Canvas 行情表组件，作为业务和高频场景主路径。
- `QuoteTablePerfConfig`：性能、交互、主题配置。
- `QuoteTableThemeTokens`：主题色 token。
- `QuoteTableDeltaAdapter` / `QuoteTableCellDelta`：业务增量行情写入 `DataView` 的适配器。
- `DataView` / `GestureMonitor` / `DATA_POS` 等模型保持对外兼容。

开发约束：

- 高频行情数据模型保持普通 class，不引入 `@Observed` / `@ObjectLink` 作为数据刷新机制。
- 普通行情数据写入完成后最多递增一次 `dataRevision`，由 Canvas 统一重绘。
- 新能力优先通过新增配置、adapter 或 typed 回调扩展。
- Canvas 绘制逻辑优先留在 `TCanvasRenderer`，组件生命周期、手势、惯性和点击换算留在 `TCanvasComponent`。

### entry

示例和压测工程负责验证组件能力：

- `entry/src/main/ets/pages/QuoteTableExample.ets`：业务接入样例。
- `entry/src/main/ets/pages/QuoteDetail.ets`：单元格点击详情页。
- `entry/src/main/ets/pages/PerfTest.ets`：性能压测入口。
- `entry/src/main/ets/perf/*`：mock 行情、压测统计、调度和 store。

开发约束：

- 压测能力只放在 `entry`，不要污染 `common_sideslipview` 对外组件库。
- 示例页应覆盖真实业务关键链路：初始化、合约切换、最新价居中、滚动暂停刷新、单元格点击、主题配置。

## 业务接入方案

### 初始化顺序

业务页面初始化必须按固定顺序执行：

1. 创建并保存 `DataView`、`GestureMonitor`、`QuoteTablePerfConfig`。
2. 调用 `DataView.SetHead(...)` 初始化表头。
3. 调用 `DataView.createDefaultData(rows, cols)` 初始化表格结构。
4. 写入中间行权价列和左右报价初始值。
5. 调用 `DataView.SetLineData(latestPrice)` 设置最新价。
6. 首次完成后递增 `latestPriceAnchorRevision`。
7. 首次完成后递增 `dataRevision`。

禁止在 `createDefaultData` 前访问 `dataView.data[row]`。

### 普通行情刷新

普通行情刷新只代表数据变化，不代表需要重新定位最新价线：

- 使用 `QuoteTableDeltaAdapter.applyCellDeltas(...)` 批量写入 cell。
- 使用 `QuoteTableDeltaAdapter.applyLatestPrice(...)` 更新最新价文本。
- 一批数据写完后最多递增一次 `dataRevision`。
- 普通行情刷新不要递增 `latestPriceAnchorRevision`。

推荐服务端或业务转换层提供单格增量：

```ts
class ServerQuoteCell {
  row: number = 0;
  side: DATA_POS = DATA_POS.LEFT;
  col: number = 0;
  value: string = '';
  color: ResourceColor = '#ff202124';
}
```

颜色建议传字符串色值，例如 `'#ffff3045'`、`'#ff22a447'`、`'#ff202124'`，不要把 `$r(...)` 资源对象直接作为 cell 颜色传给 Canvas。

### 合约切换和回到最新价

以下场景才递增 `latestPriceAnchorRevision`：

- 首次进入页面。
- 切换合约并重建表格数据。
- 用户主动触发“回到最新价”。

合约切换推荐流程：

1. 更新当前合约状态。
2. 重新获取或解析表头、行权价和首批报价。
3. 重建 `DataView` 结构数据。
4. 写入最新价。
5. 先递增 `latestPriceAnchorRevision`。
6. 再递增 `dataRevision`。

### 滚动期间刷新策略

高频行情下以手势响应优先。默认策略：

- 触摸或滚动期间不直接把行情写入 UI。
- 缓存最后一包行情。
- 滚动停止后 flush 最后一包并递增 `dataRevision`。

如果业务要求滚动中仍展示实时行情，应通过 `QuoteTablePerfConfig` 控制为低频 flush，并补充真机压测。禁止在滚动中逐 cell 高频写 UI。

## 性能配置基线

默认推荐：

```ts
const config = new QuoteTablePerfConfig();
config.defaultFlushIntervalMs = 100;
config.visibleOnly = true;
config.refreshWhileScrolling = false;
config.degradedFlushIntervalMs = 200;
config.showSideTitleHeader = true;
config.verticalScrollSensitivity = 1.18;
config.horizontalScrollSensitivity = 1.0;
```

配置原则：

- `defaultFlushIntervalMs = 100` 作为默认业务工作点。
- `degradedFlushIntervalMs = 200` 仅用于低端设备、极限压力或滚动中降级。
- `visibleOnly = true` 应保持开启。
- `refreshWhileScrolling = false` 是默认推荐，改为 true 必须补充滚动压测。
- 配置项应保留业务侧或远程灰度调整空间，不要写死在组件内部。

## 测试方案

### 功能回归

每次修改 `TCanvasComponent`、`TCanvasRenderer`、`QuoteTableDeltaAdapter`、`DataView` 或业务接入样例后，至少检查：

- 首屏是否有表头、左右报价和行权价列。
- 最新价线首次进入后是否居中。
- 普通行情刷新是否只更新数据，不强制拉回最新价线。
- 横向滑动、纵向滑动、惯性滑动是否顺畅。
- 左右 Call / Put 展开收起是否正常。
- 表头中间“切换”回调是否触发。
- 单元格点击是否能拿到 `row / side / col / value`。
- 合约切换后是否重建数据并重新居中最新价。
- 滚动期间行情是否缓存或节流，滚动结束后是否恢复最后一包。
- 主题色、四象限色和涨跌色是否符合业务预期。

### 性能回归

固定入口：

- 页面：`entry/src/main/ets/pages/PerfTest.ets`
- 统计：`entry/src/main/ets/perf/PerfStats.ets`
- 历史结果追加到：`docs/quote-table-performance-report.md`

推荐每次性能相关改动至少跑以下矩阵：

| 场景 | 参数 | 目标 |
| --- | --- | --- |
| 业务默认 | 20Hz + 1/4 表 + 100ms flush + 只刷可见 + 滚动中暂停刷新 | P95 接近 16.7ms，滑动无明显卡顿 |
| 偏高压力 | 20Hz + 半表 + 100ms flush + 只刷可见 + 滚动中暂停刷新 | P95 / P99 无明显退化 |
| 极限边界 | 20Hz + 整表 + 200ms flush 或降级策略 | 可运行，允许超过 16.7ms，但需记录降级表现 |
| 回归对照 | A_current 或历史失败场景 | 确认未误用旧路径作为性能结论 |

每个场景建议运行 30 秒以上；关键版本建议运行 60 秒以上。

必须记录：

- 设定频率和实测频率。
- `uiAppliedPerSecond`。
- `uiPaintedPerSecond`。
- `flushPerSecond`。
- `avgFlushCostMs` / `maxFlushCostMs`。
- `frameP50Ms` / `frameP95Ms` / `frameP99Ms` / `maxFrameMs`。
- 滚动回调次数。
- Canvas draw 成本。
- 内存和 GC 观察结果。

性能报告规则：

- 新压测数据追加到 `docs/quote-table-performance-report.md`，不要覆盖历史结果。
- 报告中必须写清测试日期、版本、场景、参数、原始 JSON、结论和下一步动作。
- 若实测频率和设定频率偏差过大，应先判定 mock 时钟或测试环境问题，不用该数据证明优化收益。

### 构建验证

代码修改后优先执行：

```bash
hvigorw assembleHap --no-daemon
```

若本机没有 `hvigorw`，使用项目可用的 Hvigor 入口执行等价构建。构建验证结果需要写入交付说明；无法验证时说明原因和风险。

## 后续开发路线

### 阶段 1：业务接入稳定化

目标：

- 固化 `TCanvasComponent` 作为高频行情默认接入方式。
- 清理业务侧错误接入：普通行情误增 `latestPriceAnchorRevision`、逐 cell 递增 `dataRevision`、滚动中直接高频写 UI、重复初始化。
- 完善真实业务接入样例和 README。

验收：

- 示例页覆盖首屏、合约切换、点击详情、滚动暂停刷新。
- 业务接入指南中的最终检查点均满足。
- 构建通过。

### 阶段 2：性能回归自动化和报告规范

目标：

- 统一 PerfTest 场景参数和统计字段。
- 将业务默认、偏高压力、极限边界作为固定回归矩阵。
- 每次性能变更可横向比较历史报告。

验收：

- 新增或更新性能结果追加到 `quote-table-performance-report.md`。
- 压测报告能区分输入量、UI 写入量、实际绘制量和 flush 成本。
- 可定位是否是数据调度、Canvas 绘制、滚动或测试时钟问题。

### 阶段 3：降级策略对象化

目标：

- 将当前依赖业务配置的降级策略沉淀为明确策略模型。
- 支持连续长帧、整表刷新、低端设备或滚动中自动切换 flush 档位。

建议能力：

- `enableAutoDegrade`。
- 连续 N 帧 P95 / max 超阈值后切到 `degradedFlushIntervalMs`。
- 滚动结束或压力恢复后逐步回到默认 flush。
- 降级状态进入 `PerfStats` 和 HiLog。

验收：

- 极限场景下能触发降级。
- 降级不会丢最后一包行情。
- 降级状态可观测、可关闭、可灰度。

### 阶段 4：API 易用性和类型收敛

目标：

- 降低业务接入误用概率。
- 为后续功能扩展保留类型空间。

建议方向：

- 将 `onCellClick(row, side, col, value)` 升级或补充为 typed object 回调。
- 增加业务侧可选的 `QuoteTableUpdateController` 或 helper，统一处理 pending 数据、滚动门禁和 revision 递增。
- 明确颜色 token、数值格式化和 ResourceColor 转换边界。

验收：

- 旧 API 兼容。
- 新 API 文档和样例完整。
- 业务侧不需要重复实现易错的 revision 和滚动缓存逻辑。

### 阶段 5：长期质量补强

目标：

- 提升长时间真机运行稳定性。
- 继续观察 Canvas 文本绘制、内存、GC 和偶发尖刺。

建议动作：

- 增加长时间真机运行报告：至少覆盖 `20Hz + 部分变动 + 30 分钟`。
- 检查内存是否随行情刷新增长。
- 对比不同设备档位下推荐 flush 参数。
- 必要时重新评估 BuilderNode 行方案，作为无障碍或文本质量优先场景的备选。

## 风险

- Canvas 方案需要自行维护文本度量、点击坐标换算、最新价线定位和无障碍能力，后续功能改动要避免分散实现。
- 业务如果绕过 adapter 逐 cell 高频写 UI，仍可能回到旧性能问题。
- 业务如果普通行情刷新递增 `latestPriceAnchorRevision`，会导致滑动时反复回中，表现为跳动和卡顿。
- `20Hz + 整表刷新` 已被定义为压力边界，不应被误判为默认业务目标。
- 性能数据对设备、系统版本、mock 时钟和滚动操作敏感，报告必须保留原始 JSON 和参数。

## 交付检查清单

代码或文档变更交付前检查：

- 是否遵守 `DataView` 初始化顺序。
- 是否一批行情最多递增一次 `dataRevision`。
- 普通行情刷新是否没有递增 `latestPriceAnchorRevision`。
- 滚动期间是否缓存或节流行情 UI 写入。
- 是否没有把 `$r(...)` 资源对象直接作为 Canvas cell 颜色。
- 是否保持 `TComponent`、`DataView`、`GestureMonitor` 兼容。
- 是否更新了 README、接入指南或性能报告中受影响的内容。
- 是否执行了最相关构建、测试或手动验证。
- 若无法验证，是否说明原因和剩余风险。
