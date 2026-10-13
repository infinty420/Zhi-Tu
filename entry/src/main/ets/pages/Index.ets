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
import { ContinueService } from '../services/ContinueService';
import { CloudService } from '../services/CloudService';
import { ClassService } from '../services/ClassService';
import { AchievementService } from '../services/AchievementService';
import { HomePage } from './HomePage';
import { StudyHubPage } from './StudyHubPage';
import { CommunityHubPage } from './CommunityHubPage';
import { MineHubPage } from './MineHubPage';
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
import { PhotoQuizPage } from './PhotoQuizPage';
import { NodePage } from './NodePage';

@Entry
@Component
struct Index {
  @State selectedTab: number = 0;
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    AppContextHolder.install(getContext(this) as common.UIAbilityContext);
    MindMapStore.mountToAppStorage();
    MindMapStore.getInstance().ensureInit();
    AccountService.getInstance().init();
    ContinueService.getInstance().init();
    CloudService.getInstance().init();
    ClassService.getInstance().init();
    AchievementService.getInstance().init();
    DeepLinkRouter.attach(this.pathStack);
    this.consumeLaunchIntent();
  }

  aboutToDisappear(): void {
    DeepLinkRouter.detach();
  }

  /** 消费启动意图：深链 / 卡片 router 事件 / 跨设备流转 → 进入对应导图与节点 */
  private consumeLaunchIntent(): void {
    const store = MindMapStore.getInstance();
    const snap = store.currentSnapshot();
    if (!snap) {
      return;
    }
    const nodeId = AppStorage.get<string>('launchNodeId') ?? '';
    const action = AppStorage.get<string>('launchAction') ?? '';
    const continueMapId = AppStorage.get<string>('launchMapId') ?? '';
    const continueNodeId = AppStorage.get<string>('launchContinueNodeId') ?? '';

    // Wave 12：跨设备流转——先打开流转过来的导图，再跳转到上次停留节点
    if (continueMapId.length > 0 && continueMapId !== store.currentId()) {
      store.openMapById(continueMapId);
    }
    let targetId = nodeId;
    if (targetId.length === 0 && continueNodeId.length > 0) {
      targetId = continueNodeId;
    }
    if (targetId.length === 0 && action === 'review') {
      const now = Date.now();
      const due = store.dueReviewNodes().slice().sort((a, b) => MasteryPredictor.priority(b, now) - MasteryPredictor.priority(a, now));
      if (due.length > 0) {
        targetId = due[0].id;
      }
    }
    if (targetId.length > 0) {
      const node = store.currentSnapshot() ? store.currentSnapshot()!.findNode(targetId) : undefined;
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
    } else if (name === 'PhotoQuizPage') {
      PhotoQuizPage()
    } else if (name === 'NodePage') {
      NodePage()
    }
  }

  /** 切换分区：更新选中态并清空导航栈，回到目标分区的 Hub 根页 */
  private switchTab(index: number): void {
    if (index === this.selectedTab) {
      return;
    }
    this.selectedTab = index;
    this.pathStack.clear();
  }

  build() {
    Navigation(this.pathStack) {
      if (this.selectedTab === 0) {
        HomePage({ tabKey: 0, onTabChange: (i: number) => this.switchTab(i) })
      } else if (this.selectedTab === 1) {
        StudyHubPage({ tabKey: 1, onTabChange: (i: number) => this.switchTab(i) })
      } else if (this.selectedTab === 2) {
        CommunityHubPage({ tabKey: 2, onTabChange: (i: number) => this.switchTab(i) })
      } else {
        MineHubPage({ tabKey: 3, onTabChange: (i: number) => this.switchTab(i) })
      }
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
