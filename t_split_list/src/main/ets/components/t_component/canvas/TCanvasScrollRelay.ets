export class TCanvasScrollRelayResult {
  nextOffset: number = 0;
  remainOffset: number = 0;

  constructor(nextOffset: number, remainOffset: number) {
    this.nextOffset = nextOffset;
    this.remainOffset = remainOffset;
  }
}

export class TCanvasScrollRelay {
  static applyOffset(currentOffset: number, deltaOffset: number, maxOffset: number): TCanvasScrollRelayResult {
    let safeMax = Math.max(maxOffset, 0);
    let targetOffset = currentOffset + deltaOffset;
    let nextOffset = Math.max(0, Math.min(targetOffset, safeMax));
    return new TCanvasScrollRelayResult(nextOffset, targetOffset - nextOffset);
  }
}
