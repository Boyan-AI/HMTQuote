import { DataView } from '../data_manage/DataView';
import { GestureMonitor } from '../GestureMonitor';
import {
  CENTER_ITEM_WIDTH,
  DATA_POS,
  EXPAND_STATE,
  HEAD_HEIGHT,
  ITEM_HEIGHT,
  SIDE_ITEM_WIDTH
} from '../util/Constant';
import { QuoteTablePerfConfig } from './QuoteTablePerfConfig';
import {
  CANVAS_ACTION_HEIGHT,
  CANVAS_INERTIA_DECAY,
  CANVAS_INERTIA_FRAME_MS,
  CANVAS_INERTIA_MAX_VELOCITY,
  CANVAS_INERTIA_MIN_VELOCITY,
  CANVAS_LAYOUT_ANIMATION_FRAME_MS,
  CANVAS_LAYOUT_ANIMATION_MS,
  CANVAS_PAN_AXIS_LOCK_THRESHOLD,
  CANVAS_REDRAW_INTERVAL_MS,
  CANVAS_TAP_MAX_DURATION_MS,
  CanvasPanAxis
} from './TCanvasConstants';
import { QuoteTableThemeTokens } from './QuoteTableThemeTokens';
import { TCanvasDataAdapter } from './TCanvasDataAdapter';
import { TCanvasRenderer, TCanvasRenderState } from './TCanvasRenderer';
import { TCanvasScrollRelay } from './TCanvasScrollRelay';
import { TCanvasTapGuard } from './TCanvasTapGuard';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';

/**
 * 视口级 Canvas 行情表组件。
 *
 * 该组件是 T 型报价的 Canvas-only 渲染入口。
 * 高频数据通过普通 DataView 引用读取，业务侧完成批量写入后递增 dataRevision 触发重绘。
 */
