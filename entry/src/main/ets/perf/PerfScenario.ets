import { DATA_POS } from 'common_sideslipview';

export enum PerfDistribution {
  FullRandom,
  VisibleHotspot,
  FixedHotRows,
  FixedHotCols,
  Burst,
  SameCellOverwrite,
  MovingHotspot,
  FullTable,
  HalfTable,
  QuarterTable
}

export class QuoteCellUpdate {
  side: DATA_POS = DATA_POS.RIGHT;
  row: number = 0;
  col: number = 0;
  value: string = '';
  color: ResourceColor = '#ff000000';
}

export class VisibleRange {
  startRow: number = 0;
  endRow: number = 0;
}

export class PerfScenario {
  scenarioId: string = 'rows100_cols20_10hz_fulltable';
  variantId: string = 'A_current';
  rows: number = 100;
  colsPerSide: number = 20;
  frequencyHz: number = 10;
  updatesPerBatch: number = 4000;
  distribution: PerfDistribution = PerfDistribution.FullTable;
  continueWhileScrolling: boolean = true;
  hotspotSize: number = 5;
  burstActiveTicks: number = 1;
  burstQuietTicks: number = 99;
  burstPeakMultiplier: number = 20;

  clone(): PerfScenario {
    let next = new PerfScenario();
    next.scenarioId = this.scenarioId;
    next.variantId = this.variantId;
    next.rows = this.rows;
    next.colsPerSide = this.colsPerSide;
    next.frequencyHz = this.frequencyHz;
    next.updatesPerBatch = this.updatesPerBatch;
    next.distribution = this.distribution;
    next.continueWhileScrolling = this.continueWhileScrolling;
    next.hotspotSize = this.hotspotSize;
    next.burstActiveTicks = this.burstActiveTicks;
    next.burstQuietTicks = this.burstQuietTicks;
    next.burstPeakMultiplier = this.burstPeakMultiplier;
    return next;
  }
}

export function distributionName(distribution: PerfDistribution): string {
  switch (distribution) {
    case PerfDistribution.FullRandom:
      return '全表随机';
    case PerfDistribution.VisibleHotspot:
      return '可见热点';
    case PerfDistribution.FixedHotRows:
      return '固定热点行';
    case PerfDistribution.FixedHotCols:
      return '固定热点列';
    case PerfDistribution.Burst:
      return 'Burst';
    case PerfDistribution.SameCellOverwrite:
      return '同cell覆盖';
    case PerfDistribution.MovingHotspot:
      return '跨视窗迁移';
    case PerfDistribution.FullTable:
      return '整表';
    case PerfDistribution.HalfTable:
      return '半表';
    case PerfDistribution.QuarterTable:
      return '1/4表';
    default:
      return '未知';
  }
}

export function distributionShortId(distribution: PerfDistribution): string {
  switch (distribution) {
    case PerfDistribution.FullRandom:
      return 'random';
    case PerfDistribution.VisibleHotspot:
      return 'visible';
    case PerfDistribution.FixedHotRows:
      return 'hotrows';
    case PerfDistribution.FixedHotCols:
      return 'hotcols';
    case PerfDistribution.Burst:
      return 'burst';
    case PerfDistribution.SameCellOverwrite:
      return 'overwrite';
    case PerfDistribution.MovingHotspot:
      return 'moving';
    case PerfDistribution.FullTable:
      return 'fulltable';
    case PerfDistribution.HalfTable:
      return 'halftable';
    case PerfDistribution.QuarterTable:
      return 'quartertable';
    default:
      return 'unknown';
  }
}
