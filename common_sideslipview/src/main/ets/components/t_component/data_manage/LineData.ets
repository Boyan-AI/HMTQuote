export class LineData {
  constructor(value?: number | string, position?: number) {
    this.value = value ?? '';
    this.position = position ?? 0;
  }

  value: number | string;
  fontSize: number | string | Resource = 12;
  color: ResourceColor = $r('app.color.color_992e58ff');
  position: number;
}
