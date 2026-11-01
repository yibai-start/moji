@Entry
@Component
struct TodoWidget {
  @LocalStorageProp('todayLabel') todayLabel: string = '';
  @LocalStorageProp('doneCount') doneCount: number = 0;
  @LocalStorageProp('totalCount') totalCount: number = 0;
  @LocalStorageProp('item1') item1: string = '';
  @LocalStorageProp('item2') item2: string = '';
  @LocalStorageProp('item3') item3: string = '';
  @LocalStorageProp('emptyText') emptyText: string = '今天没有待办';

  private progressWidth(): string {
    if (this.totalCount <= 0) {
      return '0%';
    }
    return `${Math.round(this.doneCount * 100 / this.totalCount)}%`;
  }

  @Builder
  itemRow(text: string) {
    Row({ space: 9 }) {
      Row()
        .width(7)
        .height(7)
        .borderRadius(4)
        .backgroundColor($r('app.color.widget_accent'))
      Text(text)
        .fontSize(13)
        .fontColor($r('app.color.widget_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(26)
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 2 }) {
          Text('今日待办')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_text'))
          Text(this.todayLabel)
            .fontSize(10)
            .fontColor($r('app.color.widget_sub'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(`${this.doneCount} / ${this.totalCount}`)
          .fontSize(12)
          .fontColor($r('app.color.widget_accent'))
      }
      .width('100%')

      Row() {
        Row()
          .width(this.progressWidth())
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.widget_accent'))
      }
      .width('100%')
      .height(4)
      .borderRadius(2)
      .backgroundColor($r('app.color.widget_track'))

      if (this.item1.length > 0) {
        this.itemRow(this.item1)
      }
      if (this.item2.length > 0) {
        this.itemRow(this.item2)
      }
      if (this.item3.length > 0) {
        this.itemRow(this.item3)
      }
      if (this.item1.length === 0) {
        Text(this.emptyText)
          .fontSize(12)
          .fontColor($r('app.color.widget_sub'))
      }

      Blank()

      Row() {
        Text('墨记')
          .fontSize(9)
          .fontColor($r('app.color.widget_sub'))
        Blank()
        Text('轻触打开')
          .fontSize(9)
          .fontColor($r('app.color.widget_sub'))
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.widget_bg'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        bundleName: 'com.mojian.notes',
        abilityName: 'EntryAbility'
      });
    })
  }
}
