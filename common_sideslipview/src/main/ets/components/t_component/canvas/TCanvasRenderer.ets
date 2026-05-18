import { display } from '@kit.ArkUI';
import { DataView } from '../data_manage/DataView';
import { ListItemData } from '../data_manage/ListItemData';
import {
  BORDER_WIDTH,
  CENTER_ITEM_WIDTH,
  EXPAND_STATE,
  HEAD_HEIGHT,
  ITEM_HEIGHT,
  SIDE_ITEM_WIDTH
} from '../util/Constant';
import { QuoteTablePerfConfig } from './QuoteTablePerfConfig';
import {
  CANVAS_ACTION_HEIGHT,
  CANVAS_ACTION_FONT_SIZE,
  CANVAS_ACTION_ICON_CHEVRON_HEIGHT,
  CANVAS_ACTION_ICON_CHEVRON_WIDTH,
  CANVAS_ACTION_ICON_GAP,
  CANVAS_ACTION_ICON_SETTING_SIZE,
  CANVAS_ACTION_COLLAPSE_CHEVRON_INSET,
  CANVAS_CELL_FONT_SIZE,
  CANVAS_CELL_SUB_FONT_SIZE,
  CANVAS_CELL_SUB_LINE_GAP,
  CANVAS_CENTER_FONT_SIZE,
  CANVAS_HEADER_FONT_SIZE,
  CANVAS_PRICE_LABEL_FONT_SIZE,
  CANVAS_PRICE_LABEL_HEIGHT,
  CANVAS_PRICE_LABEL_MIN_WIDTH,
  CANVAS_PRICE_LABEL_PADDING_X,
  CANVAS_PRICE_LABEL_RADIUS,
  CANVAS_SORT_ARROW_GAP,
  CANVAS_SORT_ARROW_HEIGHT,
  CANVAS_SORT_ARROW_WIDTH
} from './TCanvasConstants';
import { TCanvasDataAdapter } from './TCanvasDataAdapter';
import { QuoteTableThemeTokens } from './QuoteTableThemeTokens';

/**
 * Canvas 渲染状态快照。
 *
 * 主组件负责维护状态，渲染器只读取该快照并绘制，避免渲染器修改组件状态。
 */
export class TCanvasRenderState {
  dataView: DataView;
  dataAdapter: TCanvasDataAdapter;
  config: QuoteTablePerfConfig;
  viewportWidth: number = 0;
  viewportHeight: number = 0;
  verticalOffset: number = 0;
  horizontalOffset: number = 0;
  centerX: number = 0;
  expandState: EXPAND_STATE = EXPAND_STATE.Normal;
  settingIcon: ImageBitmap | undefined = undefined;
  callExpandIcon: ImageBitmap | undefined = undefined;
  putExpandIcon: ImageBitmap | undefined = undefined;
  strikeAscending: boolean = true;

  constructor(dataView: DataView, dataAdapter: TCanvasDataAdapter, config: QuoteTablePerfConfig) {
    this.dataView = dataView;
    this.dataAdapter = dataAdapter;
    this.config = config;
  }
}

/**
 * 视口级 Canvas 绘制器。
 *
 * 该类只负责绘制，不处理手势和组件生命周期，便于控制 TCanvasComponent 文件规模。
 */
export class TCanvasRenderer {
  private state: TCanvasRenderState;
  private context: CanvasRenderingContext2D;
  private pixelRatio: number = 0;
  // 字号字符串缓存：font 字符串按 vp 字号固定，避免每格重复拼接与字体解析。
  private fontCache: Map<number, string> = new Map();
  private fontCacheDpr: number = 0;
  // 每帧累积分隔线坐标，收尾一次 stroke 完成，避免逐行 beginPath/stroke 调用。
  private dividerXs: number[] = [];
  private dividerYs: number[] = [];
  // 上一次设置的 fillStyle / strokeStyle / font / lineWidth；命中缓存时跳过底层 setter。
  private lastFillStyle: string = '';
  private lastStrokeStyle: string = '';
  private lastFont: string = '';
  private lastLineWidth: number = -1;
  // '行权价' 文本宽度缓存。字号固定，宽度只随 DPR 变化。
  private strikeHeaderWidth: number = -1;
  private strikeHeaderWidthDpr: number = 0;

  constructor() {
    this.state = new TCanvasRenderState(new DataView(), new TCanvasDataAdapter(new DataView()), new QuoteTablePerfConfig());
    this.context = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  }

