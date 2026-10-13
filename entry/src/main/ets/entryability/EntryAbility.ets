import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { MindMapStore } from '../services/MindMapStore';
import { ContinueService } from '../services/ContinueService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    this.saveLaunchIntent(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /** 把启动意图（深链 / 卡片 router 事件）写入 AppStorage，供 Index 消费路由 */
  private saveLaunchIntent(want: Want): void {
    AppStorage.setOrCreate<string>('launchUri', want.uri ?? '');
    const params = want.parameters as Record<string, Object> | undefined;
    AppStorage.setOrCreate<string>('launchAction', params && params['action'] ? String(params['action']) : '');
    AppStorage.setOrCreate<string>('launchNodeId', params && params['nodeId'] ? String(params['nodeId']) : '');
    // Wave 12：跨设备流转携带的导图 / 节点 id（onContinue 写入）
    AppStorage.setOrCreate<string>('launchMapId', params && params['continueMapId'] ? String(params['continueMapId']) : '');
    AppStorage.setOrCreate<string>('launchContinueNodeId', params && params['continueNodeId'] ? String(params['continueNodeId']) : '');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 应用已在后台时，被深链 / 卡片再次唤起：刷新启动意图（launchAction / launchNodeId），
    // 由 Index 在下次 aboutToAppear 消费路由。
    this.saveLaunchIntent(want);
  }

  /** 跨设备流转：把当前导图与停留节点 id 带入目标设备（onContinue 系统钩子） */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (snap) {
      wantParam['continueMapId'] = snap.id;
      const s = ContinueService.getInstance().get();
      if (s && s.nodeId.length > 0) {
        wantParam['continueNodeId'] = s.nodeId;
      }
    }
    return AbilityConstant.OnContinueResult.AGREE;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}