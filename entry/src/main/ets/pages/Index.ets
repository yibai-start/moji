import { common } from '@kit.AbilityKit';
import { mediaquery } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Database } from '../data/Database';
import { SeedService } from '../data/SeedService';
import { NoteDao } from '../data/NoteDao';
import { TodoDao } from '../data/TodoDao';
import { TagDao } from '../data/TagDao';
import { Note, Tag, Todo } from '../model/Models';
import { TagChip } from '../components/TagChip';
import { NoteCard } from '../components/NoteCard';
import { TodoRow } from '../components/TodoRow';
import { NoteEditor } from '../components/NoteEditor';
import { ReminderService } from '../service/ReminderService';
import { WidgetService } from '../service/WidgetService';
import { BackupService } from '../service/BackupService';
import { ImageService } from '../service/ImageService';
import {
  PRIORITY_COLORS,
  PRIORITY_LABELS,
  TAB_NOTES,
  TAB_SETTINGS,
  TAB_TAGS,
  TAB_TODOS,
  TAG_COLORS,
  TODO_FILTER_ACTIVE,
  TODO_FILTER_ALL,
  TODO_FILTER_DONE,
  TODO_FILTER_TODAY,
  WIDE_BREAKPOINT
} from '../common/Constants';
import { formatDue, formatRelative, isSameDay, nowMs, withAlpha } from '../common/Utils';

const DOMAIN: number = 0x0000;
const LOG_TAG: string = 'Mojian';

// 玻璃导航栏悬浮在内容之上，内容区需要自行避让这些高度。
const NAV_BAR_HEIGHT: number = 56;
const NAV_BAR_BOTTOM: number = 12;
const NAV_OVERLAP: number = NAV_BAR_HEIGHT + NAV_BAR_BOTTOM;
const FAB_SIZE: number = 56;
const FAB_GAP: number = 12;

@Entry
@Component
struct Index {
  @State currentTab: number = TAB_NOTES;
  @State notes: Note[] = [];
  @State todos: Todo[] = [];
  @State tags: Tag[] = [];
  @State searchText: string = '';
  @State filterTagId: number = -1;
  @State todoFilter: number = TODO_FILTER_ALL;
  @State isWide: boolean = false;
  @State selectedNoteId: number = -1;
  @State ready: boolean = false;
  @State notificationEnabled: boolean = false;

  @State showSheet: boolean = false;
  @State sheetMode: number = 0;
  @State editorToken: number = 0;

  @State sheetNoteId: number = 0;
  @State sheetNoteTitle: string = '';
  @State sheetNoteContent: string = '';
  @State sheetNoteTagIds: number[] = [];
  @State sheetNoteImages: string[] = [];
  @State previewImages: string[] = [];
  @State previewAt: number = -1;
  @State editorPreviewAt: number = -1;

  @State todoSheetId: number = 0;
  @State todoTitleInput: string = '';
  @State todoDetailInput: string = '';
  @State todoDueInput: number = 0;
  @State todoPriorityInput: number = 1;
  @State todoTagIdsInput: number[] = [];

  @State tagSheetId: number = 0;
  @State tagNameInput: string = '';
  @State tagColorInput: string = TAG_COLORS[0];
  @State newTagName: string = '';
  @State newTagColor: string = TAG_COLORS[0];

  private noteDao: NoteDao = new NoteDao();
  private noteListScroller: ListScroller = new ListScroller();
  private todoDao: TodoDao = new TodoDao();
  private tagDao: TagDao = new TagDao();
  private reminderService: ReminderService = new ReminderService();
  private widgetService: WidgetService = new WidgetService();
  private backupService: BackupService = new BackupService();
  private ctx: common.UIAbilityContext | null = null;
  private tabsController: HdsTabsController = new HdsTabsController();
  private mq: mediaquery.MediaQueryListener = mediaquery.matchMediaSync(`(min-width: ${WIDE_BREAKPOINT}vp)`);
  private mqListener: (result: mediaquery.MediaQueryResult) => void =
    (result: mediaquery.MediaQueryResult) => {
      this.isWide = result.matches;
      if (this.isWide && this.selectedNoteId <= 0 && this.notes.length > 0) {
        this.selectedNoteId = this.notes[0].id;
      }
    };

  aboutToAppear(): void {
    this.ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.isWide = this.mq.matches;
    this.mq.on('change', this.mqListener);
    this.initData();
  }

  aboutToDisappear(): void {
    this.mq.off('change', this.mqListener);
  }

  private context(): common.UIAbilityContext {
    return this.ctx as common.UIAbilityContext;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  private async initData(): Promise<void> {
    try {
      await Database.getInstance().init(this.context());
      await SeedService.seedIfNeeded(this.context());
      await this.reloadAll();
      this.refreshNotificationStatus();
      if (this.isWide && this.notes.length > 0) {
        this.selectedNoteId = this.notes[0].id;
      }
      this.ready = true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, LOG_TAG, 'init failed: %{public}s', e.message);
      this.toast('数据加载失败，请重新打开应用');
    }
  }

  private async reloadAll(): Promise<void> {
    this.notes = await this.noteDao.listAll();
    this.todos = await this.todoDao.listAll();
    this.tags = await this.tagDao.listAll();
    this.widgetService.publish(this.context(), this.todos);
  }

  private async loadNotes(): Promise<void> {
    this.notes = await this.noteDao.listAll();
  }

  private async loadTodos(): Promise<void> {
    this.todos = await this.todoDao.listAll();
    this.widgetService.publish(this.context(), this.todos);
  }

  private async loadTags(): Promise<void> {
    this.tags = await this.tagDao.listAll();
  }

  private async refreshNotificationStatus(): Promise<void> {
    try {
      this.notificationEnabled = await notificationManager.isNotificationEnabled();
    } catch (err) {
      this.notificationEnabled = false;
    }
  }

