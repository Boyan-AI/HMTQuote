/**
 * 期权报价详情页路由参数。
 *
 * 业务点击 T 型报价表上的某一行后，按合约/方向/行权价跳转到本页，
 * 实际接入时可以由业务侧扩展更多字段。
 */
class QuoteDetailParams {
  contractCode: string = '';
  contractName: string = '';
  side: string = '';
  strike: string = '';
  indicatorName: string = '';
  cellValue: string = '';
  livePrice: string = '';
}

/**
 * 期权报价详情样例页。
 *
 * 该页演示如何在业务侧把 TCanvasComponent 的点击回调转化为
 * 真实的合约详情页，仅作为样例展示路由参数和基本布局。
 */
@Entry
@Component
struct QuoteDetail {
  params: QuoteDetailParams = (this.getUIContext().getRouter().getParams() as QuoteDetailParams) ?? new QuoteDetailParams();

  /**
   * 根据点击侧别返回展示文案。
   */
  private sideLabel(): string {
    if (this.params.side === 'LEFT') {
      return '看涨期权 Call';
    }
    if (this.params.side === 'RIGHT') {
      return '看跌期权 Put';
    }
    return '行权价';
  }

  /**
   * 根据点击侧别返回主色，便于业务接入时复用色板。
   */
  private sideColor(): ResourceColor {
    if (this.params.side === 'LEFT') {
      return '#ffff3045';
    }
    if (this.params.side === 'RIGHT') {
      return '#ff22a447';
    }
    return '#ff202124';
  }

  /**
   * 返回上一页。
   */
  private goBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (error) {
      console.error(`QuoteDetail back failed: ${JSON.stringify(error)}`);
    }
  }

  build() {
    Column() {
      Row()
        .height(28)
        .width('100%')
        .backgroundColor('#ffffffff')

      Row() {
        Text('返回')
          .fontSize(16)
          .fontColor('#ff2563eb')
          .textAlign(TextAlign.Start)
          .width(72)
          .onClick(() => this.goBack())
        Text('合约详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        Text(' ')
          .fontSize(16)
          .width(72)
      }
      .height(44)
      .padding({ left: 16, right: 16 })
      .borderWidth({ bottom: 0.5 })
      .borderColor('#ffe5e7eb')

      Column() {
        Text(this.params.contractName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ff111827')
          .margin({ top: 18 })
        Text(this.params.contractCode)
          .fontSize(14)
          .fontColor('#ff8a8f99')
          .margin({ top: 4 })

        Row()
          .height(0.5)
          .width('100%')
          .backgroundColor('#ffe5e7eb')
          .margin({ top: 18 })

        this.DetailRow('期权方向', this.sideLabel(), this.sideColor())
        this.DetailRow('行权价', this.params.strike, '#ff202124')
        this.DetailRow('点击指标', this.params.indicatorName, '#ff202124')
        this.DetailRow('单元格值', this.params.cellValue, this.sideColor())
        this.DetailRow('标的最新价', this.params.livePrice, '#ffff3045')

        Text('该详情页仅作为 TCanvasComponent 点击跳转样例，业务接入时可替换为实际期权合约详情。')
          .fontSize(13)
          .fontColor('#ff8a8f99')
          .margin({ top: 24 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#fff7f8fa')
  }

  /**
   * 详情页一行标签 + 值布局。
   */
  @Builder
  private DetailRow(label: string, value: string, valueColor: ResourceColor) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#ff8a8f99')
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor(valueColor)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height(44)
    .borderWidth({ bottom: 0.5 })
    .borderColor('#ffe5e7eb')
  }
}
