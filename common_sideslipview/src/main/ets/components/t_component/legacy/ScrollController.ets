export class ScrollController {
  constructor(rows: number) {
    this.Update(rows);
  }

  Update(rows: number) {
    for (let index = 0; index < rows; index++) {
      this.leftItemScroller.push(new Scroller());
      this.rightItemScroller.push(new Scroller());
    }
  }

  centerScroller: Scroller = new Scroller();
  leftItemScroller: Scroller[] = [];
  rightItemScroller: Scroller[] = [];
  leftHeadScroller: Scroller = new Scroller();
  rightHeadScroller: Scroller = new Scroller();

  LeftHorizontal(offset: number, index: number, isHead: boolean) {
    // 左侧横向滑动触发右侧横向滑动
    for (let id = 0; id < this.leftItemScroller.length; id++) {
      if (id !== index) {
        this.leftItemScroller[id].scrollBy(offset, 0);
      }

      this.rightItemScroller[id].scrollBy(-offset, 0);
    }
    if (!isHead) {
      this.leftHeadScroller.scrollBy(offset, 0)
    }
    this.rightHeadScroller.scrollBy(-offset, 0);
  }

  RightHorizontal(offset: number, index: number, isHead: boolean) {
    // 右侧横向滑动触发左侧横向滑动
    for (let id = 0; id < this.rightItemScroller.length; id++) {
      this.leftItemScroller[id].scrollBy(-offset, 0);
      if (id !== index) {
        this.rightItemScroller[id].scrollBy(offset, 0);
      }
    }
    this.leftHeadScroller.scrollBy(-offset, 0);
    if (!isHead) {
      this.rightHeadScroller.scrollBy(offset, 0);
    }
  }

  // 纵向滑动触发所有横向list的偏移量保持一致
  V2H(leftTotalXOffset: number, rightTotalXOffset: number) {
    for (let id = 0; id < this.leftItemScroller.length; id++) {
      if (Number.isNaN(leftTotalXOffset)) {
        this.leftItemScroller[id].scrollEdge(Edge.End)
      } else {
        this.leftItemScroller[id].scrollTo({
          xOffset: leftTotalXOffset,
          yOffset: 0
        });
      }

      if (rightTotalXOffset == 0) {
        this.rightItemScroller[id].scrollEdge(Edge.Start)
      } else {
        this.rightItemScroller[id].scrollTo({
          xOffset: rightTotalXOffset,
          yOffset: 0
        });
      }
    }

    if (Number.isNaN(leftTotalXOffset)) {
      this.leftHeadScroller.scrollEdge(Edge.End)
    } else {
      this.leftHeadScroller.scrollTo({
        xOffset: leftTotalXOffset,
        yOffset: 0
      });
    }

    if (rightTotalXOffset == 0) {
      this.rightHeadScroller.scrollEdge(Edge.Start)
    } else {
      this.rightHeadScroller.scrollTo({
        xOffset: rightTotalXOffset,
        yOffset: 0
      });
    }
  }
}