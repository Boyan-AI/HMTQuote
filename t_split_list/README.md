# TSplitList

`t_split_list` 是面向 HarmonyOS ArkUI 的高性能 T 型分区列表 UI 组件，可用于期权、期货报价等左右分区联动场景。

当前只支持视口级 Canvas 高性能组件：

- `TCanvasComponent`：视口级 Canvas 组件，用于高频行情和大行数场景。
- `QuoteTablePerfConfig`：Canvas 性能和交互配置。
- `QuoteTableThemeTokens`：Canvas 主题色 token。
- `QuoteTableCellDelta / QuoteTableDeltaAdapter`：服务端增量行情写入适配。

## 导出能力

```ts
export { TCanvasComponent }
export { QuoteTablePerfConfig }
export { QuoteTableThemeTokens }
export { QuoteTableCellDelta, QuoteTableDeltaAdapter }
export { TCanvasScrollRelay, TCanvasScrollRelayResult }
export { DataView }
export { GestureMonitor }
export { HeaderConfig, HeaderItem }
export { RowData }
export { ListItemData }
export { DATA_POS }
```

## 兼容性约束

- 不修改 `DataView` 对外接口。
- 不修改 `GestureMonitor` 对外接口。
- 高频行情数据模型不再依赖 `@Observed`，业务侧批量写入后通过 `dataRevision` 显式触发 Canvas 重绘。
- `TCanvasComponent` 通过普通对象引用读取 `DataView` 和 `GestureMonitor`，不会依赖对象字段赋值的响应式传播。

## 快速接入

```ts
import {
  DATA_POS,
  DataView,
  GestureMonitor,
  HeaderConfig,
  HeaderItem,
  QuoteTablePerfConfig,
  TCanvasComponent
} from 't_split_list';

@Component
struct QuoteTableDemo {
  @State private dataView: DataView = new DataView();
  @State private gestureMonitor: GestureMonitor = new GestureMonitor();
  @State private dataRevision: number = 0;
  @State private latestPriceAnchorRevision: number = 0;
  @State private strikeAscending: boolean = true;
  private config: QuoteTablePerfConfig = new QuoteTablePerfConfig();

  aboutToAppear(): void {
    let head: HeaderConfig = {
      hqData: [
        new HeaderItem(1, '买价'),
        new HeaderItem(2, '最新价'),
        new HeaderItem(3, '卖价')
      ]
    };
    this.dataView.SetHead(head).SetQuadrantColor('#fffff3f5', '#fff2fbf5');
    this.dataView.createDefaultData(200, 3);
    this.dataView.data[0].centerData.text = '960';
    this.dataView.updateByItem(DATA_POS.LEFT, 0, 0, '35.60', '#ffff3045');
    this.dataView.updateByItem(DATA_POS.RIGHT, 0, 0, '1.50', '#ff22a447');
    this.dataView.SetLineData('994.46');
    this.dataRevision++;
    this.latestPriceAnchorRevision++;
  }

  build() {
    TCanvasComponent({
      dataView: this.dataView,
      gestureMonitor: this.gestureMonitor,
      dataRevision: this.dataRevision,
      latestPriceAnchorRevision: this.latestPriceAnchorRevision,
      config: this.config,
      strikeAscending: this.strikeAscending,
      onCellClick: (row: number, side: DATA_POS, col: number, value: string) => {
        console.info(`cell row=${row}, side=${DATA_POS[side]}, col=${col}, value=${value}`);
      },
      onSettingClick: () => {
        console.info('setting clicked');
      },
      onStrikeSortToggle: (ascending: boolean) => {
        this.strikeAscending = ascending;
        this.dataView.SetStrikeAscending(ascending);
        this.dataRevision++;
      }
    })
      .width('100%')
      .height('100%')
  }
}
```

## 配置建议

```ts
const config = new QuoteTablePerfConfig();
config.defaultFlushIntervalMs = 100;
config.visibleOnly = true;
config.refreshWhileScrolling = false;
config.degradedFlushIntervalMs = 200;
config.showSideTitleHeader = true;
config.verticalScrollSensitivity = 1.18;
config.horizontalScrollSensitivity = 1.0;
config.themeTokens.priceLineColor = '#ff2563eb';
config.themeTokens.headerBackgroundColor = '#fff8fafc';
```

滚动手感说明：