  private filteredNotes(): Note[] {
    let result: Note[] = this.notes;
    if (this.filterTagId > 0) {
      result = result.filter((note: Note) => note.tags.some((tag: Tag) => tag.id === this.filterTagId));
    }
    const keyword: string = this.searchText.trim().toLowerCase();
    if (keyword.length > 0) {
      result = result.filter((note: Note) =>
      note.title.toLowerCase().includes(keyword) || note.content.toLowerCase().includes(keyword));
    }
    return result;
  }

  private filteredTodos(): Todo[] {
    const now: number = nowMs();
    let result: Todo[] = this.todos;
    if (this.todoFilter === TODO_FILTER_ACTIVE) {
      result = result.filter((todo: Todo) => !todo.done);
    } else if (this.todoFilter === TODO_FILTER_DONE) {
      result = result.filter((todo: Todo) => todo.done);
    } else if (this.todoFilter === TODO_FILTER_TODAY) {
      result = result.filter((todo: Todo) => !todo.done && todo.dueAt > 0 &&
        (isSameDay(todo.dueAt, now) || todo.dueAt < now));
    }
    return result;
  }

  private todayTotal(): number {
    const now: number = nowMs();
    return this.todos.filter((todo: Todo) => todo.dueAt > 0 && isSameDay(todo.dueAt, now)).length;
  }

  private todayDone(): number {
    const now: number = nowMs();
    return this.todos.filter((todo: Todo) => todo.dueAt > 0 && isSameDay(todo.dueAt, now) && todo.done).length;
  }

  private todayPercent(): number {
    const total: number = this.todayTotal();
    if (total === 0) {
      return 0;
    }
    return Math.round(this.todayDone() * 100 / total);
  }

  private pendingTodoCount(): number {
    return this.todos.filter((todo: Todo) => !todo.done).length;
  }

  private todoSubtitle(): string {
    const total: number = this.todayTotal();
    if (total > 0) {
      return `今日完成 ${this.todayDone()} / ${total}`;
    }
    return `${this.pendingTodoCount()} 项待完成`;
  }

  private headerSubtitle(tab: number): string {
    if (tab === TAB_NOTES) {
      return this.notes.length === 0 ? '还没有笔记' : `${this.notes.length} 条笔记 · 右滑置顶 · 左滑删除`;
    }
    if (tab === TAB_TODOS) {
      return this.todoSubtitle();
    }
    if (tab === TAB_TAGS) {
      return `${this.tags.length} 个标签`;
    }
    return '墨记 · 本地优先';
  }

  private selectedNote(): Note {
    const found: Note | undefined = this.notes.find((note: Note) => note.id === this.selectedNoteId);
    return found === undefined ? new Note() : found;
  }

  private hasSelectedNote(): boolean {
    return this.notes.some((note: Note) => note.id === this.selectedNoteId);
  }

  private isTagSelected(tagId: number): boolean {
    return this.sheetNoteTagIds.indexOf(tagId) >= 0;
  }

  private isTodoTagSelected(tagId: number): boolean {
    return this.todoTagIdsInput.indexOf(tagId) >= 0;
  }

  private onAddTap(): void {
    if (this.currentTab === TAB_NOTES) {
      this.openNewNote();
    } else if (this.currentTab === TAB_TODOS) {
      this.openNewTodo();
    } else if (this.currentTab === TAB_TAGS) {
      this.openNewTag();
    }
  }

  private openNewNote(): void {
    this.sheetNoteId = 0;
    this.sheetNoteTitle = '';
    this.sheetNoteContent = '';
    this.sheetNoteTagIds = [];
    this.sheetNoteImages = [];
    this.sheetMode = 1;
    this.editorToken++;
    this.showSheet = true;
  }

  private openExistingNote(note: Note): void {
    this.sheetNoteId = note.id;
    this.sheetNoteTitle = note.title;
    this.sheetNoteContent = note.content;
    this.sheetNoteTagIds = note.tags.map((tag: Tag) => tag.id);
    this.sheetNoteImages = note.imageFiles.slice();
    this.selectedNoteId = note.id;
    this.sheetMode = 1;
    this.editorToken++;
    this.showSheet = true;
  }

  private onNoteTap(note: Note): void {
    if (this.isWide) {
      this.selectedNoteId = note.id;
    } else {
      this.openExistingNote(note);
    }
  }

  private async persistNote(id: number, title: string, content: string, tagIds: number[],
    images: string[]): Promise<number> {
    const existing: Note | undefined = this.notes.find((note: Note) => note.id === id);
    const note: Note = new Note();
    note.id = id;
    note.title = title.trim();
    note.content = content;
    note.imageFiles = images.slice();
    note.pinned = existing === undefined ? false : existing.pinned;
    note.createdAt = existing === undefined ? nowMs() : existing.createdAt;
    note.updatedAt = nowMs();
    const savedId: number = await this.noteDao.save(note, tagIds);
    await this.loadNotes();
    if (!this.notes.some((item: Note) => item.id === this.selectedNoteId)) {
      this.selectedNoteId = savedId;
    }
    return savedId;
  }

  private async saveNoteAndClose(id: number, title: string, content: string, tagIds: number[],
    images: string[]): Promise<number> {
    const savedId: number = await this.persistNote(id, title, content, tagIds, images);
    this.toast('笔记已保存');
    return savedId;
  }

