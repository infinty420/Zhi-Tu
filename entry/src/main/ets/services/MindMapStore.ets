/**
 * MindMapStore —— 全局可观察导图仓库（单例 @Observed，挂载 AppStorage）。
 * 提供导图 CRUD、节点级命令、订阅机制与防抖实时持久化。
 */

import { Layout, MasteryLevel, ModelResult, NodeType, TITLE_MAX_LEN, failResult, okResult } from '../model/Constants';
import { LearningEvent, LearningEventType, StudyStats, VocabItem, WrongItem } from '../model/StudyModels';
import { MindMap } from '../model/MindMap';
import { MindNode, NodeRichContent, NodeRichMedia, NodeStyle, KeyPointItem, KeyPointLevel } from '../model/MindNode';
import { TreeOps } from '../model/TreeOps';
import { GenUid } from '../utils/GenUid';
import { Logger } from '../utils/Logger';
import { ReviewScheduler } from './ReviewScheduler';
import { StorageService } from './StorageService';

export interface MindMapSummary {
  id: string;
  title: string;
  subject: string;
  updatedAt: number;
  damaged: boolean;
}

export type StoreListener = (snapshot: MindMap | undefined) => void;
export type SaveErrorListener = (message: string) => void;

@Observed
export class MindMapStore {
  private static _instance: MindMapStore | undefined = undefined;

  private current: MindMap | undefined = undefined;
  private listeners: StoreListener[] = [];
  private saveErrorListeners: SaveErrorListener[] = [];
  private debounceTimer: number | undefined = undefined;
  private storage: StorageService = new StorageService();
  private initialized: boolean = false;

  static getInstance(): MindMapStore {
    if (MindMapStore._instance === undefined) {
      MindMapStore._instance = new MindMapStore();
    }
    return MindMapStore._instance;
  }

  static mountToAppStorage(): void {
    const instance = MindMapStore.getInstance();
    if (!AppStorage.has('mindMapStore')) {
      AppStorage.setOrCreate<MindMapStore>('mindMapStore', instance);
    }
  }

  /** 初始化存储连接（页面 aboutToAppear 时调用一次） */
  async ensureInit(): Promise<void> {
    if (this.initialized) {
      return;
    }
    await this.storage.init();
    this.initialized = true;
  }

  async ensureLoaded(): Promise<void> {
    if (this.current !== undefined) {
      return;
    }
    const recentId = await this.storage.loadRecent();
    if (recentId) {
      const map = await this.storage.loadMap(recentId);
      if (map) {
        this.current = map;
        this.notify();
      }
    }
  }

  // ---------- 查询 ----------
  list(): MindMapSummary[] {
    return this.storage.listSummaries();
  }

  get(id: string): MindMap | undefined {
    if (this.current && this.current.id === id) {
      return this.currentPromiseClone();
    }
    return undefined;
  }

  currentSnapshot(): MindMap | undefined {
    return this.currentClone();
  }

  hasCurrent(): boolean {
    return this.current !== undefined;
  }

  currentId(): string {
    return this.current ? this.current.id : '';
  }

  private currentClone(): MindMap | undefined {
    if (!this.current) {
      return undefined;
    }
    return this.current.clone();
  }

  private currentPromiseClone(): MindMap | undefined {
    return this.currentClone();
  }

  // ---------- 导图级命令 ----------
  createEmpty(subject?: string): string {
    const id = GenUid.nextMapId();
    const label = subject && subject.length > 0 ? `${subject}导图` : '新建导图';
    const map = MindMap.create(id, label, subject ? subject : '', '');
    const root = MindNode.create(GenUid.nextNodeId(), '中心主题', null, NodeType.GENERAL);
    map.nodes.push(root);
    this.current = map;
    this.storage.updateSummary(map.id, map.title, map.subject, map.updatedAt, false);
    this.notify();
    return id;
  }

  importMap(json: string): ModelResult<string> {
    const map = MindMap.fromJson(json);
    if (!map) {
      return failResult('导图 JSON 解析失败');
    }
    const validation = map.validate();
    if (!validation.ok) {
      return failResult('导图结构不合法：' + validation.errors.join(';'));
    }
    if (!map.id || map.id.length === 0) {
      map.id = GenUid.nextMapId();
    }
    map.updatedAt = Date.now();
    this.current = map;
    this.storage.updateSummary(map.id, map.title, map.subject, map.updatedAt, false);
    this.flushPersist();
    this.notify();
    return okResult(map.id);
  }

