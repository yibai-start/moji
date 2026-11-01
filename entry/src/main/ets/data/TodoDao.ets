import { relationalStore } from '@kit.ArkData';
import { Database } from './Database';
import { Tag, Todo } from '../model/Models';

export class TodoDao {
  async listAll(): Promise<Todo[]> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const tagMap: Map<number, Tag[]> = new Map<number, Tag[]>();
    const linkResult: relationalStore.ResultSet = await store.querySql(
      'SELECT tt.todo_id AS todo_id, t.id AS tag_id, t.name AS name, t.color AS color ' +
      'FROM todo_tag tt INNER JOIN tag t ON t.id = tt.tag_id'
    );
    while (linkResult.goToNextRow()) {
      const todoId: number = linkResult.getLong(linkResult.getColumnIndex('todo_id'));
      const tag: Tag = new Tag();
      tag.id = linkResult.getLong(linkResult.getColumnIndex('tag_id'));
      tag.name = linkResult.getString(linkResult.getColumnIndex('name'));
      tag.color = linkResult.getString(linkResult.getColumnIndex('color'));
      const existing: Tag[] | undefined = tagMap.get(todoId);
      if (existing === undefined) {
        tagMap.set(todoId, [tag]);
      } else {
        existing.push(tag);
      }
    }
    linkResult.close();

    const todos: Todo[] = [];
    const result: relationalStore.ResultSet = await store.querySql(
      'SELECT * FROM todo ORDER BY done ASC, ' +
      'CASE WHEN due_at = 0 THEN 1 ELSE 0 END ASC, due_at ASC, priority DESC, created_at DESC'
    );
    while (result.goToNextRow()) {
      const todo: Todo = new Todo();
      todo.id = result.getLong(result.getColumnIndex('id'));
      todo.title = result.getString(result.getColumnIndex('title'));
      todo.detail = result.getString(result.getColumnIndex('detail'));
      todo.done = result.getLong(result.getColumnIndex('done')) === 1;
      todo.priority = result.getLong(result.getColumnIndex('priority'));
      todo.dueAt = result.getLong(result.getColumnIndex('due_at'));
      todo.reminderId = result.getLong(result.getColumnIndex('reminder_id'));
      todo.createdAt = result.getLong(result.getColumnIndex('created_at'));
      todo.updatedAt = result.getLong(result.getColumnIndex('updated_at'));
      const tags: Tag[] | undefined = tagMap.get(todo.id);
      todo.tags = tags === undefined ? [] : tags;
      todos.push(todo);
    }
    result.close();
    return todos;
  }

  async save(todo: Todo, tagIds: number[]): Promise<number> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const values: relationalStore.ValuesBucket = {
      'title': todo.title,
      'detail': todo.detail,
      'done': todo.done ? 1 : 0,
      'priority': todo.priority,
      'due_at': todo.dueAt,
      'reminder_id': todo.reminderId,
      'created_at': todo.createdAt,
      'updated_at': todo.updatedAt
    };
    if (todo.id === 0) {
      todo.id = await store.insert('todo', values);
    } else {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('todo');
      predicates.equalTo('id', todo.id);
      await store.update(values, predicates);
    }
    await this.replaceTagsAsync(todo.id, tagIds);
    return todo.id;
  }

  private async replaceTagsAsync(todoId: number, tagIds: number[]): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('todo_tag');
    predicates.equalTo('todo_id', todoId);
    await store.delete(predicates);
    for (const tagId of tagIds) {
      const values: relationalStore.ValuesBucket = {
        'todo_id': todoId,
        'tag_id': tagId
      };
      await store.insert('todo_tag', values);
    }
  }

  async remove(todoId: number): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const linkPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('todo_tag');
    linkPredicates.equalTo('todo_id', todoId);
    await store.delete(linkPredicates);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('todo');
    predicates.equalTo('id', todoId);
    await store.delete(predicates);
  }

  async clear(): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    await store.executeSql('DELETE FROM todo_tag');
    await store.executeSql('DELETE FROM todo');
  }
}
