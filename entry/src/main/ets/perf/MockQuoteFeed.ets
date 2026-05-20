import { DATA_POS } from 'common_sideslipview';
import { PerfDistribution, PerfScenario, QuoteCellUpdate, VisibleRange } from './PerfScenario';
import { nowMs, PerfStats } from './PerfStats';
import { displaySync } from '@kit.ArkGraphics2D';

const MAX_TICKS_PER_FRAME: number = 4;

// 用 displaySync 在每个 VSync 检查是否到达 tick 时间，避免 setInterval 在高频下的累积漂移。
// 50Hz / 100Hz 下，setInterval 实测可能漂到 30-70Hz；displaySync + 时间补偿能稳定在目标频率附近。
export class MockQuoteFeed {
  private scenario: PerfScenario = new PerfScenario();
  private stats?: PerfStats;
  private sync?: displaySync.DisplaySync;
  private lastTickAt: number = 0;
  private nextDueAt: number = 0;
  private targetIntervalMs: number = 100;
  private sequence: number = 0;
  private burstTick: number = 0;
  private visibleRange: VisibleRange = new VisibleRange();
  private onBatch: (updates: QuoteCellUpdate[]) => void = (_updates: QuoteCellUpdate[]) => {
  };

  configure(scenario: PerfScenario, stats: PerfStats, onBatch: (updates: QuoteCellUpdate[]) => void) {
    this.stop();
    this.scenario = scenario.clone();
    this.stats = stats;
    this.onBatch = onBatch;
    this.targetIntervalMs = 1000 / Math.max(this.scenario.frequencyHz, 1);
    let centerRow = Math.floor(this.scenario.rows / 2);
    this.visibleRange.startRow = Math.max(0, centerRow - 10);
    this.visibleRange.endRow = Math.min(this.scenario.rows - 1, centerRow + 10);
  }

  setVisibleRange(startRow: number, endRow: number) {
    let maxRow = Math.max(this.scenario.rows - 1, 0);
    this.visibleRange.startRow = Math.max(0, Math.min(startRow, maxRow));
    this.visibleRange.endRow = Math.max(this.visibleRange.startRow, Math.min(endRow, maxRow));
  }

  start() {
    this.stop();
    let now = nowMs();
    this.lastTickAt = now;
    this.nextDueAt = now + this.targetIntervalMs;
    this.sync = displaySync.create();
    this.sync.on('frame', (_intervalInfo: displaySync.IntervalInfo) => {
      this.onVsync();
    });
    this.sync.start();
  }

  stop() {
    if (this.sync) {
      this.sync.stop();
      this.sync = undefined;
    }
  }

  private onVsync() {
    let now = nowMs();
    if (now < this.nextDueAt) {
      return;
    }

    // 如果某帧延迟很多，跳到当前时间，不补发历史 tick，避免一次性灌入大量过期行情。
    if (now - this.nextDueAt > this.targetIntervalMs * 2) {
      this.nextDueAt = now + this.targetIntervalMs;
      this.lastTickAt = now;
      return;
    }

    // 100Hz 高于常见 60Hz VSync，单帧可能需要补 2 个 tick 才能接近目标频率。
    let emitted = 0;
    while (now >= this.nextDueAt && emitted < MAX_TICKS_PER_FRAME) {
      let tickAt = this.nextDueAt;
      this.nextDueAt += this.targetIntervalMs;
      emitted++;

      let actualIntervalMs = tickAt - this.lastTickAt;
      this.lastTickAt = tickAt;
      this.stats?.recordFeedTick(actualIntervalMs);

      let updates = this.buildBatch();
      this.stats?.recordQuoteBatch(updates.length);
      if (updates.length > 0) {
        this.onBatch(updates);
      }
    }
  }

  private buildBatch(): QuoteCellUpdate[] {
    let updateCount = this.resolveUpdateCount();
    if (this.scenario.distribution === PerfDistribution.Burst) {
      let cycleLen = Math.max(this.scenario.burstActiveTicks + this.scenario.burstQuietTicks, 1);
      let phase = this.burstTick % cycleLen;
      this.burstTick++;
      if (phase < this.scenario.burstActiveTicks) {
        updateCount = this.scenario.updatesPerBatch * Math.max(this.scenario.burstPeakMultiplier, 1);
      } else {
        updateCount = 0;
      }
    }

    let updates: QuoteCellUpdate[] = [];
    for (let i = 0; i < updateCount; i++) {
      updates.push(this.createUpdate(i));
    }
    return updates;
  }

