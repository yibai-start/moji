import { formBindingData, formInfo, formProvider, FormExtensionAbility } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WidgetService } from '../service/WidgetService';
import { WidgetData } from '../model/Models';

export default class TodoFormAbility extends FormExtensionAbility {
  private widgetService: WidgetService = new WidgetService();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const rawId: Object | undefined = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
    const formId: string = rawId === undefined ? '' : rawId as string;
    this.widgetService.addFormIdSync(this.context, formId);
    const data: WidgetData = this.widgetService.readDataSync(this.context);
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    const data: WidgetData = this.widgetService.readDataSync(this.context);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
  }

  onRemoveForm(formId: string): void {
    this.widgetService.removeFormIdSync(this.context, formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
