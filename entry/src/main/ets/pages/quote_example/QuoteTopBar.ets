import { SubTabItem, TopNavItem } from './QuoteExampleModels';

/**
 * 顶部安全区 + 主导航 + 二级 Tab 复合组件。
 *
 * 该组件不持有状态，所有展示数据由父页面传入，便于样例页和真实业务页面共用。
 */
@Component
export struct QuoteTopBar {
  topNavItems: TopNavItem[] = [];
  subTabItems: SubTabItem[] = [];
  @Prop darkMode: boolean = false;

  private textPrimary(): string {
    return this.darkMode ? '#d6ffffff' : '#d6000000';
  }

  private textSecondary(): string {
    return this.darkMode ? '#66ffffff' : '#66000000';
  }

  private bgColor(): string {
    return this.darkMode ? '#ff1c1c1c' : '#ffffffff';
  }

  private iconBgColor(): string {
    return this.darkMode ? '#ff292929' : '#fff2f4f7';
  }

  private brand(): string {
    return this.darkMode ? '#ff527dff' : '#ff2e58ff';
  }

  private dividerColor(): string {
    return this.darkMode ? '#14ffffff' : '#0a000000';
  }

  /**
   * 顶部安全区占位，避免主导航贴到状态栏。
   */
  @Builder
  private SafeAreaTop() {
    Row()
      .height(28)
      .width('100%')
      .backgroundColor(this.bgColor())
  }

  /**
   * 顶部右侧圆形图标占位，统一视觉风格。
   */
  @Builder
  private RoundIcon(symbol: string) {
    Text(symbol)
      .fontSize(16)
      .fontColor(this.textPrimary())
      .textAlign(TextAlign.Center)
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(this.iconBgColor())
      .margin({ left: 8 })
  }

  /**
   * 主导航行：总览 / 自选 / 国内 / 国际 / 期权 / 套利。
   */
  @Builder
  private TopNav() {
    Row() {
      Row({ space: 15 }) {
        ForEach(this.topNavItems, (item: TopNavItem) => {
          Text(item.label)
            .fontSize(item.active ? 21 : 16)
            .fontColor(item.active ? this.textPrimary() : this.textSecondary())
            .fontWeight(item.active ? FontWeight.Bold : FontWeight.Regular)
            .maxLines(1)
        }, (item: TopNavItem) => item.label)
      }
      .layoutWeight(1)
      .clip(true)

      this.RoundIcon('🔍')
      this.RoundIcon('☰')
    }
    .height(48)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 二级 Tab：期权雷达 / T 型报价 / 策略分析 / 数据分析。
   */
  @Builder
  private SubTabs() {
    Row() {
      ForEach(this.subTabItems, (item: SubTabItem) => {
        Column() {
          Text(item.label)
            .fontSize(item.active ? 17 : 15)
            .fontWeight(item.active ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(item.active ? this.textPrimary() : this.textSecondary())
          Row()
            .width(item.active ? 22 : 0)
            .height(3)
            .borderRadius(2)
            .backgroundColor(this.brand())
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }, (item: SubTabItem) => item.label)
    }
    .height(40)
    .padding({ left: 12, right: 12 })
    .borderWidth({ bottom: 0.5 })
    .borderColor(this.dividerColor())
  }

  build() {
    Column() {
      this.SafeAreaTop()
      this.TopNav()
      this.SubTabs()
    }
    .width('100%')
    .backgroundColor(this.bgColor())
  }
}