  private resolveUpdateCount(): number {
    let totalCells = Math.max(this.scenario.rows, 1) * Math.max(this.scenario.colsPerSide, 1) * 2;
    switch (this.scenario.distribution) {
      case PerfDistribution.FullTable:
        return totalCells;
      case PerfDistribution.HalfTable:
        return Math.floor(totalCells / 2);
      case PerfDistribution.QuarterTable:
        return Math.floor(totalCells / 4);
      default:
        return this.scenario.updatesPerBatch;
    }
  }

  private createUpdate(index: number): QuoteCellUpdate {
    let update = new QuoteCellUpdate();
    update.side = this.pickSide(index);
    update.row = this.pickRow(index, update.side);
    update.col = this.pickCol(index, update.side);
    update.value = this.buildValue(update.side, update.row, update.col);
    update.color = this.sequence % 2 === 0 ? '#ffb00020' : '#ff0052cc';
    this.sequence++;
    return update;
  }

  private pickSide(index: number): DATA_POS {
    switch (this.scenario.distribution) {
      case PerfDistribution.FullTable:
      case PerfDistribution.HalfTable:
      case PerfDistribution.QuarterTable:
        return index % 2 === 0 ? DATA_POS.LEFT : DATA_POS.RIGHT;
      default:
        return (index + this.sequence) % 2 === 0 ? DATA_POS.LEFT : DATA_POS.RIGHT;
    }
  }

  private buildValue(side: DATA_POS, row: number, col: number): string {
    let displayCol = side === DATA_POS.LEFT ? this.scenario.colsPerSide - col : col + 1;
    if (this.scenario.distribution === PerfDistribution.VisibleHotspot) {
      return `R${row}C${displayCol}-${this.sequence % 1000}`;
    }
    return `${displayCol}-${this.sequence}`;
  }

  private pickRow(index: number, side: DATA_POS): number {
    let rows = Math.max(this.scenario.rows, 1);
    let hotspot = Math.max(Math.min(this.scenario.hotspotSize, rows), 1);
    switch (this.scenario.distribution) {
      case PerfDistribution.FullTable:
      case PerfDistribution.HalfTable:
      case PerfDistribution.QuarterTable:
        return Math.floor(this.pickLinearCellIndex(index, side) / Math.max(this.scenario.colsPerSide, 1)) % rows;
      case PerfDistribution.VisibleHotspot:
        return this.pickVisibleRow(index);
      case PerfDistribution.FixedHotRows:
        return index % hotspot;
      case PerfDistribution.SameCellOverwrite:
        return Math.min(1, rows - 1);
      case PerfDistribution.MovingHotspot:
        return (Math.floor(this.sequence / Math.max(this.scenario.updatesPerBatch, 1)) + index) % rows;
      default:
        return Math.floor(Math.random() * rows);
    }
  }

  private pickCol(index: number, side: DATA_POS): number {
    let cols = Math.max(this.scenario.colsPerSide, 1);
    let hotspot = Math.max(Math.min(this.scenario.hotspotSize, cols), 1);
    switch (this.scenario.distribution) {
      case PerfDistribution.FullTable:
      case PerfDistribution.HalfTable:
      case PerfDistribution.QuarterTable:
        return this.pickLinearCellIndex(index, side) % cols;
      case PerfDistribution.VisibleHotspot:
        return side === DATA_POS.LEFT ? Math.max(cols - 1 - (index % hotspot), 0) : index % hotspot;
      case PerfDistribution.FixedHotCols:
        return index % hotspot;
      case PerfDistribution.SameCellOverwrite:
        return side === DATA_POS.LEFT ? Math.max(cols - 2, 0) : Math.min(1, cols - 1);
      default:
        return Math.floor(Math.random() * cols);
    }
  }

  private pickVisibleRow(index: number): number {
    let start = this.visibleRange.startRow;
    let end = Math.max(start, this.visibleRange.endRow);
    let size = Math.max(end - start + 1, 1);
    return start + (index % size);
  }

  private pickLinearCellIndex(index: number, side: DATA_POS): number {
    let rows = Math.max(this.scenario.rows, 1);
    let cols = Math.max(this.scenario.colsPerSide, 1);
    let cellsPerSide = rows * cols;
    let pairIndex = Math.floor(index / 2);
    let stride = this.linearStride();
    let phase = side === DATA_POS.LEFT ? 0 : Math.floor(stride / 2);
    return (pairIndex * stride + phase) % cellsPerSide;
  }

  private linearStride(): number {
    switch (this.scenario.distribution) {
      case PerfDistribution.HalfTable:
        return 2;
      case PerfDistribution.QuarterTable:
        return 4;
      default:
        return 1;
    }
  }
}
