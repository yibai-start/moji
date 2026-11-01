import { relationalStore } from '@kit.ArkData';
import { Database } from './Database';
import { Tag } from '../model/Models';

export class TagDao {
  async listAll(): Promise<Tag[]> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const result: relationalStore.ResultSet = await store.querySql(
      'SELECT t.id AS id, t.name AS name, t.color AS color, t.created_at AS created_at, ' +
      '(SELECT COUNT(*) FROM note_tag nt WHERE nt.tag_id = t.id) + ' +
      '(SELECT COUNT(*) FROM todo_tag tt WHERE tt.tag_id = t.id) AS usage_count ' +
      'FROM tag t ORDER BY t.created_at ASC'
    );
    const tags: Tag[] = [];
    while (result.goToNextRow()) {
      const tag: Tag = new Tag();
      tag.id = result.getLong(result.getColumnIndex('id'));
      tag.name = result.getString(result.getColumnIndex('name'));
      tag.color = result.getString(result.getColumnIndex('color'));
      tag.createdAt = result.getLong(result.getColumnIndex('created_at'));
      tag.usageCount = result.getLong(result.getColumnIndex('usage_count'));
      tags.push(tag);
    }
    result.close();
    return tags;
  }

  async save(tag: Tag): Promise<number> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const values: relationalStore.ValuesBucket = {
      'name': tag.name,
      'color': tag.color,
      'created_at': tag.createdAt
    };
    if (tag.id === 0) {
      tag.id = await store.insert('tag', values);
    } else {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('tag');
      predicates.equalTo('id', tag.id);
      await store.update(values, predicates);
    }
    return tag.id;
  }

  async remove(tagId: number): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const noteLink: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('note_tag');
    noteLink.equalTo('tag_id', tagId);
    await store.delete(noteLink);
    const todoLink: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('todo_tag');
    todoLink.equalTo('tag_id', tagId);
    await store.delete(todoLink);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('tag');
    predicates.equalTo('id', tagId);
    await store.delete(predicates);
  }

  async clear(): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    await store.executeSql('DELETE FROM tag');
  }
}
