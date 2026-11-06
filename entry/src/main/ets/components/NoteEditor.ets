import { common } from '@kit.AbilityKit';
import { Tag } from '../model/Models';
import { TagChip } from './TagChip';
import { ImageService } from '../service/ImageService';
import { NoteSegment, noteImageNames, notePlainText, parseNoteContent, imageFileName } from '../common/Utils';

type NoteSaveHandler = (id: number, title: string, content: string, tagIds: number[]) => Promise<number>;

const IMAGE_SPAN_HEIGHT: number = 200;

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
  onAutoSave: NoteSaveHandler = async (id: number, title: string, content: string,
    tagIds: number[]): Promise<number> => {
    return id;
  };
  onSave: NoteSaveHandler = async (id: number, title: string, content: string,
    tagIds: number[]): Promise<number> => {
    return id;
  };
  onPickImages: () => Promise<string[]> = async (): Promise<string[]> => {
    return [];
  };
  onDelete: (id: number) => void = (id: number) => {
  };
  onClose: () => void = () => {
  };

  @State title: string = '';
  @State content: string = '';
  @State tagIds: number[] = [];
  @State picking: boolean = false;
  @State currentId: number = 0;
  @State saveHint: string = '自动保存已开启';
  @State previewImages: string[] = [];
  private controller: RichEditorController = new RichEditorController();
  private editorReady: boolean = false;
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
    this.content = this.initialRichContent();
    this.tagIds = this.initialTagIds.slice();
    this.currentId = this.noteId;
    this.finished = false;
    this.previewIndex = -1;
    this.previewImages = [];
    this.saveHint = '自动保存已开启';
    if (this.editorReady) {
      this.buildContent();
    }
  }

  // 旧版本笔记的图片存在 imageFiles 里、正文是纯文本；
  // 打开编辑时把它们转换成正文开头的内嵌图片标记，保存后统一为新格式。
  private initialRichContent(): string {
    let content: string = this.initialContent;
    const legacy: string[] = this.initialImages;
    if (legacy.length > 0 && noteImageNames(content).length === 0) {
      let markers: string = '';
      for (const name of legacy) {
        markers += `%%img:${name}%%\n`;
      }
      content = markers + content;
    }
    return content;
  }

  private buildContent(): void {
    this.controller.deleteSpans();
    const segments: NoteSegment[] = parseNoteContent(this.content);
    for (const seg of segments) {
      if (seg.isImage) {
        this.appendImageSpan(seg.image, undefined);
      } else {
        this.controller.addTextSpan(seg.text);
      }
    }
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
    if (this.title.trim().length === 0 && this.content.trim().length === 0) {
      this.saveHint = '自动保存已开启';
      return;
    }
    try {
      this.currentId = await this.onAutoSave(this.currentId, this.title, this.content, this.tagIds);
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
      this.currentId = await this.onSave(this.currentId, this.title, this.content, this.tagIds);
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
    if (this.title.trim().length > 0 || this.content.trim().length > 0) {
      try {
        this.currentId = await this.onAutoSave(this.currentId, this.title, this.content, this.tagIds);
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

  private appendImageSpan(fileName: string, offset?: number): void {
    const options: RichEditorImageSpanOptions = {
      imageStyle: {
        size: [344, IMAGE_SPAN_HEIGHT],
        objectFit: ImageFit.Contain
      },
      gesture: {
        onClick: () => {
          this.previewImageAt(fileName);
        }
      }
    };
    if (offset !== undefined) {
      options.offset = offset;
    }
    this.controller.addImageSpan(this.imageUri(fileName), options);
  }

  // RichEditor 内部把一个图片 span 按 1 个字符计数，与序列化后的标记长度不同，
  // 所以内部偏移量只能按 span 统计。
  private editorInternalLength(): number {
    let length: number = 0;
    const spans: Array<RichEditorTextSpanResult | RichEditorImageSpanResult> = this.controller.getSpans();
    for (let i = 0; i < spans.length; i++) {
      const text = spans[i] as RichEditorTextSpanResult;
      const image = spans[i] as RichEditorImageSpanResult;
      if (image.valueResourceStr !== undefined || image.valuePixelMap !== undefined) {
        length += 1;
      } else {
        length += text.value.length;
      }
    }
    return length;
  }

  private caretInsertPosition(): number {
    const selection: RichEditorSelection = this.controller.getSelection();
    if (selection.selection[1] >= 0) {
      return selection.selection[1];
    }
    const caret: number = this.controller.getCaretOffset();
    if (caret >= 0) {
      return caret;
    }
    return this.editorInternalLength();
  }

  private serializeContent(): string {
    let out: string = '';
    const spans: Array<RichEditorTextSpanResult | RichEditorImageSpanResult> = this.controller.getSpans();
    for (let i = 0; i < spans.length; i++) {
      const span = spans[i];
      const image = span as RichEditorImageSpanResult;
      if (image.valueResourceStr !== undefined && typeof image.valueResourceStr === 'string'
        && image.valueResourceStr.length > 0) {
        out += `%%img:${imageFileName(image.valueResourceStr)}%%`;
        continue;
      }
      const text = span as RichEditorTextSpanResult;
      out += text.value;
    }
    return out;
  }

  private previewImageAt(fileName: string): void {
    const images: string[] = noteImageNames(this.content);
    const index: number = images.indexOf(fileName);
    if (index >= 0) {
      this.previewImages = images;
      this.previewIndex = index;
    }
  }

  private async insertImages(): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      const picked: string[] = await this.onPickImages();
      if (picked.length > 0) {
        let offset: number = this.caretInsertPosition();
        for (const name of picked) {
          this.appendImageSpan(name, offset);
          offset += 1;
        }
        this.controller.setCaretOffset(offset);
        this.content = this.serializeContent();
        this.scheduleAutoSave();
      }
    } catch (err) {
      this.saveHint = '图片添加失败';
    }
    this.picking = false;
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

        RichEditor({ controller: this.controller })
          .backgroundColor(Color.Transparent)
          .padding({ left: 16, right: 16, top: 4, bottom: 12 })
          .layoutWeight(1)
          .placeholder('开始书写…', { fontColor: $r('app.color.text_tertiary') })
          .onReady(() => {
            this.editorReady = true;
            this.controller.setTypingStyle({
              fontSize: 15,
              fontColor: $r('app.color.text_primary'),
              lineHeight: 24
            });
            this.buildContent();
          })
          .onDidChange(() => {
            if (!this.editorReady) {
              return;
            }
            this.content = this.serializeContent();
            this.scheduleAutoSave();
          })

        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })

        Row({ space: 14 }) {
          Row({ space: 5 }) {
            Image($r('app.media.ic_image'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.accent'))
            Text(this.picking ? '处理中…' : '插入图片')
              .fontSize(13)
              .fontColor($r('app.color.accent'))
          }
          .onClick(() => {
            this.insertImages();
          })

          Row({ space: 5 }) {
            Image($r('app.media.ic_trash'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.danger'))
            Text('删除笔记')
              .fontSize(13)
              .fontColor($r('app.color.danger'))
          }
          .onClick(() => {
            this.confirmDelete();
          })

          Blank()

          Text(`${notePlainText(this.content).length} 字`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 16 })
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
        Text(`${this.previewIndex + 1} / ${this.previewImages.length}`)
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
        ForEach(this.previewImages, (fileName: string) => {
          Image(this.imageUri(fileName))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        }, (fileName: string) => fileName)
      }
      .index(this.previewIndex < 0 ? 0 : this.previewIndex)
      .loop(false)
      .indicator(this.previewImages.length > 1)
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
