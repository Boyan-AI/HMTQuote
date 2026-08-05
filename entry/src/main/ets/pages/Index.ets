class EntryPageItem {
  title: string = '';
  subtitle: string = '';
  route: string = '';
  tag: string = '';

  constructor(title: string, subtitle: string, route: string, tag: string) {
    this.title = title;
    this.subtitle = subtitle;
    this.route = route;
    this.tag = tag;
  }
}

/**
 * entry 首页。
 *
 * 提供性能测试页和 t_split_list 业务样例页入口，方便调试和验收。
 */
@Entry
@Component
struct Index {
  private readonly pages: EntryPageItem[] = [
    new EntryPageItem('性能测试', '进入行情表压测页，验证刷新频率、可见刷新和 Canvas 性能。', 'pages/PerfTest', 'Perf'),
    new EntryPageItem('业务样例', '进入 t_split_list Canvas T 型报价样例页。', 'pages/QuoteTableExample', 'Example')
  ];

  /**
   * 跳转到指定测试或样例页面。
   */
  private openPage(route: string): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: route });
    } catch (error) {
      console.error(`Index open page failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 构建单个入口卡片。
   */
  @Builder
  private EntryCard(item: EntryPageItem) {
    Row() {
      Column() {
        Text(item.tag)
          .fontSize(13)
          .fontColor('#ff2563eb')
          .fontWeight(FontWeight.Bold)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#ffeef3ff')
          .borderRadius(6)

        Text(item.title)
          .fontSize(22)
          .fontColor('#ff111827')
          .fontWeight(FontWeight.Bold)
          .margin({ top: 14 })

        Text(item.subtitle)
          .fontSize(14)
          .fontColor('#ff667085')
          .lineHeight(21)
          .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('>')
        .fontSize(26)
        .fontColor('#ff98a2b3')
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#ffffffff')
    .borderRadius(8)
    .border({ width: 1, color: '#ffe5e7eb' })
    .onClick(() => {
      this.openPage(item.route);
    })
  }

  build() {
    Column() {
      Column() {
        Text('T 型报价表调试入口')
          .fontSize(26)
          .fontColor('#ff111827')
          .fontWeight(FontWeight.Bold)

        Text('选择进入性能测试页面或业务样例页面。')
          .fontSize(15)
          .fontColor('#ff667085')
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 28, bottom: 20 })

      Column({ space: 14 }) {
        ForEach(this.pages, (item: EntryPageItem) => {
          this.EntryCard(item);
        }, (item: EntryPageItem) => item.route)
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#fff7f8fa')
  }
}