@Component
export struct TCanvasComponent {
  dataView: DataView = new DataView();
  gestureMonitor: GestureMonitor = new GestureMonitor();
  @Prop @Watch('handleDataChanged') dataRevision: number = 0;
  @Prop @Watch('handleLatestPriceAnchorChanged') latestPriceAnchorRevision: number = 0;
  config: QuoteTablePerfConfig = new QuoteTablePerfConfig();
  /**
   * 细粒度单元格点击回调。
   *
   * row 为行索引，side 为点击侧别，col 为指标列索引；点击中间行权价列时 col 固定为 -1。
   * value 为点击单元格自身文本，旧的 GestureMonitor.onClick 仍继续返回行权价文本。
   */
  onCellClick: (row: number, side: DATA_POS, col: number, value: string) => void =
    (_row: number, _side: DATA_POS, _col: number, _value: string) => {};
  /**
   * 表头中间设置按钮点击回调。
   *
   * 点击行权价列上方的设置图标时触发，业务侧可在这里跳转到设置页，
   * 用于调整指标列、排序规则或其他自定义配置。组件本身不持有设置态，
   * 仅把点击事件透传给业务侧处理。
   */
  onSettingClick: () => void = () => {};
  /**
   * 行权价排序切换通知。
   *
   * 组件只发出目标排序方向；DataView 的实际顺序由业务侧调整，
   * 避免组件内部重排后，业务仍按原始行号更新单元格而写错行。
   */
  onStrikeSortToggle: (ascending: boolean) => void = (_ascending: boolean) => {};
  /**
   * 纵向滑动到顶/底后的剩余滚动量回调。
   *
   * 业务把 TCanvasComponent 放在外层 Scroll 中时，可在这里调用父 Scroller.scrollBy(0, offset)，
   * 实现“子组件先滚动，到边缘后父组件继续滚动”。offset 与组件内部 verticalOffset 方向一致。
   */
  onVerticalEdgeScroll: (offset: number) => void = (_offset: number) => {};
  /**
   * 行权价排序方向。业务侧维护真实排序态并传入组件，组件据此绘制表头箭头。
   */
  @Prop @Watch('handleStrikeAscendingChanged') strikeAscending: boolean = true;
  /**
   * 暗黑模式开关。外部改变该值即切换明/暗主题并重绘整张表格。
   *
   * false=亮色（沿用业务传入 config 的主题定制），true=暗黑（使用设计稿暗黑色值）。
   */
  @Prop @Watch('handleThemeChanged') darkMode: boolean = false;
  /**
   * 表头图标（设置 + 看涨/看跌展开双箭头）为组件库自带资源，组件内部解码，无需业务传入。
   * 明暗各一套，按 darkMode 在渲染时选用；暗黑套缺省时回退亮色套。
   * 图标 PNG 位于本 HAR 模块 resources/rawfile，构建时合并进宿主 HAP。
   */
  private settingIcon: ImageBitmap | undefined = undefined;
  private callExpandIcon: ImageBitmap | undefined = undefined;
  private putExpandIcon: ImageBitmap | undefined = undefined;
  private settingIconDark: ImageBitmap | undefined = undefined;
  private callExpandIconDark: ImageBitmap | undefined = undefined;
  private putExpandIconDark: ImageBitmap | undefined = undefined;
  @State private canvasBackgroundColor: string = '#ffffffff';
  // 业务传入 config 的亮色主题基线，暗黑切回亮色时恢复，避免丢失业务定制。
  private lightThemeBaseline: QuoteTableThemeTokens | undefined = undefined;
  @State private verticalOffset: number = 0;
  @State private horizontalOffset: number = 0;
  @State private viewportHeight: number = 640;
  @State private viewportWidth: number = 360;
  @State private centerX: number = -1;
  @State private expandState: EXPAND_STATE = EXPAND_STATE.Normal;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private redrawTimerId: number = -1;
  private lastRedrawAt: number = 0;
  private panStartX: number = 0;
  private panStartHorizontalOffset: number = 0;
  private panStartedOnLeft: boolean = false;
  private panAxis: CanvasPanAxis = CanvasPanAxis.None;
  private lastPanOffsetX: number = 0;
  private lastPanOffsetY: number = 0;
  private lastPanAt: number = 0;
  private panVelocityX: number = 0;
  private panVelocityY: number = 0;
  private lastVerticalGestureOffset: number = 0;
  private inertiaTimerId: number = -1;
  private inertiaVelocity: number = 0;
  private layoutAnimationTimerId: number = -1;
  private isPanning: boolean = false;
  private pendingDataRedraw: boolean = false;
  private appliedLatestPriceAnchorRevision: number = -1;
  private latestPriceAnchorViewportWidth: number = -1;
  private latestPriceAnchorViewportHeight: number = -1;
  private dataAdapter: TCanvasDataAdapter = new TCanvasDataAdapter(this.dataView);
  private renderer: TCanvasRenderer = new TCanvasRenderer();
  private tapGuard: TCanvasTapGuard = new TCanvasTapGuard();

  /**
   * 首次出现时解码自带图标并按当前 darkMode 应用主题（含背景色），确保暗黑初始态也正确。
   */
  aboutToAppear(): void {
    this.loadHeaderIcons();
    this.lightThemeBaseline = this.config.themeTokens.clone();
    this.syncStrikeAscendingState();
    this.applyTheme();
  }

  /**
   * 解码组件库自带的表头图标（明暗两套）。
   *
   * 图标 PNG 在本 HAR 的 resources/rawfile，构建合并进宿主 HAP，用宿主 resourceManager 读取。
   * 本工程 `new ImageBitmap(路径)` 无法加载像素，需经 getRawFileContentSync + createPixelMapSync。
   * 在首帧 build 之前同步完成，避免异步回填导致首帧缺图标。
   */
  private loadHeaderIcons(): void {
    let resManager = this.getUIContext().getHostContext()?.resourceManager;
    if (!resManager) {
      return;
    }
    this.settingIcon = this.decodeIcon(resManager, 'quote_icon_setting.png');
    this.callExpandIcon = this.decodeIcon(resManager, 'quote_icon_call_expand.png');
    this.putExpandIcon = this.decodeIcon(resManager, 'quote_icon_put_expand.png');
    this.settingIconDark = this.decodeIcon(resManager, 'quote_icon_setting_dark.png');
    this.callExpandIconDark = this.decodeIcon(resManager, 'quote_icon_call_expand_dark.png');
    this.putExpandIconDark = this.decodeIcon(resManager, 'quote_icon_put_expand_dark.png');
  }

