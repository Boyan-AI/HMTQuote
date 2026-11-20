import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { DataView } from '../main/ets/components/t_component/data_manage/DataView';
import { ListItemData } from '../main/ets/components/t_component/data_manage/ListItemData';
import { RowData } from '../main/ets/components/t_component/data_manage/RowData';
import { QuoteTableCellDelta, QuoteTableDeltaAdapter } from '../main/ets/components/t_component/canvas/QuoteTableDeltaAdapter';
import { TCanvasDataAdapter } from '../main/ets/components/t_component/canvas/TCanvasDataAdapter';
import { TCanvasScrollRelay } from '../main/ets/components/t_component/canvas/TCanvasScrollRelay';
import { TCanvasTapGuard } from '../main/ets/components/t_component/canvas/TCanvasTapGuard';
import { LegacyGestureClickGate } from '../main/ets/components/t_component/legacy/LegacyGestureClickGate';
import { DATA_POS } from '../main/ets/components/t_component/util/Constant';
import { QuoteTableThemeTokens } from '../main/ets/components/t_component/canvas/QuoteTableThemeTokens';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    // 验证未定制时仍使用明暗各自的默认排序颜色。
    it('defaultSortColorFollowsTheme', 0, () => {
      let baseline = QuoteTableThemeTokens.light();
      expect(baseline.resolve(false).sortActiveColor).assertEqual('#ff2e58ff');
      expect(baseline.resolve(true).sortActiveColor).assertEqual('#ff527dff');
    });
    // 验证暗色首次解析、反复切换及输出修改均不会丢失品牌色或污染基线。
    it('brandSortColorSurvivesThemeSwitches', 0, () => {
      let baseline = QuoteTableThemeTokens.light();
      baseline.sortActiveColor = '#ffe93030';
      let dark = baseline.resolve(true);
      expect(dark.sortActiveColor).assertEqual('#ffe93030');
      expect(dark.canvasBackgroundColor).assertEqual('#ff1c1c1c');
      expect(dark.headerTextColor).assertEqual('#66ffffff');
      expect(dark.sortInactiveColor).assertEqual('#ff3b3b3b');
      dark.sortActiveColor = '#ff000000';
      let light = baseline.resolve(false);
      expect(light.sortActiveColor).assertEqual('#ffe93030');
      expect(light.canvasBackgroundColor).assertEqual('#ffffffff');
      light.sortActiveColor = '#ffffffff';
      expect(baseline.resolve(true).sortActiveColor).assertEqual('#ffe93030');
      expect(baseline.sortActiveColor).assertEqual('#ffe93030');
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    it('setStrikeAscendingReordersRowsAndRefreshesLinePosition', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(3, 0);
      dataView.data[0] = rowWithStrike('100');
      dataView.data[1] = rowWithStrike('90');
      dataView.data[2] = rowWithStrike('110');
      dataView.SetLineData('95');

      dataView.SetStrikeAscending(true);

      expect(`${dataView.data[0].centerData.text}`).assertEqual('90');
      expect(`${dataView.data[1].centerData.text}`).assertEqual('100');
      expect(`${dataView.data[2].centerData.text}`).assertEqual('110');
      expect(dataView.line.position).assertEqual(0);

      dataView.SetStrikeAscending(false);

      expect(`${dataView.data[0].centerData.text}`).assertEqual('110');
      expect(`${dataView.data[1].centerData.text}`).assertEqual('100');
      expect(`${dataView.data[2].centerData.text}`).assertEqual('90');
      expect(dataView.line.position).assertEqual(1);
    });
    it('setStrikeAscendingStateRefreshesLinePositionWithoutReorderingRows', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(3, 0);
      dataView.data[0] = rowWithStrike('110');
      dataView.data[1] = rowWithStrike('100');
      dataView.data[2] = rowWithStrike('90');
      dataView.SetLineData('95');

      dataView.SetStrikeAscendingState(false);

      expect(`${dataView.data[0].centerData.text}`).assertEqual('110');
      expect(`${dataView.data[1].centerData.text}`).assertEqual('100');
      expect(`${dataView.data[2].centerData.text}`).assertEqual('90');
      expect(dataView.line.position).assertEqual(1);
    });
    it('updateByItemRejectsOutOfRangeCoordinates', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(1, 1);

      expect(dataView.updateByItem(DATA_POS.LEFT, -1, 0, '1.00')).assertEqual(false);
      expect(dataView.updateByItem(DATA_POS.LEFT, 0, -1, '1.00')).assertEqual(false);
      expect(dataView.updateByItem(DATA_POS.LEFT, 1, 0, '1.00')).assertEqual(false);
      expect(dataView.updateByItem(DATA_POS.LEFT, 0, 1, '1.00')).assertEqual(false);
      expect(dataView.updateByItem(DATA_POS.CENTER, 0, 0, '100')).assertEqual(false);
    });
    it('applyCellDeltaRejectsMissingRows', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(2, 1);
      dataView.data = [];

      expect(QuoteTableDeltaAdapter.applyCellDelta(dataView,
        new QuoteTableCellDelta(0, DATA_POS.CENTER, 0, '100'))).assertEqual(false);
      expect(QuoteTableDeltaAdapter.applyCellDelta(dataView,
        new QuoteTableCellDelta(0, DATA_POS.LEFT, 0, '1.00'))).assertEqual(false);
    });
    it('setLineDataHidesLineForInvalidLatestPrice', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(1, 0);
      dataView.data[0] = rowWithStrike('100');

      dataView.SetLineData('');

      expect(dataView.line.position).assertEqual(-1);
    });
    it('centerStrikeDeltaRefreshesPendingLatestPricePosition', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(2, 0);
      dataView.SetLineData('105');

      QuoteTableDeltaAdapter.applyCellDelta(dataView, new QuoteTableCellDelta(0, DATA_POS.CENTER, 0, '100'));
      QuoteTableDeltaAdapter.applyCellDelta(dataView, new QuoteTableCellDelta(1, DATA_POS.CENTER, 0, '110'));

      expect(dataView.line.position).assertEqual(0);
    });
    it('strikeSortIgnoresInvalidStrikeRowsWhenRefreshingLinePosition', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(3, 0);
      dataView.data[0] = rowWithStrike('100');
      dataView.data[1] = rowWithStrike('');
      dataView.data[2] = rowWithStrike('110');
      dataView.SetLineData('105');

      dataView.SetStrikeAscending(true);

      expect(dataView.line.position).assertEqual(0);
      expect(`${dataView.data[2].centerData.text}`).assertEqual('');
    });
    it('canvasAdapterDisplaysEmptyValuesAsPlaceholder', 0, () => {
      let dataView = new DataView();
      let adapter = new TCanvasDataAdapter(dataView);

      expect(adapter.displayText(null)).assertEqual('--');
      expect(adapter.displayText(undefined)).assertEqual('--');
      expect(adapter.displayText('')).assertEqual('--');
      expect(adapter.displayText('0')).assertEqual('0');
    });
    it('missingCanvasItemFallsBackToThemeColor', 0, () => {
      let dataView = new DataView();
      dataView.createDefaultData(1, 0);
      dataView.data = [];
      let adapter = new TCanvasDataAdapter(dataView);

      expect(`${adapter.centerItem(0).fontColor}`).assertEqual('');
    });
    it('verticalScrollRelayReturnsRemainWhenCanvasHitsEdges', 0, () => {
      let topResult = TCanvasScrollRelay.applyOffset(10, -25, 120);
      expect(topResult.nextOffset).assertEqual(0);
      expect(topResult.remainOffset).assertEqual(-15);

      let middleResult = TCanvasScrollRelay.applyOffset(10, 40, 120);
      expect(middleResult.nextOffset).assertEqual(50);
      expect(middleResult.remainOffset).assertEqual(0);

      let bottomResult = TCanvasScrollRelay.applyOffset(100, 40, 120);
      expect(bottomResult.nextOffset).assertEqual(120);
      expect(bottomResult.remainOffset).assertEqual(20);
    });
    it('legacyGestureClickGateSuppressesOnlyTapAfterLongPress', 0, () => {
      let gate = new LegacyGestureClickGate();

      expect(gate.shouldAcceptTap(1000)).assertEqual(true);

      gate.markLongPressHandled(1000);

      expect(gate.shouldAcceptTap(1100)).assertEqual(false);
      expect(gate.shouldAcceptTap(1101)).assertEqual(true);
    });
    it('legacyGestureClickGateDoesNotSuppressLateTapAfterLongPress', 0, () => {
      let gate = new LegacyGestureClickGate();

      gate.markLongPressHandled(1000);

      expect(gate.shouldAcceptTap(1400)).assertEqual(true);
    });
    it('canvasTapGuardAcceptsShortStationaryTap', 0, () => {
      let guard = new TCanvasTapGuard();

      guard.handleDown(20, 30, 1000);
      guard.handleUp(1200);

      expect(guard.shouldAcceptClick(1201)).assertEqual(true);
    });
    it('canvasTapGuardRejectsLongPressClick', 0, () => {
      let guard = new TCanvasTapGuard();

      guard.handleDown(20, 30, 1000);
      guard.handleUp(1600);

      expect(guard.shouldAcceptClick(1601)).assertEqual(false);
    });
    it('canvasTapGuardRejectsMovedTouchClick', 0, () => {
      let guard = new TCanvasTapGuard();

      guard.handleDown(20, 30, 1000);
      guard.handleMove(40, 30);
      guard.handleUp(1100);

      expect(guard.shouldAcceptClick(1101)).assertEqual(false);
    });
    it('canvasTapGuardRejectsCanceledTouchClick', 0, () => {
      let guard = new TCanvasTapGuard();

      guard.handleDown(20, 30, 1000);
      guard.handleCancel();

      expect(guard.shouldAcceptClick(1100)).assertEqual(false);
    });
  });
}

function rowWithStrike(strike: string): RowData {
  let row = new RowData();
  row.centerData = new ListItemData(strike);
  return row;
}