  private setFillStyle(color: string): void {
    if (this.lastFillStyle === color) {
      return;
    }
    this.context.fillStyle = color;
    this.lastFillStyle = color;
  }

  private setStrokeStyle(color: string): void {
    if (this.lastStrokeStyle === color) {
      return;
    }
    this.context.strokeStyle = color;
    this.lastStrokeStyle = color;
  }

  private setLineWidth(width: number): void {
    if (this.lastLineWidth === width) {
      return;
    }
    this.context.lineWidth = width;
    this.lastLineWidth = width;
  }

  private setFontSize(sizeVp: number): void {
    let font = this.fontOf(sizeVp);
    if (this.lastFont === font) {
      return;
    }
    this.context.font = font;
    this.lastFont = font;
  }

  // 渲染前重置 setter 缓存与分隔线队列：renderer 在不同帧间共用，
  // Canvas 上下文若被外部影响（理论上不会，但保留兜底），避免缓存命中却实际未生效。
  private resetFrameState(): void {
    this.lastFillStyle = '';
    this.lastStrokeStyle = '';
    this.lastFont = '';
    this.lastLineWidth = -1;
    this.dividerXs = [];
    this.dividerYs = [];
  }

  /**
   * 屏幕像素密度。Canvas 几何按 vp，但 font 的 px 按设备像素解释，
   * 用密度换算才能让设计稿 vp 字号在高 DPR 设备上正确显示。
   */
  private dpr(): number {
    if (this.pixelRatio <= 0) {
      try {
        this.pixelRatio = display.getDefaultDisplaySync().densityPixels;
      } catch (error) {
        this.pixelRatio = 3;
      }
    }
    return this.pixelRatio;
  }

  /**
   * 获取当前主题 token。
   */
  private theme(): QuoteTableThemeTokens {
    return this.state.config.themeTokens;
  }

  /**
   * Canvas 字号按 px 解释，几何坐标按 vp，需用 vp2px 把设计稿 vp 字号换算成设备像素，
   * 否则在高 DPR 设备上文字会明显偏小。
   */
  private fontOf(sizeVp: number): string {
    let dpr = this.dpr();
    if (dpr !== this.fontCacheDpr) {
      this.fontCache.clear();
      this.fontCacheDpr = dpr;
    }
    let cached = this.fontCache.get(sizeVp);
    if (cached !== undefined) {
      return cached;
    }
    let font = `${sizeVp * dpr}px sans-serif`;
    this.fontCache.set(sizeVp, font);
    return font;
  }

  /**
   * 绘制完整视口。
   *
   * 1) 不再 clearRect，紧接的全屏 fillRect 已经覆盖整张画布；省一次像素清零开销。
   * 2) 行分隔线 / 表头分隔线 / 中央列纵线分两次 stroke：
   *    a) 行分隔线必须在 drawHeader 之前 stroke。若延后到收尾，会画在表头背景之上，
   *       滑动时下半行的灰线会越过表头底色裸露出来（看到表头上漂着横线）。
   *    b) 表头底部分隔线 + 中央列纵线在最后一次 stroke，盖在表头背景之上。
   *    总 stroke 次数从「每行一次」降到 2 次。
   */
  render(context: CanvasRenderingContext2D, state: TCanvasRenderState): void {
    this.context = context;
    this.state = state;
    this.resetFrameState();
    // 全屏底色（象限色半透明，需要叠在主题底色上；暗黑版底色不同于组件透明背景）。
    this.setFillStyle(this.theme().canvasBackgroundColor);
    this.context.fillRect(0, 0, state.viewportWidth, state.viewportHeight);
    let startRow = this.visibleStartRow();
    let endRow = this.visibleEndRow();
    for (let row = startRow; row <= endRow; row++) {
      this.drawRow(row);
    }
    this.drawPriceLine();
    // 行分隔线先 stroke：让随后 drawHeader 的背景把表头区域内残留的行分隔线压在底下。
    this.flushDividers();
    this.drawHeader();
    this.queueCenterColumnBorders();
    this.flushDividers();
  }

