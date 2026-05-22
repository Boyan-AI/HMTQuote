# TCanvasComponent 业务侧接入修改说明

## 目标

修复 `TCanvasComponent` 接入后可能出现的无数据点击 JS crash、滑动卡顿、行情刷新导致布局跳动等问题。

业务侧重点需要规范：

- `DataView` 初始化顺序。
- `dataRevision` / `latestPriceAnchorRevision` 更新时机。
- 滑动期间行情数据的缓存和恢复刷新。
- 单元格颜色传参格式。

## 修改范围

优先修改当前接入页，例如：

```ts
TQuote.ets
```

也就是持有以下状态并渲染 `TCanvasComponent` 的业务组件：

```ts
@State dataView: DataView = new DataView();
@State ges: GestureMonitor = new GestureMonitor();

@State private dataRevision: number = 0;
@State private latestPriceAnchorRevision: number = 0;
private config: QuoteTablePerfConfig = new QuoteTablePerfConfig();

private scrolling: boolean = false;
private touchDown: boolean = false;
```

## 1. 初始化时先创建表头和默认数据

不要在 `DataView` 还是空的时候直接写：

```ts
this.dataView.data[row].centerData.text = value;
```

正确初始化顺序：

```ts
this.dataView.SetHead(this.head);
this.dataView.createDefaultData(this.rows, this.cols);
```

然后再写入行权价、左右报价数据：

```ts
this.dataView.data[row].centerData.text = strikePrice;
this.dataView.data[row].centerData.fontColor = '#ff202124';

this.dataView.data[row].leftData[col].text = value;
this.dataView.data[row].leftData[col].fontColor = color;

this.dataView.data[row].rightData[col].text = value;
this.dataView.data[row].rightData[col].fontColor = color;
```

最后设置最新价：

```ts
this.dataView.SetLineData(this.newPrice);
```

首次初始化完成后只更新一次：

```ts
this.latestPriceAnchorRevision++;
this.dataRevision++;
```

## 2. 普通行情刷新只更新 dataRevision

普通行情推送、局部报价刷新、接口轮询刷新时，只做：

```ts
this.dataRevision++;
```

不要做：

```ts
this.latestPriceAnchorRevision++;
```

`latestPriceAnchorRevision++` 只用于：

- 首次进入页面。
- 切换合约。
- 用户点击“回到最新价”。

原因：如果每次行情刷新都更新 `latestPriceAnchorRevision`，Canvas 会不断把最新价线重新拉回中间，导致用户滑动时表格跳动、卡顿。

## 3. 批量写完数据后再更新 dataRevision

不要每写一个 cell 就更新一次：

```ts
this.dataView.data[row].leftData[col].text = value;
this.dataRevision++;
```

改成一批数据写完后只更新一次：

```ts
private applyQuoteData(): void {
  for (...) {
    this.dataView.data[row].leftData[col].text = value;
    this.dataView.data[row].leftData[col].fontColor = color;
  }

  for (...) {
    this.dataView.data[row].rightData[col].text = value;
    this.dataView.data[row].rightData[col].fontColor = color;
  }

  this.dataView.SetLineData(this.newPrice);

  this.dataRevision++;
}
```

## 4. 行权价排序由业务维护

`TCanvasComponent` 点击行权价表头时只通过 `onStrikeSortToggle(ascending)` 告诉业务目标排序方向；表头箭头和最新价线位置计算由业务传入的 `strikeAscending` 驱动。业务侧需要保存该排序态，并主动调整传入的 `DataView` 顺序。

原因：普通行情和单元格增量通常按业务 row 索引写入。如果组件内部私自重排 `DataView`，业务后续仍按原始顺序更新单元格，倒序状态下就可能写错行。

推荐接入方式：

```ts
@State private strikeAscending: boolean = true;

private applyBusinessStrikeSort(ascending: boolean): void {
  this.strikeAscending = ascending;
  this.dataView.SetStrikeAscending(ascending);
}

TCanvasComponent({
  dataView: this.dataView,
  dataRevision: this.dataRevision,
  latestPriceAnchorRevision: this.latestPriceAnchorRevision,
  strikeAscending: this.strikeAscending,
  onStrikeSortToggle: (ascending: boolean) => {
    this.applyBusinessStrikeSort(ascending);
    this.dataRevision++;
  }
})
```

切换合约或重建全量数据后，也要按当前业务排序态再整理一次：

```ts
private switchContract(code: string): void {
  this.reloadContractData(code);
  this.applyBusinessStrikeSort(this.strikeAscending);
  this.latestPriceAnchorRevision++;
  this.dataRevision++;
}
```

## 5. 滑动期间缓存最后一包行情

如果当前代码类似：

```ts
if (!this.touchDown && !this.scrolling) {
  this.parseContractResponse(structData);
}
```

这会在滑动期间直接丢掉行情。建议改成缓存最后一包。

新增字段：

```ts
private pendingStructData: StuffBaseStruct | undefined = undefined;
```

接收数据时改为：

```ts
private receiveContractResponse(structData: StuffBaseStruct): void {
  if (this.touchDown || this.scrolling) {
    this.pendingStructData = structData;
    return;
  }

  this.parseContractResponse(structData);
}
```

滚动结束后恢复最后一包：

```ts
private flushPendingData(): void {
  if (this.pendingStructData === undefined) {
    return;
  }

  const data = this.pendingStructData;
  this.pendingStructData = undefined;
  this.parseContractResponse(data);
}
```

