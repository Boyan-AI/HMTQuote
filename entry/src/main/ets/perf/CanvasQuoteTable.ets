import { DATA_POS } from 'common_sideslipview';
import { nowMs } from './PerfStats';

const ROW_HEIGHT: number = 40;
const HEADER_HEIGHT: number = 64;
const HEADER_TITLE_Y: number = 48;
const HEADER_TITLE_SIZE: number = 14;
const HEADER_ACTION_Y: number = 16;
const HEADER_ACTION_SIZE: number = 14;
const CENTER_WIDTH: number = 69;
const CELL_WIDTH: number = 76;
const TEXT_SIZE: number = 50;
const VISIBLE_ROW_BUFFER: number = 4;
const REDRAW_INTERVAL_MS: number = 16;
const CENTER_BG: string = '#fff8fafc';
const PRICE_LINE_COLOR: string = '#ff6f80ff';
const PAN_AXIS_LOCK_THRESHOLD: number = 6;
const INERTIA_FRAME_MS: number = 16;
const INERTIA_DECAY: number = 0.92;
const INERTIA_MIN_VELOCITY: number = 0.03;
const INERTIA_MAX_VELOCITY: number = 3.2;
const HEADER_COLLAPSED_ACTION_WIDTH: number = 112;
const LAYOUT_ANIMATION_MS: number = 180;
const LAYOUT_ANIMATION_FRAME_MS: number = 16;

enum CanvasPanAxis {
  None,
  Horizontal,
  Vertical
}

export class CanvasQuotePartitionColors {
  callTop: string = '#fffff3f5';
  callBottom: string = '#fff2fbf5';
  putTop: string = '#fff2fbf5';
  putBottom: string = '#fffff3f5';
}

export class CanvasQuoteHitCell {
  side: DATA_POS = DATA_POS.CENTER;
  row: number = -1;
  col: number = -1;
  value: string = '';
}

export class CanvasQuoteGridData {
  rows: number = 0;
  colsPerSide: number = 0;
  private values: string[] = [];
  private colors: string[] = [];

  reset(rows: number, colsPerSide: number) {
    this.rows = rows;
    this.colsPerSide = colsPerSide;
    let total = rows * colsPerSide * 2;
    this.values = new Array<string>(total);
    this.colors = new Array<string>(total);
    for (let index = 0; index < total; index++) {
      this.values[index] = '';
      this.colors[index] = '#ff000000';
    }
  }

  seed() {
    for (let row = 0; row < this.rows; row++) {
      for (let col = 0; col < this.colsPerSide; col++) {
        this.set(DATA_POS.LEFT, row, col, `${this.colsPerSide - col}-0`, '#ff000000');
        this.set(DATA_POS.RIGHT, row, col, `${col + 1}-0`, '#ff000000');
      }
    }
  }

  set(side: DATA_POS, row: number, col: number, value: string, color: ResourceColor): boolean {
    let key = this.encode(side, row, col);
    if (key < 0 || key >= this.values.length) {
      return false;
    }
    this.values[key] = value;
    this.colors[key] = `${color}`;
    return true;
  }

  getValue(side: DATA_POS, row: number, col: number): string {
    let key = this.encode(side, row, col);
    if (key < 0 || key >= this.values.length) {
      return '';
    }
    return this.values[key];
  }

  getColor(side: DATA_POS, row: number, col: number): string {
    let key = this.encode(side, row, col);
    if (key < 0 || key >= this.colors.length) {
      return '#ff000000';
    }
    return this.colors[key];
  }

  totalWidth(): number {
    return this.colsPerSide * CELL_WIDTH * 2 + CENTER_WIDTH;
  }

  totalHeight(): number {
    return HEADER_HEIGHT + this.rows * ROW_HEIGHT;
  }

  private encode(side: DATA_POS, row: number, col: number): number {
    if (row < 0 || row >= this.rows || col < 0 || col >= this.colsPerSide) {
      return -1;
    }
    let sideOffset = side === DATA_POS.LEFT ? 0 : this.rows * this.colsPerSide;
    return sideOffset + row * this.colsPerSide + col;
  }
}