  private async pickImages(): Promise<string[]> {
    try {
      return await ImageService.pick(this.context());
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, LOG_TAG, 'pick image failed: %{public}s', e.message);
      this.toast('图片选择失败，请重试');
      return [];
    }
  }

  private openPreview(images: string[], index: number): void {
    if (images.length === 0) {
      return;
    }
    this.previewImages = images.slice();
    this.previewAt = index;
  }

  private removeImageFile(fileName: string): void {
    try {
      ImageService.remove(this.context(), fileName);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, LOG_TAG, 'remove image failed: %{public}s', e.message);
    }
  }

  private async deleteNoteById(id: number): Promise<void> {
    const existing: Note | undefined = this.notes.find((note: Note) => note.id === id);
    if (id > 0) {
      await this.noteDao.remove(id);
    }
    if (existing !== undefined) {
      ImageService.removeAll(this.context(), existing.imageFiles);
    }
    await this.loadNotes();
    if (!this.notes.some((note: Note) => note.id === this.selectedNoteId)) {
      this.selectedNoteId = this.notes.length > 0 ? this.notes[0].id : -1;
    }
    this.showSheet = false;
    this.toast('笔记已删除');
  }

  private async togglePin(note: Note): Promise<void> {
    await this.noteDao.setPinned(note.id, !note.pinned);
    await this.loadNotes();
  }

  private confirmDeleteNote(note: Note): void {
    if (note.id <= 0) {
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
          this.deleteNoteById(note.id);
        }
      }
    });
  }

  private openNewTodo(): void {
    this.todoSheetId = 0;
    this.todoTitleInput = '';
    this.todoDetailInput = '';
    this.todoDueInput = 0;
    this.todoPriorityInput = 1;
    this.todoTagIdsInput = [];
    this.sheetMode = 2;
    this.showSheet = true;
  }

  private openExistingTodo(todo: Todo): void {
    this.todoSheetId = todo.id;
    this.todoTitleInput = todo.title;
    this.todoDetailInput = todo.detail;
    this.todoDueInput = todo.dueAt;
    this.todoPriorityInput = todo.priority;
    this.todoTagIdsInput = todo.tags.map((tag: Tag) => tag.id);
    this.sheetMode = 2;
    this.showSheet = true;
  }

  private toggleTodoTag(tagId: number): void {
    const next: number[] = [];
    let exists: boolean = false;
    for (const id of this.todoTagIdsInput) {
      if (id === tagId) {
        exists = true;
      } else {
        next.push(id);
      }
    }
    if (!exists) {
      next.push(tagId);
    }
    this.todoTagIdsInput = next;
  }

  private pickDueTime(): void {
    const base: Date = this.todoDueInput > 0 ? new Date(this.todoDueInput) : new Date(nowMs() + 3600000);
    const picked: Date = new Date(base.getTime());
    this.getUIContext().showDatePickerDialog({
      start: new Date(nowMs()),
      end: new Date(nowMs() + 365 * 24 * 3600000),
      selected: base,
      onDateAccept: (value: Date) => {
        picked.setFullYear(value.getFullYear(), value.getMonth(), value.getDate());
        this.getUIContext().showTimePickerDialog({
          selected: base,
          useMilitaryTime: true,
          onAccept: (result: TimePickerResult) => {
            picked.setHours(result.hour, result.minute, 0, 0);
            this.todoDueInput = picked.getTime();
          }
        });
      }
    });
  }

  private async saveTodoSheet(): Promise<void> {
    const title: string = this.todoTitleInput.trim();
    if (title.length === 0) {
      this.toast('请输入待办内容');
      return;
    }
    const existing: Todo | undefined = this.todos.find((todo: Todo) => todo.id === this.todoSheetId);
    const todo: Todo = new Todo();
    todo.id = this.todoSheetId;
    todo.title = title;
    todo.detail = this.todoDetailInput;
    todo.done = existing === undefined ? false : existing.done;
    todo.priority = this.todoPriorityInput;
    todo.dueAt = this.todoDueInput;
    todo.reminderId = existing === undefined ? 0 : existing.reminderId;
    todo.createdAt = existing === undefined ? nowMs() : existing.createdAt;
    todo.updatedAt = nowMs();
    const dueChanged: boolean = existing === undefined || existing.dueAt !== this.todoDueInput;
    if (todo.dueAt > nowMs() && !todo.done) {
      if (dueChanged) {
        const enabled: boolean = await this.reminderService.ensureNotification(this.context());
        if (!enabled) {
          this.toast('未开启通知权限，提醒可能不会展示');
        }
        todo.reminderId = await this.reminderService.schedule(todo);
      }
    } else if (todo.reminderId > 0) {
      await this.reminderService.cancel(todo.reminderId);
      todo.reminderId = 0;
    }
    await this.todoDao.save(todo, this.todoTagIdsInput);
    await this.loadTodos();
    this.showSheet = false;
    this.toast(todo.reminderId > 0 ? '已保存并设置提醒' : '待办已保存');
  }

  private async toggleTodo(todo: Todo): Promise<void> {
    const nextDone: boolean = !todo.done;
    if (nextDone && todo.reminderId > 0) {
      await this.reminderService.cancel(todo.reminderId);
    }
    todo.done = nextDone;
    if (nextDone) {
      todo.reminderId = 0;
    }
    todo.updatedAt = nowMs();
    await this.todoDao.save(todo, todo.tags.map((tag: Tag) => tag.id));
    if (!nextDone && todo.dueAt > nowMs() && todo.reminderId === 0) {
      todo.reminderId = await this.reminderService.schedule(todo);
      await this.todoDao.save(todo, todo.tags.map((tag: Tag) => tag.id));
    }
    await this.loadTodos();
  }

  private confirmDeleteTodo(): void {
    const id: number = this.todoSheetId;
    if (id <= 0) {
      this.showSheet = false;
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除待办',
      message: '确定要删除这条待办吗？已设置的提醒也会一并取消。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.deleteTodoById(id);
        }
      }
    });
  }

  private async deleteTodoById(id: number): Promise<void> {
    const existing: Todo | undefined = this.todos.find((todo: Todo) => todo.id === id);
    if (existing !== undefined && existing.reminderId > 0) {
      await this.reminderService.cancel(existing.reminderId);
    }
    await this.todoDao.remove(id);
    await this.loadTodos();
    this.showSheet = false;
    this.toast('待办已删除');
  }

  private openNewTag(): void {
    this.tagSheetId = 0;
    this.tagNameInput = '';
    this.tagColorInput = TAG_COLORS[0];
    this.sheetMode = 3;
    this.showSheet = true;
  }

  private openExistingTag(tag: Tag): void {
    this.tagSheetId = tag.id;
    this.tagNameInput = tag.name;
    this.tagColorInput = tag.color;
    this.sheetMode = 3;
    this.showSheet = true;
  }

  private async saveTag(): Promise<void> {
    const name: string = this.tagNameInput.trim();
    if (name.length === 0) {
      this.toast('请输入标签名称');
      return;
    }
    const duplicate: Tag | undefined =
      this.tags.find((tag: Tag) => tag.name === name && tag.id !== this.tagSheetId);
    if (duplicate !== undefined) {
      this.toast('标签名称已存在');
      return;
    }
    const existing: Tag | undefined = this.tags.find((tag: Tag) => tag.id === this.tagSheetId);
    const tag: Tag = new Tag();
    tag.id = this.tagSheetId;
    tag.name = name;
    tag.color = this.tagColorInput;
    tag.createdAt = existing === undefined ? nowMs() : existing.createdAt;
    try {
      await this.tagDao.save(tag);
    } catch (err) {
      this.toast('标签保存失败');
      return;
    }
    await this.loadTags();
    await this.loadNotes();
    await this.loadTodos();
    this.showSheet = false;
    this.toast('标签已保存');
  }

  private confirmDeleteTag(): void {
    const id: number = this.tagSheetId;
    if (id <= 0) {
      this.showSheet = false;
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除标签',
      message: '删除后，该标签会从所有笔记和待办上移除。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.deleteTagById(id);
        }
      }
    });
  }

  private async deleteTagById(id: number): Promise<void> {
    await this.tagDao.remove(id);
    if (this.filterTagId === id) {
      this.filterTagId = -1;
    }
    await this.loadTags();
    await this.loadNotes();
    await this.loadTodos();
    this.showSheet = false;
    this.toast('标签已删除');
  }

  private async addTagQuick(): Promise<void> {
    const name: string = this.newTagName.trim();
    if (name.length === 0) {
      this.toast('请输入标签名称');
      return;
    }
    if (this.tags.some((tag: Tag) => tag.name === name)) {
      this.toast('标签名称已存在');
      return;
    }
    const tag: Tag = new Tag();
    tag.name = name;
    tag.color = this.newTagColor;
    tag.createdAt = nowMs();
    try {
      await this.tagDao.save(tag);
    } catch (err) {
      this.toast('标签创建失败');
      return;
    }
    this.newTagName = '';
    await this.loadTags();
    this.toast('标签已创建');
  }

  private async enableNotification(): Promise<void> {
    const enabled: boolean = await this.reminderService.ensureNotification(this.context());
    this.notificationEnabled = enabled;
    if (enabled) {
      this.toast('通知已开启');
    } else {
      this.toast('请在系统设置中允许墨记发送通知');
    }
  }

  private async exportBackup(): Promise<void> {
    try {
      const path: string = await this.backupService.exportToFile(this.context());
      if (path.length > 0) {
        this.toast('备份已导出');
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, LOG_TAG, 'export failed: %{public}s', e.message);
      this.toast('导出失败，请重试');
    }
  }

  private confirmImportBackup(): void {
    this.getUIContext().showAlertDialog({
      title: '从备份恢复',
      message: '恢复会覆盖当前所有笔记、待办和标签，确定继续吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '继续',
        action: () => {
          this.importBackup();
        }
      }
    });
  }

  private async importBackup(): Promise<void> {
    try {
      const count: number = await this.backupService.importFromFile(this.context());
      if (count < 0) {
        return;
      }
      await this.reloadAll();
      const keep: string[] = [];
      for (const note of this.notes) {
        for (const fileName of note.imageFiles) {
          keep.push(fileName);
        }
      }
      ImageService.prune(this.context(), keep);
      this.selectedNoteId = this.notes.length > 0 ? this.notes[0].id : -1;
      this.toast(`已恢复 ${count} 条数据`);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, LOG_TAG, 'import failed: %{public}s', e.message);
      this.toast('恢复失败：请选择墨记导出的备份文件');
    }
  }

  @Builder
  pageHeader(title: string, tab: number, showAdd: boolean) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.headerSubtitle(tab))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (showAdd) {
        Row() {
          Image($r('app.media.ic_plus'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.accent'))
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.accent_soft'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onAddTap();
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  searchBar() {
    Row({ space: 8 }) {
      Image($r('app.media.ic_search'))
        .width(17)
        .height(17)
        .fillColor($r('app.color.text_tertiary'))
      TextInput({ text: this.searchText, placeholder: '搜索标题或内容' })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .padding(0)
        .layoutWeight(1)
        .height(40)
        .onChange((value: string) => {
          this.searchText = value;
        })
      if (this.searchText.length > 0) {
        Image($r('app.media.ic_close'))
          .width(15)
          .height(15)
          .fillColor($r('app.color.text_tertiary'))
          .onClick(() => {
            this.searchText = '';
          })
      }
    }
    .height(40)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.input_bg'))
    .borderRadius(12)
    .margin({ left: 16, right: 16 })
  }

  @Builder
  tagFilterRow() {
    Scroll() {
      Row({ space: 8 }) {
        Text('全部')
          .fontSize(12)
          .fontColor(this.filterTagId < 0 ? $r('app.color.accent') : $r('app.color.text_secondary'))
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(this.filterTagId < 0 ? $r('app.color.accent_soft') : $r('app.color.chip_bg'))
          .borderRadius(999)
          .onClick(() => {
            this.filterTagId = -1;
          })
        ForEach(this.tags, (tag: Tag) => {
          TagChip({
            tag: tag,
            selected: this.filterTagId === tag.id,
            onTap: () => {
              this.filterTagId = this.filterTagId === tag.id ? -1 : tag.id;
            }
          })
        }, (tag: Tag) => `filter-${tag.id}-${tag.name}-${tag.color}`)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .margin({ top: 10 })
  }

  @Builder
  emptyView(icon: Resource, message: string) {
    Column({ space: 10 }) {
      Image(icon)
        .width(42)
        .height(42)
        .fillColor($r('app.color.text_tertiary'))
        .opacity(0.55)
      Text(message)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  notesView() {
    Column() {
      this.pageHeader('笔记', TAB_NOTES, this.isWide)
      this.searchBar()
      if (this.tags.length > 0) {
        this.tagFilterRow()
      }
      if (this.filteredNotes().length === 0) {
        this.emptyView($r('app.media.ic_note'),
          this.searchText.length > 0 || this.filterTagId > 0 ? '没有找到匹配的笔记' : '点击 + 记录第一条笔记')
      } else {
        List({ space: 10, scroller: this.noteListScroller }) {
          ForEach(this.filteredNotes(), (note: Note) => {
            ListItem() {
              NoteCard({
                note: note,
                active: this.isWide && this.selectedNoteId === note.id,
                onTap: () => {
                  this.onNoteTap(note);
                },
                onTogglePin: () => {
                  this.togglePin(note);
                }
              })
            }
            .swipeAction({
              start: {
                builder: () => {
                  this.pinSwipeAction(note);
                },
                actionAreaDistance: 80,
                onAction: () => {
                  this.applyPinSwipe(note);
                }
              },
              // 删除是破坏性操作，左滑只露出按钮，必须再点一次并确认，
              // 所以这里故意不写 onAction。
              end: {
                builder: () => {
                  this.deleteSwipeAction(note);
                },
                actionAreaDistance: 80
              }
            })
          }, (note: Note) => `${note.id}-${note.updatedAt}-${note.pinned}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, top: 6 })
        .contentEndOffset(this.listEndOffset())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }

  private applyPinSwipe(note: Note): void {
    this.toast(note.pinned ? '已取消置顶' : '已置顶');
    this.togglePin(note);
    this.noteListScroller.closeAllSwipeActions();
  }

  @Builder
  pinSwipeAction(note: Note) {
    Row({ space: 6 }) {
      Image($r('app.media.ic_pin'))
        .width(18)
        .height(18)
        .fillColor(Color.White)
      Text(note.pinned ? '取消置顶' : '置顶')
        .fontSize(13)
        .fontColor(Color.White)
    }
    .width(104)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.accent'))
    .borderRadius({ topLeft: 16, bottomLeft: 16 })
    .onClick(() => {
      this.applyPinSwipe(note);
    })
  }

  private applyDeleteSwipe(note: Note): void {
    this.noteListScroller.closeAllSwipeActions();
    this.confirmDeleteNote(note);
  }

  @Builder
  deleteSwipeAction(note: Note) {
    Row({ space: 6 }) {
      Image($r('app.media.ic_trash'))
        .width(18)
        .height(18)
        .fillColor(Color.White)
      Text('删除')
        .fontSize(13)
        .fontColor(Color.White)
    }
    .width(104)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.danger'))
    .borderRadius({ topRight: 16, bottomRight: 16 })
    .onClick(() => {
      this.applyDeleteSwipe(note);
    })
  }

  @Builder
  notePreview() {
    Column() {
      if (!this.hasSelectedNote()) {
        this.emptyView($r('app.media.ic_note'), '从左侧选择一条笔记查看内容')
      } else {
        Row({ space: 8 }) {
          Text('预览')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
          Image($r('app.media.ic_pin'))
            .width(18)
            .height(18)
            .fillColor(this.selectedNote().pinned ? $r('app.color.accent') : $r('app.color.text_tertiary'))
            .padding(6)
            .onClick(() => {
              this.togglePin(this.selectedNote());
            })
          Row({ space: 5 }) {
            Image($r('app.media.ic_edit'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.accent'))
            Text('编辑')
              .fontSize(12)
              .fontColor($r('app.color.accent'))
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.accent_soft'))
          .borderRadius(999)
          .onClick(() => {
            this.openExistingNote(this.selectedNote());
          })
          Image($r('app.media.ic_trash'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.danger'))
            .padding(6)
            .onClick(() => {
              this.confirmDeleteNote(this.selectedNote());
            })
        }
        .width('100%')
        .padding({ left: 24, right: 20, top: 12, bottom: 8 })

        Scroll() {
          Column({ space: 12 }) {
            Text(this.selectedNote().title.trim().length === 0 ? '无标题笔记' : this.selectedNote().title)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(34)
            Row({ space: 6 }) {
              if (this.selectedNote().tags.length > 0) {
                ForEach(this.selectedNote().tags, (tag: Tag) => {
                  TagChip({ tag: tag, compact: true, selected: false })
                }, (tag: Tag) => `preview-${this.selectedNoteId}-${tag.id}`)
              }
              Blank()
              Text(formatRelative(this.selectedNote().updatedAt))
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            Divider()
              .color($r('app.color.divider'))
            if (this.selectedNote().imageFiles.length > 0) {
              Column({ space: 10 }) {
                ForEach(this.selectedNote().imageFiles, (fileName: string, index: number) => {
                  Image(ImageService.displayUri(this.context(), fileName))
                    .width('100%')
                    .constraintSize({ maxHeight: 320 })
                    .objectFit(ImageFit.Contain)
                    .borderRadius(12)
                    .backgroundColor($r('app.color.bg_card'))
                    .onClick(() => {
                      this.openPreview(this.selectedNote().imageFiles, index);
                    })
                }, (fileName: string) => `preview-img-${this.selectedNoteId}-${fileName}`)
              }
              .width('100%')
            }
            Text(this.selectedNote().content.trim().length === 0 ? '空白笔记' : this.selectedNote().content)
              .fontSize(15)
              .lineHeight(26)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 24, right: 24, top: 8, bottom: 24 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  todoFilterChip(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.todoFilter === index ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.todoFilter === index ? $r('app.color.accent') : $r('app.color.chip_bg'))
      .borderRadius(999)
      .onClick(() => {
        this.todoFilter = index;
      })
  }

  @Builder
  todosView() {
    Column() {
      this.pageHeader('待办', TAB_TODOS, this.isWide)
      Row({ space: 8 }) {
        this.todoFilterChip('全部', TODO_FILTER_ALL)
        this.todoFilterChip('进行中', TODO_FILTER_ACTIVE)
        this.todoFilterChip('今天', TODO_FILTER_TODAY)
        this.todoFilterChip('已完成', TODO_FILTER_DONE)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Column({ space: 8 }) {
        Row() {
          Text('今日进度')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(`${this.todayDone()} / ${this.todayTotal()}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        Row() {
          Row()
            .width(`${this.todayPercent()}%`)
            .height(6)
            .borderRadius(3)
            .backgroundColor($r('app.color.success'))
        }
        .width('100%')
        .height(6)
        .borderRadius(3)
        .backgroundColor($r('app.color.track'))
        Text(`${this.pendingTodoCount()} 项未完成`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.accent_soft'))
      .borderRadius(16)
      .margin({ left: 16, right: 16, top: 12 })

      if (this.filteredTodos().length === 0) {
        this.emptyView($r('app.media.ic_check_circle'), '这里还没有待办')
      } else {
        List({ space: 8 }) {
          ForEach(this.filteredTodos(), (todo: Todo) => {
            ListItem() {
              TodoRow({
                todo: todo,
                onToggle: () => {
                  this.toggleTodo(todo);
                },
                onTap: () => {
                  this.openExistingTodo(todo);
                }
              })
            }
          }, (todo: Todo) => `${todo.id}-${todo.updatedAt}-${todo.done}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, top: 12 })
        .contentEndOffset(this.listEndOffset())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  colorDots(selectedColor: string, onPick: (color: string) => void) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(TAG_COLORS, (color: string) => {
        Row()
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor(color)
          .border({ width: selectedColor === color ? 3 : 0, color: $r('app.color.bg_page') })
          .margin({ right: 10, bottom: 10 })
          .onClick(() => {
            onPick(color);
          })
      }, (color: string) => color)
    }
    .width('100%')
  }

  @Builder
  tagsView() {
    Column() {
      this.pageHeader('标签', TAB_TAGS, this.isWide)
      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 10 }) {
            Text('新建标签')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Row({ space: 8 }) {
              TextInput({ text: this.newTagName, placeholder: '标签名称' })
                .fontSize(14)
                .backgroundColor($r('app.color.input_bg'))
                .borderRadius(10)
                .layoutWeight(1)
                .height(40)
                .onChange((value: string) => {
                  this.newTagName = value;
                })
              Button('添加')
                .fontSize(13)
                .height(36)
                .borderRadius(18)
                .backgroundColor($r('app.color.accent'))
                .fontColor(Color.White)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  this.addTagQuick();
                })
            }
            .width('100%')
            this.colorDots(this.newTagColor, (color: string) => {
              this.newTagColor = color;
            })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border_soft') })
          .alignItems(HorizontalAlign.Start)

          if (this.tags.length === 0) {
            Column({ space: 8 }) {
              Image($r('app.media.ic_tag'))
                .width(36)
                .height(36)
                .fillColor($r('app.color.text_tertiary'))
                .opacity(0.55)
              Text('用颜色给笔记和待办分类')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .padding({ top: 32, bottom: 32 })
          } else {
            ForEach(this.tags, (tag: Tag) => {
              Row({ space: 12 }) {
                Row()
                  .width(12)
                  .height(12)
                  .borderRadius(6)
                  .backgroundColor(tag.color)
                Column({ space: 2 }) {
                  Text(tag.name)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                  Text(`${tag.usageCount} 处使用`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Image($r('app.media.ic_edit'))
                  .width(16)
                  .height(16)
                  .fillColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius(14)
              .border({ width: 1, color: $r('app.color.border_soft') })
              .onClick(() => {
                this.openExistingTag(tag);
              })
            }, (tag: Tag) => `tag-${tag.id}-${tag.usageCount}-${tag.name}-${tag.color}`)
          }
        }
        .padding({ left: 16, right: 16, top: 4, bottom: this.listEndOffset() })
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  settingsView() {
    Column() {
      this.pageHeader('我的', TAB_SETTINGS, false)
      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_bell'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.accent'))
              Column({ space: 2 }) {
                Text('通知与到期提醒')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text(this.notificationEnabled ? '通知已开启，待办到期会提醒你' : '通知未开启，提醒可能无法展示')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (!this.notificationEnabled) {
                Button('开启')
                  .fontSize(12)
                  .height(32)
                  .borderRadius(16)
                  .backgroundColor($r('app.color.accent'))
                  .fontColor(Color.White)
                  .padding({ left: 14, right: 14 })
                  .onClick(() => {
                    this.enableNotification();
                  })
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border_soft') })

          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_today'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.accent'))
              Text('桌面服务卡片')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            Text('在桌面长按墨记图标，选择「服务卡片」，添加 2×4 的今日待办卡片，随时查看今天要做的事。')
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border_soft') })
          .alignItems(HorizontalAlign.Start)

          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Image($r('app.media.ic_export'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.accent'))
              Column({ space: 2 }) {
                Text('导出备份')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('将笔记、待办和标签保存为 JSON 文件')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Image($r('app.media.ic_chevron_right'))
                .width(14)
                .height(14)
                .fillColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .onClick(() => {
              this.exportBackup();
            })
            Divider()
              .color($r('app.color.divider'))
            Row({ space: 10 }) {
              Image($r('app.media.ic_import'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.accent'))
              Column({ space: 2 }) {
                Text('从备份恢复')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('选择墨记导出的 JSON 备份文件')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Image($r('app.media.ic_chevron_right'))
                .width(14)
                .height(14)
                .fillColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .onClick(() => {
              this.confirmImportBackup();
            })
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border_soft') })

          Column({ space: 10 }) {
            Row() {
              Text('深色模式')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('跟随系统')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            Row() {
              Text('数据统计')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.notes.length} 笔记 · ${this.todos.length} 待办 · ${this.tags.length} 标签`)
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            Row() {
              Text('版本')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('1.0.0')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            Text('灵感来自开源项目 Notesnook（GPL-3.0）。墨记使用原生 ArkTS 重写，所有数据仅保存在本机；笔记图片保存在应用沙箱内，不随 JSON 备份导出。')
              .fontSize(11)
              .lineHeight(17)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
          .border({ width: 1, color: $r('app.color.border_soft') })
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 16, right: 16, top: 4, bottom: this.isWide ? 32 : NAV_OVERLAP + 20 })
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  fab(bottomInset: number) {
    Row() {
      Image($r('app.media.ic_plus'))
        .width(24)
        .height(24)
        .fillColor(Color.White)
    }
    .width(56)
    .height(56)
    .borderRadius(28)
    .backgroundColor($r('app.color.accent'))
    .justifyContent(FlexAlign.Center)
    .margin({ right: 20, bottom: bottomInset })
    .shadow({ radius: 10, color: '#33000000', offsetY: 3 })
    .onClick(() => {
      this.onAddTap();
    })
  }

  @Builder
  tabBarItem(index: number, label: string, icon: Resource) {
    Column({ space: 3 }) {
      Image(icon)
        .width(21)
        .height(21)
        .fillColor(this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_tertiary'))
      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_tertiary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  railItem(index: number, label: string, icon: Resource) {
    Column({ space: 3 }) {
      Image(icon)
        .width(21)
        .height(21)
        .fillColor(this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_tertiary'))
      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_tertiary'))
    }
    .width(64)
    .height(54)
    .borderRadius(14)
    .backgroundColor(this.currentTab === index ? $r('app.color.accent_soft') : Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  @Builder
  navRail() {
    Column() {
      Row() {
        Text('墨')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width(44)
      .height(44)
      .borderRadius(14)
      .backgroundColor($r('app.color.accent'))
      .justifyContent(FlexAlign.Center)
      .margin({ top: 18, bottom: 22 })

      this.railItem(TAB_NOTES, '笔记', $r('app.media.ic_note'))
      this.railItem(TAB_TODOS, '待办', $r('app.media.ic_check_circle'))
      this.railItem(TAB_TAGS, '标签', $r('app.media.ic_tag'))
      this.railItem(TAB_SETTINGS, '我的', $r('app.media.ic_settings'))
      Blank()
      Text('v1.0')
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ bottom: 16 })
    }
    .width(88)
    .height('100%')
    .backgroundColor($r('app.color.nav_bg'))
    .border({ width: { right: 1 }, color: $r('app.color.divider') })
  }

  private fabInset(): number {
    return this.isWide ? 20 : NAV_OVERLAP + FAB_GAP;
  }

  private listEndOffset(): number {
    return this.fabInset() + FAB_SIZE + FAB_GAP;
  }

  @Builder
  phoneLayout() {
    Column() {
      if (!this.ready) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.accent'))
          Text('正在加载…')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        HdsTabs({ controller: this.tabsController }) {
          TabContent() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              this.notesView()
              this.fab(this.fabInset())
            }
            .width('100%')
            .height('100%')
          }
          .tabBar(this.tabBarItem(TAB_NOTES, '笔记', $r('app.media.ic_note')))

          TabContent() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              this.todosView()
              this.fab(this.fabInset())
            }
            .width('100%')
            .height('100%')
          }
          .tabBar(this.tabBarItem(TAB_TODOS, '待办', $r('app.media.ic_check_circle')))

          TabContent() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              this.tagsView()
              this.fab(this.fabInset())
            }
            .width('100%')
            .height('100%')
          }
          .tabBar(this.tabBarItem(TAB_TAGS, '标签', $r('app.media.ic_tag')))

          TabContent() {
            this.settingsView()
          }
          .tabBar(this.tabBarItem(TAB_SETTINGS, '我的', $r('app.media.ic_settings')))
        }
        .barPosition(BarPosition.End)
        .barOverlap(true)
        .barHeight(NAV_BAR_HEIGHT)
        .barBackgroundColor(Color.Transparent)
        .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)
        .barFloatingStyle({
          barSideMargin: 0,
          barBottomMargin: NAV_BAR_BOTTOM,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .onChange((index: number) => {
          this.currentTab = index;
        })
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  wideLayout() {
    Row() {
      this.navRail()
      Column() {
        if (!this.ready) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.accent'))
            Text('正在加载…')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.currentTab === TAB_NOTES) {
          Row() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              this.notesView()
              this.fab(this.fabInset())
            }
            .width(380)
            .height('100%')
            Divider()
              .vertical(true)
              .color($r('app.color.divider'))
            this.notePreview()
          }
          .width('100%')
          .height('100%')
        } else {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Row() {
              if (this.currentTab === TAB_TODOS) {
                this.todosView()
              } else if (this.currentTab === TAB_TAGS) {
                this.tagsView()
              } else {
                this.settingsView()
              }
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .constraintSize({ maxWidth: 820 })

            if (this.currentTab !== TAB_SETTINGS) {
              this.fab(this.fabInset())
            }
          }
          .width('100%')
          .height('100%')
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sheetContent() {
    if (this.sheetMode === 1) {
      NoteEditor({
        noteId: this.sheetNoteId,
        initialTitle: this.sheetNoteTitle,
        initialContent: this.sheetNoteContent,
        initialTagIds: this.sheetNoteTagIds,
        initialImages: this.sheetNoteImages,
        tags: this.tags,
        resetToken: this.editorToken,
        previewIndex: this.editorPreviewAt,
        onAutoSave: (id: number, title: string, content: string, tagIds: number[],
          images: string[]): Promise<number> => {
          return this.persistNote(id, title, content, tagIds, images);
        },
        onSave: (id: number, title: string, content: string, tagIds: number[],
          images: string[]): Promise<number> => {
          return this.saveNoteAndClose(id, title, content, tagIds, images);
        },
        onPickImages: (): Promise<string[]> => {
          return this.pickImages();
        },
        onRemoveImage: (fileName: string) => {
          this.removeImageFile(fileName);
        },
        onDelete: (id: number) => {
          this.deleteNoteById(id);
        },
        onClose: () => {
          this.showSheet = false;
        }
      })
    } else if (this.sheetMode === 2) {
      this.todoSheetContent()
    } else if (this.sheetMode === 3) {
      this.tagSheetContent()
    }
  }

  @Builder
  todoSheetContent() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text(this.todoSheetId > 0 ? '编辑待办' : '新建待办')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Button('保存')
            .fontSize(13)
            .height(32)
            .borderRadius(16)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.saveTodoSheet();
            })
        }
        .width('100%')

        TextInput({ text: this.todoTitleInput, placeholder: '要做什么？' })
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(12)
          .height(46)
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => {
            this.todoTitleInput = value;
          })

        TextArea({ text: this.todoDetailInput, placeholder: '补充说明（可选）' })
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(12)
          .height(92)
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .onChange((value: string) => {
            this.todoDetailInput = value;
          })

        Column({ space: 8 }) {
          Text('截止时间')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Row({ space: 10 }) {
            Row({ space: 6 }) {
              Image($r('app.media.ic_clock'))
                .width(15)
                .height(15)
                .fillColor(this.todoDueInput > 0 ? $r('app.color.accent') : $r('app.color.text_tertiary'))
              Text(this.todoDueInput > 0 ? formatDue(this.todoDueInput) : '添加截止时间')
                .fontSize(14)
                .fontColor(this.todoDueInput > 0 ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
            }
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              this.pickDueTime();
            })
            if (this.todoDueInput > 0) {
              Text('清除')
                .fontSize(12)
                .fontColor($r('app.color.danger'))
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .onClick(() => {
                  this.todoDueInput = 0;
                })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(12)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Text('优先级')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Row({ space: 8 }) {
            ForEach(PRIORITY_LABELS, (label: string, index: number) => {
              Text(label)
                .fontSize(13)
                .fontColor(this.todoPriorityInput === index ? PRIORITY_COLORS[index] : $r('app.color.text_secondary'))
                .padding({ left: 18, right: 18, top: 7, bottom: 7 })
                .backgroundColor(this.todoPriorityInput === index ?
                withAlpha(PRIORITY_COLORS[index], '22') : $r('app.color.chip_bg'))
                .borderRadius(999)
                .border({
                  width: 1,
                  color: this.todoPriorityInput === index ? PRIORITY_COLORS[index] : $r('app.color.chip_bg')
                })
                .onClick(() => {
                  this.todoPriorityInput = index;
                })
            }, (label: string) => label)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          Text('标签')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          if (this.tags.length === 0) {
            Text('还没有标签，可在「标签」页创建')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          } else {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.tags, (tag: Tag) => {
                  TagChip({
                    tag: tag,
                    selected: this.isTodoTagSelected(tag.id),
                    onTap: () => {
                      this.toggleTodoTag(tag.id);
                    }
                  })
                }, (tag: Tag) => `todo-sheet-${tag.id}-${tag.name}-${tag.color}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.todoSheetId > 0) {
          Row({ space: 6 }) {
            Image($r('app.media.ic_trash'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.danger'))
            Text('删除待办')
              .fontSize(13)
              .fontColor($r('app.color.danger'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.confirmDeleteTodo();
          })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  tagSheetContent() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text(this.tagSheetId > 0 ? '编辑标签' : '新建标签')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Button('保存')
            .fontSize(13)
            .height(32)
            .borderRadius(16)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.saveTag();
            })
        }
        .width('100%')

        TextInput({ text: this.tagNameInput, placeholder: '标签名称' })
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(12)
          .height(44)
          .padding({ left: 14, right: 14 })
          .onChange((value: string) => {
            this.tagNameInput = value;
          })

        Column({ space: 8 }) {
          Text('颜色')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          this.colorDots(this.tagColorInput, (color: string) => {
            this.tagColorInput = color;
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 8 }) {
          Row()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(this.tagColorInput)
          Text(this.tagNameInput.trim().length === 0 ? '标签预览' : this.tagNameInput.trim())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.chip_bg'))
        .borderRadius(999)

        if (this.tagSheetId > 0) {
          Row({ space: 6 }) {
            Image($r('app.media.ic_trash'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.danger'))
            Text('删除标签')
              .fontSize(13)
              .fontColor($r('app.color.danger'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.confirmDeleteTag();
          })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  private async loadAllSilently(): Promise<void> {
    try {
      await this.reloadAll();
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, LOG_TAG, 'reload after sheet failed: %{public}s', e.message);
    }
  }

  onBackPress(): boolean {
    if (this.editorPreviewAt >= 0) {
      this.editorPreviewAt = -1;
      return true;
    }
    if (this.previewAt >= 0) {
      this.previewAt = -1;
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      if (this.isWide) {
        this.wideLayout()
      } else {
        this.phoneLayout()
      }
      if (this.previewAt >= 0) {
        this.imagePreviewOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showSheet, this.sheetContent(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('app.color.bg_page'),
      onWillDismiss: (action: DismissSheetAction) => {
        if (this.editorPreviewAt >= 0) {
          this.editorPreviewAt = -1;
          return;
        }
        action.dismiss();
      },
      onDisappear: () => {
        this.editorPreviewAt = -1;
        this.loadAllSilently();
      }
    })
  }

  @Builder
  imagePreviewOverlay() {
    Column() {
      Row({ space: 8 }) {
        Text(`${this.previewAt + 1} / ${this.previewImages.length}`)
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
          Image(ImageService.displayUri(this.context(), fileName))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        }, (fileName: string) => `overlay-${this.selectedNoteId}-${fileName}`)
      }
      .index(this.previewAt < 0 ? 0 : this.previewAt)
      .loop(false)
      .indicator(this.previewImages.length > 1)
      .layoutWeight(1)
      .onChange((index: number) => {
        this.previewAt = index;
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
      this.previewAt = -1;
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
  }
}
