/**
 * 合约概要区域。
 *
 * 显示标的名称、当前最新价、涨跌、到期天数和最高/最低/振幅等指标。
 * 父页面通过 @Prop 把变化频繁的 livePrice 传入，其余文案当前先用样例固定值。
 */
@Component
export struct QuoteContractSummary {
  @Prop livePrice: string = '';
  @Prop darkMode: boolean = false;

  private textPrimary(): string {
    return this.darkMode ? '#d6ffffff' : '#d6000000';
  }

  private textSecondary(): string {
    return this.darkMode ? '#66ffffff' : '#66000000';
  }

  private brand(): string {
    return this.darkMode ? '#ff527dff' : '#ff2e58ff';
  }

  private dividerColor(): string {
    return this.darkMode ? '#14ffffff' : '#0a000000';
  }

  /**
   * 合约概要右侧单行指标，左标签 + 值 + 右标签 + 值。
   */
  @Builder
  private MetricRow(leftLabel: string, leftValue: string, leftColor: ResourceColor,
                    rightLabel: string, rightValue: string, rightColor: ResourceColor) {
    Row() {
      Text(leftLabel)
        .fontSize(12)
        .fontColor(this.textSecondary())
        .width(34)
        .maxLines(1)
      Text(leftValue)
        .fontSize(12)
        .fontColor(leftColor)
        .textAlign(TextAlign.End)
        .width(58)
        .maxLines(1)
      Text(rightLabel)
        .fontSize(12)
        .fontColor(this.textSecondary())
        .width(64)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .margin({ left: 12 })
      Text(rightValue)
        .fontSize(12)
        .fontColor(rightColor)
        .textAlign(TextAlign.End)
        .width(58)
        .maxLines(1)
        .margin({ left: 6 })
    }
    .width('100%')
    .height(18)
  }

  build() {
    Column() {
      Row() {
        Text('沪深300ETF期权')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textPrimary())
        Text('▼')
          .fontSize(11)
          .fontColor(this.textSecondary())
          .margin({ left: 4 })
        Text('标的')
          .fontSize(11)
          .fontColor(this.brand())
          .border({ width: 1, color: this.brand(), radius: 3 })
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .margin({ left: 14 })
        Text('沪深300ETF')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textPrimary())
          .margin({ left: 8 })
        Text('主')
          .fontSize(11)
          .fontColor('#ffffffff')
          .backgroundColor('#ffbf864d')
          .borderRadius(3)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .margin({ left: 4 })
      }
      .height(28)
      .width('100%')

      Row() {
        Column() {
          Text(this.livePrice)
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffff2436')
            .maxLines(1)
          Text('+194  +2.34%')
            .fontSize(15)
            .fontColor('#ffff2436')
            .maxLines(1)
            .margin({ top: 2 })
          Text('剩余 210 天到期')
            .fontSize(12)
            .fontColor(this.textSecondary())
            .maxLines(1)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(11)

        Column() {
          this.MetricRow('最高', '269888.50', '#ffff2436', '成交', '5542.0万', this.textPrimary())
          this.MetricRow('最低', '269000.00', '#ff07ab4b', '持仓', '46.89万', this.textPrimary())
          this.MetricRow('振幅', '10.56%', this.textPrimary(), '历史波动率', '30.56%', this.textPrimary())
        }
        .width(232)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .borderWidth({ bottom: 0.5 })
    .borderColor(this.dividerColor())
  }
}
