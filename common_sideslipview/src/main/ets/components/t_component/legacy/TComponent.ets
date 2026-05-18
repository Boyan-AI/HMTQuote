import { DataView } from '../data_manage/DataView';
import { RowData } from '../data_manage/RowData';
import { ListItemData } from '../data_manage/ListItemData';
import { ScrollController } from './ScrollController';
import { LineData } from '../data_manage/LineData';
import {
  ANIMATION_DURATION,
  DATA_POS,
  FILL_UP_STRING,
  HEAD_HEIGHT,
  ICON_HEIGHT,
  ICON_WIDTH,
  ITEM_HEIGHT,
  LINE_HEIGHT,
  ITEM_TEXT_HEIGHT,
  TEXT_MAX_LINES,
  TEXT_MIN_FONT_SIZE,
  HEAD_TEXT_HEIGHT,
  CENTER_ITEM_WIDTH,
  SIDE_ITEM_WIDTH,
  EXPAND_PULL,
  EXPAND_CALL,
  BORDER_COLOR,
  BORDER_WIDTH,
  EXPAND_STATE,
} from '../util/Constant';
import { GestureMonitor } from '../GestureMonitor';
import { HeaderItem } from '../data_manage/TableHeaderConfigModel';
import { TController } from './TController';
import { LegacyGestureClickGate } from './LegacyGestureClickGate';

@Component
struct ItemComponent {
  itemData: ListItemData = new ListItemData();
  @Prop isHead: boolean = false;
  @Prop isCenter: boolean = false;
  @Prop itemBackgroundColor: ResourceColor = $r('app.color.surface_layer1_foreground');

  build() {
    Row() {
      Text(this.itemData.text?.toString())
        .fontColor(this.itemData.fontColor)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .maxLines(TEXT_MAX_LINES)
        .minFontSize(TEXT_MIN_FONT_SIZE)
        .maxFontSize(this.itemData.fontSize)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(this.isHead ? HEAD_TEXT_HEIGHT : ITEM_TEXT_HEIGHT)
        .layoutWeight(1)
        .padding({ left: 4, right: 4 })

      if (this.itemData.icon) {
        Image(this.itemData.icon)
          .height(ICON_HEIGHT)
          .width(ICON_WIDTH)
      }
    }
    .border({
      color: BORDER_COLOR,
      width: {
        top: BORDER_WIDTH,
        bottom: BORDER_WIDTH,
        left: this.isCenter ? BORDER_WIDTH : 0,
        right: this.isCenter ? BORDER_WIDTH : 0
      }
    })
    .backgroundColor(this.itemBackgroundColor)
    .width(this.isCenter ? CENTER_ITEM_WIDTH : SIDE_ITEM_WIDTH)
    .height(this.isHead ? HEAD_HEIGHT : ITEM_HEIGHT)
  }
}


@Component
struct DividerWithNum {
  line: LineData = new LineData();

  build() {
    Row() {
      Divider()
        .layoutWeight(1)
        .color(this.line.color)
        .strokeWidth(1)
      Text(this.line.value.toString())
        .fontSize(this.line.fontSize)
        .backgroundColor($r('app.color.elements_text_primary_01'))
        .fontColor($r('app.color.elements_button_bg_on_color_02'))
        .borderRadius(2)
        .height(16)
        .fontWeight(FontWeight.Medium)
        .padding({ left: 4, right: 4 })
      Divider()
        .layoutWeight(1)
        .color(this.line.color)
        .strokeWidth(1)
        .color($r('app.color.elements_text_primary_01'))
    }
    .height(LINE_HEIGHT)
  }
}

@Component
export struct TComponent {
  dataView: DataView = new DataView();
  gestureMonitor: GestureMonitor = new GestureMonitor();
  private scrollController: ScrollController = new ScrollController(this.dataView.data.length);
  tController: TController = new TController();
  @State private linePos: number = -NaN;
  @State @Watch('onColRowChange') private cols: number = this.dataView.getCols();
  @State @Watch('onColRowChange') private rows: number = this.dataView.getRows();
  @State private isExpand: number = EXPAND_STATE.Normal;
  // 记录横向总滑动offset，当纵向有新的List进入显示区域，将其滑动到相应offset
  private leftTotalXOffset: number = NaN;
  private rightTotalXOffset: number = 0;
  @State private reachStart: boolean = false;
  @State private reachEnd: boolean = false;
  private leftGestureGate: LegacyGestureClickGate = new LegacyGestureClickGate();
  private rightGestureGate: LegacyGestureClickGate = new LegacyGestureClickGate();

  onColRowChange() {
    this.scrollController.Update(this.rows);
    this.leftTotalXOffset = NaN;
    this.rightTotalXOffset = 0;
    this.scrollController.V2H(this.leftTotalXOffset, this.rightTotalXOffset);
  }

