import { ContractTabItem } from './QuoteExampleModels';

/**
 * 合约切换栏。
 *
 * 父页面传入合约项列表，组件不持有切换状态，
 * 业务接入时可在外部通过更新 contractTabs 来切换激活项。
 */
@Component
export struct QuoteContractTabs {
  @Prop contractTabs: ContractTabItem[] = [];
  @Prop darkMode: boolean = false;
  /**
   * 合约点击回调。
   *
   * 父页面在这里切换合约数据，并触发 Canvas 首次绘制定位最新价。
   */
  onContractClick: (code: string) => void = (_code: string) => {};

  private brand(): string {
    return this.darkMode ? '#ff527dff' : '#ff2e58ff';
  }

  private inactiveText(): string {
    return this.darkMode ? '#99ffffff' : '#99000000';
  }

  private activeChipBg(): string {
    return this.darkMode ? '#332e58ff' : '#1a2e58ff';
  }

  private inactiveChipBg(): string {
    return this.darkMode ? '#0fffffff' : '#0a000000';
  }

  private bgColor(): string {
    return this.darkMode ? '#ff1c1c1c' : '#ffffffff';
  }

  private dividerColor(): string {
    return this.darkMode ? '#14ffffff' : '#0a000000';
  }

  build() {
    List({ space: 8 }) {
      ForEach(this.contractTabs, (item: ContractTabItem) => {
        ListItem() {
          Row() {
            Text(item.code)
              .fontSize(15)
              .fontWeight(item.active ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(item.active ? this.brand() : this.inactiveText())
            if (item.badge.length > 0) {
              Text(item.badge)
                .fontSize(11)
                .fontColor('#ffffffff')
                .backgroundColor('#ffbf864d')
                .borderRadius(3)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .margin({ left: 6 })
            }
          }
          .alignItems(VerticalAlign.Center)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(item.active ? this.activeChipBg() : this.inactiveChipBg())
          .borderRadius(4)
          .onClick(() => {
            this.onContractClick(item.code);
          })
        }
      }, (item: ContractTabItem) => `${item.code}_${item.active}`)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.bgColor())
    .borderWidth({ top: 0.5, bottom: 0.5 })
    .borderColor(this.dividerColor())
  }
}
