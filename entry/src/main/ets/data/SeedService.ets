import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { NoteDao } from './NoteDao';
import { TagDao } from './TagDao';
import { TodoDao } from './TodoDao';
import { Note, Tag, Todo } from '../model/Models';
import { PREF_NAME, PREF_SEEDED, TAG_COLORS } from '../common/Constants';
import { nowMs, startOfDay } from '../common/Utils';

export class SeedService {
  static async seedIfNeeded(context: common.Context): Promise<void> {
    const pref: preferences.Preferences = await preferences.getPreferences(context, { name: PREF_NAME });
    const seeded: boolean = await pref.get(PREF_SEEDED, false) as boolean;
    if (seeded) {
      return;
    }
    const noteDao: NoteDao = new NoteDao();
    const tagDao: TagDao = new TagDao();
    const todoDao: TodoDao = new TodoDao();
    const existingNotes: Note[] = await noteDao.listAll();
    if (existingNotes.length === 0) {
      await SeedService.createSeedData(tagDao, noteDao, todoDao);
    }
    await pref.put(PREF_SEEDED, true);
    await pref.flush();
  }

  private static async createSeedData(tagDao: TagDao, noteDao: NoteDao, todoDao: TodoDao): Promise<void> {
    const base: number = nowMs();

    const work: Tag = await SeedService.addTag(tagDao, '工作', TAG_COLORS[5], base + 1);
    const life: Tag = await SeedService.addTag(tagDao, '生活', TAG_COLORS[3], base + 2);
    const idea: Tag = await SeedService.addTag(tagDao, '灵感', TAG_COLORS[7], base + 3);
    const read: Tag = await SeedService.addTag(tagDao, '读书', TAG_COLORS[6], base + 4);
    const urgent: Tag = await SeedService.addTag(tagDao, '紧急', TAG_COLORS[0], base + 5);

    const welcome: Note = new Note();
    welcome.title = '欢迎使用墨记';
    welcome.content = '墨记是一款原生鸿蒙笔记与待办应用，灵感来自开源项目 Notesnook。\n\n' +
      '你可以：\n' +
      '· 记录想法，并用彩色标签整理\n' +
      '· 添加带截止时间和优先级的待办\n' +
      '· 把「今日待办」服务卡片放到桌面\n' +
      '· 为待办设置到期提醒\n' +
      '· 导出 JSON 备份，换机后随时恢复\n\n' +
      '所有数据都保存在本机，不上传云端。';
    welcome.pinned = true;
    welcome.createdAt = base - 3 * 86400000;
    welcome.updatedAt = base - 120000;
    await noteDao.save(welcome, [idea.id, life.id]);

    const reading: Note = new Note();
    reading.title = '读书笔记 ·《纳瓦尔宝典》';
    reading.content = '财富是睡后仍在增长的收入，而不是用时间换钱。\n\n' +
      '把自己产品化：找到只有你能做、社会又需要的事，然后规模化。\n\n' +
      '判断力比努力更重要。杠杆有三种：劳动力、资本、代码与媒体。';
    reading.createdAt = base - 2 * 86400000;
    reading.updatedAt = base - 2 * 3600000;
    await noteDao.save(reading, [read.id]);

    const product: Note = new Note();
    product.title = '产品灵感清单';
    product.content = '1. 服务卡片展示今日三件最重要的事。\n' +
      '2. 标签颜色即语义：红色紧急、蓝色工作、绿色生活。\n' +
      '3. 编辑器自动保存，退出即同步。\n' +
      '4. 每周回顾：把未完成的待办重新排序。';
    product.createdAt = base - 86400000;
    product.updatedAt = base - 30 * 60000;
    await noteDao.save(product, [idea.id, work.id]);

    const today: number = startOfDay(base);

    const todo1: Todo = new Todo();
    todo1.title = '整理会议纪要并同步给团队';
    todo1.detail = '把上午讨论的三个方案整理成一页纸，标记需要拍板的点。';
    todo1.priority = 2;
    todo1.dueAt = today + 18 * 3600000;
    todo1.createdAt = base - 5 * 3600000;
    todo1.updatedAt = base - 5 * 3600000;
    await todoDao.save(todo1, [work.id, urgent.id]);

    const todo2: Todo = new Todo();
    todo2.title = '给阳台的绿植浇水';
    todo2.detail = '';
    todo2.priority = 1;
    todo2.dueAt = today + 24 * 3600000 + 9 * 3600000;
    todo2.createdAt = base - 86400000;
    todo2.updatedAt = base - 86400000;
    await todoDao.save(todo2, [life.id]);

    const todo3: Todo = new Todo();
    todo3.title = '读完《纳瓦尔宝典》第三章';
    todo3.detail = '把有启发的句子摘录到读书笔记。';
    todo3.done = true;
    todo3.priority = 1;
    todo3.createdAt = base - 3 * 86400000;
    todo3.updatedAt = base - 3600000;
    await todoDao.save(todo3, [read.id]);

    const todo4: Todo = new Todo();
    todo4.title = '准备下周分享会提纲';
    todo4.detail = '主题：如何用服务卡片提升效率。';
    todo4.priority = 1;
    todo4.dueAt = today + 2 * 86400000 + 14 * 3600000;
    todo4.createdAt = base - 2 * 3600000;
    todo4.updatedAt = base - 2 * 3600000;
    await todoDao.save(todo4, [work.id, idea.id]);
  }

  private static async addTag(tagDao: TagDao, name: string, color: string, createdAt: number): Promise<Tag> {
    const tag: Tag = new Tag();
    tag.name = name;
    tag.color = color;
    tag.createdAt = createdAt;
    tag.id = await tagDao.save(tag);
    return tag;
  }
}
