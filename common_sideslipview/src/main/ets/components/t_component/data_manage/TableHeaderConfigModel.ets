export interface HeaderConfig {
  hqData: Array<HeaderItem>
}

export class HeaderItem {
  mobileid: number
  name: string
  isFix?: boolean
  sortable?: boolean
  extDataIds?: Array<number>

  constructor(mobileid: number, name: string, isFix?: boolean, sortable?: boolean, extDataId?: Array<number>) {
    this.mobileid = mobileid
    this.name = name
    this.isFix = isFix
    this.sortable = sortable
    this.extDataIds = extDataId
  }
}