  /** 已存在导图时以新建导图产出，不覆盖已有（spec 5.1.1-7） */
  importAsNew(json: string): ModelResult<string> {
    const map = MindMap.fromJson(json);
    if (!map) {
      return failResult('导图 JSON 解析失败');
    }
    const validation = map.validate();
    if (!validation.ok) {
      return failResult('导图结构不合法：' + validation.errors.join(';'));
    }
    map.id = GenUid.nextMapId();
    map.updatedAt = Date.now();
    this.current = map;
    this.storage.updateSummary(map.id, map.title, map.subject, map.updatedAt, false);
    this.flushPersist();
    this.notify();
    return okResult(map.id);
  }

  deleteMap(id: string): void {
    if (this.current && this.current.id === id) {
      this.current = undefined;
    }
    this.storage.deleteMap(id);
    this.notify();
  }

  setCurrentMap(map: MindMap): void {
    this.current = map;
    this.storage.setRecent(map.id);
    this.storage.updateSummary(map.id, map.title, map.subject, map.updatedAt, false);
    this.flushPersist();
    this.notify();
  }

  /** 只读加载指定导图（不改变当前导图，供全局搜索等只读场景使用） */
  async peekMap(id: string): Promise<MindMap | undefined> {
    await this.ensureInit();
    return this.storage.loadMap(id);
  }

  /** 从本地加载并打开指定导图（损坏返回 false） */
  async openMapById(id: string): Promise<boolean> {
    await this.ensureInit();
    const map = await this.storage.loadMap(id);
    if (!map) {
      return false;
    }
    this.current = map;
    this.storage.setRecent(map.id);
    this.notify();
    return true;
  }

  // ---------- 节点级命令 ----------
  addNode(parentId: string, text: string, type: NodeType): ModelResult<string> {
    const map = this.current;
    if (!map) {
      return failResult('当前无导图');
    }
    if (!map.findNode(parentId)) {
      return failResult('父节点不存在');
    }
    const finalText = text.length > 100 ? text.substring(0, 100) : text;
    const node = MindNode.create(GenUid.nextNodeId(), finalText, parentId, type);
    node.userEdited = true;
    map.nodes.push(node);
    this.schedulePersist();
    return okResult(node.id);
  }

  removeNode(id: string, cascade: boolean): ModelResult<void> {
    const map = this.current;
    if (!map) {
      return failResult('当前无导图');
    }
    const node = map.findNode(id);
    if (!node) {
      return failResult('节点不存在');
    }
    if (node.parentId === null) {
      return failResult('根节点不可删除');
    }
    if (!cascade && node.childrenOf(map).length > 0) {
      return failResult('请先确认级联删除');
    }
    const toRemove = TreeOps.collectSubtreeIds(map.nodes, id);
    map.nodes = map.nodes.filter((n) => !toRemove.includes(n.id));
    this.schedulePersist();
    return okResult(undefined);
  }

