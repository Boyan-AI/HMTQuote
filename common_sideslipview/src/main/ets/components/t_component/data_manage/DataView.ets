import { LineData } from "./LineData";
import { RowData } from "./RowData";
import { ListItemData } from "./ListItemData";
import { HeaderConfig, HeaderItem } from "./TableHeaderConfigModel";
import { DATA_POS } from "../util/Constant";

export class DataView {
  data: RowData[] = [];
  head: HeaderItem[] = [];
  line: LineData = new LineData('', -1);
  private quadrant_1_3_color: ResourceColor = '#0f07ab4b';
  private quadrant_2_4_color: ResourceColor = '#0dff2436';
  private rows: number = 0;
  private cols: number = 0;
  private newPrice: number = 0;
  private ascending: boolean = true;

  public getRows(): number {
    return this.rows;
  }

  public getCols(): number {
    return this.cols;
  }

  public isStrikeAscending(): boolean {
    return this.ascending;
  }

  private validNumber(value: number | string): number | undefined {
    let text = `${value}`.trim();
    if (text.length === 0) {
      return undefined;
    }
    let numberValue = Number(text);
    return Number.isNaN(numberValue) ? undefined : numberValue;
  }

  /**
   * 判断指定行是否存在真实 RowData。初始化或合约切换过程中 rows 与 data 可能短暂不同步。
   */
  public hasRow(row: number): boolean {
    return row >= 0 && row < this.rows && this.data[row] !== undefined;
  }

  /**
   * 按行权价升/降序重排数据，并刷新最新价线位置。
   *
   * 用于点击行权价列切换排序：左右两侧报价随各自所在行一起移动，最新价线按新顺序重新定位。
   */
  SetStrikeAscending(ascending: boolean) {
    this.ascending = ascending;
    this.data.sort((a: RowData, b: RowData): number => {
      let strikeA = this.validNumber(a.centerData.text);
      let strikeB = this.validNumber(b.centerData.text);
      if (strikeA === undefined && strikeB === undefined) {
        return 0;
      }
      if (strikeA === undefined) {
        return 1;
      }
      if (strikeB === undefined) {
        return -1;
      }
      return ascending ? strikeA - strikeB : strikeB - strikeA;
    });
    this.RefreshLinePosition();
    return this;
  }

  /**
   * 只同步当前排序方向，不重排数据；用于业务已按目标顺序传入数据时刷新最新价线位置。
   */
  SetStrikeAscendingState(ascending: boolean) {
    this.ascending = ascending;
    this.RefreshLinePosition();
    return this;
  }

  /**
   * 设置四象限背景色。
   *
   * quadrant_1_3_color 对应右上/左下，quadrant_2_4_color 对应左上/右下。
   * Canvas 模式会先尝试读取该颜色；无法转换为 Canvas 色值时再回退到主题 token。
   */
  SetQuadrantColor(quadrant_1_3_color: ResourceColor, quadrant_2_4_color: ResourceColor) {
    this.quadrant_1_3_color = quadrant_1_3_color;
    this.quadrant_2_4_color = quadrant_2_4_color;
    return this;
  }

  /**
   * 获取四象限背景色。象限定义沿用旧 TComponent：1/3 一组，2/4 一组。
   *
   * 降序时一三/二四两组颜色互换：点击排序切换升降序后，四象限配色随之对调。
   */
  GetQuadrantColor(quadrant: number) {
    let isGroup13 = quadrant == 1 || quadrant == 3;
    if (!this.ascending) {
      isGroup13 = !isGroup13;
    }
    return isGroup13 ? this.quadrant_1_3_color : this.quadrant_2_4_color;
  }

  private JudgePosition() {
    let pos: number = -1;
    for (let index = 0; index < this.data.length; index++) {
      let strike = this.validNumber(this.data[index].centerData.text);
      if (strike === undefined) {
        continue;
      }
      if (this.ascending ? (this.newPrice >= strike) : (this.newPrice <= strike)) {
        pos++;
      }
    }
    return pos;
  }

  /**
   * 最新价为空或无法转成数字时，不绘制最新价线，也不触发 Canvas 居中。
   */
  private hasLatestPrice(value: number | string = this.line.value): boolean {
    return `${value}`.trim().length > 0 && !Number.isNaN(this.newPrice);
  }

  SetLineData(newPrice: string) {
    this.newPrice = Number(newPrice);
    this.line = new LineData(newPrice, this.hasLatestPrice(newPrice) ? this.JudgePosition() : -1);
    return this;
  }

  /**
   * 按当前行权价数据重新计算最新价线位置。
   *
   * 服务端可能先下发最新价，再分批下发行权价/中心列数据；中心列补齐后调用该方法可恢复锚点定位。
   */
  RefreshLinePosition() {
    this.line = new LineData(this.line.value, this.hasLatestPrice() ? this.JudgePosition() : -1);
    return this;
  }

  /**
   * 设置指标表头。列数变化时会按当前行数重建默认行数据，业务应随后重新填充报价内容。
   */
  SetHead(head: HeaderConfig) {
    this.head = [];
    this.head = head.hqData;
    let cols = head.hqData.length;
    if (this.cols != cols) {
      this.cols = cols;
      this.createDefaultData(this.rows, this.cols);
    }
    return this;
  }

  /**
   * 创建默认行列结构。该方法会清空原有 data，适合首次初始化或合约切换后重建结构。
   */
  createDefaultData(rows: number, cols: number) {
    this.rows = rows;
    this.cols = cols;

    this.data = [];
    this.data = Array.from({ length: rows }, (_v: RowData, i: number) => {
      let listData: RowData = new RowData();
      listData.leftData = Array.from({ length: cols }, (_v: ListItemData, j: number) => {
        let listItemDataLeft: ListItemData = new ListItemData();
        return listItemDataLeft;
      })
      listData.rightData = Array.from({ length: cols }, (_v: ListItemData, j: number) => {
        let listItemDataRight: ListItemData = new ListItemData();
        return listItemDataRight;
      })
      return listData;
    })
  }

  /**
   * 直接替换完整行列数据。适合业务一次性构建好带值数据，避免先创建单元格再全量赋值。
   */
  SetData(rows: number, cols: number, data: RowData[]) {
    this.rows = rows;
    this.cols = cols;
    this.data = data;
  }

  /**
   * 更新左右报价区指定单元格。
   *
   * 仅支持 DATA_POS.LEFT / DATA_POS.RIGHT；CENTER 行权价列请通过 QuoteTableDeltaAdapter 或直接改 centerData。
   * 返回 false 表示行列越界、行数据尚未创建或 side 不支持，调用方不应递增 dataRevision。
   */
  updateByItem(flag: DATA_POS, row: number, col: number, text: string,
    fontColor: ResourceColor = $r('app.color.color_66000000')) {
    if (!this.hasRow(row) || col < 0 || col >= this.cols) {
      return false;
    }

    if (flag == DATA_POS.LEFT) {
      this.data[row].leftData[col].text = text;
      this.data[row].leftData[col].fontColor = fontColor;
      return true;
    }
    if (flag == DATA_POS.RIGHT) {
      this.data[row].rightData[col].text = text;
      this.data[row].rightData[col].fontColor = fontColor;
      return true;
    }
    return false;
  }
}
