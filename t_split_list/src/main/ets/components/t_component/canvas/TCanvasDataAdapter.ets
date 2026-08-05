import { DataView } from '../data_manage/DataView';
import { ListItemData } from '../data_manage/ListItemData';
import { RowData } from '../data_manage/RowData';

/**
 * Canvas 组件的数据适配器。
 *
 * 该类只负责把现有 DataView 的列序转换成 Canvas 需要的显示序：
 * 左右两侧以行权价为中心对称，靠近行权价的列都使用低序号指标。
 */
export class TCanvasDataAdapter {
  private dataView: DataView;
  // 空颜色表示交给主题兜底；否则暗黑模式下缺失行/列的占位文本会沿用亮色硬编码。
  private emptyItem: ListItemData = new ListItemData('--', 15, '');

  constructor(dataView: DataView) {
    this.dataView = dataView;
  }

  /**
   * 更新当前数据源引用，避免高频数据变化时反复创建适配器对象。
   */
  updateDataView(dataView: DataView): void {
    this.dataView = dataView;
  }

  /**
   * 获取当前行数。
   */
  rows(): number {
    return this.dataView.getRows();
  }

  /**
   * 获取当前每侧列数。
   */
  cols(): number {
    return this.dataView.getCols();
  }

  /**
   * 判断指定行是否有可用数据。业务初始化过程中 rows 和 data 可能短暂不同步。
   */
  hasRow(row: number): boolean {
    return this.dataView.hasRow(row);
  }

  /**
   * 获取指定行数据，行不存在时返回 undefined。
   */
  row(row: number): RowData | undefined {
    if (!this.hasRow(row)) {
      return undefined;
    }
    return this.dataView.data[row];
  }

  /**
   * 获取中间行权价单元格，缺失时返回安全空单元格。
   */
  centerItem(row: number): ListItemData {
    return this.row(row)?.centerData ?? this.emptyItem;
  }

  /**
   * 获取左侧表头名称，左侧按靠近行权价从低序号到高序号排列。
   */
  leftHeaderName(col: number): string {
    return this.dataView.head[col]?.name ?? '';
  }

  /**
   * 获取右侧表头名称，右侧按低序号到高序号排列。
   */
  rightHeaderName(col: number): string {
    return this.dataView.head[col]?.name ?? '';
  }

  /**
   * 统一显示文本兜底。服务端空值、初始化空值或异常空引用均显示为 "--"。
   */
  displayText(value: number | string | null | undefined): string {
    if (value === null || value === undefined) {
      return '--';
    }
    let text = `${value}`;
    return text.trim().length === 0 ? '--' : text;
  }

  /**
   * 获取左侧单元格数据。
   */
  leftItem(row: number, col: number): ListItemData {
    return this.row(row)?.leftData[col] ?? this.emptyItem;
  }

  /**
   * 获取右侧单元格数据。
   */
  rightItem(row: number, col: number): ListItemData {
    return this.row(row)?.rightData[col] ?? this.emptyItem;
  }

  /**
   * 将 ArkUI 颜色转换为 Canvas 可用颜色；资源色无法直接用于 Canvas 时使用兜底色。
   */
  canvasColor(color: ResourceColor, fallback: string): string {
    if (typeof color === 'string') {
      // 空串表示“未指定颜色”，回退到主题色（随明暗切换），用于中性文字格。
      return color.length > 0 ? color : fallback;
    }
    if (typeof color === 'number') {
      return this.numberToCanvasColor(color);
    }
    return fallback;
  }

  /**
   * ArkUI ResourceColor 可能以整数形式传入，Canvas 需要 #AARRGGBB 字符串。
   */
  private numberToCanvasColor(color: number): string {
    let value = Math.floor(Math.max(color, 0));
    if (value <= 0xFFFFFF) {
      value = 0xFF000000 + value;
    }
    let hex = value.toString(16);
    while (hex.length < 8) {
      hex = `0${hex}`;
    }
    return `#${hex.slice(hex.length - 8)}`;
  }
}
