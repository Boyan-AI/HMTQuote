import { QuoteTableThemeTokens } from './QuoteTableThemeTokens';

/**
 * 行情表高性能渲染配置。
 *
 * 该配置用于控制 Canvas 渲染、可见范围刷新、滑动刷新和降级策略。
 * 默认值按当前压测结论设置：20Hz 部分变动行情、100ms flush、滑动中暂停刷新。
 */
export class QuoteTablePerfConfig {
  renderMode: string = 'viewportCanvas';
  defaultFlushIntervalMs: number = 100;
  highPriorityFlushIntervalMs: number = 50;
  degradedFlushIntervalMs: number = 200;
  visibleOnly: boolean = true;
  refreshWhileScrolling: boolean = false;
  scrollingFlushIntervalMs: number = 200;
  visibleRowBuffer: number = 4;
  visibleColBuffer: number = 1;
  enablePerfStats: boolean = true;
  enableAutoDegrade: boolean = true;
  showSideTitleHeader: boolean = true;
  verticalScrollSensitivity: number = 1.25;
  horizontalScrollSensitivity: number = 1.10;
  themeTokens: QuoteTableThemeTokens = new QuoteTableThemeTokens();

  /**
   * 复制当前配置，避免业务侧复用同一对象时被组件内部状态污染。
   */
  clone(): QuoteTablePerfConfig {
    let next = new QuoteTablePerfConfig();
    next.renderMode = this.renderMode;
    next.defaultFlushIntervalMs = this.defaultFlushIntervalMs;
    next.highPriorityFlushIntervalMs = this.highPriorityFlushIntervalMs;
    next.degradedFlushIntervalMs = this.degradedFlushIntervalMs;
    next.visibleOnly = this.visibleOnly;
    next.refreshWhileScrolling = this.refreshWhileScrolling;
    next.scrollingFlushIntervalMs = this.scrollingFlushIntervalMs;
    next.visibleRowBuffer = this.visibleRowBuffer;
    next.visibleColBuffer = this.visibleColBuffer;
    next.enablePerfStats = this.enablePerfStats;
    next.enableAutoDegrade = this.enableAutoDegrade;
    next.showSideTitleHeader = this.showSideTitleHeader;
    next.verticalScrollSensitivity = this.verticalScrollSensitivity;
    next.horizontalScrollSensitivity = this.horizontalScrollSensitivity;
    next.themeTokens = this.themeTokens.clone();
    return next;
  }
}
