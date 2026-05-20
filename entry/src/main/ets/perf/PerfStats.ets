import { PerfScenario } from './PerfScenario';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemDateTime } from '@kit.BasicServicesKit';

const PERF_DOMAIN = 0xC0FF;
const PERF_TAG = 'PerfStats';
const SNAPSHOT_CACHE_MS = 200;
const FRAME_BUFFER_LIMIT = 600;

// 返回纳秒级精度的毫秒（带小数）。Date.now() 在部分设备上量子化到 1-15ms，无法做 100Hz 的间隔统计。
export function nowMs(): number {
  let ns = systemDateTime.getTime(true);
  return ns / 1_000_000;
}

export class PerfHealthContext {
  scrolling: boolean = false;
  continueWhileScrolling: boolean = true;
  feedRunning: boolean = false;
}

export class PerfCounters {
  quoteBatches: number = 0;
  quoteUpdates: number = 0;
  // 调度层"成功处理"的更新数（A 版本下等于 updateByItem 成功次数；B/C/D 应是 store 接收到的合并前 update 数）
  uiAppliedUpdates: number = 0;
  // UI 实际触发重绘的 cell 数；A 版本下等于 uiAppliedUpdates，B/C/D 应小于 uiAppliedUpdates（合并后）
  uiPaintedCells: number = 0;
  flushCount: number = 0;
  scrollCallbacks: number = 0;
  scrollerSyncCount: number = 0;
  feedTicks: number = 0;
  invalidFeedTicks: number = 0;
  frameCount: number = 0;
  flushedCells: number = 0;
  maxFlushCells: number = 0;
  lastFlushCells: number = 0;
  totalFlushCostMs: number = 0;
  maxFlushCostMs: number = 0;
  lastFlushCostMs: number = 0;
  canvasDrawCount: number = 0;
  totalCanvasDrawCostMs: number = 0;
  maxCanvasDrawCostMs: number = 0;
  lastCanvasDrawCostMs: number = 0;
}

export class PerfSnapshot {
  elapsedMs: number = 0;
  quoteUpdatesPerSecond: number = 0;
  uiAppliedPerSecond: number = 0;
  uiPaintedPerSecond: number = 0;
  flushPerSecond: number = 0;
  flushedCellsPerSecond: number = 0;
  maxFlushCells: number = 0;
  lastFlushCells: number = 0;
  avgFlushCostMs: number = 0;
  maxFlushCostMs: number = 0;
  lastFlushCostMs: number = 0;
  canvasDrawPerSecond: number = 0;
  avgCanvasDrawCostMs: number = 0;
  maxCanvasDrawCostMs: number = 0;
  lastCanvasDrawCostMs: number = 0;
  measuredFrequencyHz: number = 0;
  targetFrequencyHz: number = 0;
  frequencyDriftPercent: number = 0;
  quoteUpdates: number = 0;
  uiAppliedUpdates: number = 0;
  uiPaintedCells: number = 0;
  scrollCallbacks: number = 0;
  scrollerSyncCount: number = 0;
  frameCount: number = 0;
  frameP50Ms: number = 0;
  frameP95Ms: number = 0;
  frameP99Ms: number = 0;
  maxFrameMs: number = 0;
  health: string = '未开始';
  healthReason: string = '';
}

export class PerfStats {
  private scenario: PerfScenario = new PerfScenario();
  private counters: PerfCounters = new PerfCounters();
  private startedAt: number = 0;
  private lastFrameAt: number = 0;
  private frameDurations: number[] = [];
  private lastHealth: string = '未开始';
  private lastWarnAt: number = 0;
  private cachedSnapshot: PerfSnapshot | null = null;
  private cachedAt: number = 0;
  private context: PerfHealthContext = new PerfHealthContext();

  start(scenario: PerfScenario) {
    this.scenario = scenario.clone();
    this.counters = new PerfCounters();
    this.startedAt = nowMs();
    this.lastFrameAt = 0;
    this.frameDurations = [];
    this.lastHealth = '采样中';
    this.lastWarnAt = 0;
    this.cachedSnapshot = null;
    this.cachedAt = 0;
  }

  reset() {
    this.counters = new PerfCounters();
    this.startedAt = nowMs();
    this.lastFrameAt = 0;
    this.frameDurations = [];
    this.lastHealth = '采样中';
    this.lastWarnAt = 0;
    this.cachedSnapshot = null;
    this.cachedAt = 0;
  }

  updateContext(context: PerfHealthContext) {
    this.context.scrolling = context.scrolling;
    this.context.continueWhileScrolling = context.continueWhileScrolling;
    this.context.feedRunning = context.feedRunning;
  }

