import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { relationalStore } from '@kit.ArkData';
import { NoteDao } from '../data/NoteDao';
import { TagDao } from '../data/TagDao';
import { TodoDao } from '../data/TodoDao';
import { Database } from '../data/Database';
import { BackupPayload, Note, NoteTagLink, Tag, Todo, TodoTagLink } from '../model/Models';
import { pad2 } from '../common/Utils';

export class BackupService {
  private noteDao: NoteDao = new NoteDao();
  private tagDao: TagDao = new TagDao();
  private todoDao: TodoDao = new TodoDao();

  async exportToFile(context: common.UIAbilityContext): Promise<string> {
    const payload: BackupPayload = await this.buildPayload();
    const text: string = JSON.stringify(payload, null, 2);
    const now: Date = new Date();
    const fileName: string = `mojian-backup-${now.getFullYear()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}` +
      `-${pad2(now.getHours())}${pad2(now.getMinutes())}.json`;
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = ['.json'];
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await documentPicker.save(options);
    if (uris.length === 0) {
      return '';
    }
    const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
    return uris[0];
  }

  async importFromFile(context: common.UIAbilityContext): Promise<number> {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.json'];
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await documentPicker.select(options);
    if (uris.length === 0) {
      return -1;
    }
    const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
    let text: string = '';
    try {
      text = this.readAll(file);
    } finally {
      fileIo.closeSync(file);
    }
    const payload: BackupPayload = this.parsePayload(text);
    await this.restore(payload);
    return payload.notes.length + payload.todos.length + payload.tags.length;
  }

  private readAll(file: fileIo.File): string {
    const size: number = fileIo.statSync(file.fd).size;
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    const readLength: number = fileIo.readSync(file.fd, buffer);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(buffer, 0, readLength));
  }

  private parsePayload(text: string): BackupPayload {
    const payload: BackupPayload = JSON.parse(text) as BackupPayload;
    if (payload.app !== 'mojian' || payload.version !== 1) {
      throw new Error('不是有效的墨记备份文件');
    }
    return payload;
  }

  private async buildPayload(): Promise<BackupPayload> {
    const tags: Tag[] = await this.tagDao.listAll();
    const notes: Note[] = await this.noteDao.listAll();
    const todos: Todo[] = await this.todoDao.listAll();
    const payload: BackupPayload = new BackupPayload();
    payload.exportedAt = new Date().getTime();
    payload.tags = tags;
    payload.notes = notes;
    payload.todos = todos;
    const noteLinks: NoteTagLink[] = [];
    for (const note of notes) {
      for (const tag of note.tags) {
        const link: NoteTagLink = new NoteTagLink();
        link.noteId = note.id;
        link.tagId = tag.id;
        noteLinks.push(link);
      }
    }
    const todoLinks: TodoTagLink[] = [];
    for (const todo of todos) {
      for (const tag of todo.tags) {
        const link: TodoTagLink = new TodoTagLink();
        link.todoId = todo.id;
        link.tagId = tag.id;
        todoLinks.push(link);
      }
    }
    payload.noteTags = noteLinks;
    payload.todoTags = todoLinks;
    return payload;
  }

  private async restore(payload: BackupPayload): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    await store.executeSql('DELETE FROM note_tag');
    await store.executeSql('DELETE FROM todo_tag');
    await store.executeSql('DELETE FROM note');
    await store.executeSql('DELETE FROM todo');
    await store.executeSql('DELETE FROM tag');

    for (const tag of payload.tags) {
      const args: Array<relationalStore.ValueType> = [tag.id, tag.name, tag.color, tag.createdAt];
      await store.executeSql(
        'INSERT INTO tag (id, name, color, created_at) VALUES (?, ?, ?, ?)', args);
    }
    for (const note of payload.notes) {
      const images: string[] = note.imageFiles ? note.imageFiles : [];
      const args: Array<relationalStore.ValueType> = [
        note.id, note.title, note.content, JSON.stringify(images),
        note.pinned ? 1 : 0, note.createdAt, note.updatedAt
      ];
      await store.executeSql(
        'INSERT INTO note (id, title, content, images, pinned, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        args);
    }
    for (const todo of payload.todos) {
      const args: Array<relationalStore.ValueType> = [
        todo.id, todo.title, todo.detail, todo.done ? 1 : 0, todo.priority,
        todo.dueAt, todo.reminderId, todo.createdAt, todo.updatedAt
      ];
      await store.executeSql(
        'INSERT INTO todo (id, title, detail, done, priority, due_at, reminder_id, created_at, updated_at) ' +
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', args);
    }
    for (const link of payload.noteTags) {
      const args: Array<relationalStore.ValueType> = [link.noteId, link.tagId];
      await store.executeSql('INSERT INTO note_tag (note_id, tag_id) VALUES (?, ?)', args);
    }
    for (const link of payload.todoTags) {
      const args: Array<relationalStore.ValueType> = [link.todoId, link.tagId];
      await store.executeSql('INSERT INTO todo_tag (todo_id, tag_id) VALUES (?, ?)', args);
    }
    try {
      await store.executeSql('DELETE FROM sqlite_sequence');
    } catch (err) {
      // sqlite_sequence only exists once an AUTOINCREMENT table has been written
    }
  }
}
