import {
  DATA_POS,
  DataView,
  GestureMonitor,
  QuoteTablePerfConfig,
  TCanvasComponent
} from 't_split_list';
import {
  BottomNavItem,
  ContractTabItem,
  SubTabItem,
  TopNavItem
} from './quote_example/QuoteExampleModels';
import { QuoteBottomTabs } from './quote_example/QuoteBottomTabs';
import { QuoteContractSummary } from './quote_example/QuoteContractSummary';
import { QuoteContractTabs } from './quote_example/QuoteContractTabs';
import { QuoteMockData } from './quote_example/QuoteMockData';
import { QuoteTopBar } from './quote_example/QuoteTopBar';

/**
 * TCanvasComponent 业务接入样例页。
 *
 * 该页面只负责持有状态、订阅 gestureMonitor 点击、跑 mock 行情刷新，
 * 顶部、合约摘要、合约 tab 和底部导航分别拆到 quote_example/ 目录下的子组件。
 */
@Entry
@Component
struct QuoteTableExample {
  @State private dataView: DataView = new DataView();
  @State private gestureMonitor: GestureMonitor = new GestureMonitor();
  @State private dataRevision: number = 0;
  @State private latestPriceAnchorRevision: number = 0;
  @State private livePrice: string = '994.46';
  @State private tableScrolling: boolean = false;
  @State private darkMode: boolean = false;
  @State private strikeAscending: boolean = true;
  private pageScroller: Scroller = new Scroller();
  private perfConfig: QuoteTablePerfConfig = new QuoteTablePerfConfig();
  private refreshTimerId: number = -1;
  private readonly topNavItems: TopNavItem[] = [
    new TopNavItem('总览', false),
    new TopNavItem('自选', false),
    new TopNavItem('国内', false),
    new TopNavItem('国际', false),
    new TopNavItem('期权', true),
    new TopNavItem('套利', false)
  ];
  private readonly subTabItems: SubTabItem[] = [
    new SubTabItem('期权雷达', false),
    new SubTabItem('T型报价', true),
    new SubTabItem('策略分析', false),
    new SubTabItem('数据分析', false)
  ];
  @State private contractTabs: ContractTabItem[] = [
    new ContractTabItem('IO3506', '主', true),
    new ContractTabItem('IO2507', '', false),
    new ContractTabItem('IO2508', '', false),
    new ContractTabItem('IO2509', '', false),
    new ContractTabItem('IO2512', '', false)
  ];
  private readonly bottomNavItems: BottomNavItem[] = [
    new BottomNavItem('quote_tab_home.svg', '首页', false),
    new BottomNavItem('quote_tab_quote.svg', '行情', true),
    new BottomNavItem('quote_tab_trade.svg', '交易', false),
    new BottomNavItem('quote_tab_info.svg', '资讯', false)
  ];

  aboutToAppear(): void {
    this.perfConfig.visibleOnly = true;
    this.perfConfig.defaultFlushIntervalMs = 100;
    this.perfConfig.refreshWhileScrolling = false;
    this.perfConfig.themeTokens.priceLineColor = '#ff2e58ff';
    this.perfConfig.themeTokens.headerBackgroundColor = '#ffffffff';
    QuoteMockData.prepareInitialData(this.dataView, this.livePrice);
    this.applyBusinessStrikeSort(this.strikeAscending);
    this.latestPriceAnchorRevision++;
    this.gestureMonitor.onClick = (index: number, flag: DATA_POS, value: string) => {
      console.info(`QuoteTableExample legacy click row=${index}, side=${DATA_POS[flag]}, strike=${value}`);
    };
    this.gestureMonitor.onLongPress = (index: number, flag: DATA_POS, value: string) => {
      this.showLongPressToast(index, flag, value);
    };
    this.gestureMonitor.onScroll = () => {
      this.tableScrolling = true;
    };
    this.gestureMonitor.onScrollStop = () => {
      this.tableScrolling = false;
    };
    this.startQuoteRefresh();
  }