  /**
   * 把 rawfile PNG 解码为 Canvas 可用的 ImageBitmap，失败时返回 undefined（绘制侧回退纯文案）。
   */
  private decodeIcon(resManager: resourceManager.ResourceManager, fileName: string): ImageBitmap | undefined {
    try {
      let content = resManager.getRawFileContentSync(fileName);
      let imageSource = image.createImageSource(content.buffer as ArrayBuffer);
      let pixelMap = imageSource.createPixelMapSync();
      return new ImageBitmap(pixelMap);
    } catch (error) {
      console.error(`TCanvasComponent decode icon ${fileName} failed: ${JSON.stringify(error)}`);
      return undefined;
    }
  }

  /**
   * darkMode 变化回调：切换主题 token 与背景色并请求重绘。
   */
  private handleThemeChanged(): void {
    this.applyTheme();
    this.requestRedraw();
  }

  /**
   * 根据 darkMode 选用暗黑/亮色基线主题，并同步 Canvas 背景色。
   */
  private applyTheme(): void {
    let theme = this.darkMode ? QuoteTableThemeTokens.dark() :
      (this.lightThemeBaseline ?? QuoteTableThemeTokens.light()).clone();
    this.config.themeTokens = theme;
    this.canvasBackgroundColor = theme.canvasBackgroundColor;
  }

  /**
   * 组件消失时释放重绘、惯性和布局动画定时器。
   */
  aboutToDisappear(): void {
    if (this.redrawTimerId >= 0) {
      clearTimeout(this.redrawTimerId);
      this.redrawTimerId = -1;
    }
    this.stopInertia();
    this.stopLayoutAnimation();
  }

  /**
   * DataView 变化后请求下一帧重绘。
   */
  private handleDataChanged(): void {
    this.syncStrikeAscendingState();
    this.dataAdapter.updateDataView(this.dataView);
    this.clampOffsets();
    if (this.isPanning && !this.config.refreshWhileScrolling) {
      this.pendingDataRedraw = true;
      return;
    }
    this.requestRedraw();
  }

  /**
   * 业务侧排序态变化后重绘表头箭头，并按已排序数据刷新最新价线视口位置。
   */
  private handleStrikeAscendingChanged(): void {
    this.syncStrikeAscendingState();
    this.dataAdapter.updateDataView(this.dataView);
    this.clampOffsets();
    this.centerLatestPriceLine(false);
    this.requestRedraw();
  }

  /**
   * 最新价锚点版本变化后，把最新价线定位到当前视口中间。
   */
  private handleLatestPriceAnchorChanged(): void {
    this.centerLatestPriceLineIfNeeded();
  }

  /**
   * 同步业务传入的排序方向到 DataView，不改变业务维护的当前行顺序。
   */
  private syncStrikeAscendingState(): void {
    this.dataView.SetStrikeAscendingState(this.strikeAscending);
  }

  /**
   * 计算表头总高度，包含展开收起标题条和列标题。
   */
  private headerHeight(): number {
    return (this.config.showSideTitleHeader ? CANVAS_ACTION_HEIGHT : 0) + HEAD_HEIGHT;
  }

