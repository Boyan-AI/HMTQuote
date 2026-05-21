# common_sideslipview 组件库说明

本文档说明 `common_sideslipview` 的模块结构、Canvas T 型报价绘制链路、数据刷新协议和后续扩展注意事项。目标读者是后续维护或接入该组件库的研发人员。

## 1. 模块定位

`common_sideslipview` 是一个 HAR 组件库，当前只支持视口级 Canvas T 型报价实现：

- `canvas/`：视口级 Canvas 实现，包括 `TCanvasComponent`、`TCanvasRenderer`、配置、主题和增量适配器。
- `data_manage/`：Canvas 数据模型，包括 `DataView`、`RowData`、`ListItemData`、`LineData`、`HeaderConfig`。
- `GestureMonitor`：点击和滚动回调桥接对象，作为普通对象传给 Canvas 组件。
- `util/Constant`：共享尺寸和枚举，Canvas 使用其中的行高、列宽、方向枚举。

对外导出集中在 `common_sideslipview/Index.ets`。新增能力应优先从这里导出，避免业务直接依赖内部路径。

## 2. 关键文件职责

### 2.1 Canvas 模式

- `TCanvasComponent.ets`
  - ArkUI 组件入口。
  - 维护视口尺寸、滚动 offset、展开状态、排序状态、明暗模式、定时器和手势状态。
  - 通过普通对象引用接收 `dataView`、`gestureMonitor`，通过 `dataRevision`、`latestPriceAnchorRevision`、`strikeAscending`、`darkMode` 等显式版本或属性驱动重绘。
  - 点击、滑动、惯性、展开收起、最新价居中都在这里处理。

- `TCanvasRenderer.ets`
  - 纯 Canvas 绘制器。
  - 输入 `TCanvasRenderState` 快照，只读取状态，不修改组件状态。
  - 负责绘制底色、行背景、左右报价单元格、行权价列、表头、排序箭头、最新价线和分隔线。
  - 内部缓存 font、fillStyle、strokeStyle、lineWidth，减少高频绘制时的重复 setter 调用。

- `TCanvasDataAdapter.ets`
  - 将 `DataView` 转成 Canvas 绘制所需的读取接口。
  - 负责列序、缺失行兜底、ArkUI `ResourceColor` 到 Canvas 字符串颜色的转换。
  - 缺失数据使用空颜色 `''`，表示交给主题 token 兜底。

- `QuoteTablePerfConfig.ets`
  - Canvas 模式配置项。
  - 包括刷新策略、可见区域 buffer、滑动刷新策略、滚动灵敏度、是否显示顶部 Call/Put 标题条、主题 token。

- `QuoteTableThemeTokens.ets`
  - Canvas 主题色 token。
  - 亮色为默认字段值，`dark()` 返回暗黑主题副本。
  - token 是可变对象，业务可复制后覆盖局部颜色；组件内部通过 `clone()` 避免共享状态污染。

- `QuoteTableDeltaAdapter.ets`
  - 服务端增量行情写入适配器。
  - 只负责写 `DataView`，不负责网络请求、节流、定时器或 `dataRevision` 递增。
  - 写入失败会返回 `false`，调用方不应因此递增刷新版本。

### 2.2 共享数据模型

- `DataView`
  - 表格主数据容器：`head`、`data`、`line`、行列数、象限色、行权价排序方向。
  - 普通 class，不声明 `@Observed`；高频赋值不会触发 ArkUI 对象字段响应式传播。
  - `createDefaultData(rows, cols)` 会清空并重建行列结构。
  - `SetLineData(latestPrice)` 设置最新价并刷新最新价线位置；空值或非数字会将 position 设为 `-1`，Canvas 不绘制最新价线。
  - `SetStrikeAscending(ascending)` 会按中间行权价重排行数据，并同步最新价线位置。
  - `updateByItem(...)` 只支持左右报价区，CENTER 行权价列不通过该方法写入。

- `RowData`
  - 单行数据：`centerData`、`leftData[]`、`rightData[]`。