  onDataChange() {
    this.cols = this.dataView.getCols();
    this.rows = this.dataView.getRows();
    this.linePos = this.GetLinePos(0);
  }

  /**
   * 触发旧版左侧点击回调，长按已消费时屏蔽同一轮触摸补发的点击。
   */
  private notifyLeftTap(index: number): void {
    if (!this.leftGestureGate.shouldAcceptTap()) {
      return;
    }
    this.gestureMonitor.onClick(index, DATA_POS.LEFT, `${this.dataView.data[index].centerData.text}`);
  }

  /**
   * 触发旧版右侧点击回调，长按已消费时屏蔽同一轮触摸补发的点击。
   */
  private notifyRightTap(index: number): void {
    if (!this.rightGestureGate.shouldAcceptTap()) {
      return;
    }
    this.gestureMonitor.onClick(index, DATA_POS.RIGHT, `${this.dataView.data[index].centerData.text}`);
  }

  /**
   * 触发旧版左侧长按回调，并记录需要屏蔽后续点击。
   */
  private notifyLeftLongPress(index: number): void {
    this.leftGestureGate.markLongPressHandled();
    this.gestureMonitor.onLongPress(index, DATA_POS.LEFT, `${this.dataView.data[index].centerData.text}`);
  }

  /**
   * 触发旧版右侧长按回调，并记录需要屏蔽后续点击。
   */
  private notifyRightLongPress(index: number): void {
    this.rightGestureGate.markLongPressHandled();
    this.gestureMonitor.onLongPress(index, DATA_POS.RIGHT, `${this.dataView.data[index].centerData.text}`);
  }

  aboutToAppear(): void {
    this.scrollController = new ScrollController(this.rows);
    this.linePos = this.GetLinePos(0);
    if (this.tController) {
      this.tController.scroll2center = () => {
        this.scrollController.centerScroller.scrollToIndex(this.dataView.line.position, false, ScrollAlign.CENTER);
      };
    }
  }

  GetLinePos(offset: number): number {
    let scrollOffset = this.scrollController.centerScroller.currentOffset()?.yOffset ?? 0;
    let lineInitPos: number = (this.dataView.line.position + 1) * ITEM_HEIGHT;
    let pos = lineInitPos - scrollOffset - (LINE_HEIGHT / 2) - offset;
    return pos;
  }

  @Builder
  Head() {
    Row() {
      List({ scroller: this.scrollController.leftHeadScroller }) {
        ForEach(this.dataView.head, (item: HeaderItem, index: number) => {
          ListItem() {
            ItemComponent({
              itemData: new ListItemData(this.dataView.head[this.cols - 1 -index].name, 13,
                $r('app.color.elements_text_tertiary')),
              isHead: true,
              isCenter: false
            })
          }
        })
      }
      .onAttach(() => {
        if (Number.isNaN(this.leftTotalXOffset)) {
          this.scrollController.leftHeadScroller.scrollEdge(Edge.End)
        } else {
          this.scrollController.rightHeadScroller.scrollTo({
            xOffset: this.leftTotalXOffset,
            yOffset: 0
          });
        }
      })
      .visibility((this.isExpand == EXPAND_STATE.Right) ? Visibility.None : Visibility.Visible)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .listDirection(Axis.Horizontal)
      .onScrollStop(() => {
        this.gestureMonitor.onScrollStop();
      })
      .onScrollFrameBegin((offset: number, state) => {
        if (state == ScrollState.Scroll || state == ScrollState.Fling) {
          this.gestureMonitor.onScroll();
        }
        let leftCurrentOffset = this.scrollController.leftHeadScroller.currentOffset().xOffset;
        let rightCurrentOffset = this.scrollController.rightHeadScroller.currentOffset().xOffset;

        if ((offset > 0) && (rightCurrentOffset < offset)) {
          offset = rightCurrentOffset;
        }
        if ((offset < 0) && (leftCurrentOffset < -offset)) {
          offset = -leftCurrentOffset;
        }

        this.leftTotalXOffset = leftCurrentOffset + offset;
        this.rightTotalXOffset = rightCurrentOffset - offset;
        this.scrollController.LeftHorizontal(offset, -1, true);
        return { offsetRemain: offset }
      })
      .layoutWeight(1)
      .height(HEAD_HEIGHT)
      .animation({ duration: ANIMATION_DURATION })

      ItemComponent({
        itemData: new ListItemData('行权价', 13, $r('app.color.elements_text_tertiary')),
        isHead: true,
        isCenter: true
      })

      List({ scroller: this.scrollController.rightHeadScroller }) {
        ForEach(this.dataView.head, (item: HeaderItem) => {
          ListItem() {
            ItemComponent({
              itemData: new ListItemData(item.name, 13, $r('app.color.elements_text_tertiary')),
              isHead: true,
              isCenter: false
            })
          }
        })
      }
      .onAttach(() => {
        if (this.rightTotalXOffset == 0) {
          this.scrollController.rightHeadScroller.scrollEdge(Edge.Start)
        } else {
          this.scrollController.rightHeadScroller.scrollTo({
            xOffset: this.rightTotalXOffset,
            yOffset: 0
          });
        }
      })
      .visibility((this.isExpand == EXPAND_STATE.Left) ? Visibility.None : Visibility.Visible)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .listDirection(Axis.Horizontal)
      .onScrollStop(() => {
        this.gestureMonitor.onScrollStop();
      })
      .onScrollFrameBegin((offset: number, state) => {
        if (state == ScrollState.Scroll || state == ScrollState.Fling) {
          this.gestureMonitor.onScroll();
        }
        let leftCurrentOffset = this.scrollController.leftHeadScroller.currentOffset().xOffset;
        let rightCurrentOffset = this.scrollController.rightHeadScroller.currentOffset().xOffset;

        if ((offset > 0) && (leftCurrentOffset < offset)) {
          offset = leftCurrentOffset;
        }
        if ((offset < 0) && (rightCurrentOffset < -offset)) {
          offset = -rightCurrentOffset;
        }

        this.leftTotalXOffset = leftCurrentOffset - offset;
        this.rightTotalXOffset = rightCurrentOffset + offset;
        this.scrollController.RightHorizontal(offset, -1, true);
        return { offsetRemain: offset }
      })
      .layoutWeight(1)
      .height(HEAD_HEIGHT)
      .animation({ duration: ANIMATION_DURATION })
    }
    .height(HEAD_HEIGHT)
    .width(FILL_UP_STRING)
  }