  /**
   * 按帧率限制请求 Canvas 重绘，避免同一批数据触发多次绘制。
   */
  private requestRedraw(): void {
    if (this.redrawTimerId >= 0) {
      return;
    }
    let now = Date.now();
    let delay = Math.max(0, CANVAS_REDRAW_INTERVAL_MS - (now - this.lastRedrawAt));
    this.redrawTimerId = setTimeout(() => {
      this.redrawTimerId = -1;
      this.redraw();
    }, delay);
  }

  /**
   * 重绘当前视口内的表头、可见行、最新价线。
   */
  private redraw(): void {
    this.lastRedrawAt = Date.now();
    this.centerLatestPriceLineIfNeeded(false);
    this.renderer.render(this.context, this.currentRenderState());
  }

  /**
   * 按需把最新价线定位到视口中间，避免普通行情刷新导致表格反复跳动。
   */
  private centerLatestPriceLineIfNeeded(shouldRequestRedraw: boolean = true): void {
    let viewportChanged = this.viewportWidth !== this.latestPriceAnchorViewportWidth ||
      this.viewportHeight !== this.latestPriceAnchorViewportHeight;
    if (this.latestPriceAnchorRevision === this.appliedLatestPriceAnchorRevision && !viewportChanged) {
      return;
    }
    if (this.centerLatestPriceLine(shouldRequestRedraw)) {
      this.appliedLatestPriceAnchorRevision = this.latestPriceAnchorRevision;
      this.latestPriceAnchorViewportWidth = this.viewportWidth;
      this.latestPriceAnchorViewportHeight = this.viewportHeight;
    }
  }

  /**
   * 将最新价线滚动到可见区域中线位置。
   */
  private centerLatestPriceLine(shouldRequestRedraw: boolean = true): boolean {
    this.syncStrikeAscendingState();
    if (this.dataView.line.position < 0) {
      return false;
    }
    let bodyHeight = Math.max(this.viewportHeight - this.headerHeight(), 0);
    if (bodyHeight <= 0) {
      return false;
    }
    let targetOffset = (this.dataView.line.position + 1) * ITEM_HEIGHT - bodyHeight / 2;
    this.verticalOffset = Math.max(0, targetOffset);
    this.clampOffsets();
    if (shouldRequestRedraw) {
      this.requestRedraw();
    }
    return true;
  }

  /**
   * 生成当前 Canvas 渲染状态快照。
   */
  private currentRenderState(): TCanvasRenderState {
    this.dataAdapter.updateDataView(this.dataView);
    let state = new TCanvasRenderState(this.dataView, this.dataAdapter, this.config);
    state.viewportWidth = this.viewportWidth;
    state.viewportHeight = this.viewportHeight;
    state.verticalOffset = this.verticalOffset;
    state.horizontalOffset = this.horizontalOffset;
    state.centerX = this.centerStartX();
    state.expandState = this.expandState;
    state.settingIcon = this.darkMode ? (this.settingIconDark ?? this.settingIcon) : this.settingIcon;
    state.callExpandIcon = this.darkMode ? (this.callExpandIconDark ?? this.callExpandIcon) : this.callExpandIcon;
    state.putExpandIcon = this.darkMode ? (this.putExpandIconDark ?? this.putExpandIcon) : this.putExpandIcon;
    state.strikeAscending = this.strikeAscending;
    return state;
  }
  /**
   * 获取当前行数。
   */
  private rows(): number {
    return this.dataAdapter.rows();
  }

  /**
   * 获取当前每侧列数。
   */
  private cols(): number {
    return this.dataAdapter.cols();
  }

  /**
   * 计算当前可见起始行。
   */
  private visibleStartRow(): number {
    let row = Math.floor(Math.max(this.verticalOffset, 0) / ITEM_HEIGHT) - this.config.visibleRowBuffer;
    return Math.max(0, row);
  }

  /**
   * 计算当前可见结束行。
   */
  private visibleEndRow(): number {
    let visibleBodyHeight = Math.max(this.viewportHeight - this.headerHeight(), 0);
    let bottom = this.verticalOffset + visibleBodyHeight;
    let row = Math.ceil(Math.max(bottom, 0) / ITEM_HEIGHT) + this.config.visibleRowBuffer;
    return Math.min(this.rows() - 1, row);
  }