  /**
   * 把累积的水平/垂直分隔线一次性 stroke 出来。同 strokeStyle / lineWidth 下合并到单个 path。
   */
  private flushDividers(): void {
    if (this.dividerXs.length === 0 && this.dividerYs.length === 0) {
      return;
    }
    this.setStrokeStyle(this.theme().borderColor);
    this.setLineWidth(BORDER_WIDTH);
    this.context.beginPath();
    let half = BORDER_WIDTH / 2;
    let width = this.state.viewportWidth;
    let height = this.state.viewportHeight;
    for (let i = 0; i < this.dividerYs.length; i++) {
      let y = this.dividerYs[i] - half;
      this.context.moveTo(0, y);
      this.context.lineTo(width, y);
    }
    for (let i = 0; i < this.dividerXs.length; i++) {
      let x = this.dividerXs[i] - half;
      this.context.moveTo(x, 0);
      this.context.lineTo(x, height);
    }
    this.context.stroke();
    this.dividerXs = [];
    this.dividerYs = [];
  }

  /**
   * 把一条横向分割线坐标加入待画队列，render 收尾时统一 stroke。
   */
  private queueHorizontalDivider(y: number): void {
    this.dividerYs.push(y);
  }

  /**
   * 入队行权价列左右两条纵向分割线（贯穿表头与数据区），render 收尾统一 stroke。
   */
  private queueCenterColumnBorders(): void {
    this.dividerXs.push(this.centerStartX());
    this.dividerXs.push(this.rightStartX());
  }

  /**
   * 绘制固定表头，表头始终覆盖在数据行之上。
   * 表头底/中分隔线只入队，render 收尾统一 stroke。
   */
  private drawHeader(): void {
    this.setFillStyle(this.theme().headerBackgroundColor);
    this.context.fillRect(0, 0, this.state.viewportWidth, this.headerHeight());
    this.drawHeaderActions();
    this.drawHeaderCells();
    if (this.state.config.showSideTitleHeader) {
      this.queueHorizontalDivider(CANVAS_ACTION_HEIGHT);
    }
    this.queueHorizontalDivider(this.headerHeight());
  }

  /**
   * 绘制 Call / Put 展开收起标题条。
   *
   * 常态：标题居中于各自半区，紧贴标题的“展开”双箭头指向中心（看涨»、看跌«）。
   * 展开态：标题居中于变宽的数据区，另在贴近行权价列一侧绘制“收起”双箭头，
   * 方向指向收起时数据区的回缩方向（看涨展开«、看跌展开»），点击该数据区即可收起。
   */
  private drawHeaderActions(): void {
    if (!this.state.config.showSideTitleHeader) {
      return;
    }
    let centerX = this.centerStartX();
    let rightStart = this.rightStartX();
    let midY = CANVAS_ACTION_HEIGHT / 2;
    this.setFontSize(CANVAS_ACTION_FONT_SIZE);
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    if (this.state.expandState !== EXPAND_STATE.Right) {
      this.setFillStyle(this.theme().callColor);
      let callCenter = Math.max(centerX / 2, 0);
      this.context.fillText('看涨期权Call', callCenter, midY);
      if (this.state.expandState === EXPAND_STATE.Left) {
        this.drawChevron(centerX - CANVAS_ACTION_COLLAPSE_CHEVRON_INSET, midY, this.state.putExpandIcon);
      } else {
        this.drawInlineChevron('看涨期权Call', callCenter, midY, this.state.callExpandIcon, true);
      }
    }
    this.drawSwitchIcon(centerX + CENTER_ITEM_WIDTH / 2, midY);
    if (this.state.expandState !== EXPAND_STATE.Left) {
      this.setFillStyle(this.theme().putColor);
      let putCenter = rightStart + Math.max(this.state.viewportWidth - rightStart, 0) / 2;
      this.context.fillText('看跌期权put', putCenter, midY);
      if (this.state.expandState === EXPAND_STATE.Right) {
        this.drawChevron(rightStart + CANVAS_ACTION_COLLAPSE_CHEVRON_INSET, midY, this.state.callExpandIcon);
      } else {
        this.drawInlineChevron('看跌期权put', putCenter, midY, this.state.putExpandIcon, false);
      }
    }
  }

  /**
   * 在标题文案紧邻处绘制“展开”双箭头，onRight 决定贴右(»)还是贴左(«)。
   */
  private drawInlineChevron(text: string, textCenterX: number, centerY: number,
    icon: ImageBitmap | undefined, onRight: boolean): void {
    if (!icon) {
      return;
    }
    let textWidth = this.context.measureText(text).width;
    let iconW = CANVAS_ACTION_ICON_CHEVRON_WIDTH;
    let iconH = CANVAS_ACTION_ICON_CHEVRON_HEIGHT;
    let iconX = onRight ? textCenterX + textWidth / 2 + CANVAS_ACTION_ICON_GAP :
      textCenterX - textWidth / 2 - CANVAS_ACTION_ICON_GAP - iconW;
    this.context.drawImage(icon, iconX, centerY - iconH / 2, iconW, iconH);
  }

