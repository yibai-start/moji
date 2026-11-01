import { Tag, Todo } from '../model/Models';
import { formatDue, isOverdue, withAlpha } from '../common/Utils';
import { PRIORITY_COLORS } from '../common/Constants';

@Component
export struct TodoRow {
  @Prop todo: Todo = new Todo();
  onToggle: () => void = () => {
  };
  onTap: () => void = () => {
  };

  private dueColor(): ResourceColor {
    return isOverdue(this.todo.dueAt, this.todo.done) ? $r('app.color.danger') : $r('app.color.text_tertiary');
  }

  private dueText(): string {
    if (this.todo.done && this.todo.dueAt > 0) {
      return formatDue(this.todo.dueAt);
    }
    if (isOverdue(this.todo.dueAt, this.todo.done)) {
      return `已逾期 · ${formatDue(this.todo.dueAt)}`;
    }
    return formatDue(this.todo.dueAt);
  }

  build() {
    Row({ space: 12 }) {
      Stack() {
        Row()
          .width(22)
          .height(22)
          .borderRadius(11)
          .border({
            width: 1.5,
            color: this.todo.done ? $r('app.color.success') : PRIORITY_COLORS[this.todo.priority]
          })
          .backgroundColor(this.todo.done ? withAlpha('#30A46C', '22') : Color.Transparent)
        if (this.todo.done) {
          Image($r('app.media.ic_check'))
            .width(14)
            .height(14)
            .fillColor($r('app.color.success'))
        }
      }
      .width(24)
      .height(24)
      .onClick(() => {
        this.onToggle();
      })

      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(this.todo.title.trim().length === 0 ? '未命名待办' : this.todo.title)
            .fontSize(15)
            .fontWeight(this.todo.done ? FontWeight.Normal : FontWeight.Medium)
            .fontColor(this.todo.done ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
            .decoration({
              type: this.todo.done ? TextDecorationType.LineThrough : TextDecorationType.None,
              color: $r('app.color.text_tertiary')
            })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Image($r('app.media.ic_flag'))
            .width(12)
            .height(12)
            .fillColor(PRIORITY_COLORS[this.todo.priority])
            .opacity(this.todo.priority === 0 ? 0.35 : 0.9)
        }
        .width('100%')

        if (this.todo.dueAt > 0 || this.todo.tags.length > 0) {
          Row({ space: 8 }) {
            if (this.todo.dueAt > 0) {
              Row({ space: 3 }) {
                Image($r('app.media.ic_clock'))
                  .width(11)
                  .height(11)
                  .fillColor(this.dueColor())
                Text(this.dueText())
                  .fontSize(11)
                  .fontColor(this.dueColor())
              }
            }
            Row({ space: 4 }) {
              ForEach(this.todo.tags.slice(0, 3), (tag: Tag) => {
                Row()
                  .width(6)
                  .height(6)
                  .borderRadius(3)
                  .backgroundColor(tag.color)
              }, (tag: Tag) => `${this.todo.id}-${tag.id}-${tag.color}`)
            }
          }
          .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.border_soft') })
    .onClick(() => {
      this.onTap();
    })
  }
}