  /**
   * 判断左侧区域是否可见。
   */
  private isLeftVisible(): boolean {
    return this.expandState !== EXPAND_STATE.Right;
  }

  /**
   * 判断右侧区域是否可见。
   */
  private isRightVisible(): boolean {
    return this.expandState !== EXPAND_STATE.Left;
  }

  /**
   * 获取中间列左边界。
   */
  private centerStartX(): number {
    if (this.centerX >= 0) {
      return this.centerX;
    }
    return this.targetCenterStartX();
  }

  /**
   * 获取右侧数据起始边界。
   */
  private rightStartX(): number {
    return this.centerStartX() + CENTER_ITEM_WIDTH;
  }

  /**
   * 计算左侧指定列的绘制 x 坐标。
   */
  private leftCellX(col: number): number {
    return this.centerStartX() - (col + 1) * SIDE_ITEM_WIDTH + this.horizontalOffset;
  }

  /**
   * 计算右侧指定列的绘制 x 坐标。
   */
  private rightCellX(col: number): number {
    return this.rightStartX() + col * SIDE_ITEM_WIDTH - this.horizontalOffset;
  }

  /**
   * 判断普通横向区域是否在视口内。
   */
  private isVisibleX(x: number, width: number): boolean {
    return x + width >= 0 && x <= this.viewportWidth;
  }

  /**
   * 判断左侧列是否在左侧可见范围内。
   */
  private isVisibleLeftX(x: number, width: number): boolean {
    return x < this.centerStartX() && x + width >= 0;
  }

  /**
   * 判断右侧列是否在右侧可见范围内。
   */
  private isVisibleRightX(x: number, width: number): boolean {
    return x + width > this.rightStartX() && x <= this.viewportWidth;
  }

  /**
   * 约束横纵 offset 不超过可滚动边界。
   */
  private clampOffsets(): void {
    let maxVertical = this.maxVerticalOffset();
    let sideWidth = this.cols() * SIDE_ITEM_WIDTH;
    let sideViewportWidth = 0;
    if (this.isLeftVisible()) {
      sideViewportWidth = Math.max(sideViewportWidth, this.centerStartX());
    }
    if (this.isRightVisible()) {
      sideViewportWidth = Math.max(sideViewportWidth, this.viewportWidth - this.rightStartX());
    }
    let maxHorizontal = (this.isLeftVisible() || this.isRightVisible()) ? Math.max(sideWidth - sideViewportWidth, 0) :
      0;
    this.verticalOffset = Math.max(0, Math.min(this.verticalOffset, maxVertical));
    this.horizontalOffset = Math.max(0, Math.min(this.horizontalOffset, maxHorizontal));
  }

  /**
   * 计算纵向最大可滚动偏移。
   */
  private maxVerticalOffset(): number {
    return Math.max(this.rows() * ITEM_HEIGHT - Math.max(this.viewportHeight - this.headerHeight(), 0), 0);
  }

  /**
   * 计算展开状态对应的中间列目标位置。
   */
  private targetCenterStartX(): number {
    let middle = Math.max((this.viewportWidth - CENTER_ITEM_WIDTH) / 2, 0);
    if (this.expandState === EXPAND_STATE.Right) {
      return 0;
    }
    if (this.expandState === EXPAND_STATE.Left) {
      return Math.max(this.viewportWidth - CENTER_ITEM_WIDTH, 0);
    }
    return middle;
  }

  /**
   * 停止展开收起布局动画。
   */
  private stopLayoutAnimation(): void {
    if (this.layoutAnimationTimerId >= 0) {
      clearInterval(this.layoutAnimationTimerId);
      this.layoutAnimationTimerId = -1;
    }
  }