  // timestampMs 为可选的 VSync 时间戳（毫秒，可带小数）。
  // 若由 displaySync 驱动，传入 intervalInfo.timestamp / 1e6；
  // 若无外部时钟，传 undefined，内部用 nowMs。
  recordFrame(timestampMs?: number) {
    let now = (timestampMs !== undefined) ? timestampMs : nowMs();
    this.counters.frameCount++;
    if (this.lastFrameAt > 0) {
      let duration = now - this.lastFrameAt;
      if (duration > 0 && duration < 1000) {
        this.frameDurations.push(duration);
        if (this.frameDurations.length > FRAME_BUFFER_LIMIT) {
          this.frameDurations.shift();
        }
      }
    }
    this.lastFrameAt = now;
  }

  recordFeedTick(actualIntervalMs: number) {
    this.counters.feedTicks++;
    let targetIntervalMs = 1000 / Math.max(this.scenario.frequencyHz, 1);
    if (actualIntervalMs > targetIntervalMs * 2 || actualIntervalMs < targetIntervalMs * 0.5) {
      this.counters.invalidFeedTicks++;
    }
  }

  recordQuoteBatch(updateCount: number) {
    this.counters.quoteBatches++;
    this.counters.quoteUpdates += updateCount;
  }

  recordUiApplied(count: number) {
    this.counters.uiAppliedUpdates += count;
  }

  recordUiPainted(count: number) {
    this.counters.uiPaintedCells += count;
  }

  recordFlush(cellCount: number = 0, costMs: number = 0) {
    this.counters.flushCount++;
    this.counters.flushedCells += cellCount;
    this.counters.lastFlushCells = cellCount;
    this.counters.maxFlushCells = Math.max(this.counters.maxFlushCells, cellCount);
    this.counters.totalFlushCostMs += costMs;
    this.counters.lastFlushCostMs = costMs;
    this.counters.maxFlushCostMs = Math.max(this.counters.maxFlushCostMs, costMs);
  }

  recordCanvasDraw(costMs: number) {
    this.counters.canvasDrawCount++;
    this.counters.totalCanvasDrawCostMs += costMs;
    this.counters.lastCanvasDrawCostMs = costMs;
    this.counters.maxCanvasDrawCostMs = Math.max(this.counters.maxCanvasDrawCostMs, costMs);
  }

  recordScrollCallback() {
    this.counters.scrollCallbacks++;
  }

  recordScrollerSync(count: number) {
    this.counters.scrollerSyncCount += count;
  }

  snapshot(): PerfSnapshot {
    let now = nowMs();
    if (this.cachedSnapshot !== null && now - this.cachedAt < SNAPSHOT_CACHE_MS) {
      return this.cachedSnapshot;
    }
    let elapsedMs = Math.max(now - this.startedAt, 1);
    let elapsedSeconds = elapsedMs / 1000;
    let snapshot = new PerfSnapshot();
    snapshot.elapsedMs = Math.round(elapsedMs);
    snapshot.quoteUpdatesPerSecond = Math.round(this.counters.quoteUpdates / elapsedSeconds);
    snapshot.uiAppliedPerSecond = Math.round(this.counters.uiAppliedUpdates / elapsedSeconds);
    snapshot.uiPaintedPerSecond = Math.round(this.counters.uiPaintedCells / elapsedSeconds);
    snapshot.flushPerSecond = Math.round(this.counters.flushCount / elapsedSeconds);
    snapshot.flushedCellsPerSecond = Math.round(this.counters.flushedCells / elapsedSeconds);
    snapshot.maxFlushCells = this.counters.maxFlushCells;
    snapshot.lastFlushCells = this.counters.lastFlushCells;
    snapshot.avgFlushCostMs = this.counters.flushCount > 0 ? this.counters.totalFlushCostMs / this.counters.flushCount : 0;
    snapshot.maxFlushCostMs = this.counters.maxFlushCostMs;
    snapshot.lastFlushCostMs = this.counters.lastFlushCostMs;
    snapshot.canvasDrawPerSecond = Math.round(this.counters.canvasDrawCount / elapsedSeconds);
    snapshot.avgCanvasDrawCostMs =
      this.counters.canvasDrawCount > 0 ? this.counters.totalCanvasDrawCostMs / this.counters.canvasDrawCount : 0;
    snapshot.maxCanvasDrawCostMs = this.counters.maxCanvasDrawCostMs;
    snapshot.lastCanvasDrawCostMs = this.counters.lastCanvasDrawCostMs;
    snapshot.measuredFrequencyHz = Math.round(this.counters.feedTicks / elapsedSeconds);
    snapshot.targetFrequencyHz = this.scenario.frequencyHz;
    snapshot.frequencyDriftPercent = this.calcFrequencyDrift(snapshot.measuredFrequencyHz, this.scenario.frequencyHz);
    snapshot.quoteUpdates = this.counters.quoteUpdates;
    snapshot.uiAppliedUpdates = this.counters.uiAppliedUpdates;
    snapshot.uiPaintedCells = this.counters.uiPaintedCells;
    snapshot.scrollCallbacks = this.counters.scrollCallbacks;
    snapshot.scrollerSyncCount = this.counters.scrollerSyncCount;
    snapshot.frameCount = this.counters.frameCount;
    let percentiles = this.calcPercentiles();
    snapshot.frameP50Ms = percentiles[0];
    snapshot.frameP95Ms = percentiles[1];
    snapshot.frameP99Ms = percentiles[2];
    snapshot.maxFrameMs = percentiles[3];
    this.markHealth(snapshot);
    this.logThresholdAlert(snapshot);
    this.cachedSnapshot = snapshot;
    this.cachedAt = now;
    return snapshot;
  }

