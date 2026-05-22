# T 型行情表性能优化汇报

## 一句话结论

本轮优化已将 T 型期权/期货行情表从“每个 cell 一个 ArkUI 组件高频刷新”推进到 `common_sideslipview` 内的视口级 Canvas 高性能组件。核心路径是：行情增量写入缓存，Canvas 只绘制当前视口，滚动期间暂停或节流 UI flush，合约切换时最新价线居中。

## 背景问题

原组件基于嵌套 `List`、每个单元格一个 ArkUI 组件、每行左右横向 `Scroller`。在高频行情和大表格场景下，主要问题是：

- 高频行情会触发大量 ArkUI 组件更新。
- 不可见 cell 也可能参与写入和刷新。
- 横向/纵向滚动与行情 flush 竞争 UI 线程。
- A/B 早期方案降低 flush 频率后，P95 长帧仍明显，说明瓶颈不只在数据合并，还在 per-cell 组件结构和绘制链路。

## 方案演进

| 阶段 | 方案 | 结论 |
| --- | --- | --- |
| A 当前组件逐 cell 写入 | 一批行情逐个 `DataView.updateByItem` | P95 可达 46ms、61ms、123ms，存在明确卡顿风险 |
| B 调度合并 | 行情先入队，再按 flush 周期批量写 UI | 可降低 UI 写入量，但 P95 未根治 |
| C 只刷可见 | 不可见行留在缓存，只 flush 可见区域 | 写入量下降，但组件结构仍有长帧 |
| D Canvas 原型 | 去掉 per-cell ArkUI 组件，改 Canvas 绘制 | flush 成本大幅下降，路线成立 |
| D1 视口级 Canvas | 只绘制可见行，合并 redraw | P95 稳定进入 16.7ms 预算内，draw 成本低 |
| 业务组件落地 | 在 `common_sideslipview` 新增 `TCanvasComponent` | 已完成样例、README、点击、主题、增量接入、合约切换等业务链路 |

## 核心性能结论

详细原始数据见 `docs/quote-table-performance-report.md`。关键结论：

- 组件表格逐 cell 更新在基准场景下已稳定触发长帧，P95 最高记录到 123ms 级别。
- Canvas 方案将平均 flush 成本从组件表格的约 13-15ms 降到约 1ms 左右。
- 视口级 Canvas + redraw 合并后，`maxCanvasDrawCostMs` 从 83ms 级别降到约 3.45ms。
- 20Hz 业务上限复测：
  - `20Hz + 1/4 表 + 100ms flush`：P95 约 16.61ms，达标。
  - `20Hz + 半表 + 100ms flush`：P95 / P99 稳定，达标。
  - `20Hz + 整表`：可运行但 P95 约 24.91ms，只作为压力边界，不建议作为默认刷新策略。
- 业务默认推荐：`20Hz + 部分变动 + 100ms flush + 只刷可见 + 滚动中暂停 flush`。
- 2026-05-22 最新验证：`assembleHap --no-daemon` 完整通过，包括 `PackageHap / SignHap / assembleHap`。

## 当前交付内容

### common_sideslipview

新增视口级 Canvas 组件和配套能力：

- `TCanvasComponent`：Canvas 行情表主体。
- `QuoteTablePerfConfig`：性能和交互配置。
- `QuoteTableThemeTokens`：主题色 token。
- `QuoteTableDeltaAdapter` / `QuoteTableCellDelta`：服务端增量行情写入适配器。
- `TCanvasRenderer`：纯绘制逻辑。
- `TCanvasDataAdapter`：`DataView` 到 Canvas 显示列序适配。
- `TCanvasConstants`：Canvas 尺寸、手势和动画常量。

已通过 `common_sideslipview/Index.ets` 导出新增能力。

### entry 样例

新增业务样例和详情页：

- `entry/src/main/ets/pages/QuoteTableExample.ets`
- `entry/src/main/ets/pages/QuoteDetail.ets`
- `entry/src/main/ets/pages/quote_example/*`

样例覆盖：