@Component
export struct CanvasQuoteTable {
  data: CanvasQuoteGridData = new CanvasQuoteGridData();
  partitionColors: CanvasQuotePartitionColors = new CanvasQuotePartitionColors();
  @Prop @Watch('requestRedraw') revision: number = 0;
  onDrawCost: (costMs: number) => void = (_costMs: number) => {
  };
  onCellTap: (cell: CanvasQuoteHitCell) => void = (_cell: CanvasQuoteHitCell) => {
  };
  onScrollStateChange: (scrolling: boolean) => void = (_scrolling: boolean) => {
  };
  onVisibleRangeChange: (startRow: number, endRow: number) => void = (_startRow: number, _endRow: number) => {
  };
  @State private verticalOffset: number = 0;
  @State private horizontalOffset: number = 0;
  @State private leftExpanded: boolean = true;
  @State private rightExpanded: boolean = true;
  @State private centerX: number = -1;
  @Prop @Watch('requestRedraw') latestPrice: number = 50;
  private panStartVerticalOffset: number = 0;
  private panStartHorizontalOffset: number = 0;
  private panStartX: number = 0;
  private panStartedOnLeft: boolean = false;
  private panAxis: CanvasPanAxis = CanvasPanAxis.None;
  private lastPanOffsetX: number = 0;
  private lastPanOffsetY: number = 0;
  private lastPanAt: number = 0;
  private panVelocityX: number = 0;
  private panVelocityY: number = 0;
  private inertiaTimerId: number = -1;
  private inertiaVelocity: number = 0;
  private layoutAnimationTimerId: number = -1;
  @State private viewportHeight: number = 640;
  @State private viewportWidth: number = 360;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private redrawTimerId: number = -1;
  private lastRedrawAt: number = 0;

  aboutToDisappear() {
    if (this.redrawTimerId >= 0) {
      clearTimeout(this.redrawTimerId);
      this.redrawTimerId = -1;
    }
    this.stopInertia();
    this.stopLayoutAnimation();
  }

  private requestRedraw() {
    if (this.redrawTimerId >= 0) {
      return;
    }
    let now = nowMs();
    let delay = Math.max(0, REDRAW_INTERVAL_MS - (now - this.lastRedrawAt));
    this.redrawTimerId = setTimeout(() => {
      this.redrawTimerId = -1;
      this.redraw();
    }, delay);
  }

  private redraw() {
    this.lastRedrawAt = nowMs();
    let startedAt = nowMs();
    this.notifyVisibleRange();
    this.context.clearRect(0, 0, this.viewportWidth, this.viewportHeight);
    let startRow = this.visibleStartRow();
    let endRow = this.visibleEndRow();
    for (let row = startRow; row <= endRow; row++) {
      this.drawRow(row);
    }
    this.drawPriceLine();
    this.drawHeader();
    this.onDrawCost(nowMs() - startedAt);
  }