  /**
   * 页面退出时停止样例行情刷新。
   */
  aboutToDisappear(): void {
    if (this.refreshTimerId >= 0) {
      clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
  }

  /**
   * 点击单元格后跳转到合约详情样例页。
   *
   * 业务接入时可以替换为真实详情页路由，参数中已带上合约、方向、行权价、指标和值。
   */
  private openQuoteDetail(row: number, side: DATA_POS, col: number, cellValue: string): void {
    let strike = `${this.dataView.data[row].centerData.text}`;
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/QuoteDetail',
        params: {
          contractCode: this.activeContractCode(),
          contractName: `沪深300ETF期权 ${this.activeContractCode()}`,
          side: DATA_POS[side],
          strike: strike,
          indicatorName: this.indicatorName(side, col),
          cellValue: cellValue,
          livePrice: this.livePrice
        }
      });
    } catch (error) {
      console.error(`QuoteTableExample open detail failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 样例长按反馈：弹出命中的合约、行、方向和行权价，便于验证长按不会走点击跳转。
   */
  private showLongPressToast(row: number, side: DATA_POS, strike: string): void {
    let message = `长按 ${this.activeContractCode()} | 第${row + 1}行 | ${DATA_POS[side]} | 行权价 ${strike}`;
    console.info(`QuoteTableExample long press ${message}`);
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2500,
        bottom: 96
      });
    } catch (error) {
      console.error(`QuoteTableExample long press toast failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 根据点击侧别和列索引返回业务指标名。
   */
  private indicatorName(side: DATA_POS, col: number): string {
    if (side === DATA_POS.CENTER || col < 0) {
      return '行权价';
    }
    return this.dataView.head[col]?.name ?? '报价';
  }

  /**
   * 获取当前激活合约代码。
   */
  private activeContractCode(): string {
    for (let index = 0; index < this.contractTabs.length; index++) {
      if (this.contractTabs[index].active) {
        return this.contractTabs[index].code;
      }
    }
    return this.contractTabs[0]?.code ?? 'IO3506';
  }

  /**
   * 切换合约后重建样例数据，并触发 Canvas 首次绘制定位最新价。
   */
  private switchContract(code: string): void {
    if (code === this.activeContractCode()) {
      this.latestPriceAnchorRevision++;
      return;
    }
    let nextTabs: ContractTabItem[] = [];
    for (let index = 0; index < this.contractTabs.length; index++) {
      let item = this.contractTabs[index];
      nextTabs.push(new ContractTabItem(item.code, item.badge, item.code === code));
    }
    this.contractTabs = nextTabs;
    this.livePrice = this.initialLivePrice(code);
    QuoteMockData.prepareInitialData(this.dataView, this.livePrice);
    this.applyBusinessStrikeSort(this.strikeAscending);
    this.latestPriceAnchorRevision++;
    this.dataRevision++;
  }

  /**
   * 业务侧统一维护 DataView 顺序，保证排序后普通行情仍按当前行序写入正确单元格。
   */
  private applyBusinessStrikeSort(ascending: boolean): void {
    this.strikeAscending = ascending;
    this.dataView.SetStrikeAscending(ascending);
  }

  /**
   * 构造不同合约的样例初始最新价，便于验证切换后的定位行为。
   */
  private initialLivePrice(code: string): string {
    if (code === 'IO2507') {
      return '1006.28';
    }
    if (code === 'IO2508') {
      return '1014.72';
    }
    if (code === 'IO2509') {
      return '1021.36';
    }
    if (code === 'IO2512') {
      return '1030.18';
    }
    return '994.46';
  }

  /**
   * 启动样例行情刷新，用于验证业务组件实时更新能力。
   */
  private startQuoteRefresh(): void {
    if (this.refreshTimerId >= 0) {
      clearInterval(this.refreshTimerId);
    }
    this.refreshTimerId = setInterval(() => {
      if (this.tableScrolling && !this.perfConfig.refreshWhileScrolling) {
        return;
      }
      this.livePrice = QuoteMockData.applyRandomUpdates(this.dataView, this.livePrice);
      this.dataRevision++;
    }, 50);
  }

  /**
   * T 型报价滑到顶/底后，把剩余纵向滑动量交给外层业务页面继续滚动。
   */
  private handleQuoteEdgeScroll(offset: number): void {
    this.pageScroller.scrollBy(0, offset);
  }

  /**
   * 明暗切换按钮：浮在顶部右侧，点击翻转 darkMode，组件与周边随之重绘。
   */
  @Builder
  private ThemeToggle() {
    Text(this.darkMode ? '☀ 亮色' : '🌙 暗黑')
      .fontSize(12)
      .fontColor(this.darkMode ? '#d6ffffff' : '#d6000000')
      .backgroundColor(this.darkMode ? '#ff292929' : '#fff2f4f7')
      .borderRadius(14)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ top: 30, right: 12 })
      .onClick(() => {
        this.darkMode = !this.darkMode;
      })
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Scroll(this.pageScroller) {
        Column() {
          QuoteTopBar({
            topNavItems: this.topNavItems,
            subTabItems: this.subTabItems,
            darkMode: this.darkMode
          })
          QuoteContractSummary({ livePrice: this.livePrice, darkMode: this.darkMode })
          TCanvasComponent({
            dataView: this.dataView,
            gestureMonitor: this.gestureMonitor,
            dataRevision: this.dataRevision,
            latestPriceAnchorRevision: this.latestPriceAnchorRevision,
            config: this.perfConfig,
            strikeAscending: this.strikeAscending,
            darkMode: this.darkMode,
            onCellClick: (row: number, side: DATA_POS, col: number, value: string) => {
              this.openQuoteDetail(row, side, col, value);
            },
            onSettingClick: () => {
              // 点击行权价列上方设置图标。业务接入时在此 pushUrl 跳转到真实设置页，
              // 调整指标列、排序规则等；样例仅打印日志占位。
              console.info('QuoteTableExample setting clicked');
            },
            onStrikeSortToggle: (ascending: boolean) => {
              this.applyBusinessStrikeSort(ascending);
              this.dataRevision++;
            },
            onVerticalEdgeScroll: (offset: number) => {
              this.handleQuoteEdgeScroll(offset);
            }
          })
            .height(520)
            .width('100%')
          QuoteContractTabs({
            contractTabs: this.contractTabs,
            darkMode: this.darkMode,
            onContractClick: (code: string) => {
              this.switchContract(code);
            }
          })
          QuoteBottomTabs({ bottomNavItems: this.bottomNavItems, darkMode: this.darkMode })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .backgroundColor(this.darkMode ? '#ff0d0d0d' : '#ffffffff')

      this.ThemeToggle()
    }
    .width('100%')
    .height('100%')
  }
}