  /**
   * 在指定中心点绘制双箭头图标，用于展开态贴近行权价列的“收起”箭头。
   */
  private drawChevron(centerX: number, centerY: number, icon: ImageBitmap | undefined): void {
    if (!icon) {
      return;
    }
    let iconW = CANVAS_ACTION_ICON_CHEVRON_WIDTH;
    let iconH = CANVAS_ACTION_ICON_CHEVRON_HEIGHT;
    this.context.drawImage(icon, centerX - iconW / 2, centerY - iconH / 2, iconW, iconH);
  }

  /**
   * 绘制中间“切换”设置图标，图标资源缺失时回退为“切换”文案。
   */
  private drawSwitchIcon(centerX: number, centerY: number): void {
    let icon = this.state.settingIcon;
    if (!icon) {
      this.setFillStyle(this.theme().actionTextColor);
      this.context.fillText('切换', centerX, centerY);
      return;
    }
    let size = CANVAS_ACTION_ICON_SETTING_SIZE;
    this.context.drawImage(icon, centerX - size / 2, centerY - size / 2, size, size);
  }

  /**
   * 绘制左右指标表头和中间行权价表头。
   */
  private drawHeaderCells(): void {
    let y = this.state.config.showSideTitleHeader ? CANVAS_ACTION_HEIGHT : 0;
    this.setFontSize(CANVAS_HEADER_FONT_SIZE);
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.setFillStyle(this.theme().headerTextColor);
    let leftStart = this.visibleLeftStartCol();
    let leftEnd = this.visibleLeftEndCol();
    let rightStartCol = this.visibleRightStartCol();
    let rightEnd = this.visibleRightEndCol();
    for (let col = leftStart; col <= leftEnd; col++) {
      let leftX = this.leftCellX(col);
      if (this.isLeftVisible() && this.isVisibleLeftX(leftX, SIDE_ITEM_WIDTH)) {
        this.context.fillText(this.state.dataAdapter.displayText(this.state.dataAdapter.leftHeaderName(col)),
          leftX + SIDE_ITEM_WIDTH / 2,
          y + HEAD_HEIGHT / 2);
      }
    }
    for (let col = rightStartCol; col <= rightEnd; col++) {
      let rightX = this.rightCellX(col);
      if (this.isRightVisible() && this.isVisibleRightX(rightX, SIDE_ITEM_WIDTH)) {
        this.context.fillText(this.state.dataAdapter.displayText(this.state.dataAdapter.rightHeaderName(col)),
          rightX + SIDE_ITEM_WIDTH / 2,
          y + HEAD_HEIGHT / 2);
      }
    }
    let centerX = this.centerStartX();
    this.setFillStyle(this.theme().centerBackgroundColor);
    this.context.fillRect(centerX, y, CENTER_ITEM_WIDTH, HEAD_HEIGHT);
    this.setFillStyle(this.theme().headerTextColor);
    let centerTextX = centerX + CENTER_ITEM_WIDTH / 2;
    let centerTextY = y + HEAD_HEIGHT / 2;
    this.context.fillText('行权价', centerTextX, centerTextY);
    this.drawSortArrows(centerTextX + this.strikeHeaderTextWidth() / 2 + CANVAS_SORT_ARROW_GAP * 2, centerTextY);
  }

  /**
   * '行权价' 三个字宽度缓存：字号 + DPR 固定，避免每帧 measureText。
   */
  private strikeHeaderTextWidth(): number {
    let dpr = this.dpr();
    if (this.strikeHeaderWidth >= 0 && this.strikeHeaderWidthDpr === dpr) {
      return this.strikeHeaderWidth;
    }
    this.strikeHeaderWidth = this.context.measureText('行权价').width;
    this.strikeHeaderWidthDpr = dpr;
    return this.strikeHeaderWidth;
  }

