import { Note, Tag } from '../model/Models';
import { TagChip } from './TagChip';
import { excerpt, formatRelative } from '../common/Utils';

@Component
export struct NoteCard {
  @Prop note: Note = new Note();
  @Prop active: boolean = false;
  onTap: () => void = () => {
  };
  onTogglePin: () => void = () => {
  };

  private displayTitle(): string {
    return this.note.title.trim().length === 0 ? '无标题笔记' : this.note.title;
  }

  private displayExcerpt(): string {
    const text: string = this.note.content.trim();
    if (text.length === 0) {
      return this.note.imageFiles.length > 0 ? `${this.note.imageFiles.length} 张图片` : '空白笔记';
    }
    return excerpt(text, 90);
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.displayTitle())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Image($r('app.media.ic_pin'))
          .width(15)
          .height(15)
          .fillColor(this.note.pinned ? $r('app.color.accent') : $r('app.color.text_tertiary'))
          .opacity(this.note.pinned ? 1 : 0.5)
          .onClick(() => {
            this.onTogglePin();
          })
      }

      Text(this.displayExcerpt())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(19)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 6 }) {
        if (this.note.tags.length > 0) {
          ForEach(this.note.tags.slice(0, 3), (tag: Tag) => {
            TagChip({
              tag: tag,
              compact: true,
              selected: false,
              onTap: () => {
                this.onTap();
              }
            })
          }, (tag: Tag) => `${this.note.id}-${tag.id}-${tag.name}-${tag.color}`)
        }
        if (this.note.imageFiles.length > 0) {
          Row({ space: 3 }) {
            Image($r('app.media.ic_image'))
              .width(12)
              .height(12)
              .fillColor($r('app.color.text_tertiary'))
            Text(`${this.note.imageFiles.length}`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
        Blank()
        Text(formatRelative(this.note.updatedAt))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.active ? $r('app.color.accent_soft') : $r('app.color.bg_card'))
    .borderRadius(16)
    .border({ width: 1, color: this.active ? $r('app.color.accent') : $r('app.color.border_soft') })
    .onClick(() => {
      this.onTap();
    })
  }
}
