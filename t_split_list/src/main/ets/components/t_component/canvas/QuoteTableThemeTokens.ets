/**
 * T 型报价 Canvas 主题色 token。
 *
 * Canvas 无法直接用 ArkUI 资源色（$r），所以明暗两版都以 #AARRGGBB 字符串维护，
 * 通过 light()/dark() 工厂产出。业务侧也可复制后覆盖局部颜色做品牌色定制。
 * 默认字段值即亮色，保证未显式取主题的旧调用方行为不变。
 */
export class QuoteTableThemeTokens {
  callColor: string = '#ffff2436';
  putColor: string = '#ff07ab4b';
  actionTextColor: string = '#ff8a8a8a';
  headerTextColor: string = '#66000000';
  priceLineColor: string = '#ff2e58ff';
  priceLabelTextColor: string = '#ffffffff';
  cellTextColor: string = '#d6000000';
  cellSubTextColor: string = '#66000000';
  centerTextColor: string = '#d6000000';
  centerBackgroundColor: string = '#ffffffff';
  headerBackgroundColor: string = '#ffffffff';
  // Canvas 元素整体底色，作为行背景未被象限色覆盖区域的默认底。
  canvasBackgroundColor: string = '#ffffffff';
  borderColor: string = '#0a000000';
  leftAboveLineBackgroundColor: string = '#0dff2436';
  leftBelowLineBackgroundColor: string = '#0f07ab4b';
  rightAboveLineBackgroundColor: string = '#0f07ab4b';
  rightBelowLineBackgroundColor: string = '#0dff2436';
  sortActiveColor: string = '#ff2e58ff';
  sortInactiveColor: string = '#ffd1d1d1';

  /**
   * 亮色主题（默认）。
   */
  static light(): QuoteTableThemeTokens {
    return new QuoteTableThemeTokens();
  }

  /**
   * 暗黑主题，色值取自设计稿暗黑版（node 73:14037）。
   * 涨跌红绿与象限半透明底色两版通用，文字/背景/分隔线/品牌蓝改为暗色对应值。
   */
  static dark(): QuoteTableThemeTokens {
    let next = new QuoteTableThemeTokens();
    next.actionTextColor = '#66ffffff';
    next.headerTextColor = '#66ffffff';
    next.priceLineColor = '#ff527dff';
    next.priceLabelTextColor = '#ffffffff';
    next.cellTextColor = '#d6ffffff';
    next.cellSubTextColor = '#66ffffff';
    next.centerTextColor = '#d6ffffff';
    next.centerBackgroundColor = '#ff1c1c1c';
    next.headerBackgroundColor = '#ff1c1c1c';
    next.canvasBackgroundColor = '#ff1c1c1c';
    next.borderColor = '#14ffffff';
    next.sortActiveColor = '#ff527dff';
    next.sortInactiveColor = '#ff3b3b3b';
    return next;
  }

  /**
   * 复制主题色，避免业务侧和组件内部共享同一个可变对象。
   */
  clone(): QuoteTableThemeTokens {
    let next = new QuoteTableThemeTokens();
    next.callColor = this.callColor;
    next.putColor = this.putColor;
    next.actionTextColor = this.actionTextColor;
    next.headerTextColor = this.headerTextColor;
    next.priceLineColor = this.priceLineColor;
    next.priceLabelTextColor = this.priceLabelTextColor;
    next.cellTextColor = this.cellTextColor;
    next.cellSubTextColor = this.cellSubTextColor;
    next.centerTextColor = this.centerTextColor;
    next.centerBackgroundColor = this.centerBackgroundColor;
    next.headerBackgroundColor = this.headerBackgroundColor;
    next.canvasBackgroundColor = this.canvasBackgroundColor;
    next.borderColor = this.borderColor;
    next.leftAboveLineBackgroundColor = this.leftAboveLineBackgroundColor;
    next.leftBelowLineBackgroundColor = this.leftBelowLineBackgroundColor;
    next.rightAboveLineBackgroundColor = this.rightAboveLineBackgroundColor;
    next.rightBelowLineBackgroundColor = this.rightBelowLineBackgroundColor;
    next.sortActiveColor = this.sortActiveColor;
    next.sortInactiveColor = this.sortInactiveColor;
    return next;
  }
}