  /**
   * 绘制行权价表头的排序双三角：上(正序激活,蓝)/下(灰)。
   */
  private drawSortArrows(x: number, centerY: number): void {
    let w = CANVAS_SORT_ARROW_WIDTH;
    let h = CANVAS_SORT_ARROW_HEIGHT;
    let gap = CANVAS_SORT_ARROW_GAP;
    let topY = centerY - (h * 2 + gap) / 2;
    let upColor = this.state.strikeAscending ? this.theme().sortActiveColor : this.theme().sortInactiveColor;
    let downColor = this.state.strikeAscending ? this.theme().sortInactiveColor : this.theme().sortActiveColor;
    this.setFillStyle(upColor);
    this.context.beginPath();
    this.context.moveTo(x + w / 2, topY);
    this.context.lineTo(x, topY + h);
    this.context.lineTo(x + w, topY + h);
    this.context.closePath();
    this.context.fill();
    let downTop = topY + h + gap;
    this.setFillStyle(downColor);
    this.context.beginPath();
    this.context.moveTo(x, downTop);
    this.context.lineTo(x + w, downTop);
    this.context.lineTo(x + w / 2, downTop + h);
    this.context.closePath();
    this.context.fill();
  }

  /**
   * 绘制指定行的可见单元格。
   */
  private drawRow(row: number): void {
    if (!this.state.dataAdapter.hasRow(row)) {
      return;
    }
    let y = this.headerHeight() + row * ITEM_HEIGHT - this.state.verticalOffset;
    this.drawRowBackground(row, y);
    this.setFontSize(CANVAS_CELL_FONT_SIZE);
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    let leftStart = this.visibleLeftStartCol();
    let leftEnd = this.visibleLeftEndCol();
    let rightStartCol = this.visibleRightStartCol();
    let rightEnd = this.visibleRightEndCol();
    for (let col = leftStart; col <= leftEnd; col++) {
      let leftX = this.leftCellX(col);
      if (this.isLeftVisible() && this.isVisibleLeftX(leftX, SIDE_ITEM_WIDTH)) {
        this.drawCell(this.state.dataAdapter.leftItem(row, col), leftX, y);
      }
    }
    for (let col = rightStartCol; col <= rightEnd; col++) {
      let rightX = this.rightCellX(col);
      if (this.isRightVisible() && this.isVisibleRightX(rightX, SIDE_ITEM_WIDTH)) {
        this.drawCell(this.state.dataAdapter.rightItem(row, col), rightX, y);
      }
    }
    this.drawCenterCell(row, y);
    this.queueHorizontalDivider(y + ITEM_HEIGHT);
  }

  /**
   * 绘制行背景四象限颜色。
   */
  private drawRowBackground(row: number, y: number): void {
    let centerX = this.centerStartX();
    let rightStart = this.rightStartX();
    let aboveLine = row <= this.state.dataView.line.position;
    this.setFillStyle(this.state.dataAdapter.canvasColor(aboveLine ?
      this.state.dataView.GetQuadrantColor(2) : this.state.dataView.GetQuadrantColor(3), aboveLine ?
      this.theme().leftAboveLineBackgroundColor : this.theme().leftBelowLineBackgroundColor));
    this.context.fillRect(0, y, centerX, ITEM_HEIGHT);
    this.setFillStyle(this.theme().centerBackgroundColor);
    this.context.fillRect(centerX, y, CENTER_ITEM_WIDTH, ITEM_HEIGHT);
    this.setFillStyle(this.state.dataAdapter.canvasColor(aboveLine ?
      this.state.dataView.GetQuadrantColor(1) : this.state.dataView.GetQuadrantColor(4), aboveLine ?
      this.theme().rightAboveLineBackgroundColor : this.theme().rightBelowLineBackgroundColor));
    this.context.fillRect(rightStart, y, Math.max(this.state.viewportWidth - rightStart, 0), ITEM_HEIGHT);
  }

  /**
   * 绘制普通报价单元格。配置了 subText 时主值上移、下方追加灰色副文本。
   */
  private drawCell(item: ListItemData, x: number, y: number): void {
    let centerX = x + SIDE_ITEM_WIDTH / 2;
    let centerY = y + ITEM_HEIGHT / 2;
    let mainColor = this.state.dataAdapter.canvasColor(item.fontColor, this.theme().cellTextColor);
    this.drawCellWithSub(this.state.dataAdapter.displayText(item.text), item.subText, centerX, centerY, mainColor);
  }

  /**
   * 在单元格中心绘制主值；若有副文本，则主值上移并在其下方画灰色小字。
   * 副文本会临时切换到副字号，画完后显式还原为单元格主字号（不依赖读取 context.font，
   * 因为 Canvas 的 font getter 返回值不保证与设入值一致，读回还原会污染同行后续单元格）。
   */
  private drawCellWithSub(text: string, subText: string, centerX: number, centerY: number,
    mainColor: string): void {
    this.setFillStyle(mainColor);
    if (subText.length === 0) {
      this.context.fillText(text, centerX, centerY);
      return;
    }
