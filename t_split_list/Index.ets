// TSplitList T 型分区列表 UI 组件库对外入口。
// 后续只支持 Canvas 模式：TCanvasComponent 通过普通数据对象 + 显式 revision 驱动重绘。
// 共享：data_manage/ 数据模型、GestureMonitor、util/Constant 枚举与尺寸。

// ===== 共享数据与工具 =====
export { DATA_POS } from './src/main/ets/components/t_component/util/Constant';
export { DataView } from './src/main/ets/components/t_component/data_manage/DataView';
export { HeaderConfig, HeaderItem } from './src/main/ets/components/t_component/data_manage/TableHeaderConfigModel';
export { RowData } from './src/main/ets/components/t_component/data_manage/RowData';
export { ListItemData } from './src/main/ets/components/t_component/data_manage/ListItemData';
export { GestureMonitor } from './src/main/ets/components/t_component/GestureMonitor';

// ===== Canvas 模式 =====
export { TCanvasComponent } from './src/main/ets/components/t_component/canvas/TCanvasComponent';
export { QuoteTablePerfConfig } from './src/main/ets/components/t_component/canvas/QuoteTablePerfConfig';
export { QuoteTableThemeTokens } from './src/main/ets/components/t_component/canvas/QuoteTableThemeTokens';
export { QuoteTableCellDelta, QuoteTableDeltaAdapter } from './src/main/ets/components/t_component/canvas/QuoteTableDeltaAdapter';
export { TCanvasScrollRelay, TCanvasScrollRelayResult } from './src/main/ets/components/t_component/canvas/TCanvasScrollRelay';
