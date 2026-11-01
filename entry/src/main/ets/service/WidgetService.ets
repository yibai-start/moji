import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Todo, WidgetData } from '../model/Models';
import { PREF_FORM_IDS, PREF_NAME, PREF_WIDGET_DATA } from '../common/Constants';
import { endOfDay, nowMs, startOfDay, todayLabel, truncate } from '../common/Utils';

const DOMAIN: number = 0x0001;
const TAG: string = 'WidgetService';

export class WidgetService {
  async publish(context: common.Context, todos: Todo[]): Promise<void> {
    const data: WidgetData = this.buildData(todos);
    try {
      const pref: preferences.Preferences = await preferences.getPreferences(context, { name: PREF_NAME });
      await pref.put(PREF_WIDGET_DATA, JSON.stringify(data));
      await pref.flush();
      const raw: string = await pref.get(PREF_FORM_IDS, '[]') as string;
      const formIds: string[] = JSON.parse(raw) as string[];
      for (const formId of formIds) {
        try {
          await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
        } catch (err) {
          const e = err as BusinessError;
          hilog.warn(DOMAIN, TAG, 'update form %{public}s failed: %{public}s', formId, e.message);
        }
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'publish widget data failed: %{public}s', e.message);
    }
  }

  buildData(todos: Todo[]): WidgetData {
    const now: number = nowMs();
    const dayStart: number = startOfDay(now);
    const dayEnd: number = endOfDay(now);
    const dueToday: Todo[] = todos.filter((t: Todo) => t.dueAt > 0 && t.dueAt >= dayStart && t.dueAt <= dayEnd);
    const isTodayMode: boolean = dueToday.length > 0;
    const scope: Todo[] = isTodayMode ? dueToday : todos;
    const active: Todo[] = scope.filter((t: Todo) => !t.done);
    const data: WidgetData = new WidgetData();
    data.todayLabel = todayLabel();
    data.totalCount = scope.length;
    data.doneCount = scope.filter((t: Todo) => t.done).length;
    data.item1 = active.length > 0 ? truncate(active[0].title, 16) : '';
    data.item2 = active.length > 1 ? truncate(active[1].title, 16) : '';
    data.item3 = active.length > 2 ? truncate(active[2].title, 16) : '';
    if (active.length === 0) {
      data.emptyText = isTodayMode ? '今天的待办已完成' : '暂无待办事项';
    } else if (!isTodayMode) {
      data.emptyText = '今天没有到期的待办';
    }
    return data;
  }

  readDataSync(context: common.Context): WidgetData {
    try {
      const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const raw: string = pref.getSync(PREF_WIDGET_DATA, '') as string;
      if (raw.length === 0) {
        const empty: WidgetData = new WidgetData();
        empty.emptyText = '打开墨记查看今日待办';
        return empty;
      }
      return JSON.parse(raw) as WidgetData;
    } catch (err) {
      return new WidgetData();
    }
  }

  addFormIdSync(context: common.Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    try {
      const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const raw: string = pref.getSync(PREF_FORM_IDS, '[]') as string;
      const formIds: string[] = JSON.parse(raw) as string[];
      if (formIds.indexOf(formId) < 0) {
        formIds.push(formId);
        pref.putSync(PREF_FORM_IDS, JSON.stringify(formIds));
        pref.flushSync();
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'add form id sync failed: %{public}s', e.message);
    }
  }

  removeFormIdSync(context: common.Context, formId: string): void {
    try {
      const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const raw: string = pref.getSync(PREF_FORM_IDS, '[]') as string;
      const formIds: string[] = JSON.parse(raw) as string[];
      const index: number = formIds.indexOf(formId);
      if (index >= 0) {
        formIds.splice(index, 1);
        pref.putSync(PREF_FORM_IDS, JSON.stringify(formIds));
        pref.flushSync();
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'remove form id sync failed: %{public}s', e.message);
    }
  }
}
