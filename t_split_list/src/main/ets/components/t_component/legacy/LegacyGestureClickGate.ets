export class LegacyGestureClickGate {
  private suppressTapUntil: number = 0;
  private readonly suppressTapWindowMs: number = 350;

  /**
   * 记录长按已经被业务消费，用短时间窗口屏蔽同一轮触摸释放后可能补发的点击。
   */
  markLongPressHandled(now: number = Date.now()): void {
    this.suppressTapUntil = now + this.suppressTapWindowMs;
  }

  /**
   * 判断当前点击是否可触发业务回调，并消费长按后的点击屏蔽窗口。
   */
  shouldAcceptTap(now: number = Date.now()): boolean {
    if (now <= this.suppressTapUntil) {
      this.suppressTapUntil = 0;
      return false;
    }
    return true;
  }
}
