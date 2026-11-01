import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Todo } from '../model/Models';
import { BUNDLE_NAME, ENTRY_ABILITY } from '../common/Constants';
import { nowMs } from '../common/Utils';

const DOMAIN: number = 0x0001;
const TAG: string = 'ReminderService';

export class ReminderService {
  async ensureNotification(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      await notificationManager.requestEnableNotification(context);
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'request notification failed: %{public}s', e.message);
      return false;
    }
  }

  async schedule(todo: Todo): Promise<number> {
    if (todo.dueAt <= nowMs()) {
      return 0;
    }
    if (todo.reminderId > 0) {
      await this.cancel(todo.reminderId);
    }
    const date: Date = new Date(todo.dueAt);
    const wantAgent: reminderAgentManager.WantAgent = {
      pkgName: BUNDLE_NAME,
      abilityName: ENTRY_ABILITY
    };
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: date.getFullYear(),
        month: date.getMonth() + 1,
        day: date.getDate(),
        hour: date.getHours(),
        minute: date.getMinutes(),
        second: 0
      },
      title: '待办提醒',
      content: todo.title.length === 0 ? '你有一条待办需要处理' : todo.title,
      wantAgent: wantAgent,
      ringDuration: 3,
      snoozeTimes: 0
    };
    try {
      return await reminderAgentManager.publishReminder(request);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'publish reminder failed: %{public}s', e.message);
      return 0;
    }
  }

  async cancel(reminderId: number): Promise<void> {
    if (reminderId <= 0) {
      return;
    }
    try {
      await reminderAgentManager.cancelReminder(reminderId);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'cancel reminder failed: %{public}s', e.message);
    }
  }
}