- 200 行 T 型报价表。
- 每 50ms mock 刷新 180 个 cell。
- 滚动期间暂停 mock UI 写入，滚动结束恢复。
- 合约切换选中态。
- 合约切换后最新价线居中。
- 点击单元格进入详情页，携带方向、行权价、指标名、单元格值。
- 表头“切换”区域回调。
- 主题色配置示例。

### 文档

- `common_sideslipview/README.md`：业务接入手册。
- `docs/quote-table-performance-plan.md`：优化方案和测试计划。
- `docs/quote-table-performance-report.md`：阶段性压测数据、方案变更和真机反馈记录。
- `docs/quote-table-performance-summary.md`：本汇报文件。

## 业务接入方式

推荐服务端返回单格增量：

```ts
class ServerQuoteCell {
  row: number = 0;
  side: DATA_POS = DATA_POS.LEFT;
  col: number = 0;
  value: string = '';
  color: ResourceColor = '#ff202124';
}
```

业务侧转换为 `QuoteTableCellDelta`，批量写入 `DataView`：

```ts
let deltas: QuoteTableCellDelta[] = cells.map((cell: ServerQuoteCell) => {
  return new QuoteTableCellDelta(cell.row, cell.side, cell.col, cell.value, cell.color);
});
let updatedCount = QuoteTableDeltaAdapter.applyCellDeltas(this.dataView, deltas);
QuoteTableDeltaAdapter.applyLatestPrice(this.dataView, latestPrice);
if (updatedCount > 0) {
  this.dataRevision++;
}
```

刷新规则：

- 普通行情刷新：递增 `dataRevision`。
- 首次进入、合约切换、业务主动回到最新价：递增 `latestPriceAnchorRevision`。
- 滚动中建议缓存或节流 UI 写入，滚动结束后恢复刷新。

## 推荐配置

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

推荐默认工作点：

- 行情频率：20Hz 左右。
- 数据分布：部分变动，优先按可见区域 flush。
- 滚动策略：滑动和惯性期间暂停 UI flush。
- 极限压力：整表或高频全量变更时，降级到 200ms flush 或进一步暂停滚动中刷新。

## 已验证交互能力

- 左右 Call / Put 展开收起。
- 表头中间“切换”回调。
- 横向和纵向手势方向锁。
- 惯性滑动。
- 合约切换选中态。
- 切换合约后最新价线居中。
- 单元格点击细粒度回调。
- 旧 `GestureMonitor.onClick(row, side, value)` 兼容。

## 接入 Checklist

- 初始化表头：`DataView.SetHead(...)`。
- 初始化行权价列和左右初始数据。
- 设置最新价：`DataView.SetLineData(latestPrice)`。
- 首屏初始化后递增 `dataRevision` 和 `latestPriceAnchorRevision`。
- 服务端返回 `row / side / col / value / color`。
- 用 `QuoteTableDeltaAdapter.applyCellDeltas` 批量写入。
- 每批 UI flush 后递增 `dataRevision`。
- 合约切换后重建结构数据，并递增 `latestPriceAnchorRevision`。
- 滚动期间缓存或节流行情 UI 写入。
- 指标级跳转使用 `onCellClick`。
- 列设置入口使用 `onSettingClick`。
- 主题切换覆盖 `config.themeTokens`。

## 风险和后续

- 20Hz 整表输入属于压力边界，P95 约 24.91ms，不建议作为默认业务目标。
- Canvas draw 偶发尖刺需要后续长时间真机运行继续观察。
- 自动降级策略尚未对象化落地，当前通过配置和业务刷新策略控制。
- 业务点击回调后续可从参数列表升级为 typed object，降低后续扩展成本。
- 接入真实行情后，建议补一轮 `20Hz + 部分变动 + 真机长时间运行` 回归报告。

## 参考文档

- 详细方案：`docs/quote-table-performance-plan.md`
- 详细压测和变更记录：`docs/quote-table-performance-report.md`
- 业务接入手册：`common_sideslipview/README.md`