  renameNode(id: string, text: string): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(id);
    if (!node) {
      return;
    }
    node.text = text.length > 100 ? text.substring(0, 100) : text;
    node.userEdited = true;
    this.schedulePersist();
  }

  /** 移动节点（含环检测），index 为兄弟位置（-1=末尾） */
  moveNode(id: string, newParentId: string, index?: number): ModelResult<void> {
    const map = this.current;
    if (!map) {
      return failResult('当前无导图');
    }
    if (!map.findNode(id)) {
      return failResult('节点不存在');
    }
    if (!map.findNode(newParentId)) {
      return failResult('目标节点不存在');
    }
    if (id === newParentId) {
      return failResult('不能将节点移动到其自身下');
    }
    if (TreeOps.isAncestorOf(map.nodes, id, newParentId)) {
      return failResult('不能将节点移动到其自身子树下');
    }
    const finalIndex = index !== undefined && index !== null ? index : -1;
    map.nodes = TreeOps.reorderSiblings(map.nodes, id, newParentId, finalIndex);
    this.schedulePersist();
    return okResult(undefined);
  }

  retypeNode(id: string, type: NodeType): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(id);
    if (!node) {
      return;
    }
    node.type = type;
    node.userEdited = true;
    this.schedulePersist();
  }

  restyleNode(id: string, style: Partial<NodeStyle>): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(id);
    if (!node) {
      return;
    }
    if (style.color && style.color.length > 0) {
      node.style.color = style.color;
    }
    if (style.shape) {
      node.style.shape = style.shape;
    }
    node.userEdited = true;
    this.schedulePersist();
  }

  /** 批量应用样式：只改类型匹配的节点（Agent restyle 全量应用） */
  restyleNodesByIds(ids: string[], style: Partial<NodeStyle>): number {
    const map = this.current;
    if (!map) {
      return 0;
    }
    let applied = 0;
    for (let i = 0; i < ids.length; i++) {
      const node = map.findNode(ids[i]);
      if (node) {
        if (style.color && style.color.length > 0) {
          node.style.color = style.color;
        }
        if (style.shape) {
          node.style.shape = style.shape;
        }
        node.userEdited = true;
        applied++;
      }
    }
    if (applied > 0) {
      this.schedulePersist();
    }
    return applied;
  }

  updateDetail(id: string, detail: string, mode: 'replace' | 'append'): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(id);
    if (!node) {
      return;
    }
    if (mode === 'append') {
      node.detail = node.detail.length > 0 ? `${node.detail}\n${detail}` : detail;
    } else {
      node.detail = detail;
    }
    node.userEdited = true;
    this.schedulePersist();
  }

  setCollapsed(id: string, collapsed: boolean): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(id);
    if (!node) {
      return;
    }
    node.collapsed = collapsed;
    this.schedulePersist();
  }

  setLayout(layout: Layout): void {
    const map = this.current;
    if (!map) {
      return;
    }
    map.layout = layout;
    this.schedulePersist();
  }

  setTheme(theme: string): void {
    const map = this.current;
    if (!map) {
      return;
    }
    if (theme === 'ocean' || theme === 'forest' || theme === 'sunset') {
      map.theme = theme;
      this.schedulePersist();
    }
  }

  updateTitle(title: string): void {
    const map = this.current;
    if (!map) {
      return;
    }
    map.title = title.length > TITLE_MAX_LEN ? title.substring(0, TITLE_MAX_LEN) : title;
    this.schedulePersist();
  }

  // ---------- v1.1 学习闭环命令 ----------

  /** 标记节点掌握度（学习模式）。记录一次 study 学习事件，触发持久化。 */
  setMastery(nodeId: string, mastery: MasteryLevel): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    if (!node) {
      return;
    }
    node.mastery = mastery;
    if (mastery === MasteryLevel.KNOWN) {
      ReviewScheduler.clear(node);
    } else if (mastery === MasteryLevel.UNKNOWN || mastery === MasteryLevel.FUZZY) {
      // 标记为不会 / 模糊时，立即排入复习队列
      ReviewScheduler.scheduleNext(node);
    }
    this.recordStudyEvent(nodeId, LearningEventType.STUDY, mastery);
    this.schedulePersist();
  }

  /** 更新节点媒体富内容（图片/公式字符串/链接/标签），整体替换（v1.2） */
  updateRich(nodeId: string, rich: NodeRichMedia): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    if (!node) {
      return;
    }
    node.rich = {
      images: rich.images,
      formula: rich.formula,
      links: rich.links,
      tags: rich.tags
    };
    this.schedulePersist();
  }

  // ---------- Phase X 学科化富内容命令 ----------

  /**
   * 合并更新学科化富内容。
   * mode='replace'：用 patch 整体替换 node.richContent；
   * mode='append'：按字段合并（数组在末尾追加、学科专项槽位整体覆盖、引用按 url 去重）。
   * 已存在的用户要点（addedBy='user'）在 append 时不被覆盖。
   */
  updateRichContent(nodeId: string, patch: Partial<NodeRichContent>, mode: 'replace' | 'append'): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    if (!node) {
      return;
    }
    if (mode === 'replace') {
      const merged: NodeRichContent = {
        keyPoints: patch.keyPoints ? patch.keyPoints : node.richContent.keyPoints,
        formulas: patch.formulas ? patch.formulas : node.richContent.formulas,
        examples: patch.examples ? patch.examples : node.richContent.examples,
        misconceptions: patch.misconceptions ? patch.misconceptions : node.richContent.misconceptions,
        references: patch.references ? patch.references : node.richContent.references,
        chinese: patch.chinese ? patch.chinese : node.richContent.chinese,
        history: patch.history ? patch.history : node.richContent.history,
        geography: patch.geography ? patch.geography : node.richContent.geography,
        chemistry: patch.chemistry ? patch.chemistry : node.richContent.chemistry,
        biology: patch.biology ? patch.biology : node.richContent.biology,
        politics: patch.politics ? patch.politics : node.richContent.politics,
        english: patch.english ? patch.english : node.richContent.english
      };
      node.richContent = merged;
    } else {
      const cur = node.richContent;
      if (patch.keyPoints) {
        cur.keyPoints = cur.keyPoints.concat(patch.keyPoints);
      }
      if (patch.formulas) {
        cur.formulas = cur.formulas.concat(patch.formulas);
      }
      if (patch.examples) {
        cur.examples = cur.examples.concat(patch.examples);
      }
      if (patch.misconceptions) {
        cur.misconceptions = cur.misconceptions.concat(patch.misconceptions);
      }
      if (patch.references) {
        const seen: string[] = cur.references.map((r) => r.url);
        for (let i = 0; i < patch.references.length; i++) {
          if (seen.indexOf(patch.references[i].url) < 0) {
            cur.references.push(patch.references[i]);
          }
        }
      }
      if (patch.chinese) {
        cur.chinese = patch.chinese;
      }
      if (patch.history) {
        cur.history = patch.history;
      }
      if (patch.geography) {
        cur.geography = patch.geography;
      }
      if (patch.chemistry) {
        cur.chemistry = patch.chemistry;
      }
      if (patch.biology) {
        cur.biology = patch.biology;
      }
      if (patch.politics) {
        cur.politics = patch.politics;
      }
      if (patch.english) {
        cur.english = patch.english;
      }
    }
    node.userEdited = true;
    this.schedulePersist();
  }

  /** 新增一条核心要点（AI 或用户手动补充） */
  addKeyPoint(nodeId: string, text: string, level: KeyPointLevel): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    if (!node) {
      return;
    }
    const kp: KeyPointItem = {
      id: `kp_${GenUid.nextWrongId()}_${node.richContent.keyPoints.length}`,
      text: text,
      level: level,
      memorized: false,
      addedBy: 'user'
    };
    node.richContent.keyPoints.push(kp);
    node.userEdited = true;
    this.schedulePersist();
  }

  /** 删除一条要点 */
  removeKeyPoint(nodeId: string, keyPointId: string): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    if (!node) {
      return;
    }
    node.richContent.keyPoints = node.richContent.keyPoints.filter((k) => k.id !== keyPointId);
    node.userEdited = true;
    this.schedulePersist();
  }

  /** 标记一条要点是否已记住 */
  markKeyPointMemorized(nodeId: string, keyPointId: string, memorized: boolean): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    if (!node) {
      return;
    }
    for (let i = 0; i < node.richContent.keyPoints.length; i++) {
      if (node.richContent.keyPoints[i].id === keyPointId) {
        node.richContent.keyPoints[i].memorized = memorized;
        break;
      }
    }
    this.schedulePersist();
  }

  /** 自测判分后的结果归集：更新掌握度、错题本、复习排队 */
  recordQuiz(nodeId: string, correct: boolean, question: string, answer: string, userAnswer: string): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    const mastery: MasteryLevel = correct ? MasteryLevel.KNOWN : MasteryLevel.UNKNOWN;
    if (node) {
      node.lastReviewedAt = Date.now();
      node.mastery = mastery;
      if (correct) {
        ReviewScheduler.clear(node);
      } else {
        node.wrongCount = node.wrongCount + 1;
        ReviewScheduler.scheduleNext(node);
      }
    }
    this.recordStudyEvent(nodeId, LearningEventType.QUIZ, mastery, correct);
    if (!correct && node) {
      const wrong: WrongItem = {
        id: GenUid.nextWrongId(),
        mapId: map.id,
        nodeId: node.id,
        nodeText: node.text,
        question: question,
        answer: answer,
        userAnswer: userAnswer,
        createdAt: Date.now()
      };
      this.storage.addWrongItem(wrong);
    }
    this.schedulePersist();
  }

  /** 复习消项：标记已会并推进阶梯（超过阶梯则清除） */
  markReviewed(nodeId: string): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const node = map.findNode(nodeId);
    if (!node) {
      return;
    }
    node.mastery = MasteryLevel.KNOWN;
    node.lastReviewedAt = Date.now();
    if (node.reviewCount >= ReviewScheduler.INTERVALS.length) {
      ReviewScheduler.clear(node);
    } else {
      ReviewScheduler.scheduleNext(node);
    }
    this.recordStudyEvent(nodeId, LearningEventType.REVIEW, MasteryLevel.KNOWN, true);
    this.schedulePersist();
  }

  /** 今日待复习数量（基于当前导图） */
  dueReviewCount(): number {
    const map = this.current;
    if (!map) {
      return 0;
    }
    return ReviewScheduler.dueCount(map);
  }

  /** 当前导图待复习节点（供首页卡片 / 深链路由复用） */
  dueReviewNodes(): MindNode[] {
    const map = this.current;
    if (!map) {
      return [];
    }
    return ReviewScheduler.dueNodes(map);
  }

  /** 学习统计快照（基于当前导图） */
  getStudyStats(): StudyStats {
    const map = this.current;
    return this.storage.computeStudyStats(map ? map : new MindMap());
  }

  getWrongItems(): WrongItem[] {
    return this.storage.getWrongItems();
  }

  /** 学习事件（只读，供学情报告 / 周报月报聚合） */
  getLearningEvents(): LearningEvent[] {
    return this.storage.getLearningEvents();
  }

  removeWrongItem(id: string): void {
    this.storage.removeWrongItem(id);
  }

  getVocabItems(): VocabItem[] {
    return this.storage.getVocabItems();
  }

  addVocabItem(item: VocabItem): void {
    this.storage.addVocabItem(item);
  }

  removeVocabItem(id: string): void {
    this.storage.removeVocabItem(id);
  }

  private recordStudyEvent(nodeId: string, type: LearningEventType, mastery: MasteryLevel, correct?: boolean): void {
    const map = this.current;
    if (!map) {
      return;
    }
    const ev: LearningEvent = {
      id: GenUid.nextEventId(),
      mapId: map.id,
      nodeId: nodeId,
      date: MindMapStore.todayStr(),
      type: type,
      mastery: mastery,
      correct: correct
    };
    this.storage.addLearningEvent(ev);
  }

  private static todayStr(): string {
    const d = new Date();
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    const day = d.getDate();
    return `${y}-${m < 10 ? '0' + m : m}-${day < 10 ? '0' + day : day}`;
  }

  // ---------- 订阅 ----------
  subscribe(listener: StoreListener): () => void {
    this.listeners.push(listener);
    return () => {
      const idx = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  subscribeSaveError(listener: SaveErrorListener): () => void {
    this.saveErrorListeners.push(listener);
    return () => {
      const idx = this.saveErrorListeners.indexOf(listener);
      if (idx >= 0) {
        this.saveErrorListeners.splice(idx, 1);
      }
    };
  }

  // ---------- 内部 ----------
  private notify(): void {
    const snapshot = this.currentClone();
    const observers = this.listeners.slice();
    for (let i = 0; i < observers.length; i++) {
      try {
        observers[i](snapshot);
      } catch (err) {
        Logger.error('MindMapStore', `listener error: ${JSON.stringify(err)}`);
      }
    }
  }

  private schedulePersist(): void {
    const map = this.current;
    if (!map) {
      return;
    }
    map.updatedAt = Date.now();
    this.notify();
    if (this.debounceTimer !== undefined) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = undefined;
      this.flushPersist();
    }, 300);
  }

  private async flushPersist(): Promise<void> {
    const map = this.current;
    if (!map) {
      return;
    }
    const saved = await this.storage.saveMap(map);
    if (!saved) {
      const errs = this.saveErrorListeners.slice();
      for (let i = 0; i < errs.length; i++) {
        errs[i]('保存失败，请检查存储空间');
      }
    }
  }
}