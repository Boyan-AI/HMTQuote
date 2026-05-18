/**
 * 视口级 Canvas 行情表内部常量。
 *
 * 常量集中放置，避免 TCanvasComponent 单文件过大，也方便后续按业务主题调整。
 */
export const CANVAS_ACTION_HEIGHT: number = 36;
export const CANVAS_ACTION_FONT_SIZE: number = 14;
export const CANVAS_HEADER_FONT_SIZE: number = 13;
export const CANVAS_CELL_FONT_SIZE: number = 15;
// 单元格副文本字号（vp）。
export const CANVAS_CELL_SUB_FONT_SIZE: number = 11;
// 有副文本时，主值上移、副文本下移的半行偏移量（vp）。
export const CANVAS_CELL_SUB_LINE_GAP: number = 9;
export const CANVAS_CENTER_FONT_SIZE: number = 15;
export const CANVAS_PRICE_LABEL_FONT_SIZE: number = 12;
export const CANVAS_PRICE_LABEL_HEIGHT: number = 20;
// 已废弃：保留以兼容外部引用；最新价标签现在按文本宽度自适应（CANVAS_PRICE_LABEL_PADDING_X 控制内边距）。
export const CANVAS_PRICE_LABEL_WIDTH: number = 66;
// 最新价标签左右内边距（vp）。
export const CANVAS_PRICE_LABEL_PADDING_X: number = 8;
// 最新价标签圆角半径（vp），大于 HEIGHT/2 时按 HEIGHT/2 收敛（胶囊形）。
export const CANVAS_PRICE_LABEL_RADIUS: number = 4;
// 最新价标签自适应宽度的下限（vp），防止极短文本（如个位数）出现过窄的小块。
export const CANVAS_PRICE_LABEL_MIN_WIDTH: number = 40;
export const CANVAS_ACTION_ICON_SETTING_SIZE: number = 18;
export const CANVAS_ACTION_ICON_CHEVRON_WIDTH: number = 12;
export const CANVAS_ACTION_ICON_CHEVRON_HEIGHT: number = 10;
export const CANVAS_ACTION_ICON_GAP: number = 4;
// 展开态下“收起”双箭头中心距行权价列边界的内缩距离（vp）。
export const CANVAS_ACTION_COLLAPSE_CHEVRON_INSET: number = 30;
export const CANVAS_SORT_ARROW_WIDTH: number = 7;
export const CANVAS_SORT_ARROW_HEIGHT: number = 5;
export const CANVAS_SORT_ARROW_GAP: number = 2;
export const CANVAS_REDRAW_INTERVAL_MS: number = 16;
export const CANVAS_PAN_AXIS_LOCK_THRESHOLD: number = 6;
// Canvas 点击需要自行区分短按、长按和拖动，超过该时长不再触发业务点击。
export const CANVAS_TAP_MAX_DURATION_MS: number = 500;
// 手指移动超过该距离视为滚动/拖动，不再触发业务点击。
export const CANVAS_TAP_MOVE_TOLERANCE: number = 8;
export const CANVAS_INERTIA_FRAME_MS: number = 16;
export const CANVAS_INERTIA_DECAY: number = 0.95;
export const CANVAS_INERTIA_MIN_VELOCITY: number = 0.03;
export const CANVAS_INERTIA_MAX_VELOCITY: number = 3.2;
export const CANVAS_LAYOUT_ANIMATION_MS: number = 180;
export const CANVAS_LAYOUT_ANIMATION_FRAME_MS: number = 16;

/**
 * Canvas 手势方向锁。
 */
export enum CanvasPanAxis {
  None,
  Horizontal,
  Vertical
}
