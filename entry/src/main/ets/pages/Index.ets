/**
 * Index —— 根页面：Navigation (NavPathStack) 容器。
 * 注册首页 + 全部 NavDestination（导图主界面、我的导图、专项子界面 + v2.0 一起学 + 通用节点详情页）。
 */
import { common } from '@kit.AbilityKit';

import { AppContextHolder } from '../utils/AppContext';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { MindMapStore } from '../services/MindMapStore';
import { MasteryPredictor } from '../services/MasteryPredictor';
import { NodeType } from '../model/Constants';
import { AccountService } from '../services/AccountService';
import { CloudService } from '../services/CloudService';
import { ClassService } from '../services/ClassService';
import { HomePage } from './HomePage';
import { MindMapPage } from './MindMapPage';
import { MyMapsPage } from './MyMapsPage';
import { MathPlotPage } from './MathPlotPage';
import { PhysicsSimPage } from './PhysicsSimPage';
import { EnglishExamplesPage } from './EnglishExamplesPage';
import { StudyPage } from './StudyPage';
import { StatsPage } from './StatsPage';
import { WrongBookPage } from './WrongBookPage';
import { HistoryTimelinePage } from './HistoryTimelinePage';
import { GeoMapPage } from './GeoMapPage';
import { ChemPage } from './ChemPage';
import { BioPage } from './BioPage';
import { AccountPage } from './AccountPage';
import { SharePage } from './SharePage';
import { MarketPage } from './MarketPage';
import { ClassPage } from './ClassPage';
import { SearchPage } from './SearchPage';
import { NodePage } from './NodePage';

@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    AppContextHolder.install(getContext(this) as common.UIAbilityContext);
    MindMapStore.mountToAppStorage();
    MindMapStore.getInstance().ensureInit();
    AccountService.getInstance().init();
    CloudService.getInstance().init();
    ClassService.getInstance().init();
    DeepLinkRouter.attach(this.pathStack);
    this.consumeLaunchIntent();
  }

  aboutToDisappear(): void {
    DeepLinkRouter.detach();
  }

  /** 消费启动意图：深链 / 卡片 router 事件 → 经 DeepLinkRouter 进入对应节点或复习 */
  private consumeLaunchIntent(): void {
    const store = MindMapStore.getInstance();
    const snap = store.currentSnapshot();
    if (!snap) {
      return;
    }
    const nodeId = AppStorage.get<string>('launchNodeId') ?? '';
    const action = AppStorage.get<string>('launchAction') ?? '';
    let targetId = nodeId;
    if (targetId.length === 0 && action === 'review') {
      const now = Date.now();
      const due = store.dueReviewNodes().slice().sort((a, b) => MasteryPredictor.priority(b, now) - MasteryPredictor.priority(a, now));
      if (due.length > 0) {
        targetId = due[0].id;
      }
    }
    if (targetId.length > 0) {
      const node = snap.findNode(targetId);
      const type = node ? node.type : NodeType.GENERAL;
      DeepLinkRouter.route(targetId, type, '');
    }
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'MindMapPage') {
      MindMapPage()
    } else if (name === 'MyMapsPage') {
      MyMapsPage()
    } else if (name === 'MathPlotPage') {
      MathPlotPage()
    } else if (name === 'PhysicsSimPage') {
      PhysicsSimPage()
    } else if (name === 'EnglishExamplesPage') {
      EnglishExamplesPage()
    } else if (name === 'StudyPage') {
      StudyPage({ mapId: param as string })
    } else if (name === 'StatsPage') {
      StatsPage()
    } else if (name === 'WrongBookPage') {
      WrongBookPage()
    } else if (name === 'HistoryTimelinePage') {
      HistoryTimelinePage()
    } else if (name === 'GeoMapPage') {
      GeoMapPage()
    } else if (name === 'ChemPage') {
      ChemPage()
    } else if (name === 'BioPage') {
      BioPage()
    } else if (name === 'AccountPage') {
      AccountPage()
    } else if (name === 'SharePage') {
      SharePage()
    } else if (name === 'MarketPage') {
      MarketPage()
    } else if (name === 'ClassPage') {
      ClassPage()
    } else if (name === 'SearchPage') {
      SearchPage()
    } else if (name === 'NodePage') {
      NodePage()
    }
  }

  build() {
    Navigation(this.pathStack) {
      HomePage()
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