  private drawHeader() {
    this.context.fillStyle = '#fff5f7fa';
    this.context.fillRect(0, 0, this.viewportWidth, HEADER_HEIGHT);
    this.context.strokeStyle = '#22000000';
    this.context.lineWidth = 0.5;
    this.context.font = `${HEADER_TITLE_SIZE}px sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillStyle = '#ff333333';

    for (let col = 0; col < this.data.colsPerSide; col++) {
      let leftX = this.leftCellX(col);
      let rightX = this.rightCellX(col);
      if ((!this.leftExpanded || !this.isVisibleLeftX(leftX, CELL_WIDTH)) &&
        (!this.rightExpanded || !this.isVisibleRightX(rightX, CELL_WIDTH))) {
        continue;
      }
      if (this.leftExpanded && this.isVisibleLeftX(leftX, CELL_WIDTH)) {
        this.context.strokeRect(leftX, 0, CELL_WIDTH, HEADER_HEIGHT);
        this.context.fillText(`指标${this.data.colsPerSide - col}`, leftX + CELL_WIDTH / 2, HEADER_TITLE_Y);
      }
      if (this.rightExpanded && this.isVisibleRightX(rightX, CELL_WIDTH)) {
        this.context.strokeRect(rightX, 0, CELL_WIDTH, HEADER_HEIGHT);
        this.context.fillText(`指标${col + 1}`, rightX + CELL_WIDTH / 2, HEADER_TITLE_Y);
      }
    }

    let centerX = this.centerStartX();
    this.context.fillStyle = '#fffffbeb';
    this.context.fillRect(centerX, 0, CENTER_WIDTH, HEADER_HEIGHT);
    this.context.strokeRect(centerX, 0, CENTER_WIDTH, HEADER_HEIGHT);
    this.context.fillStyle = '#ff8a8a8a';
    this.context.font = `${HEADER_ACTION_SIZE}px sans-serif`;
    this.context.fillText('切换', centerX + CENTER_WIDTH / 2, HEADER_ACTION_Y);
    this.drawHeaderActions();
    this.context.fillStyle = '#ff333333';
    this.context.font = `${HEADER_TITLE_SIZE}px sans-serif`;
    this.context.fillText('行权价', centerX + CENTER_WIDTH / 2, HEADER_TITLE_Y);
  }

  private drawHeaderActions() {
    let leftX = this.leftActionX();
    let leftWidth = this.leftActionWidth();
    let rightX = this.rightActionX();
    let rightWidth = this.rightActionWidth();
    this.context.font = `${HEADER_ACTION_SIZE}px sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    if (leftWidth > 0) {
      this.context.fillStyle = '#ffff3045';
      this.context.fillText('看涨期权Call >>', leftX + leftWidth / 2, HEADER_ACTION_Y);
    }
    if (rightWidth > 0) {
      this.context.fillStyle = '#ff22a447';
      this.context.fillText('<< 看跌期权Put', rightX + rightWidth / 2, HEADER_ACTION_Y);
    }
  }

