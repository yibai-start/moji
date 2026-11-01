import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const SQL_CREATE: string[] = [
  `CREATE TABLE IF NOT EXISTS tag (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    color TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS note (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL DEFAULT '',
    content TEXT NOT NULL DEFAULT '',
    images TEXT NOT NULL DEFAULT '[]',
    pinned INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS todo (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    detail TEXT NOT NULL DEFAULT '',
    done INTEGER NOT NULL DEFAULT 0,
    priority INTEGER NOT NULL DEFAULT 1,
    due_at INTEGER NOT NULL DEFAULT 0,
    reminder_id INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS note_tag (
    note_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (note_id, tag_id)
  )`,
  `CREATE TABLE IF NOT EXISTS todo_tag (
    todo_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (todo_id, tag_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_note_updated ON note (updated_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_todo_due ON todo (due_at)`
];

export class Database {
  private static readonly instance: Database = new Database();
  private store: relationalStore.RdbStore | null = null;

  private constructor() {
  }

  static getInstance(): Database {
    return Database.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'mojian.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    for (const sql of SQL_CREATE) {
      await this.store.executeSql(sql);
    }
    await this.ensureColumn('note', 'images', "TEXT NOT NULL DEFAULT '[]'");
  }

  private async ensureColumn(table: string, column: string, definition: string): Promise<void> {
    const store: relationalStore.RdbStore = this.getStore();
    let exists: boolean = false;
    const result: relationalStore.ResultSet = await store.querySql(`PRAGMA table_info(${table})`);
    const nameIndex: number = result.getColumnIndex('name');
    while (result.goToNextRow()) {
      if (result.getString(nameIndex) === column) {
        exists = true;
      }
    }
    result.close();
    if (!exists) {
      await store.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
    }
  }

  getStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('Database is not initialized');
    }
    return this.store;
  }
}
