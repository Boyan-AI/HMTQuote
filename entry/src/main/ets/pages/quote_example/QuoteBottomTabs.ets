import { BottomNavItem } from './QuoteExampleModels';

/**
 * 底部主导航。
 *
 * 父页面传入导航项列表，组件本身不处理点击，
 * 业务接入时可以在 ForEach 内补 onClick 跳转。
 */
@Component
export struct QuoteBottomTabs {
  bottomNavItems: BottomNavItem[] = [];
  @Prop darkMode: boolean = false;

  private brand(): string {
    return this.darkMode ? '#ff527dff' : '#ff2e58ff';
  }

  private textPrimary(): string {
    return this.darkMode ? '#d6ffffff' : '#d6000000';
  }

  private bgColor(): string {
    return this.darkMode ? '#ff1c1c1c' : '#ffffffff';
  }

  private dividerColor(): string {
    return this.darkMode ? '#14ffffff' : '#0a000000';
  }

  build() {
    Row() {
      ForEach(this.bottomNavItems, (item: BottomNavItem) => {
        Column() {
          Image($rawfile(item.icon))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor(item.active ? this.brand() : this.textPrimary())
            .draggable(false)
          Text(item.label)
            .fontSize(11)
            .fontColor(item.active ? this.brand() : this.textPrimary())
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }, (item: BottomNavItem) => item.label)
    }
    .height(54)
    .padding({ left: 8, right: 8, top: 6, bottom: 8 })
    .borderWidth({ top: 0.5 })
    .borderColor(this.dividerColor())
    .backgroundColor(this.bgColor())
  }
}
