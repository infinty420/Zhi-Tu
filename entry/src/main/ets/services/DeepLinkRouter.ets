/**
 * DeepLinkRouter —— 深链路由与回填（导航深链族）。
 * 按 nodeType 压栈 NavDestination；general 跳转通用节点详情页 NodePage；
 * backfill 以「【回填】来源标识：内容」前缀追加写入节点 detail，不覆盖用户已有内容。
 */

import { NodeType } from '../model/Constants';
import { DeepLink } from '../model/DeepLink';
import { MindMapStore } from './MindMapStore';
import { Logger } from '../utils/Logger';

const DEEP_LINK_KEY = 'zhitu_deepLink';

/** 节点类型 → 深链页面名（与 Index.ets NavDestination 注册一致） */
const NODE_TYPE_PAGE: Map<NodeType, string> = new Map<NodeType, string>([
  [NodeType.GENERAL, 'NodePage'],
  [NodeType.MATH, 'MathPlotPage'],
  [NodeType.PHYSICS, 'PhysicsSimPage'],
  [NodeType.ENGLISH, 'EnglishExamplesPage'],
  [NodeType.HISTORY, 'HistoryTimelinePage'],
  [NodeType.GEO, 'GeoMapPage'],
  [NodeType.CHEM, 'ChemPage'],
  [NodeType.BIO, 'BioPage']
]);

export class DeepLinkRouter {
  private static stack: NavPathStack | undefined = undefined;

  static attach(stack: NavPathStack): void {
    DeepLinkRouter.stack = stack;
  }

  static detach(): void {
    DeepLinkRouter.stack = undefined;
  }

  static async route(nodeId: string, nodeType: NodeType, payload: string): Promise<void> {
    const stack = DeepLinkRouter.stack;
    if (!stack) {
      Logger.error('DeepLinkRouter', 'nav stack not attached');
      return;
    }
    const routeName = DeepLinkRouter.routeName(nodeType);
    if (routeName.length === 0) {
      Logger.warn('DeepLinkRouter', `no route for type ${nodeType}`);
      return;
    }
    const link = DeepLink.create(nodeId, nodeType, payload);
    AppStorage.setOrCreate<DeepLink>(DEEP_LINK_KEY, link);
    try {
      stack.pushPathByName(routeName, link);
    } catch (err) {
      Logger.error('DeepLinkRouter', `push ${routeName} failed: ${JSON.stringify(err as Object)}`);
    }
  }

  /** 通用入栈导航 */
  static push(name: string): void {
    DeepLinkRouter.pushWithParam(name, undefined);
  }

  /** 带参数入栈导航（如 StudyPage 需要 mapId） */
  static pushWithParam(name: string, param: Object | undefined): void {
    const stack = DeepLinkRouter.stack;
    if (!stack) {
      return;
    }
    try {
      stack.pushPathByName(name, param);
    } catch (err) {
      Logger.error('DeepLinkRouter', `push ${name} failed: ${JSON.stringify(err as Object)}`);
    }
  }

  /** 出栈返回 */
  static pop(): void {
    const stack = DeepLinkRouter.stack;
    if (!stack) {
      return;
    }
    try {
      stack.pop();
    } catch (err) {
      Logger.error('DeepLinkRouter', `pop failed: ${JSON.stringify(err as Object)}`);
    }
  }

  static currentLink(): DeepLink {
    const stored = AppStorage.get<DeepLink>(DEEP_LINK_KEY);
    if (stored) {
      return stored;
    }
    return DeepLink.create('', NodeType.GENERAL, '');
  }

  static routeName(type: NodeType): string {
    const name = NODE_TYPE_PAGE.get(type);
    if (name && name.length > 0) {
      return name;
    }
    return '';
  }

  /** 结果回填：追加写入节点 detail（不覆盖用户已有内容） */
  static backfill(nodeId: string, content: string): void {
    if (!nodeId || nodeId.length === 0 || !content || content.length === 0) {
      Logger.warn('DeepLinkRouter', 'backfill ignored: empty args');
      return;
    }
    const store = MindMapStore.getInstance();
    const snap = store.currentSnapshot();
    if (snap && snap.findNode(nodeId)) {
      const text = `【回填】专项学习：${content}`;
      store.updateDetail(nodeId, text, 'append');
      Logger.aiRequest('DeepLinkRouter', 'backfill', nodeId);
    } else {
      Logger.warn('DeepLinkRouter', `backfill node missing: ${nodeId}`);
    }
  }
}
