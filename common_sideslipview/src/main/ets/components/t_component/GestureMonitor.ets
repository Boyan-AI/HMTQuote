import { DATA_POS } from "./util/Constant";

export class GestureMonitor {
  onClick: (index: number, flag: DATA_POS, value: string) => void =
    (index, data_pos, value) => {
      console.info(`onClick_${DATA_POS[data_pos]}_${index}_${value}`)
    };
  onLongPress: (index: number, flag: DATA_POS, value: string) => void =
    (index, data_pos, value) => {
      console.info(`onLongPress_${DATA_POS[data_pos]}_${index}_${value}`)
    };
  onScroll: () => void = () => {
  };
  onScrollStop: () => void = () => {
  };
  onScrollVisibleContentChange: (start: VisibleListContentInfo, end: VisibleListContentInfo) => void =
    (start: VisibleListContentInfo, end: VisibleListContentInfo) => {
    };
}
