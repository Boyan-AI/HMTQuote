import { DATA_POS } from 't_split_list';
import { QuoteCellUpdate } from './PerfScenario';

export class QuoteCellKey {
  side: DATA_POS = DATA_POS.RIGHT;
  row: number = 0;
  col: number = 0;
}

export class QuoteCellSnapshot {
  side: DATA_POS = DATA_POS.RIGHT;
  row: number = 0;
  col: number = 0;
  value: string = '';
  color: ResourceColor = '#ff000000';
}

export class QuoteTableStore {
  private rows: number = 0;
  private colsPerSide: number = 0;
  private values: string[] = [];
  private colors: ResourceColor[] = [];
  private pendingKeys: number[] = [];
  private pendingSet: Set<number> = new Set();

  reset(rows: number, colsPerSide: number) {
    this.rows = rows;
    this.colsPerSide = colsPerSide;
    let total = rows * colsPerSide * 2;
    this.values = new Array<string>(total);
    this.colors = new Array<ResourceColor>(total);
    for (let index = 0; index < total; index++) {
      this.values[index] = '';
      this.colors[index] = '#ff000000';
    }
    this.pendingKeys = [];
    this.pendingSet.clear();
  }

  applyBatch(updates: QuoteCellUpdate[]): number {
    let applied = 0;
    for (let index = 0; index < updates.length; index++) {
      if (this.applyUpdate(updates[index])) {
        applied++;
      }
    }
    return applied;
  }

  drainPending(): QuoteCellSnapshot[] {
    let snapshots: QuoteCellSnapshot[] = [];
    for (let index = 0; index < this.pendingKeys.length; index++) {
      let key = this.pendingKeys[index];
      snapshots.push(this.createSnapshot(key));
    }
    this.pendingKeys = [];
    this.pendingSet.clear();
    return snapshots;
  }

  drainPendingInRowRange(startRow: number, endRow: number): QuoteCellSnapshot[] {
    let snapshots: QuoteCellSnapshot[] = [];
    let retainedKeys: number[] = [];
    let safeStart = Math.max(0, Math.min(startRow, this.rows - 1));
    let safeEnd = Math.max(safeStart, Math.min(endRow, this.rows - 1));

    for (let index = 0; index < this.pendingKeys.length; index++) {
      let key = this.pendingKeys[index];
      let decoded = this.decodeKey(key);
      if (decoded.row >= safeStart && decoded.row <= safeEnd) {
        snapshots.push(this.createSnapshot(key));
        this.pendingSet.delete(key);
      } else {
        retainedKeys.push(key);
      }
    }
    this.pendingKeys = retainedKeys;
    return snapshots;
  }

  private applyUpdate(update: QuoteCellUpdate): boolean {
    let key = this.encodeKey(update.side, update.row, update.col);
    if (key < 0 || key >= this.values.length) {
      return false;
    }
    this.values[key] = update.value;
    this.colors[key] = update.color;
    if (!this.pendingSet.has(key)) {
      this.pendingSet.add(key);
      this.pendingKeys.push(key);
    }
    return true;
  }

  private encodeKey(side: DATA_POS, row: number, col: number): number {
    if (row < 0 || row >= this.rows || col < 0 || col >= this.colsPerSide) {
      return -1;
    }
    let sideOffset = side === DATA_POS.LEFT ? 0 : this.rows * this.colsPerSide;
    return sideOffset + row * this.colsPerSide + col;
  }

  private decodeKey(key: number): QuoteCellKey {
    let cellCountPerSide = this.rows * this.colsPerSide;
    let side = key < cellCountPerSide ? DATA_POS.LEFT : DATA_POS.RIGHT;
    let offset = key < cellCountPerSide ? key : key - cellCountPerSide;
    let decoded = new QuoteCellKey();
    decoded.side = side;
    decoded.row = Math.floor(offset / this.colsPerSide);
    decoded.col = offset % this.colsPerSide;
    return decoded;
  }

  private createSnapshot(key: number): QuoteCellSnapshot {
    let decoded = this.decodeKey(key);
    let snapshot = new QuoteCellSnapshot();
    snapshot.side = decoded.side;
    snapshot.row = decoded.row;
    snapshot.col = decoded.col;
    snapshot.value = this.values[key];
    snapshot.color = this.colors[key];
    return snapshot;
  }
}
