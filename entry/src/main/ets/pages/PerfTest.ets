import {
  DATA_POS,
  HeaderConfig,
  HeaderItem
} from 'common_sideslipview';
import { MockQuoteFeed } from '../perf/MockQuoteFeed';
import {
  distributionName,
  distributionShortId,
  PerfDistribution,
  PerfScenario,
  QuoteCellUpdate
} from '../perf/PerfScenario';
import { nowMs, PerfHealthContext, PerfStats } from '../perf/PerfStats';
import {
  CanvasQuoteGridData,
  CanvasQuoteHitCell,
  CanvasQuotePartitionColors,
  CanvasQuoteTable
} from '../perf/CanvasQuoteTable';
import { QuoteCellSnapshot } from '../perf/QuoteTableStore';
import { QuoteUpdateScheduler } from '../perf/QuoteUpdateScheduler';
import { displaySync } from '@kit.ArkGraphics2D';

const SETTLE_BEFORE_STATS_MS = 500;
const DEFAULT_SCHEDULER_FLUSH_INTERVAL_MS = 100;
const LATEST_PRICE_INTERVAL_MS = 200;

@Entry
@Component
struct PerfTest {
  @State private canvasData: CanvasQuoteGridData = new CanvasQuoteGridData();
  @State private partitionColors: CanvasQuotePartitionColors = new CanvasQuotePartitionColors();
  @State private canvasRevision: number = 0;
  @State private latestPrice: number = 50;
  @State private summary: string = '未开始';
  @State private running: boolean = false;
  @State private rows: number = 100;
  @State private colsPerSide: number = 20;
  @State private frequencyHz: number = 20;
  @State private updatesPerBatch: number = 4000;
  @State private distribution: PerfDistribution = PerfDistribution.QuarterTable;
  @State private continueWhileScrolling: boolean = false;
  @State private liveProbeText: string = 'LIVE未启动';
  @State private forceFullRefresh: boolean = false;
  @State private useScheduler: boolean = true;
  @State private visualProbe: boolean = false;
  @State private schedulerFlushIntervalMs: number = DEFAULT_SCHEDULER_FLUSH_INTERVAL_MS;
  @State private visibleOnlyRefresh: boolean = true;

  private readonly frequencyOptions: number[] = [10, 20, 50, 100];
  private readonly schedulerFlushOptions: number[] = [33, 100, 200];
  private readonly partitionColorOptions: CanvasQuotePartitionColors[] = [
    this.createPartitionColors('#fffff3f5', '#fff2fbf5', '#fff2fbf5', '#fffff3f5'),
    this.createPartitionColors('#ffffecef', '#ffeaf8ee', '#ffeaf8ee', '#ffffecef'),
    this.createPartitionColors('#fffdf2f8', '#fff0fbf4', '#fff0fbf4', '#fffdf2f8'),
    this.createPartitionColors('#ffffffff', '#fff7fbff', '#fff7fbff', '#ffffffff')
  ];
  private readonly distributionOptions: PerfDistribution[] = [
    PerfDistribution.FullTable,
    PerfDistribution.HalfTable,
    PerfDistribution.QuarterTable
  ];
  private readonly stats: PerfStats = new PerfStats();
  private readonly feed: MockQuoteFeed = new MockQuoteFeed();
  private readonly scheduler: QuoteUpdateScheduler = new QuoteUpdateScheduler();
  private head: HeaderConfig = { hqData: [] };
  private scrolling: boolean = false;
  private summaryTimerId: number = -1;
  private settleTimerId: number = -1;
  private latestPriceTimerId: number = -1;
  private frameSync?: displaySync.DisplaySync;
  private diagnosticSeq: number = 0;
  private latestPriceSeq: number = 0;
  private visibleStartRow: number = 0;
  private visibleEndRow: number = 20;
  private partitionColorIndex: number = 0;

  aboutToAppear(): void {
    this.prepareScenarioData();
    this.stats.start(this.currentScenario());
    this.pushHealthContext();
    this.startStatsTimers();
    this.startFrameSync();
  }

  aboutToDisappear(): void {
    this.stopFeed();
    this.stopStatsTimers();
    this.stopFrameSync();
  }

  // 用 displaySync 拿真实 VSync 时间戳，避免 setInterval(16) 测的是"主线程繁忙度"而非掉帧。
  private startFrameSync() {
    this.stopFrameSync();
    this.frameSync = displaySync.create();
    this.frameSync.on('frame', (intervalInfo: displaySync.IntervalInfo) => {
      // intervalInfo.timestamp 单位纳秒
      this.stats.recordFrame(intervalInfo.timestamp / 1_000_000);
    });
    this.frameSync.start();
  }

