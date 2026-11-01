export class Tag {
  id: number = 0;
  name: string = '';
  color: string = '#6E56CF';
  createdAt: number = 0;
  usageCount: number = 0;
}

export class Note {
  id: number = 0;
  title: string = '';
  content: string = '';
  pinned: boolean = false;
  createdAt: number = 0;
  updatedAt: number = 0;
  tags: Tag[] = [];
  imageFiles: string[] = [];
}

export class Todo {
  id: number = 0;
  title: string = '';
  detail: string = '';
  done: boolean = false;
  priority: number = 1;
  dueAt: number = 0;
  reminderId: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  tags: Tag[] = [];
}

export class NoteTagLink {
  noteId: number = 0;
  tagId: number = 0;
}

export class TodoTagLink {
  todoId: number = 0;
  tagId: number = 0;
}

export class WidgetData {
  todayLabel: string = '今日待办';
  doneCount: number = 0;
  totalCount: number = 0;
  item1: string = '';
  item2: string = '';
  item3: string = '';
  emptyText: string = '今天没有待办';
}

export class BackupPayload {
  app: string = 'mojian';
  version: number = 1;
  exportedAt: number = 0;
  tags: Tag[] = [];
  notes: Note[] = [];
  todos: Todo[] = [];
  noteTags: NoteTagLink[] = [];
  todoTags: TodoTagLink[] = [];
}

export class TagDraft {
  name: string = '';
  color: string = '#6E56CF';
}