请求回调中不要直接调用：

```ts
this.parseContractResponse(structData);
```

改为：

```ts
this.receiveContractResponse(structData);
```

## 6. GestureMonitor 里处理滚动状态

在初始化方法中配置滚动回调：

```ts
private initView(): void {
  this.ges.onScroll = () => {
    this.scrolling = true;
  };

  this.ges.onScrollStop = () => {
    setTimeout(() => {
      this.scrolling = false;
      this.flushPendingData();
    }, 200);
  };

  this.ges.onClick = (index: number, flag: DATA_POS, value: string) => {
    // 原有点击逻辑
  };

  this.dataView.SetQuadrantColor('#0f07ab4b', '#0dff2436');
}
```

如果已有 `InitView()`，在已有方法里合并这些逻辑，不要重复创建多个 `onScroll` / `onScrollStop`。

## 7. 外层 touch 只做刷新门禁

如果外层保留：

```ts
.onTouch((event) => {
  if (event.type === TouchType.Down) {
    this.touchDown = true;
  }

  if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
    setTimeout(() => {
      this.touchDown = false;
    }, 500);
  }
})
```

可以保留，但不要阻止事件传给 `TCanvasComponent`。不要加会拦截事件的手势或 return 逻辑。

如果不需要 `touchDown`，可以删除外层 `.onTouch`，仅依赖 `ges.onScroll` / `ges.onScrollStop`。

## 8. onVisibleAreaChange 不要重复初始化

如果当前代码类似：

```ts
.onVisibleAreaChange([0, 1], (isExpanding, currentRatio) => {
  if (isExpanding && currentRatio >= 1) {
    this.getHeadConfig();
    this.onCurrentContractChange();
  }
})
```

需要加一次性保护：

```ts
private initialized: boolean = false;

private ensureInit(): void {
  if (this.initialized) {
    return;
  }

  this.initialized = true;
  this.getHeadConfig();
  this.onCurrentContractChange();
}
```

然后改成：

```ts
.onVisibleAreaChange([0, 1], (isVisible, currentRatio) => {
  if (isVisible && currentRatio >= 1) {
    this.ensureInit();
  }
})
```

切换合约时如果需要重新初始化，不要改 `initialized`，直接走专门的切换方法。

## 9. 切换合约时重建数据并更新两个 revision

切换合约建议流程：

```ts
private onCurrentContractChange(): void {
  // 1. 更新 currentContract。
  // 2. 重新请求或解析表头。
  // 3. 设置 rows / cols。
  // 4. this.dataView.SetHead(this.head)。
  // 5. this.dataView.createDefaultData(this.rows, this.cols)。
  // 6. 填充表格数据。
  // 7. this.dataView.SetLineData(this.newPrice)。

  this.latestPriceAnchorRevision++;
  this.dataRevision++;
}
```

## 10. 颜色全部传字符串色值

Canvas 单元格颜色建议全部用字符串：

```ts
'#ffff3045'
'#ff22a447'
'#ff202124'
```

不要给单元格传：

```ts
$r('app.color.xxx')
```

尤其是以下字段建议使用字符串色值：

- `fontColor`
- `SetQuadrantColor(...)`

## TCanvasComponent 传参检查

保持如下接入方式：

```ts
TCanvasComponent({
  dataView: this.dataView,
  gestureMonitor: this.ges,
  dataRevision: this.dataRevision,
  latestPriceAnchorRevision: this.latestPriceAnchorRevision,
  config: this.config,
  strikeAscending: this.strikeAscending,
  onCellClick: (row: number, side: DATA_POS, col: number, value: string) => {
    // 业务点击
  },
  onSettingClick: () => {
    // 表头中间“切换”
  }
})
  .width('100%')
  .height('100%')
```

如果外层业务页面本身可滚动，把 `TCanvasComponent` 放进父 `Scroll` 时建议这样接：

```ts
private parentScroller: Scroller = new Scroller();

build() {
  Scroll(this.parentScroller) {
    Column() {
      // 上方业务内容
      TCanvasComponent({
        dataView: this.dataView,
        gestureMonitor: this.ges,
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

这种接法下，T 型报价先滚动自己的报价行；滚动到顶端或底部后，剩余纵向滑动量再交给父页面。外层不要在 T 型报价外再挂会抢占手势的 `PanGesture`，也不要在 `.onTouch` 中阻断事件。

## 最终检查点

- 普通行情刷新里没有调用 `this.latestPriceAnchorRevision++`。
- 每批行情数据写完后只调用一次 `this.dataRevision++`。
- 访问 `this.dataView.data[row]` 前，已经执行过 `this.dataView.createDefaultData(this.rows, this.cols)`。
- 行权价中心列若分批到达，优先通过 `QuoteTableDeltaAdapter.applyCellDelta(s)` 写入，适配器会同步刷新最新价线位置。
- 滑动期间行情数据缓存到 `pendingStructData`，滚动结束后通过 `flushPendingData()` 恢复最后一包。
- 外层可滚动页面接入了 `onVerticalEdgeScroll`，并由父 `Scroller.scrollBy(0, offset)` 处理剩余滑动量。
- 单元格颜色传字符串色值，不传 `$r(...)`。
- `onVisibleAreaChange` 不会重复触发初始化。
