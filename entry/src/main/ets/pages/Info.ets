class InfoParams {
  row: number = -1;
  side: number = -1;
  col: number = -1;
  value: string = '';
}

@Entry
@Component
struct Info {
  params: InfoParams = this.getUIContext().getRouter().getParams() as InfoParams;

  build() {
    Column() {
      Text('Info')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
      Text(`row: ${this.params.row}`)
        .fontSize(18)
      Text(`side: ${this.params.side}`)
        .fontSize(18)
      Text(`col: ${this.params.col}`)
        .fontSize(18)
      Text(`value: ${this.params.value}`)
        .fontSize(18)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .height('100%')
    .width('100%')
  }
}
