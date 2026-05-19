import {
  DATA_POS,
  DataView,
  HeaderConfig,
  HeaderItem,
  QuoteTableCellDelta,
  QuoteTableDeltaAdapter
} from 'common_sideslipview';

/**
 * 样例页 mock 数据辅助类。
 *
 * 把表头、初始单元格、最新价线和随机刷新逻辑集中在这里，
 * 避免样例页直接掺杂大段 mock 行情构造代码。
 */
export class QuoteMockData {
  private static readonly INDICATOR_COUNT: number = 8;
  private static readonly ROW_COUNT: number = 200;
  private static readonly DELTA_COUNT_PER_TICK: number = 180;

  /**
   * 构造接近真实期权报价页的初始数据。
   */
  static prepareInitialData(dataView: DataView, livePrice: string): void {
    let head: HeaderConfig = {
      hqData: [
        new HeaderItem(1, '最新价'),
        new HeaderItem(2, '隐含波动率'),
        new HeaderItem(3, '卖价'),
        new HeaderItem(4, '涨跌'),
        new HeaderItem(5, 'Delta'),
        new HeaderItem(6, 'Gamma'),
        new HeaderItem(7, 'Theta'),
        new HeaderItem(8, 'Rho')
      ]
    };
    dataView.SetHead(head).SetQuadrantColor('#0f07ab4b', '#0dff2436');
    dataView.createDefaultData(QuoteMockData.ROW_COUNT, QuoteMockData.INDICATOR_COUNT);

    for (let row = 0; row < dataView.getRows(); row++) {
      let strike = 904 + row * 8;
      let distance = Math.abs(strike - 994);
      let callBase = Math.max(0.18, (1050 - strike) / 9 + row * 0.03);
      let putBase = Math.max(0.18, (strike - 930) / 9 + (dataView.getRows() - row) * 0.02);
      dataView.data[row].centerData.text = `${strike}`;
      // 行权价为中性文字，留空走主题色（明暗自适应），不可烤死亮色否则暗黑下不可见。
      dataView.data[row].centerData.fontColor = '';

      QuoteMockData.fillSideRow(dataView, DATA_POS.LEFT, row, callBase, distance,
        QuoteMockData.callColor(row));
      QuoteMockData.fillSideRow(dataView, DATA_POS.RIGHT, row, putBase, distance,
        QuoteMockData.putColor(row));
    }
    dataView.SetLineData(livePrice);
  }

  /**
   * 在指定行的指定侧填入一组样例指标值。
   */
  private static fillSideRow(dataView: DataView, side: DATA_POS, row: number,
                             base: number, distance: number, color: ResourceColor): void {
    // 红绿语义列（最新价/卖价/涨跌）带显式涨跌色；中性列（IV/希腊字母）留空走主题色。
    dataView.updateByItem(side, row, 0, base.toFixed(2), color);
    dataView.updateByItem(side, row, 1, `${(18 + distance / 12).toFixed(2)}%`, '');
    dataView.updateByItem(side, row, 2, (base + 0.08).toFixed(2), color);
    dataView.updateByItem(side, row, 3,
      `${row % 2 === 0 ? '+' : '-'}${(0.02 + row * 0.01).toFixed(2)}`, color);
    dataView.updateByItem(side, row, 4, (0.12 + distance / 1000).toFixed(4), '');
    dataView.updateByItem(side, row, 5, (0.0012 + row * 0.0001).toFixed(4), '');
    dataView.updateByItem(side, row, 6, `-${(0.42 + row * 0.035).toFixed(4)}`, '');
    dataView.updateByItem(side, row, 7,
      `${row < 14 ? '-' : ''}${(0.0028 - row * 0.00008).toFixed(4)}`, '');
    // 示例：在最新价、卖价列下方展示挂单量副文本（如 “x35”）。
    let sideData = side === DATA_POS.LEFT ? dataView.data[row].leftData : dataView.data[row].rightData;
    sideData[0].subText = `x${30 + row % 9}`;
    sideData[2].subText = `x${30 + row % 9}`;
  }

  /**
   * 模拟一次随机行情 delta，返回新的最新价文本。
   */
  static applyRandomUpdates(dataView: DataView, livePrice: string): string {
    let rows = dataView.getRows();
    let deltas: QuoteTableCellDelta[] = [];
    for (let index = 0; index < QuoteMockData.DELTA_COUNT_PER_TICK; index++) {
      let row = Math.floor(Math.random() * rows);
      let pick = Math.floor(Math.random() * 3);
      let col = pick === 0 ? 0 : pick + 1;
      let side = Math.random() > 0.5 ? DATA_POS.LEFT : DATA_POS.RIGHT;
      let oldValue = Number(side === DATA_POS.LEFT ? dataView.data[row].leftData[col].text :
        dataView.data[row].rightData[col].text);
      let nextValue = Math.max(0.01, oldValue + (Math.random() - 0.5) * 0.28);
      let color: ResourceColor = nextValue >= oldValue ? '#ffff2436' : '#ff07ab4b';
      deltas.push(new QuoteTableCellDelta(row, side, col, nextValue.toFixed(2), color));
    }
    QuoteTableDeltaAdapter.applyCellDeltas(dataView, deltas);
    let nextPrice = Math.max(940, Math.min(1048, Number(livePrice) + (Math.random() - 0.5) * 1.2));
    let nextText = nextPrice.toFixed(2);
    QuoteTableDeltaAdapter.applyLatestPrice(dataView, nextText);
    return nextText;
  }

  /**
   * 构造 Call 示例涨跌色。
   */
  private static callColor(row: number): ResourceColor {
    return row < 11 ? '#ffff2436' : '#ff07ab4b';
  }

  /**
   * 构造 Put 示例涨跌色。
   */
  private static putColor(row: number): ResourceColor {
    return row < 13 ? '#ff07ab4b' : '#ffff2436';
  }
}
