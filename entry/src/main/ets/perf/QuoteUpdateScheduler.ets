import { QuoteCellUpdate } from './PerfScenario';
import { nowMs, PerfStats } from './PerfStats';
import { QuoteCellSnapshot, QuoteTableStore } from './QuoteTableStore';

export class QuoteUpdateScheduler {
  private readonly store: QuoteTableStore = new QuoteTableStore();
  private stats?: PerfStats;
  private flushIntervalMs: number = 33;
  private timerId: number = -1;
  private flushHandler: (snapshots: QuoteCellSnapshot[]) => number = (_snapshots: QuoteCellSnapshot[]) => 0;
  private shouldFlush: () => boolean = () => true;
  private visibleOnly: boolean = false;
  private getVisibleStartRow: () => number = () => 0;
  private getVisibleEndRow: () => number = () => 2147483647;

  configure(rows: number, colsPerSide: number, stats: PerfStats,
    flushHandler: (snapshots: QuoteCellSnapshot[]) => number, flushIntervalMs: number = 33,
    shouldFlush: () => boolean = () => true, visibleOnly: boolean = false,
    getVisibleStartRow: () => number = () => 0, getVisibleEndRow: () => number = () => 2147483647) {
    this.stop();
    this.store.reset(rows, colsPerSide);
    this.stats = stats;
    this.flushHandler = flushHandler;
    this.flushIntervalMs = flushIntervalMs;
    this.shouldFlush = shouldFlush;
    this.visibleOnly = visibleOnly;
    this.getVisibleStartRow = getVisibleStartRow;
    this.getVisibleEndRow = getVisibleEndRow;
  }

  start() {
    this.stop();
    this.timerId = setInterval(() => {
      this.flush();
    }, this.flushIntervalMs);
  }

  stop() {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  enqueue(updates: QuoteCellUpdate[]) {
    let applied = this.store.applyBatch(updates);
    this.stats?.recordUiApplied(applied);
  }

  flush() {
    if (!this.shouldFlush()) {
      return;
    }
    let snapshots = this.visibleOnly ?
      this.store.drainPendingInRowRange(this.getVisibleStartRow(), this.getVisibleEndRow()) :
      this.store.drainPending();
    if (snapshots.length <= 0) {
      return;
    }
    let startedAt = nowMs();
    let painted = this.flushHandler(snapshots);
    let costMs = nowMs() - startedAt;
    this.stats?.recordFlush(snapshots.length, costMs);
    this.stats?.recordUiPainted(painted);
  }
}