  /**
   * 开始中间行权价列移动动画。
   */
  private animateLayoutToTarget(): void {
    this.stopLayoutAnimation();
    let from = this.centerStartX();
    let to = this.targetCenterStartX();
    if (Math.abs(from - to) < 1) {
      this.centerX = to;
      this.clampOffsets();
      this.requestRedraw();
      return;
    }
    let startedAt = Date.now();
    this.layoutAnimationTimerId = setInterval(() => {
      let progress = Math.min((Date.now() - startedAt) / CANVAS_LAYOUT_ANIMATION_MS, 1);
      let eased = 1 - Math.pow(1 - progress, 3);
      this.centerX = from + (to - from) * eased;
      this.clampOffsets();
      this.requestRedraw();
      if (progress >= 1) {
        this.centerX = to;
        this.stopLayoutAnimation();
        this.clampOffsets();
        this.requestRedraw();
      }
    }, CANVAS_LAYOUT_ANIMATION_FRAME_MS);
  }

  /**
   * 处理表头展开收起点击。
   */
  private handleHeaderTap(x: number, y: number): boolean {
    if (!this.config.showSideTitleHeader) {
      return false;
    }
    if (y > CANVAS_ACTION_HEIGHT) {
      return false;
    }
    if (x < this.centerStartX()) {
      this.expandState = this.expandState === EXPAND_STATE.Left ? EXPAND_STATE.Normal : EXPAND_STATE.Left;
      this.animateLayoutToTarget();
      return true;
    }
    if (x > this.rightStartX()) {
      this.expandState = this.expandState === EXPAND_STATE.Right ? EXPAND_STATE.Normal : EXPAND_STATE.Right;
      this.animateLayoutToTarget();
      return true;
    }
    this.onSettingClick();
    return true;
  }

  /**
   * 命中左侧指标列，未命中真实列时返回 -1。
   */
  private hitLeftCol(x: number): number {
    for (let col = 0; col < this.cols(); col++) {
      let cellX = this.leftCellX(col);
      if (this.isVisibleLeftX(cellX, SIDE_ITEM_WIDTH) && x >= cellX && x < cellX + SIDE_ITEM_WIDTH) {
        return col;
      }
    }
    return -1;
  }

  /**
   * 命中右侧指标列，未命中真实列时返回 -1。
   */
  private hitRightCol(x: number): number {
    for (let col = 0; col < this.cols(); col++) {
      let cellX = this.rightCellX(col);
      if (this.isVisibleRightX(cellX, SIDE_ITEM_WIDTH) && x >= cellX && x < cellX + SIDE_ITEM_WIDTH) {
        return col;
      }
    }
    return -1;
  }

  /**
   * 获取命中单元格自身文本。
   */
  private hitCellValue(row: number, side: DATA_POS, col: number): string {
    if (side === DATA_POS.LEFT && col >= 0) {
      return this.dataAdapter.displayText(this.dataAdapter.leftItem(row, col).text);
    }
    if (side === DATA_POS.RIGHT && col >= 0) {
      return this.dataAdapter.displayText(this.dataAdapter.rightItem(row, col).text);
    }
    return this.dataAdapter.displayText(this.dataAdapter.centerItem(row).text);
  }

  /**
   * 同时触发旧点击回调和新增细粒度点击回调。
   */
  private notifyCellClick(row: number, side: DATA_POS, col: number): void {
    if (!this.dataAdapter.hasRow(row)) {
      return;
    }
    let strike = this.dataAdapter.displayText(this.dataAdapter.centerItem(row).text);
    let cellValue = this.hitCellValue(row, side, col);
    this.gestureMonitor.onClick(row, side, strike);
    if (side === DATA_POS.CENTER || col >= 0) {
      this.onCellClick(row, side, col, cellValue);
    }
  }

  /**
   * 触发旧版长按回调；Canvas 长按只做旧接口透传，不触发点击跳转。
   */
  private notifyCellLongPress(row: number, side: DATA_POS): void {
    if (!this.dataAdapter.hasRow(row)) {
      return;
    }
    let strike = this.dataAdapter.displayText(this.dataAdapter.centerItem(row).text);
    this.gestureMonitor.onLongPress(row, side, strike);
  }

