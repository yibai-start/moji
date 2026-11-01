import { common } from '@kit.AbilityKit';
import { Tag } from '../model/Models';
import { TagChip } from './TagChip';
import { ImageService } from '../service/ImageService';

type NoteSaveHandler = (id: number, title: string, content: string, tagIds: number[],
  images: string[]) => Promise<number>;

@Component
export struct NoteEditor {
  @Prop noteId: number = 0;
  @Prop initialTitle: string = '';
  @Prop initialContent: string = '';
  @Prop initialTagIds: number[] = [];
  @Prop initialImages: string[] = [];
  @Prop tags: Tag[] = [];
  @Prop @Watch('handleReset') resetToken: number = 0;
  @Link previewIndex: number;
  onAutoSave: NoteSaveHandler = async (id: number, title: string, content: string, tagIds: number[],
    images: string[]): Promise<number> => {
    return id;
  };
  onSave: NoteSaveHandler = async (id: number, title: string, content: string, tagIds: number[],
    images: string[]): Promise<number> => {
    return id;
  };
  onPickImages: () => Promise<string[]> = async (): Promise<string[]> => {
    return [];
  };
  onRemoveImage: (fileName: string) => void = (fileName: string) => {
  };
  onDelete: (id: number) => void = (id: number) => {
  };
  onClose: () => void = () => {
  };

  @State title: string = '';
  @State content: string = '';
  @State tagIds: number[] = [];
  @State images: string[] = [];
  @State picking: boolean = false;
  @State currentId: number = 0;
  @State saveHint: string = '自动保存已开启';
  private timer: number = -1;
  private finished: boolean = false;

  aboutToAppear(): void {
    this.resetFromProps();
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (!this.finished) {
      this.performAutoSave();
    }
  }

  handleReset(): void {
    this.resetFromProps();
  }

  private resetFromProps(): void {
    this.title = this.initialTitle;
    this.content = this.initialContent;
    this.tagIds = this.initialTagIds.slice();
    this.images = this.initialImages.slice();
    this.currentId = this.noteId;
    this.finished = false;
    this.previewIndex = -1;
    this.saveHint = '自动保存已开启';
  }