  private stopFrameSync() {
    if (this.frameSync) {
      this.frameSync.stop();
      this.frameSync = undefined;
    }
  }

  private startStatsTimers() {
    this.stopStatsTimers();
    this.summaryTimerId = setInterval(() => {
      this.summary = this.stats.summaryText();
    }, 1000);
  }

  private stopStatsTimers() {
    if (this.summaryTimerId >= 0) {
      clearInterval(this.summaryTimerId);
      this.summaryTimerId = -1;
    }
    if (this.settleTimerId >= 0) {
      clearTimeout(this.settleTimerId);
      this.settleTimerId = -1;
    }
  }

  private isFeedActive(): boolean {
    return this.running || this.settleTimerId >= 0;
  }

  private pushHealthContext() {
    let ctx = new PerfHealthContext();
    ctx.scrolling = this.scrolling;
    ctx.continueWhileScrolling = this.continueWhileScrolling;
    ctx.feedRunning = this.running;
    this.stats.updateContext(ctx);
  }

  private currentScenario(): PerfScenario {
    let scenario = new PerfScenario();
    scenario.scenarioId =
      `rows100_cols20_${this.frequencyHz}hz_${distributionShortId(this.distribution)}`;
    scenario.variantId = this.currentVariantId();
    scenario.rows = this.rows;
    scenario.colsPerSide = this.colsPerSide;
    scenario.frequencyHz = this.frequencyHz;
    scenario.updatesPerBatch = this.updatesPerBatch;
    scenario.distribution = this.distribution;
    scenario.continueWhileScrolling = this.continueWhileScrolling;
    return scenario;
  }

  private prepareScenarioData() {
    this.latestPrice = Math.floor(this.rows / 2);
    this.head = this.createHeaderConfig(this.colsPerSide);
    this.canvasData.reset(this.rows, this.colsPerSide);
    this.canvasData.seed();
    this.canvasRevision++;
  }

  private createHeaderConfig(cols: number): HeaderConfig {
    let hqData: HeaderItem[] = [];
    for (let col = 0; col < cols; col++) {
      hqData.push(new HeaderItem(col + 1, `指标${col + 1}`));
    }
    return { hqData: hqData };
  }

  // 先初始化 Canvas 数据，等 UI 稳定 500ms 后再 reset stats，再 start feed。
  private startFeed() {
    this.prepareScenarioData();
    let scenario = this.currentScenario();
    this.feed.configure(scenario, this.stats, (updates: QuoteCellUpdate[]) => {
      this.applyUpdates(updates);
    });
    this.summary = '准备中（等待 UI 稳定）...';
    if (this.settleTimerId >= 0) {
      clearTimeout(this.settleTimerId);
    }
    this.settleTimerId = setTimeout(() => {
      this.settleTimerId = -1;
      this.stats.start(scenario);
      this.running = true;
      this.pushHealthContext();
      if (this.useScheduler) {
        this.scheduler.configure(this.rows, this.colsPerSide, this.stats, (snapshots: QuoteCellSnapshot[]) => {
          return this.flushScheduledUpdates(snapshots);
        }, this.schedulerFlushIntervalMs, () => {
          return !(this.scrolling && !this.continueWhileScrolling);
        }, this.visibleOnlyRefresh, () => {
          return this.visibleStartRow;
        }, () => {
          return this.visibleEndRow;
        });
        this.scheduler.start();
      } else {
        this.scheduler.stop();
      }
      this.feed.start();
      this.startLatestPriceTimer();
      this.summary = this.stats.summaryText();
    }, SETTLE_BEFORE_STATS_MS);
  }

  private restartFeed() {
    this.feed.stop();
    this.scheduler.stop();
    this.stopLatestPriceTimer();
    this.running = false;
    this.pushHealthContext();
    this.startFeed();
  }

  private stopFeed() {
    this.feed.stop();
    this.scheduler.stop();
    this.stopLatestPriceTimer();
    if (this.settleTimerId >= 0) {
      clearTimeout(this.settleTimerId);
      this.settleTimerId = -1;
    }
    this.running = false;
    this.pushHealthContext();
    this.summary = this.stats.summaryText();
  }

  private resetStats() {
    this.stats.reset();
    this.pushHealthContext();
    this.summary = this.stats.summaryText();
  }

  private exportSnapshot() {
    this.stats.exportToHilog();
    this.summary = `${this.stats.summaryText()} | 已导出 hilog (tag=PerfStats)`;
  }

