export class ListItemData {
  text: number | string = '--';
  // 主值下方的副文本，空串表示不显示；用于展示数量等附属信息（如 “x35”）。
  subText: string = '';
  fontSize: number | string | Resource;
  fontColor: ResourceColor;
  icon?: PixelMap | ResourceStr | DrawableDescriptor;

  constructor(text: number | string = '--', fontSize: number | string | Resource = 15,
    fontColor: ResourceColor = $r('app.color.elements_text_primary_02')) {
    this.text = text;
    this.fontSize = fontSize;
    this.fontColor = fontColor;
  }
}