  /**
   * 处理单元格点击命中，并兼容旧 GestureMonitor 点击透传。
   */
  private handleTap(x: number, y: number): void {
    if (this.handleHeaderTap(x, y)) {
      return;
    }
    if (y < this.headerHeight()) {
      let centerStart = this.centerStartX();
      let rightStart = this.rightStartX();
      if (x >= centerStart && x < rightStart) {
        this.toggleStrikeSort();
      }
      return;
    }
    let row = Math.floor((y - this.headerHeight() + this.verticalOffset) / ITEM_HEIGHT);
    if (row < 0 || row >= this.rows() || !this.dataAdapter.hasRow(row)) {
      return;
    }
    let centerStart = this.centerStartX();
    let rightStart = this.rightStartX();
    if (this.isLeftVisible() && x >= 0 && x < centerStart) {
      this.notifyCellClick(row, DATA_POS.LEFT, this.hitLeftCol(x));
      return;
    }
    if (x >= centerStart && x < rightStart) {
      this.notifyCellClick(row, DATA_POS.CENTER, -1);
      return;
    }
    if (this.isRightVisible() && x >= rightStart && x < this.viewportWidth) {
      this.notifyCellClick(row, DATA_POS.RIGHT, this.hitRightCol(x));
    }
  }

  /**
   * 处理单元格长按命中，给旧 GestureMonitor 长按接口透传行、侧别和行权价。
   */
  private handleLongPress(x: number, y: number): void {
    if (y < this.headerHeight()) {
      return;
    }
    let row = Math.floor((y - this.headerHeight() + this.verticalOffset) / ITEM_HEIGHT);
    if (row < 0 || row >= this.rows() || !this.dataAdapter.hasRow(row)) {
      return;
    }
    let centerStart = this.centerStartX();
    let rightStart = this.rightStartX();
    if (this.isLeftVisible() && x >= 0 && x < centerStart) {
      this.notifyCellLongPress(row, DATA_POS.LEFT);
      return;
    }
    if (x >= centerStart && x < rightStart) {
      this.notifyCellLongPress(row, DATA_POS.CENTER);
      return;
    }
    if (this.isRightVisible() && x >= rightStart && x < this.viewportWidth) {
      this.notifyCellLongPress(row, DATA_POS.RIGHT);
    }
  }

  /**
   * 切换行权价升/降序：组件只通知业务侧目标方向，排序和状态回传由业务统一维护。
   */
  private toggleStrikeSort(): void {
    this.onStrikeSortToggle(!this.strikeAscending);
  }

  /**
   * 停止惯性滑动。
   */
  private stopInertia(): void {
    if (this.inertiaTimerId >= 0) {
      clearInterval(this.inertiaTimerId);
      this.inertiaTimerId = -1;
    }
    this.inertiaVelocity = 0;
  }

  /**
   * 结束滚动状态，并合并滚动期间被暂停的数据刷新。
   */
  private finishScrolling(): void {
    this.isPanning = false;
    this.gestureMonitor.onScrollStop();
    if (this.pendingDataRedraw) {
      this.pendingDataRedraw = false;
      this.clampOffsets();
      this.requestRedraw();
    }
  }

  /**
   * 启动惯性滑动。
   */
  private startInertia(): void {
    let velocity = this.panAxis === CanvasPanAxis.Horizontal ? this.panVelocityX : this.panVelocityY;
    if (Math.abs(velocity) < CANVAS_INERTIA_MIN_VELOCITY) {
      this.finishScrolling();
      return;
    }
    this.stopInertia();
    this.inertiaVelocity = Math.max(-CANVAS_INERTIA_MAX_VELOCITY, Math.min(velocity, CANVAS_INERTIA_MAX_VELOCITY));
    this.inertiaTimerId = setInterval(() => {