- `ListItemData`
  - 单元格展示数据：主文本、可选副文本、字号、颜色、可选图标。
  - Canvas 模式约定颜色为空字符串时使用主题兜底。

## 3. Canvas 绘制流程

`TCanvasComponent.requestRedraw()` 会按 `CANVAS_REDRAW_INTERVAL_MS` 节流重绘，最终调用：

```text
TCanvasComponent.redraw()
  -> centerLatestPriceLineIfNeeded(false)
  -> renderer.render(context, currentRenderState())
```

`TCanvasRenderer.render()` 的绘制顺序：

1. 使用 `theme.canvasBackgroundColor` 铺满整个 Canvas。
2. 计算可见起止行，只绘制视口附近行。
3. 逐行绘制：
   - 四象限背景。
   - 左右报价单元格。
   - 中间行权价单元格。
   - 行分隔线入队。
4. 绘制最新价线和价格标签。
5. 先 flush 行分隔线，避免分隔线覆盖表头背景。
6. 绘制固定表头。
7. 入队中间行权价列左右边框和表头底部分隔线。
8. 最后一次 flush 分隔线。

这个顺序保证滑动时表头始终盖住数据区，分隔线不会穿过表头裸露。

## 4. 数据刷新协议

Canvas 模式通过版本号触发重绘，业务侧必须区分两个版本：

- `dataRevision`
  - 普通行情刷新、批量 delta 写入完成后递增。
  - 用于通知组件下一帧重绘，是普通行情数据变更的唯一 UI 触发点。

- `latestPriceAnchorRevision`
  - 首次进入、合约切换、用户主动回到最新价时递增。
  - 用于让组件把最新价线滚动到视口中间。
  - 普通行情刷新不要递增，否则用户滑动时会被反复拉回最新价位置。

推荐顺序：

```text
初始化或合约切换：
  SetHead(...)
  createDefaultData(...)
  写入行权价和首批左右报价
  SetLineData(latestPrice)
  latestPriceAnchorRevision++
  dataRevision++

普通行情刷新：
  QuoteTableDeltaAdapter.applyCellDeltas(...)
  QuoteTableDeltaAdapter.applyLatestPrice(...)
  dataRevision++
```

如果 `applyCellDeltas` 返回 0，说明没有真实写入，业务可跳过本次 `dataRevision++`。
如果中心行权价列晚于最新价到达，`QuoteTableDeltaAdapter` 写入 CENTER 单元格后会刷新最新价线位置；组件绘制前仍会按未处理的 `latestPriceAnchorRevision` 重试居中。

### 4.1 QuoteTableDeltaAdapter 真实行情接入示例

`QuoteTableDeltaAdapter` 不是 mock 专用工具。它的定位是把业务接口返回的“单元格增量”批量写入 `DataView`，让业务页面不用散落直接访问 `dataView.data[row].leftData[col]` 的代码。mock 数据只是复用了这条真实接入链路来模拟行情推送。

示例：业务接口返回左右报价区的变动单元格和最新价。

```ts
class ServerQuoteCell {
  row: number = 0;
  side: DATA_POS = DATA_POS.LEFT;
  col: number = 0;
  value: string = '';
  color: ResourceColor = '';
}

private applyQuoteResponse(cells: ServerQuoteCell[], latestPrice: string): void {
  let deltas: QuoteTableCellDelta[] = cells.map((cell: ServerQuoteCell) => {
    return new QuoteTableCellDelta(cell.row, cell.side, cell.col, cell.value, cell.color);
  });

  let updatedCount = QuoteTableDeltaAdapter.applyCellDeltas(this.dataView, deltas);
  QuoteTableDeltaAdapter.applyLatestPrice(this.dataView, latestPrice);

  if (updatedCount > 0) {
    this.dataRevision++;
  }
}
```

如果接口返回的是全量快照，也可以先在业务层把快照 diff 成 `QuoteTableCellDelta[]`，再走同一个 adapter。这样后续切换 mock、轮询、WebSocket 或真实推送时，组件侧写入协议保持一致。

## 5. 交互流程

### 5.1 点击