  summaryText(): string {
    let s = this.snapshot();
    let reason = s.healthReason.length > 0 ? `(${s.healthReason})` : '';
    return `状态 ${s.health}${reason} | 行情 ${s.quoteUpdatesPerSecond}/秒 | UI写入 ${s.uiAppliedPerSecond}/秒 | UI绘制 ${s.uiPaintedPerSecond}/秒 | flush cost max ${s.maxFlushCostMs.toFixed(1)}ms | canvas ${s.canvasDrawPerSecond}/秒 max ${s.maxCanvasDrawCostMs.toFixed(1)}ms | P95 ${s.frameP95Ms.toFixed(1)}ms / P99 ${s.frameP99Ms.toFixed(1)}ms / max ${s.maxFrameMs.toFixed(1)}ms`;
  }

  exportJsonLine(): string {
    let s = this.snapshot();
    return JSON.stringify({
      scenarioId: this.scenario.scenarioId,
      variantId: this.scenario.variantId,
      timestamp: Date.now(),
      elapsedMs: s.elapsedMs,
      quoteUpdatesPerSecond: s.quoteUpdatesPerSecond,
      uiAppliedPerSecond: s.uiAppliedPerSecond,
      uiPaintedPerSecond: s.uiPaintedPerSecond,
      flushPerSecond: s.flushPerSecond,
      flushedCellsPerSecond: s.flushedCellsPerSecond,
      maxFlushCells: s.maxFlushCells,
      lastFlushCells: s.lastFlushCells,
      avgFlushCostMs: s.avgFlushCostMs,
      maxFlushCostMs: s.maxFlushCostMs,
      lastFlushCostMs: s.lastFlushCostMs,
      canvasDrawPerSecond: s.canvasDrawPerSecond,
      avgCanvasDrawCostMs: s.avgCanvasDrawCostMs,
      maxCanvasDrawCostMs: s.maxCanvasDrawCostMs,
      lastCanvasDrawCostMs: s.lastCanvasDrawCostMs,
      measuredFrequencyHz: s.measuredFrequencyHz,
      targetFrequencyHz: s.targetFrequencyHz,
      frequencyDriftPercent: s.frequencyDriftPercent,
      quoteUpdates: s.quoteUpdates,
      uiAppliedUpdates: s.uiAppliedUpdates,
      uiPaintedCells: s.uiPaintedCells,
      scrollCallbacks: s.scrollCallbacks,
      scrollerSyncCount: s.scrollerSyncCount,
      frameCount: s.frameCount,
      frameP50Ms: s.frameP50Ms,
      frameP95Ms: s.frameP95Ms,
      frameP99Ms: s.frameP99Ms,
      maxFrameMs: s.maxFrameMs,
      health: s.health,
      healthReason: s.healthReason
    });
  }

  // 通过 hilog.info 输出 JSONL，便于 hdc shell hilog -T PerfStats 抓取
  exportToHilog() {
    let line = this.exportJsonLine();
    hilog.info(PERF_DOMAIN, PERF_TAG, '%{public}s', line);
  }

