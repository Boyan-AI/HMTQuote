# TSplitList 组件库说明

本文档说明 `t_split_list` 的模块结构、Canvas T 型分区列表绘制链路、数据刷新协议和后续扩展注意事项。目标读者是后续维护或接入该组件库的研发人员。

## 1. 模块定位

`t_split_list` 是一个 HAR 组件库，当前只支持视口级 Canvas T 型报价实现：

- `canvas/`：视口级 Canvas 实现，包括 `TCanvasComponent`、`TCanvasRenderer`、配置、主题和增量适配器。
- `data_manage/`：Canvas 数据模型，包括 `DataView`、`RowData`、`ListItemData`、`LineData`、`HeaderConfig`。
- `GestureMonitor`：点击和滚动回调桥接对象，作为普通对象传给 Canvas 组件。
- `util/Constant`：共享尺寸和枚举，Canvas 使用其中的行高、列宽、方向枚举。

对外导出集中在 `t_split_list/Index.ets`。新增能力应优先从这里导出，避免业务直接依赖内部路径。

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

- 顶部 Call/Put 标题区：切换左右展开态。
- 顶部中间设置图标：触发 `onSettingClick()`。
- 行权价表头：组件调用 `onStrikeSortToggle(ascending)` 通知业务目标排序方向，表头箭头由业务传入的 `strikeAscending` 驱动。
- 数据区单元格：
  - 先调用旧的 `gestureMonitor.onClick(row, side, strike)`。
  - 再按命中情况调用 `onCellClick(row, side, col, value)`。

业务侧收到 `onStrikeSortToggle(ascending)` 后，应保存排序态、主动重排传入的 `DataView`，并把新的 `strikeAscending` 传回组件。这样普通行情或单元格增量更新时，业务的 row 索引与当前数据顺序始终由同一层维护，避免组件内部重排后业务仍按旧顺序写入导致错行。

### 5.2 滑动

- PanGesture 起手后先锁定横向或纵向。
- 横向滑动只影响左右报价区偏移，中间行权价列固定。
- 纵向滑动影响所有数据行。
- 如果业务传入 `onVerticalEdgeScroll(offset)`，纵向滑动会先消费 T 型报价内部滚动；到顶或到底后，未消费的剩余 offset 会回调给业务层，业务可调用外层 `Scroller.scrollBy(0, offset)` 继续滚动父页面。
- 松手后按速度启动惯性滑动。
- `refreshWhileScrolling=false` 时，组件会在滑动中延迟重绘数据变化；业务侧仍建议缓存高频行情，滑动结束后合并刷新。

### 5.3 展开收起

`expandState` 有三种状态：

- `Normal`：左右区都可见，行权价列居中。
- `Left`：看涨区展开，行权价列移动到右侧。
- `Right`：看跌区展开，行权价列移动到左侧。

展开收起会触发布局动画，动画过程中持续 clamp 横纵 offset，避免展开后滚动范围越界。

## 6. 主题与颜色

Canvas 不能直接稳定使用 ArkUI `$r(...)` 资源色，所以主题默认使用 `#AARRGGBB` 字符串。

颜色来源优先级：

1. 单元格自己的 `fontColor`，如果是字符串且非空则直接使用。
2. `ResourceColor` 是数字时转成 `#AARRGGBB`。
3. 其他情况或空字符串时，回退到主题 token。

暗黑模式由 `TCanvasComponent.darkMode` 控制：

- `false`：使用业务传入 config 的亮色主题基线副本。
- `true`：使用 `QuoteTableThemeTokens.dark()`，并保留亮色基线中非默认的 `sortActiveColor`，让业务排序品牌色在明暗模式通用。未定制时仍使用暗色默认蓝。

业务如果需要品牌色定制，应在组件首次出现前修改 `config.themeTokens`。运行期大规模替换配置对象不属于当前稳定协议，后续如有需要应增加显式 `configRevision` 或专门 watcher。

## 7. 扩展建议

新增 Canvas 能力时建议遵循以下边界：

- 组件状态、手势和生命周期放在 `TCanvasComponent`。
- 纯绘制逻辑放在 `TCanvasRenderer`。
- 数据读取、颜色转换和缺失兜底放在 `TCanvasDataAdapter`。
- 服务端数据结构到 `DataView` 的转换放在 `QuoteTableDeltaAdapter` 或业务层 adapter。
- 新的公开配置放在 `QuoteTablePerfConfig` 或 `QuoteTableThemeTokens`，并同步 `clone()`。
- 新的公开能力需要从 `Index.ets` 导出，并同步 README 或本文档。

避免在 renderer 中直接修改 `DataView` 或组件状态，否则会破坏“状态快照 -> 纯绘制”的边界。

## 8. 常见问题排查

- 点击单元格无响应：
  - 检查 `dataView.createDefaultData(...)` 是否已执行。
  - 检查行列索引是否越界。
  - 检查是否点击在表头区域，表头区域不会触发普通单元格回调。

- 普通行情刷新导致表格跳动：
  - 检查普通刷新是否错误递增了 `latestPriceAnchorRevision`。
  - 普通行情只应递增 `dataRevision`。

- 暗黑模式文字不可见：
  - 中性文本颜色应传空字符串 `''`，让主题兜底。
  - 不要把中性文字硬编码成亮色主题黑色。

- 最新价线不显示：
  - 检查是否调用 `DataView.SetLineData(latestPrice)`。
  - 空字符串或非数字最新价会把 position 设为 `-1`，Canvas 会跳过绘制。

- 写入 delta 后没有刷新：
  - `QuoteTableDeltaAdapter` 只写数据，不递增 `dataRevision`。
  - 业务需要在一批写入完成后递增一次 `dataRevision`。

## 9. 本轮 review 结论

本轮针对 Canvas 绘制模式做了以下防御性修复和文档同步：

- `DataView.updateByItem(...)` 增加负数行列、缺失行和不支持 side 的校验，避免越界访问。
- `QuoteTableDeltaAdapter.applyCellDelta(...)` 改用 `DataView.hasRow(...)`，避免 rows 与 data 短暂不同步时写入 undefined 行。
- `DataView.SetLineData(...)` 对空/非法最新价使用 position `-1`，Canvas 不再绘制空最新价线。
- `TCanvasDataAdapter` 的占位单元格使用空颜色，缺失数据在明暗模式下都走主题兜底。
- 接入文档中的列设置回调名同步为当前接口 `onSettingClick`。
