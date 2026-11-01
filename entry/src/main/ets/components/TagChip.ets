import { Tag } from '../model/Models';
import { withAlpha } from '../common/Utils';

@Component
export struct TagChip {
  @Prop tag: Tag = new Tag();
  @Prop selected: boolean = false;
  @Prop compact: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row({ space: 5 }) {
      Row()
        .width(this.compact ? 5 : 6)
        .height(this.compact ? 5 : 6)
        .borderRadius(3)
        .backgroundColor(this.selected ? this.tag.color : $r('app.color.text_tertiary'))
      Text(this.tag.name)
        .fontSize(this.compact ? 11 : 12)
        .fontColor(this.selected ? this.tag.color : $r('app.color.text_secondary'))
        .maxLines(1)
    }
    .padding({
      left: this.compact ? 8 : 10,
      right: this.compact ? 8 : 10,
      top: this.compact ? 3 : 5,
      bottom: this.compact ? 3 : 5
    })
    .backgroundColor(this.selected ? withAlpha(this.tag.color, '22') : $r('app.color.chip_bg'))
    .borderRadius(999)
    .border({ width: 1, color: this.selected ? withAlpha(this.tag.color, '66') : $r('app.color.chip_bg') })
    .onClick(() => {
      this.onTap();
    })
  }
}