  private startLatestPriceTimer() {
    this.stopLatestPriceTimer();
    this.latestPriceSeq = 0;
    this.latestPriceTimerId = setInterval(() => {
      this.latestPriceSeq++;
      let center = Math.floor(this.rows / 2);
      let wave = Math.sin(this.latestPriceSeq / 5) * 2.4;
      this.latestPrice = Math.max(0, Math.min(this.rows - 1, center + wave));
    }, LATEST_PRICE_INTERVAL_MS);
  }

  private stopLatestPriceTimer() {
    if (this.latestPriceTimerId >= 0) {
      clearInterval(this.latestPriceTimerId);
      this.latestPriceTimerId = -1;
    }
  }

  private diagnosticUpdate() {
    let centerRow = Math.floor(this.rows / 2);
    let leftCol = Math.max(this.colsPerSide - 1, 0);
    let rightCol = 0;
    this.diagnosticSeq++;
    let value = `诊断${this.diagnosticSeq}`;
    let canvasLeftUpdated = this.canvasData.set(DATA_POS.LEFT, centerRow, leftCol, value, '#ffb00020');
    let canvasRightUpdated = this.canvasData.set(DATA_POS.RIGHT, centerRow, rightCol, value, '#ffb00020');
    if (canvasLeftUpdated || canvasRightUpdated) {
      this.canvasRevision++;
    }
    let applied = (canvasLeftUpdated ? 1 : 0) + (canvasRightUpdated ? 1 : 0);
    this.stats.recordUiApplied(applied);
    this.stats.recordUiPainted(applied);
    this.summary = `${this.stats.summaryText()} | 诊断写入 ${canvasLeftUpdated && canvasRightUpdated ? '成功' : '失败'}`;
  }

  // Canvas-only 路径：行情可直接写入 Canvas 数据缓存，最后通过 canvasRevision 合并触发重绘。
  private applyUpdates(updates: QuoteCellUpdate[]) {
    if (this.useScheduler) {
      this.scheduler.enqueue(updates);
      return;
    }
    if (this.scrolling && !this.continueWhileScrolling) {
      return;
    }
    let startedAt = nowMs();
    let applied = 0;
    for (let index = 0; index < updates.length; index++) {
      let update = updates[index];
      if (this.applyUpdateToRender(update.side, update.row, update.col, update.value, update.color)) {
        applied++;
      }
    }
    if (applied > 0) {
      if (this.visualProbe) {
        applied += this.applyVisibleProbe();
      }
      if (this.forceFullRefresh) {
        this.forceRefreshTable();
      }
    }
    // A 版本下 applied == painted（每次 setter 都触发响应式重绘）
    this.stats.recordFlush(updates.length, nowMs() - startedAt);
    this.stats.recordUiApplied(applied);
    this.stats.recordUiPainted(applied);
  }

  private flushScheduledUpdates(snapshots: QuoteCellSnapshot[]): number {
    return this.flushCanvasSnapshots(snapshots);
  }

  private flushCanvasSnapshots(snapshots: QuoteCellSnapshot[]): number {
    let painted = 0;
    for (let index = 0; index < snapshots.length; index++) {
      let snapshot = snapshots[index];
      if (this.canvasData.set(snapshot.side, snapshot.row, snapshot.col, snapshot.value, snapshot.color)) {
        painted++;
      }
    }
    if (painted > 0) {
      this.canvasRevision++;
    }
    return painted;
  }

