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