  private drawRow(row: number) {
    let y = HEADER_HEIGHT + row * ROW_HEIGHT - this.verticalOffset;
    this.drawRowQuadrantBackground(row, y);
    this.context.strokeStyle = '#14000000';
    this.context.lineWidth = 0.5;
    this.context.font = `${TEXT_SIZE}px sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';

    for (let col = 0; col < this.data.colsPerSide; col++) {
      let leftX = this.leftCellX(col);
      if (this.leftExpanded && this.isVisibleLeftX(leftX, CELL_WIDTH)) {
        this.drawCell(DATA_POS.LEFT, row, col, leftX, y);
      }
      let rightX = this.rightCellX(col);
      if (this.rightExpanded && this.isVisibleRightX(rightX, CELL_WIDTH)) {
        this.drawCell(DATA_POS.RIGHT, row, col, rightX, y);
      }
    }

    let centerX = this.centerStartX();
    if (this.isVisibleX(centerX, CENTER_WIDTH)) {
      this.context.fillStyle = CENTER_BG;
      this.context.fillRect(centerX, y, CENTER_WIDTH, ROW_HEIGHT);
      this.context.strokeRect(centerX, y, CENTER_WIDTH, ROW_HEIGHT);
      this.context.fillStyle = '#ff111827';
      this.context.fillText(`${row}`, centerX + CENTER_WIDTH / 2, y + ROW_HEIGHT / 2);
    }
  }

  private drawRowQuadrantBackground(row: number, y: number) {
    let centerX = this.centerStartX();
    let rightX = this.leftRightStartX();
    let isAbovePrice = row < this.priceBoundaryRow();

    this.context.fillStyle = isAbovePrice ? this.partitionColors.callTop : this.partitionColors.callBottom;
    this.context.fillRect(0, y, centerX, ROW_HEIGHT);

    this.context.fillStyle = CENTER_BG;
    this.context.fillRect(centerX, y, CENTER_WIDTH, ROW_HEIGHT);

    this.context.fillStyle = isAbovePrice ? this.partitionColors.putTop : this.partitionColors.putBottom;
    this.context.fillRect(rightX, y, Math.max(this.viewportWidth - rightX, 0), ROW_HEIGHT);
  }

  private drawCell(side: DATA_POS, row: number, col: number, x: number, y: number) {
    this.context.strokeRect(x, y, CELL_WIDTH, ROW_HEIGHT);
    this.context.fillStyle = this.data.getColor(side, row, col);
    this.context.fillText(this.data.getValue(side, row, col), x + CELL_WIDTH / 2, y + ROW_HEIGHT / 2);
  }

  private drawPriceLine() {
    let y = HEADER_HEIGHT + this.priceBoundaryRow() * ROW_HEIGHT - this.verticalOffset;
    if (y < HEADER_HEIGHT - ROW_HEIGHT || y > this.viewportHeight + ROW_HEIGHT) {
      return;
    }
    this.context.strokeStyle = PRICE_LINE_COLOR;
    this.context.lineWidth = 1;
    this.context.beginPath();
    this.context.moveTo(0, y);
    this.context.lineTo(this.viewportWidth, y);
    this.context.stroke();

    let centerX = this.centerStartX();
    let labelWidth = Math.min(CENTER_WIDTH - 10, 58);
    let labelHeight = 24;
    this.context.fillStyle = PRICE_LINE_COLOR;
    this.context.fillRect(centerX + (CENTER_WIDTH - labelWidth) / 2, y - labelHeight / 2, labelWidth, labelHeight);
    this.context.fillStyle = '#ffffffff';
    this.context.font = `${Math.min(TEXT_SIZE, 15)}px sans-serif`;
    this.context.textAlign = 'center';
    this.context.textBaseline = 'middle';
    this.context.fillText(this.priceLabel(), centerX + CENTER_WIDTH / 2, y);
    this.context.strokeStyle = '#14000000';
    this.context.lineWidth = 0.5;
  }

  private centerStartX(): number {
    if (this.centerX >= 0) {
      return this.centerX;
    }
    return this.targetCenterStartX();
  }

  private leftRightStartX(): number {
    return this.centerStartX() + CENTER_WIDTH;
  }

  private leftActionX(): number {
    return 0;
  }

  private leftActionWidth(): number {
    if (this.leftExpanded) {
      return Math.max(this.centerStartX(), 0);
    }
    return Math.min(HEADER_COLLAPSED_ACTION_WIDTH, this.viewportWidth);
  }

  private rightActionX(): number {
    if (this.rightExpanded) {
      return Math.max(this.leftRightStartX(), 0);
    }
    return Math.max(this.viewportWidth - HEADER_COLLAPSED_ACTION_WIDTH, 0);
  }

  private rightActionWidth(): number {
    if (this.rightExpanded) {
      return Math.max(this.viewportWidth - this.leftRightStartX(), 0);
    }
    return Math.min(HEADER_COLLAPSED_ACTION_WIDTH, this.viewportWidth);
  }

  private leftCellX(col: number): number {
    return this.centerStartX() - (col + 1) * CELL_WIDTH + this.horizontalOffset;
  }

  private rightCellX(col: number): number {
    return this.leftRightStartX() + col * CELL_WIDTH - this.horizontalOffset;
  }

  private visibleStartRow(): number {
    let row = Math.floor(Math.max(this.verticalOffset, 0) / ROW_HEIGHT) - VISIBLE_ROW_BUFFER;
    return Math.max(0, row);
  }

  private visibleEndRow(): number {
    let visibleBodyHeight = Math.max(this.viewportHeight - HEADER_HEIGHT, 0);
    let bottom = this.verticalOffset + visibleBodyHeight;
    let row = Math.ceil(Math.max(bottom, 0) / ROW_HEIGHT) + VISIBLE_ROW_BUFFER;
    return Math.min(this.data.rows - 1, row);
  }

  private notifyVisibleRange() {
    this.onVisibleRangeChange(this.visibleStartRow(), this.visibleEndRow());
  }

  private priceRow(): number {
    return Math.max(0, Math.min(Math.floor(this.latestPrice), this.data.rows - 1));
  }

  private priceBoundaryRow(): number {
    let boundary = Math.floor(this.latestPrice) + 1;
    return Math.max(0, Math.min(boundary, this.data.rows));
  }

  private priceLabel(): string {
    return this.latestPrice.toFixed(1);
  }

  private isVisibleX(x: number, width: number): boolean {
    return x + width >= 0 && x <= this.viewportWidth;
  }

  private isVisibleLeftX(x: number, width: number): boolean {
    return x < this.centerStartX() && x + width >= 0;
  }

  private isVisibleRightX(x: number, width: number): boolean {
    return x + width > this.leftRightStartX() && x <= this.viewportWidth;
  }

  private clampOffsets() {
    let maxVertical = Math.max(this.data.rows * ROW_HEIGHT - Math.max(this.viewportHeight - HEADER_HEIGHT, 0), 0);
    let sideWidth = this.data.colsPerSide * CELL_WIDTH;
    let sideViewportWidth = 0;
    if (this.leftExpanded) {
      sideViewportWidth = Math.max(sideViewportWidth, this.centerStartX());
    }
    if (this.rightExpanded) {
      sideViewportWidth = Math.max(sideViewportWidth, this.viewportWidth - this.leftRightStartX());
    }
    let maxHorizontal = (this.leftExpanded || this.rightExpanded) ? Math.max(sideWidth - sideViewportWidth, 0) : 0;
    this.verticalOffset = Math.max(0, Math.min(this.verticalOffset, maxVertical));
    this.horizontalOffset = Math.max(0, Math.min(this.horizontalOffset, maxHorizontal));
  }

  private targetCenterStartX(): number {
    let middle = Math.max((this.viewportWidth - CENTER_WIDTH) / 2, 0);
    if (!this.leftExpanded && this.rightExpanded) {
      return 0;
    }
    if (this.leftExpanded && !this.rightExpanded) {
      return Math.max(this.viewportWidth - CENTER_WIDTH, 0);
    }
    return middle;
  }

  private stopLayoutAnimation() {
    if (this.layoutAnimationTimerId >= 0) {
      clearInterval(this.layoutAnimationTimerId);
      this.layoutAnimationTimerId = -1;
    }
  }

  private animateLayoutToTarget() {
    this.stopLayoutAnimation();
    let from = this.centerStartX();
    let to = this.targetCenterStartX();
    if (Math.abs(from - to) < 1) {
      this.centerX = to;
      this.clampOffsets();
      this.notifyVisibleRange();
      this.requestRedraw();
      return;
    }
    let startedAt = nowMs();
    this.layoutAnimationTimerId = setInterval(() => {
      let progress = Math.min((nowMs() - startedAt) / LAYOUT_ANIMATION_MS, 1);
      let eased = 1 - Math.pow(1 - progress, 3);
      this.centerX = from + (to - from) * eased;
      this.clampOffsets();
      this.notifyVisibleRange();
      this.requestRedraw();
      if (progress >= 1) {
        this.centerX = to;
        this.stopLayoutAnimation();
        this.clampOffsets();
        this.notifyVisibleRange();
        this.requestRedraw();
      }
    }, LAYOUT_ANIMATION_FRAME_MS);
  }

  private stopInertia() {
    if (this.inertiaTimerId >= 0) {
      clearInterval(this.inertiaTimerId);
      this.inertiaTimerId = -1;
    }
    this.inertiaVelocity = 0;
  }

  private startInertia() {
    let velocity = this.panAxis === CanvasPanAxis.Horizontal ? this.panVelocityX : this.panVelocityY;
    if (Math.abs(velocity) < INERTIA_MIN_VELOCITY) {
      this.onScrollStateChange(false);
      return;
    }
    this.stopInertia();
    this.inertiaVelocity = Math.max(-INERTIA_MAX_VELOCITY, Math.min(velocity, INERTIA_MAX_VELOCITY));
    this.inertiaTimerId = setInterval(() => {
      if (Math.abs(this.inertiaVelocity) < INERTIA_MIN_VELOCITY) {
        this.stopInertia();
        this.onScrollStateChange(false);
        return;
      }
      let beforeX = this.horizontalOffset;
      let beforeY = this.verticalOffset;
      if (this.panAxis === CanvasPanAxis.Horizontal) {
        this.horizontalOffset += this.inertiaVelocity * INERTIA_FRAME_MS;
      } else {
        this.verticalOffset += this.inertiaVelocity * INERTIA_FRAME_MS;