- `verticalScrollSensitivity` 越大，纵向拖动同样距离滚动越远。
- 如果真机上仍觉得纵向阻力强，可微调到 `1.25` 左右。
- 高频刷新场景建议滚动期间暂停或节流 UI flush，把接口返回先缓存到内存，滚动结束后再刷新可见区域。

如果 T 型报价被放进外层可滚动业务页，建议让父组件持有 `Scroller`，并接入 `onVerticalEdgeScroll`：

```ts
private parentScroller: Scroller = new Scroller();

build() {
  Scroll(this.parentScroller) {
    Column() {
      // 上方业务内容
      TCanvasComponent({
        dataView: this.dataView,
        gestureMonitor: this.gestureMonitor,
        dataRevision: this.dataRevision,
        latestPriceAnchorRevision: this.latestPriceAnchorRevision,
        config: this.config,
        strikeAscending: this.strikeAscending,
        onVerticalEdgeScroll: (offset: number) => {
          this.parentScroller.scrollBy(0, offset);
        }
      })
        .width('100%')
        .height(520)
      // 下方业务内容
    }
  }
}
```

`TCanvasComponent` 会先消费自己的纵向滚动；到顶或到底后，剩余纵向 offset 才会通过 `onVerticalEdgeScroll` 交给父页面。外层不要在包裹 T 型报价的节点上额外挂会抢占的 `PanGesture` 或阻断型 `onTouch`。

## 真实行情接入

服务端建议直接返回显示文本和颜色，组件不再推导涨跌色：

```ts
class ServerQuoteCell {
  row: number = 0;
  side: DATA_POS = DATA_POS.LEFT;
  col: number = 0;
  value: string = '';
  color: ResourceColor = '#ff202124';
}
```

业务层转换为 `QuoteTableCellDelta` 后批量写入：

```ts
import {
  DataView,
  QuoteTableCellDelta,
  QuoteTableDeltaAdapter
} from 't_split_list';

@State private dataView: DataView = new DataView();
@State private dataRevision: number = 0;

private applyServerDeltas(cells: ServerQuoteCell[], latestPrice: string): void {
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

`QuoteTableDeltaAdapter` 只负责写入 `DataView`，不负责网络请求、定时器和 `dataRevision` 递增。业务侧可以继续复用自己的请求合并、节流和错误处理逻辑。

## 刷新规则

- 普通行情刷新：应用 delta 后递增 `dataRevision`。
- 合约切换、首次进入或业务明确需要重新定位最新价：递增 `latestPriceAnchorRevision`。
- `latestPriceAnchorRevision` 与 `dataRevision` 分离，避免普通行情刷新反复把用户拉回最新价位置。
- 合约切换建议顺序：准备表头和行权价 -> 应用首批数据 -> 设置最新价 -> 递增 `latestPriceAnchorRevision` -> 递增 `dataRevision`。
- 如果服务端先下发最新价、后分批下发行权价，中心列通过 `QuoteTableDeltaAdapter.applyCellDelta(s)` 写入时会自动刷新最新价线位置。

## 最新价居中定位

合约首次绘制或切换合约时，业务通常需要让最新价线位于表格可视区域中间：

```ts
@State private latestPriceAnchorRevision: number = 0;