  @Builder
  ExpandCallPut() {
    Row() {
      ItemComponent({
        itemData: new ListItemData(EXPAND_CALL),
        isHead: true,
        isCenter: false
      })
        .onClick(() => {
          this.isExpand = (this.isExpand === EXPAND_STATE.Normal) ? EXPAND_STATE.Left : EXPAND_STATE.Normal;
        })
        .visibility((this.isExpand == EXPAND_STATE.Right) ? Visibility.None : Visibility.Visible)
        .layoutWeight(1)
        .height(HEAD_HEIGHT)
        .animation({ duration: ANIMATION_DURATION })
      ItemComponent({
        itemData: new ListItemData('^'),
        isHead: true,
        isCenter: true
      })
      ItemComponent({
        itemData: new ListItemData(EXPAND_PULL),
        isHead: true,
        isCenter: false
      })
        .layoutWeight(1)
        .onClick(() => {
          this.isExpand = (this.isExpand === EXPAND_STATE.Normal) ? EXPAND_STATE.Right : EXPAND_STATE.Normal;
        })
        .visibility((this.isExpand == EXPAND_STATE.Left) ? Visibility.None : Visibility.Visible)
        .height(HEAD_HEIGHT)
        .animation({ duration: ANIMATION_DURATION })
    }
    .height(HEAD_HEIGHT)
    .width(FILL_UP_STRING)
  }

  build() {
    if (this.cols != 0) {
      Column() {
        // this.ExpandCallPut()
        this.Head()
        Stack() {
          List({ scroller: this.scrollController.centerScroller }) {
            ForEach(this.dataView.data, (item: RowData, index: number) => {
              ListItem() {
                Row() {
                  // 左边数据
                  List({ scroller: this.scrollController.leftItemScroller[index] }) {
                    ForEach(item.leftData, (itemLeft: ListItemData) => {
                      ListItem() {
                        ItemComponent({
                          itemData: itemLeft,
                          isHead: false,
                          isCenter: false,
                          itemBackgroundColor: this.dataView.GetQuadrantColor((index <= this.dataView.line.position) ?
                            2 :
                            3)
                        })
                      }
                    })
                  }
                  .visibility((this.isExpand == EXPAND_STATE.Right) ? Visibility.None : Visibility.Visible)
                  .onAttach(() => {
                    if (Number.isNaN(this.leftTotalXOffset)) {
                      this.scrollController.leftItemScroller[index].scrollEdge(Edge.End)
                    } else {
                      this.scrollController.leftItemScroller[index].scrollTo({
                        xOffset: this.leftTotalXOffset,
                        yOffset: 0
                      });
                    }
                  })
                  .height(ITEM_HEIGHT)
                  .layoutWeight(1)
                  .animation({ duration: ANIMATION_DURATION })
                  .height(ITEM_HEIGHT)
                  .scrollBar(BarState.Off)
                  .edgeEffect(EdgeEffect.None)
                  .listDirection(Axis.Horizontal)
                  .nestedScroll({
                    scrollForward: NestedScrollMode.PARALLEL,
                    scrollBackward: NestedScrollMode.PARALLEL
                  })
                  .onScrollFrameBegin((offset: number, state: ScrollState) => {
                    if (state == ScrollState.Scroll || state == ScrollState.Fling) {
                      this.gestureMonitor.onScroll();
                    }
