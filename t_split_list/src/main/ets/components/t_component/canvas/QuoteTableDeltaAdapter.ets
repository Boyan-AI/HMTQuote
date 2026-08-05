import { DataView } from '../data_manage/DataView';
import { DATA_POS } from '../util/Constant';

/**
 * T 型报价单元格增量数据。
 *
 * 该模型用于承接服务端返回的单格行情，颜色由服务端直接给出，组件只负责按颜色显示。
 */
export class QuoteTableCellDelta {
  row: number = 0;
  side: DATA_POS = DATA_POS.LEFT;
  col: number = 0;
  value: string = '';
  color: ResourceColor = '#ff202124';

  constructor(row: number = 0, side: DATA_POS = DATA_POS.LEFT, col: number = 0,
              value: string = '', color: ResourceColor = '#ff202124') {
    this.row = row;
    this.side = side;
    this.col = col;
    this.value = value;
    this.color = color;
  }
}

/**
 * T 型报价增量数据适配器。
 *
 * 业务层把请求返回的 delta 转成 QuoteTableCellDelta 后交给本适配器，
 * 适配器只负责写入 DataView，不负责网络请求和 dataRevision 递增。
 */
export class QuoteTableDeltaAdapter {
  /**
   * 批量应用单元格增量，返回真实写入成功的单元格数量。
   */
  static applyCellDeltas(dataView: DataView, deltas: QuoteTableCellDelta[]): number {
    let updatedCount = 0;
    for (let index = 0; index < deltas.length; index++) {
      if (QuoteTableDeltaAdapter.applyCellDelta(dataView, deltas[index])) {
        updatedCount++;
      }
    }
    return updatedCount;
  }

  /**
   * 应用单个单元格增量。
   *
   * LEFT / RIGHT 写入左右报价区；CENTER 写入中间行权价列，col 会被忽略。
   */
  static applyCellDelta(dataView: DataView, delta: QuoteTableCellDelta): boolean {
    if (!dataView.hasRow(delta.row)) {
      return false;
    }
    if (delta.side === DATA_POS.CENTER) {
      dataView.data[delta.row].centerData.text = delta.value;
      dataView.data[delta.row].centerData.fontColor = delta.color;
      dataView.RefreshLinePosition();
      return true;
    }
    if (delta.col < 0 || delta.col >= dataView.getCols()) {
      return false;
    }
    if (delta.side === DATA_POS.LEFT || delta.side === DATA_POS.RIGHT) {
      return dataView.updateByItem(delta.side, delta.row, delta.col, delta.value, delta.color);
    }
    return false;
  }

  /**
   * 应用最新价文本，并刷新 DataView 内部最新价线位置。
   */
  static applyLatestPrice(dataView: DataView, latestPrice: string): void {
    dataView.SetLineData(latestPrice);
  }
}