  private markHealth(snapshot: PerfSnapshot) {
    if (snapshot.elapsedMs < 1000) {
      snapshot.health = '采样中';
      snapshot.healthReason = '数据不足1秒';
      return;
    }

    // 用户主动关闭"滑动中刷新"且当前正在滑动，UI 写入为 0 是预期行为，不算异常
    let intentionalNoUi = this.context.scrolling && !this.context.continueWhileScrolling;

    if (!intentionalNoUi && this.context.feedRunning && snapshot.quoteUpdatesPerSecond > 0 &&
      snapshot.uiAppliedPerSecond <= 0) {
      snapshot.health = '异常';
      snapshot.healthReason = '行情有输入但UI无写入';
      return;
    }
    if (snapshot.frameP95Ms >= 50) {
      snapshot.health = '异常';
      snapshot.healthReason = `P95帧间隔${snapshot.frameP95Ms.toFixed(1)}ms>=50ms`;
      return;
    }
    if (this.context.feedRunning && snapshot.frequencyDriftPercent >= 50) {
      snapshot.health = '异常';
      snapshot.healthReason = `实测频率偏差${snapshot.frequencyDriftPercent}%>=50%`;
      return;
    }
    if (snapshot.frameP95Ms >= 33) {
      snapshot.health = '警告';
      snapshot.healthReason = `P95帧间隔${snapshot.frameP95Ms.toFixed(1)}ms>=33ms`;
      return;
    }
    if (this.context.feedRunning && snapshot.frequencyDriftPercent >= 20) {
      snapshot.health = '警告';
      snapshot.healthReason = `实测频率偏差${snapshot.frequencyDriftPercent}%>=20%`;
      return;
    }
    snapshot.health = '正常';
    snapshot.healthReason = '';
  }

  private logThresholdAlert(snapshot: PerfSnapshot) {
    if (snapshot.health !== '警告' && snapshot.health !== '异常') {
      this.lastHealth = snapshot.health;
      return;
    }

    let now = Date.now();
    let healthChanged = snapshot.health !== this.lastHealth;
    let shouldThrottleLog = now - this.lastWarnAt >= 5000;
    if (!healthChanged && !shouldThrottleLog) {
      return;
    }

    this.lastHealth = snapshot.health;
    this.lastWarnAt = now;
    let message = this.buildAlertMessage(snapshot);
    if (snapshot.health === '异常') {
      hilog.error(PERF_DOMAIN, PERF_TAG, '%{public}s', message);
    } else {
      hilog.warn(PERF_DOMAIN, PERF_TAG, '%{public}s', message);
    }
  }

  private buildAlertMessage(snapshot: PerfSnapshot): string {
    return JSON.stringify({
      level: snapshot.health,
      reason: snapshot.healthReason,
      scenarioId: this.scenario.scenarioId,
      variantId: this.scenario.variantId,
      elapsedMs: snapshot.elapsedMs,
      quoteUpdatesPerSecond: snapshot.quoteUpdatesPerSecond,
      uiAppliedPerSecond: snapshot.uiAppliedPerSecond,
      uiPaintedPerSecond: snapshot.uiPaintedPerSecond,
      flushPerSecond: snapshot.flushPerSecond,
      flushedCellsPerSecond: snapshot.flushedCellsPerSecond,
      maxFlushCells: snapshot.maxFlushCells,
      lastFlushCells: snapshot.lastFlushCells,
      avgFlushCostMs: snapshot.avgFlushCostMs,
      maxFlushCostMs: snapshot.maxFlushCostMs,
      lastFlushCostMs: snapshot.lastFlushCostMs,
      canvasDrawPerSecond: snapshot.canvasDrawPerSecond,
      avgCanvasDrawCostMs: snapshot.avgCanvasDrawCostMs,
      maxCanvasDrawCostMs: snapshot.maxCanvasDrawCostMs,
      lastCanvasDrawCostMs: snapshot.lastCanvasDrawCostMs,
      measuredFrequencyHz: snapshot.measuredFrequencyHz,
      targetFrequencyHz: snapshot.targetFrequencyHz,
      frequencyDriftPercent: snapshot.frequencyDriftPercent,
      frameP95Ms: snapshot.frameP95Ms,
      frameP99Ms: snapshot.frameP99Ms,
      maxFrameMs: snapshot.maxFrameMs,
      scrollCallbacks: snapshot.scrollCallbacks,
      scrollerSyncCount: snapshot.scrollerSyncCount
    });
  }

  private calcFrequencyDrift(measured: number, target: number): number {
    if (target <= 0) {
      return 0;
    }
    return Math.round(Math.abs(measured - target) * 100 / target);
  }

  // 同时计算 P50/P95/P99 和 max，避免多次排序
  private calcPercentiles(): number[] {
    if (this.frameDurations.length <= 0) {
      return [0, 0, 0, 0];
    }
    let sorted = this.frameDurations.slice().sort((a: number, b: number) => a - b);
    let len = sorted.length;
    let p50 = sorted[Math.min(len - 1, Math.floor(len * 50 / 100))];
    let p95 = sorted[Math.min(len - 1, Math.floor(len * 95 / 100))];
    let p99 = sorted[Math.min(len - 1, Math.floor(len * 99 / 100))];
    let max = sorted[len - 1];
    return [p50, p95, p99, max];
  }
}
