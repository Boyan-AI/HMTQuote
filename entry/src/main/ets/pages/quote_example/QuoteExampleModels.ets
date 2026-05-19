/**
 * 样例页用到的纯数据模型集合。
 *
 * 这些类只承载展示字段，不包含任何 UI 行为，便于在多个 @Component 之间共享。
 */

/**
 * 顶部主导航项。
 */
export class TopNavItem {
  label: string = '';
  active: boolean = false;

  constructor(label: string, active: boolean) {
    this.label = label;
    this.active = active;
  }
}

/**
 * 二级 Tab 项。
 */
export class SubTabItem {
  label: string = '';
  active: boolean = false;

  constructor(label: string, active: boolean) {
    this.label = label;
    this.active = active;
  }
}

/**
 * 合约切换项。
 */
export class ContractTabItem {
  code: string = '';
  badge: string = '';
  active: boolean = false;
