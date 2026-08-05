import {
  CANVAS_TAP_MAX_DURATION_MS,
  CANVAS_TAP_MOVE_TOLERANCE
} from './TCanvasConstants';

export class TCanvasTapGuard {
  private touchActive: boolean = false;
  private hasPendingTouchClick: boolean = false;
  private pendingClickAllowed: boolean = true;
  private downAt: number = 0;
  private downX: number = 0;
  private downY: number = 0;
  private movedBeyondTap: boolean = false;

  /**
   * 记录触摸起点，为后续点击判断提供按压时长和移动距离基准。
   */
  handleDown(x: number, y: number, now: number = Date.now()): void {
    this.touchActive = true;
    this.hasPendingTouchClick = true;
    this.pendingClickAllowed = true;
    this.downAt = now;
    this.downX = x;
    this.downY = y;
    this.movedBeyondTap = false;
  }

  /**
   * 记录触摸移动，移动超过容差后本轮触摸不再视为点击。
   */
  handleMove(x: number, y: number): void {
    if (!this.touchActive) {
      return;
    }
    let dx = x - this.downX;
    let dy = y - this.downY;
    let moveToleranceSquared = CANVAS_TAP_MOVE_TOLERANCE * CANVAS_TAP_MOVE_TOLERANCE;
    if (dx * dx + dy * dy > moveToleranceSquared) {
      this.movedBeyondTap = true;
    }
  }

  /**
   * 触摸结束时结算本轮触摸是否仍可触发点击。
   */
  handleUp(now: number = Date.now()): void {
    if (!this.touchActive) {
      return;
    }
    this.pendingClickAllowed = !this.movedBeyondTap && now - this.downAt <= CANVAS_TAP_MAX_DURATION_MS;
    this.touchActive = false;
  }

  /**
   * 触摸取消时拒绝本轮后续 click，避免被系统取消的手势继续触发业务点击。
   */
  handleCancel(): void {
    if (!this.hasPendingTouchClick) {
      return;
    }
    this.pendingClickAllowed = false;
    this.touchActive = false;
  }

  /**
   * 判断框架补发的 click 是否应进入业务点击，并消费本轮触摸状态。
   */
  shouldAcceptClick(now: number = Date.now()): boolean {
    if (!this.hasPendingTouchClick) {
      return true;
    }
    let durationAllowed = now - this.downAt <= CANVAS_TAP_MAX_DURATION_MS;
    let accepted = this.pendingClickAllowed && !this.movedBeyondTap && durationAllowed;
    this.hasPendingTouchClick = false;
    this.touchActive = false;
    return accepted;
  }
}
