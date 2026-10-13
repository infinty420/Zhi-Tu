/**
 * FormAbility —— 智图桌面速记卡片（Wave 6）。
 * 长按桌面「智图」卡片可添加；卡片展示一句复习引导，点击经 router 事件唤起 App 进入复习。
 */

import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';

/** 卡片初始绑定数据（键名与 FormCard.ets 的 @LocalStorageProp 对应） */
interface FormInitData {
  title: string;
  tip: string;
  reviewText: string;
}

export default class FormAbility extends FormExtensionAbility {
  /** 卡片首次添加：返回初始绑定数据（键名与 FormCard.ets 的 @LocalStorageProp 对应） */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const data: FormInitData = {
      title: '智图 · 今日复习',
      tip: '点卡片，进入一个待复习知识点',
      reviewText: '开始复习'
    };
    return formBindingData.createFormBindingData(data);
  }

  onCastToNormalForm(formId: string): void {
    // 卡片从暂态转为常态（本应用无需额外处理）
  }

  onUpdateForm(formId: string): void {
    // 更新开关关闭，暂无需主动刷新
  }

  onRemoveForm(formId: string): void {
    // 卡片移除时的清理（本应用无需额外处理）
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片自定义事件（本应用未定义 message 协议）
  }
}
