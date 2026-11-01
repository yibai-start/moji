import { relationalStore } from '@kit.ArkData';
import { Database } from './Database';
import { Note, Tag } from '../model/Models';

function parseImageFiles(raw: string): string[] {
  if (raw === undefined || raw === null || raw.length === 0) {
    return [];
  }
  try {
    const parsed: string[] = JSON.parse(raw) as string[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    return [];
  }
}

export class NoteDao {
  async listAll(): Promise<Note[]> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const tagMap: Map<number, Tag[]> = new Map<number, Tag[]>();
    const linkResult: relationalStore.ResultSet = await store.querySql(
      'SELECT nt.note_id AS note_id, t.id AS tag_id, t.name AS name, t.color AS color ' +
      'FROM note_tag nt INNER JOIN tag t ON t.id = nt.tag_id'
    );
    while (linkResult.goToNextRow()) {
      const noteId: number = linkResult.getLong(linkResult.getColumnIndex('note_id'));
      const tag: Tag = new Tag();
      tag.id = linkResult.getLong(linkResult.getColumnIndex('tag_id'));
      tag.name = linkResult.getString(linkResult.getColumnIndex('name'));
      tag.color = linkResult.getString(linkResult.getColumnIndex('color'));
      const existing: Tag[] | undefined = tagMap.get(noteId);
      if (existing === undefined) {
        tagMap.set(noteId, [tag]);
      } else {
        existing.push(tag);
      }
    }
    linkResult.close();

    const notes: Note[] = [];
    const result: relationalStore.ResultSet = await store.querySql(
      'SELECT * FROM note ORDER BY pinned DESC, updated_at DESC'
    );
    while (result.goToNextRow()) {
      const note: Note = new Note();
      note.id = result.getLong(result.getColumnIndex('id'));
      note.title = result.getString(result.getColumnIndex('title'));
      note.content = result.getString(result.getColumnIndex('content'));
      note.pinned = result.getLong(result.getColumnIndex('pinned')) === 1;
      note.createdAt = result.getLong(result.getColumnIndex('created_at'));
      note.updatedAt = result.getLong(result.getColumnIndex('updated_at'));
      note.imageFiles = parseImageFiles(result.getString(result.getColumnIndex('images')));
      const tags: Tag[] | undefined = tagMap.get(note.id);
      note.tags = tags === undefined ? [] : tags;
      notes.push(note);
    }
    result.close();
    return notes;
  }

  async save(note: Note, tagIds: number[]): Promise<number> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const values: relationalStore.ValuesBucket = {
      'title': note.title,
      'content': note.content,
      'images': JSON.stringify(note.imageFiles),
      'pinned': note.pinned ? 1 : 0,
      'created_at': note.createdAt,
      'updated_at': note.updatedAt
    };
    if (note.id === 0) {
      note.id = await store.insert('note', values);
    } else {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('note');
      predicates.equalTo('id', note.id);
      await store.update(values, predicates);
    }
    await this.replaceTagsAsync(note.id, tagIds);
    return note.id;
  }

  private async replaceTagsAsync(noteId: number, tagIds: number[]): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('note_tag');
    predicates.equalTo('note_id', noteId);
    await store.delete(predicates);
    for (const tagId of tagIds) {
      const values: relationalStore.ValuesBucket = {
        'note_id': noteId,
        'tag_id': tagId
      };
      await store.insert('note_tag', values);
    }
  }

  async setPinned(noteId: number, pinned: boolean): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const values: relationalStore.ValuesBucket = {
      'pinned': pinned ? 1 : 0,
      'updated_at': new Date().getTime()
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('note');
    predicates.equalTo('id', noteId);
    await store.update(values, predicates);
  }

  async remove(noteId: number): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    const linkPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('note_tag');
    linkPredicates.equalTo('note_id', noteId);
    await store.delete(linkPredicates);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('note');
    predicates.equalTo('id', noteId);
    await store.delete(predicates);
  }

  async clear(): Promise<void> {
    const store: relationalStore.RdbStore = Database.getInstance().getStore();
    await store.executeSql('DELETE FROM note_tag');
    await store.executeSql('DELETE FROM note');
  }
}