private switchContract(latestPrice: string): void {
  QuoteTableDeltaAdapter.applyLatestPrice(this.dataView, latestPrice);
  this.latestPriceAnchorRevision++;
  this.dataRevision++;
}
```

普通行情刷新只递增 `dataRevision`，不会重新定位；合约切换、首次进入或业务主动回到最新价时，再递增 `latestPriceAnchorRevision`。

## 点击回调

`TCanvasComponent` 会同时保留旧点击回调和新增细粒度回调：

- `GestureMonitor.onClick(row, side, value)`：旧接口，`value` 为该行中间行权价文本。
- `GestureMonitor.onLongPress(row, side, value)`：旧版长按接口；长按与点击互斥，不应同时触发 `onClick`。
- `onCellClick(row, side, col, value)`：新增接口，`value` 为点击单元格自身文本；点击中间行权价列时 `col = -1`。
- `onVerticalEdgeScroll(offset)`：可选接口，T 型报价纵向滑到顶/底后，把未消费的纵向滑动量交给外层业务 `Scroll`。

`side` 取自 `DATA_POS`：

- `LEFT`：Call 区。
- `RIGHT`：Put 区。
- `CENTER`：行权价列。

样例详情页位于：

```text
entry/src/main/ets/pages/QuoteDetail.ets
```

## 表头设置回调

标题条中间的“切换”区域可作为业务设置入口：

```ts
TCanvasComponent({
  dataView: this.dataView,
  gestureMonitor: this.gestureMonitor,
  dataRevision: this.dataRevision,
  config: this.config,
  strikeAscending: this.strikeAscending,
  onSettingClick: () => {
    // 打开列设置、合约切换或自定义配置面板。
  }
})
```

左右标题点击仍用于展开 / 收起。展开后箭头会反向展示，提示再次点击可恢复普通左右分栏。

## 主题色配置

`QuoteTablePerfConfig.themeTokens` 默认提供一套明色主题。

在组件首次出现前设置 `config.themeTokens.sortActiveColor = '#ffe93030'`，可让排序激活箭头在明暗模式下均使用品牌红。未定制时使用各模式默认蓝色；其他主题字段仍按原有明暗主题规则处理。

可覆盖的常用字段：

- `callColor`：Call 标题色。
- `putColor`：Put 标题色。
- `priceLineColor`：最新价线和标签底色。
- `centerBackgroundColor`：行权价列底色。
- `headerBackgroundColor`：表头底色。
- `borderColor`：单元格分割线颜色。
- `leftAboveLineBackgroundColor / leftBelowLineBackgroundColor`：左侧最新价线上下四象限兜底色。
- `rightAboveLineBackgroundColor / rightBelowLineBackgroundColor`：右侧最新价线上下四象限兜底色。

如业务已经通过 `DataView.SetQuadrantColor` 配置四象限色，Canvas 会优先读取 `DataView` 的颜色；token 中的四象限字段作为无法解析资源色时的兜底。

## 接入 Checklist

- 初始化 `DataView.SetHead(...)`。
- 初始化行数据和中间行权价列。
- 调用 `DataView.SetLineData(latestPrice)` 设置最新价线。
- 首次进入后递增 `dataRevision` 和 `latestPriceAnchorRevision`。
- 服务端返回 `row / side / col / value / color`。
- 用 `QuoteTableDeltaAdapter.applyCellDeltas` 批量应用增量。
- 每批 UI flush 后递增 `dataRevision`。
- 合约切换后重建结构数据，并递增 `latestPriceAnchorRevision`。
- 滚动中缓存或节流行情 UI 写入，滚动结束后恢复刷新。
- 如外层页面也需要滚动，使用 `onVerticalEdgeScroll` 接力到父 `Scroller`。
- 如需指标级跳转，使用 `onCellClick`。
- 如需列设置入口，使用 `onSettingClick`。
- 业务侧通过 `strikeAscending` 传入当前排序态；组件会用该状态计算最新价线位置和表头箭头。点击行权价表头时，`TCanvasComponent` 只通过 `onStrikeSortToggle(ascending)` 通知目标方向，业务侧负责保存排序态、重排 `DataView` 并递增 `dataRevision`。
- 如需主题切换，覆盖 `config.themeTokens`。

## 完整样例页

完整样例页位于：

```text
entry/src/main/ets/pages/QuoteTableExample.ets
```

样例覆盖：

- 顶部安全区、主导航、二级 Tab。
- 合约概要。
- 200 行 T 型报价表。
- 每 50ms mock 刷新 180 个 cell。
- 滚动期间暂停 mock UI 写入。
- 最新价居中。
- 合约切换。
- 点击跳转详情。
- 底部主导航。

## 文件结构

```text
src/main/ets/components/t_component/canvas/QuoteTablePerfConfig.ets
  高频行情渲染配置。

src/main/ets/components/t_component/canvas/QuoteTableThemeTokens.ets
  Canvas 主题色 token。

src/main/ets/components/t_component/canvas/QuoteTableDeltaAdapter.ets
  服务端增量行情到 DataView 的写入适配器。

src/main/ets/components/t_component/canvas/TCanvasConstants.ets
  Canvas 常量和手势方向枚举。

src/main/ets/components/t_component/canvas/TCanvasDataAdapter.ets
  DataView 到 Canvas 显示列序的适配。

src/main/ets/components/t_component/canvas/TCanvasRenderer.ets
  Canvas 绘制器，只处理绘制。

src/main/ets/components/t_component/canvas/TCanvasComponent.ets
  ArkUI 组件，处理生命周期、手势、惯性、展开收起、定位和点击透传。
```

## 后续待补

- 业务点击回调类型对象化。
- 自动降级策略。