  private scheduleAutoSave(): void {
    this.saveHint = '正在保存…';
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.performAutoSave();
    }, 900);
  }

  private async performAutoSave(): Promise<void> {
    if (this.finished) {
      return;
    }
    if (this.title.trim().length === 0 && this.content.trim().length === 0 && this.images.length === 0) {
      this.saveHint = '自动保存已开启';
      return;
    }
    try {
      this.currentId = await this.onAutoSave(this.currentId, this.title, this.content, this.tagIds, this.images);
      this.saveHint = '已自动保存';
    } catch (err) {
      this.saveHint = '保存失败';
    }
  }

  private async commit(): Promise<void> {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    try {
      this.currentId = await this.onSave(this.currentId, this.title, this.content, this.tagIds, this.images);
      this.finished = true;
      this.onClose();
    } catch (err) {
      this.saveHint = '保存失败，请重试';
    }
  }

  private async closeWithSave(): Promise<void> {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (this.title.trim().length > 0 || this.content.trim().length > 0 || this.images.length > 0) {
      try {
        this.currentId = await this.onAutoSave(this.currentId, this.title, this.content, this.tagIds, this.images);
      } catch (err) {
        this.saveHint = '保存失败';
      }
    }
    this.finished = true;
    this.onClose();
  }

  private confirmDelete(): void {
    if (this.currentId <= 0) {
      this.finished = true;
      this.onDelete(0);
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除笔记',
      message: '删除后无法恢复，确定要删除这条笔记吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.finished = true;
          this.onDelete(this.currentId);
        }
      }
    });
  }

  private toggleTag(tagId: number): void {
    const next: number[] = [];
    let exists: boolean = false;
    for (const id of this.tagIds) {
      if (id === tagId) {
        exists = true;
      } else {
        next.push(id);
      }
    }
    if (!exists) {
      next.push(tagId);
    }
    this.tagIds = next;
    this.scheduleAutoSave();
  }

  private isTagSelected(tagId: number): boolean {
    return this.tagIds.indexOf(tagId) >= 0;
  }

  private imageUri(fileName: string): string {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return ImageService.displayUri(context, fileName);
  }

  private async addImages(): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      const picked: string[] = await this.onPickImages();
      if (picked.length > 0) {
        this.images = this.images.concat(picked);
        this.saveHint = '正在保存…';
        this.currentId = await this.onAutoSave(this.currentId, this.title, this.content, this.tagIds, this.images);
        this.saveHint = '已自动保存';
      }
    } catch (err) {
      this.saveHint = '图片添加失败';
    }
    this.picking = false;
  }

  private removeImage(index: number): void {
    const removed: string = this.images[index];
    const next: string[] = [];
    for (let i = 0; i < this.images.length; i++) {
      if (i !== index) {
        next.push(this.images[i]);
      }
    }
    this.images = next;
    this.onRemoveImage(removed);
    this.scheduleAutoSave();
  }

  build() {
    Stack() {
      Column() {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(this.currentId > 0 ? '编辑笔记' : '新建笔记')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.saveHint)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('保存')
            .fontSize(13)
            .height(32)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .borderRadius(16)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.commit();
            })
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
            .padding(8)
            .onClick(() => {
              this.closeWithSave();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 14, top: 10, bottom: 10 })

        TextInput({ text: this.title, placeholder: '标题' })
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          .maxLength(120)
          .onChange((value: string) => {
            this.title = value;
            this.scheduleAutoSave();
          })

        Scroll() {
          Row({ space: 8 }) {
            if (this.tags.length === 0) {
              Text('还没有标签，可在「标签」页创建')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            } else {
              ForEach(this.tags, (tag: Tag) => {
                TagChip({
                  tag: tag,
                  selected: this.isTagSelected(tag.id),
                  onTap: () => {
                    this.toggleTag(tag.id);
                  }
                })
              }, (tag: Tag) => `${tag.id}-${tag.name}-${tag.color}`)
            }
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ top: 4, bottom: 8 })

        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.images, (fileName: string, index: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(this.imageUri(fileName))
                  .width(76)
                  .height(76)
                  .borderRadius(12)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.input_bg'))
                Row() {
                  Image($r('app.media.ic_close'))
                    .width(11)
                    .height(11)
                    .fillColor(Color.White)
                }
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor('#99000000')
                .justifyContent(FlexAlign.Center)
                .margin({ top: 4, right: 4 })
                .onClick(() => {
                  this.removeImage(index);
                })
              }
              .onClick(() => {
                this.previewIndex = index;
              })
            }, (fileName: string) => fileName)

            Column({ space: 3 }) {
              Image($r('app.media.ic_plus'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.accent'))
              Text(this.picking ? '处理中…' : '添加图片')
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width(76)
            .height(76)
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.border_soft'), style: BorderStyle.Dashed })
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.addImages();
            })
          }
          .padding({ left: 16, right: 16, top: 2, bottom: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ bottom: 8 })

        TextArea({ text: this.content, placeholder: '开始书写…' })
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .lineHeight(24)
          .backgroundColor(Color.Transparent)
          .padding({ left: 16, right: 16, top: 4, bottom: 12 })
          .layoutWeight(1)
          .maxLength(100000)
          .onChange((value: string) => {
            this.content = value;
            this.scheduleAutoSave();
          })

        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })

        Row({ space: 6 }) {
          Image($r('app.media.ic_trash'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.danger'))
          Text('删除笔记')
            .fontSize(13)
            .fontColor($r('app.color.danger'))
          Blank()
          Text(`${this.content.length} 字`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 16 })
        .onClick(() => {
          this.confirmDelete();
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))

      if (this.previewIndex >= 0) {
        this.imagePreview()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  imagePreview() {
    Column() {
      Row({ space: 8 }) {
        Text(`${this.previewIndex + 1} / ${this.images.length}`)
          .fontSize(13)
          .fontColor(Color.White)
        Blank()
        Image($r('app.media.ic_close'))
          .width(20)
          .height(20)
          .fillColor(Color.White)
          .padding(8)
      }
      .width('100%')
      .padding({ left: 20, right: 14, top: 12, bottom: 6 })

      Swiper() {
        ForEach(this.images, (fileName: string) => {
          Image(this.imageUri(fileName))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        }, (fileName: string) => fileName)
      }
      .index(this.previewIndex < 0 ? 0 : this.previewIndex)
      .loop(false)
      .indicator(this.images.length > 1)
      .layoutWeight(1)
      .onChange((index: number) => {
        this.previewIndex = index;
      })

      Text('轻触任意处关闭')
        .fontSize(11)
        .fontColor('#99FFFFFF')
        .margin({ top: 8, bottom: 22 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0000000')
    .onClick(() => {
      this.previewIndex = -1;
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
  }
}