  private applyVisibleProbe(): number {
    this.diagnosticSeq++;
    let value = `LIVE${this.diagnosticSeq % 1000}`;
    this.liveProbeText = value;
    let applied = 0;
    let rows = [
      0,
      1,
      Math.floor(this.rows / 2),
      Math.max(this.rows - 2, 0),
      Math.max(this.rows - 1, 0),
      Math.floor((this.visibleStartRow + this.visibleEndRow) / 2)
    ];
    let rightCols = [0, 1, 2, 3, 4];
    let leftCols = [
      Math.max(this.colsPerSide - 1, 0),
      Math.max(this.colsPerSide - 2, 0),
      Math.max(this.colsPerSide - 3, 0),
      Math.max(this.colsPerSide - 4, 0),
      Math.max(this.colsPerSide - 5, 0)
    ];

    for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      let row = Math.max(0, Math.min(rows[rowIndex], this.rows - 1));
      for (let colIndex = 0; colIndex < rightCols.length; colIndex++) {
        if (this.applyUpdateToRender(DATA_POS.RIGHT, row, rightCols[colIndex], value, '#ff0052cc')) {
          applied++;
        }
        if (this.applyUpdateToRender(DATA_POS.LEFT, row, leftCols[colIndex], value, '#ff0052cc')) {
          applied++;
        }
      }
    }
    return applied;
  }

  private forceRefreshTable() {
    this.canvasRevision++;
  }

  private cycleFrequency() {
    this.frequencyHz = this.nextNumber(this.frequencyOptions, this.frequencyHz);
    this.applyScenarioChange(false);
  }

  private cycleDistribution() {
    let currentIndex = this.distributionOptions.indexOf(this.distribution);
    let nextIndex = (currentIndex + 1) % this.distributionOptions.length;
    this.distribution = this.distributionOptions[nextIndex];
    this.applyScenarioChange(false);
  }

  private toggleContinueWhileScrolling() {
    this.continueWhileScrolling = !this.continueWhileScrolling;
    this.pushHealthContext();
    this.applyScenarioChange(false);
  }

  private toggleForceFullRefresh() {
    this.forceFullRefresh = !this.forceFullRefresh;
    this.summary = `${this.stats.summaryText()} | 强制整表刷新${this.forceFullRefresh ? '开' : '关'}`;
  }

  private toggleSchedulerMode() {
    this.useScheduler = !this.useScheduler;
    this.applyScenarioChange(false);
  }

  private toggleVisualProbe() {
    this.visualProbe = !this.visualProbe;
    this.summary = `${this.stats.summaryText()} | LIVE探针${this.visualProbe ? '开' : '关'}`;
  }

  private toggleVisibleOnlyRefresh() {
    this.visibleOnlyRefresh = !this.visibleOnlyRefresh;
    this.applyScenarioChange(false);
  }

  private cycleSchedulerFlushInterval() {
    this.schedulerFlushIntervalMs = this.nextNumber(this.schedulerFlushOptions, this.schedulerFlushIntervalMs);
    this.applyScenarioChange(false);
  }

  private cyclePartitionColors() {
    this.partitionColorIndex = (this.partitionColorIndex + 1) % this.partitionColorOptions.length;
    this.partitionColors = this.partitionColorOptions[this.partitionColorIndex];
    this.canvasRevision++;
  }

  private applyBusinessDefaultPreset() {
    this.applyPreset(20, PerfDistribution.QuarterTable, 100);
  }

  private applyHighPressurePreset() {
    this.applyPreset(20, PerfDistribution.HalfTable, 100);
  }

  private applyExtremeDegradePreset() {
    this.applyPreset(20, PerfDistribution.FullTable, 200);
  }

  private applyPreset(frequencyHz: number, distribution: PerfDistribution, flushIntervalMs: number) {
    this.frequencyHz = frequencyHz;
    this.distribution = distribution;
    this.schedulerFlushIntervalMs = flushIntervalMs;
    this.useScheduler = true;
    this.visibleOnlyRefresh = true;
    this.continueWhileScrolling = false;
    this.forceFullRefresh = false;
    this.visualProbe = false;
    this.applyScenarioChange(true);
  }

  private updateCanvasScrollState(scrolling: boolean) {
    if (this.scrolling === scrolling) {
      return;
    }
    this.scrolling = scrolling;
    this.pushHealthContext();
  }

  private updateCanvasVisibleRange(startRow: number, endRow: number) {
    let normalizedStart = Math.max(0, Math.min(startRow, this.rows - 1));
    let normalizedEnd = Math.max(normalizedStart, Math.min(endRow, this.rows - 1));
    if (this.visibleStartRow === normalizedStart && this.visibleEndRow === normalizedEnd) {
      return;
    }
    this.visibleStartRow = normalizedStart;
    this.visibleEndRow = normalizedEnd;
    this.feed.setVisibleRange(normalizedStart, normalizedEnd);
  }

  private currentVariantId(): string {
    if (!this.useScheduler) {
      return 'D_canvas_direct';
    }
    return this.visibleOnlyRefresh ? 'D_canvas_visible_scheduler' : 'D_canvas_scheduler';
  }

  private applyUpdateToRender(side: DATA_POS, row: number, col: number, value: string, color: ResourceColor): boolean {
    let updated = this.canvasData.set(side, row, col, value, color);
    if (updated) {
      this.canvasRevision++;
    }
    return updated;
  }

  private createPartitionColors(callTop: string, callBottom: string, putTop: string,
    putBottom: string): CanvasQuotePartitionColors {
    let colors = new CanvasQuotePartitionColors();
    colors.callTop = callTop;
    colors.callBottom = callBottom;
    colors.putTop = putTop;
    colors.putBottom = putBottom;
    return colors;
  }

  private applyScenarioChange(needRebuild: boolean) {
    if (this.isFeedActive()) {
      this.restartFeed();
    } else if (needRebuild) {
      this.prepareScenarioData();
      this.stats.start(this.currentScenario());
    } else {
      this.stats.start(this.currentScenario());
    }
    this.pushHealthContext();
    this.summary = this.stats.summaryText();
  }

  private nextNumber(options: number[], current: number): number {
    let index = options.indexOf(current);
    return options[(index + 1) % options.length];
  }

  private healthColor(): ResourceColor {
    let snapshot = this.stats.snapshot();
    if (snapshot.health === '异常') {
      return '#ffb00020';
    }
    if (snapshot.health === '警告') {
      return '#ff9a6700';
    }
    return '#ff555555';
  }

  private currentConfigText(): string {
    return `100行 x 每侧20列 | ${this.frequencyHz}Hz | 行情变化${distributionName(this.distribution)} | ${this.currentVariantId()} | flush ${this.schedulerFlushIntervalMs}ms`;
  }

  private currentStrategyText(): string {
    return `只刷可见 ${this.visibleOnlyRefresh ? '开' : '关'} | 滑动刷新 ${this.continueWhileScrolling ? '开' : '关'} | 强制整表刷新 ${this.forceFullRefresh ? '开' : '关'} | LIVE探针 ${this.visualProbe ? '开' : '关'}`;
  }

  build() {
    Column() {
      Column() {
        Row() {
          Column() {
            Text('行情表压测')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#ff111827')
            Text(this.currentConfigText())
              .fontSize(11)
              .fontColor('#ff6b7280')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button(this.isFeedActive() ? '停止' : '开始')
            .fontSize(13)
            .height(34)
            .backgroundColor(this.isFeedActive() ? '#ffef4444' : '#ff2563eb')
            .fontColor('#ffffffff')
            .borderRadius(6)
            .margin({ left: 8 })
            .onClick(() => {
              if (this.isFeedActive()) {
                this.stopFeed();
              } else {
                this.startFeed();
              }
            })
          Button('导出')
            .fontSize(13)
            .height(34)
            .backgroundColor('#ffe5e7eb')
            .fontColor('#ff111827')
            .borderRadius(6)
            .margin({ left: 6 })
            .onClick(() => {
              this.exportSnapshot();
            })
        }
        .width('100%')

        Row() {
          Text(this.summary)
            .fontSize(11)
            .fontColor(this.healthColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.isFeedActive() ? 'RUNNING' : 'IDLE')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isFeedActive() ? '#ff15803d' : '#ff6b7280')
            .backgroundColor(this.isFeedActive() ? '#ffdcfce7' : '#fff3f4f6')
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor('#ffffffff')

      Column() {
        Row() {
          Text('场景')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ff374151')
          Blank()
          Button('重置')
            .fontSize(11)
            .height(28)
            .backgroundColor('#fff3f4f6')
            .fontColor('#ff374151')
            .borderRadius(6)
            .onClick(() => {
              this.resetStats();
            })
          Button('诊断')
            .fontSize(11)
            .height(28)
            .backgroundColor('#fff3f4f6')
            .fontColor('#ff374151')
            .borderRadius(6)
            .margin({ left: 6 })
            .onClick(() => {
              this.diagnosticUpdate();
            })
        }
        .width('100%')

        Flex({ wrap: FlexWrap.Wrap }) {
          Button('业务默认')
            .fontSize(12)
            .height(30)
            .backgroundColor('#ff2563eb')
            .fontColor('#ffffffff')
            .borderRadius(6)
            .margin({ right: 6, top: 6 })
            .onClick(() => {
              this.applyBusinessDefaultPreset();
            })
          Button('偏高压力')
            .fontSize(12)
            .height(30)
            .backgroundColor('#fffef3c7')
            .fontColor('#ff92400e')
            .borderRadius(6)
            .margin({ right: 6, top: 6 })
            .onClick(() => {
              this.applyHighPressurePreset();
            })
          Button('极限降级')
            .fontSize(12)
            .height(30)
            .backgroundColor('#ffffe4e6')
            .fontColor('#ffbe123c')
            .borderRadius(6)
            .margin({ right: 6, top: 6 })
            .onClick(() => {
              this.applyExtremeDegradePreset();
            })
        }
        .width('100%')

        Flex({ wrap: FlexWrap.Wrap }) {
