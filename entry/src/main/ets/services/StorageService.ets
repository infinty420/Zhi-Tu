/**
 * StorageService —— 本地持久化。
 * Preferences 保存导图列表索引/最近打开项/损坏标记；RDB 保存导图全量 JSON（maps 表按 id 主键）。
 * 损坏数据处理：解析失败时索引标记「数据异常」，禁止编辑但可删除。
 */
import { preferences, relationalStore } from '@kit.ArkData';
import { MasteryLevel } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { LearningEvent, LearningEventType, StudyStats, VocabItem, WrongItem } from '../model/StudyModels';
import { AppContextHolder } from '../utils/AppContext';
import { Logger } from '../utils/Logger';
import { MindMapSummary } from './MindMapStore';

const PREF_NAME = 'zhitu_store';
const KEY_SUMMARIES = 'zhitu_summaries';
const KEY_RECENT = 'zhitu_recent';
const KEY_LEARNING_EVENTS = 'zhitu_learning_events';
const KEY_WRONG_BOOK = 'zhitu_wrong_book';
const KEY_VOCAB_BOOK = 'zhitu_vocab_book';
const DB_NAME = 'zhitu.db';
const TABLE_MAPS = 'maps';
const KEY_MAP_PREFIX = 'zhitu_map_';

export class StorageService {
  private pref: preferences.Preferences | undefined = undefined;
  private rdb: relationalStore.RdbStore | undefined = undefined;
  private summaries: MindMapSummary[] = [];
  private events: LearningEvent[] = [];
  private wrongItems: WrongItem[] = [];
  private vocabItems: VocabItem[] = [];
  private ready: boolean = false;

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const storeConfig: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.rdb = await relationalStore.getRdbStore(ctx, storeConfig);
      await this.rdb.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE_MAPS} (id TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)`);
      await this.loadSummariesFromPref();
      await this.loadLearningFromPref();
      this.ready = true;
      Logger.info('StorageService', 'init success');
    } catch (err) {
      Logger.error('StorageService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  isReady(): boolean {
    return this.ready;
  }

  // ---------- 索引（Preferences） ----------
  listSummaries(): MindMapSummary[] {
    const result: MindMapSummary[] = [];
    for (let i = 0; i < this.summaries.length; i++) {
      result.push({
        id: this.summaries[i].id,
        title: this.summaries[i].title,
        subject: this.summaries[i].subject,
        updatedAt: this.summaries[i].updatedAt,
        damaged: this.summaries[i].damaged
      });
    }
    return result;
  }

  async loadSummariesFromPref(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      const raw = (await this.pref.get(KEY_SUMMARIES, '[]')) as string;
      const arr = raw && raw.length > 0 ? (JSON.parse(raw) as MindMapSummary[]) : [];
      this.summaries = arr ? arr : [];
    } catch (err) {
      this.summaries = [];
    }
  }

  private async flushSummaries(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(KEY_SUMMARIES, JSON.stringify(this.summaries));
      await this.pref.flush();
    } catch (err) {
      Logger.error('StorageService', `flush summaries failed: ${JSON.stringify(err)}`);
    }
  }

  updateSummary(id: string, title: string, subject: string, updatedAt: number, damaged: boolean): void {
    let exist = false;
    for (let i = 0; i < this.summaries.length; i++) {
      if (this.summaries[i].id === id) {
        this.summaries[i].title = title;
        this.summaries[i].subject = subject;
        this.summaries[i].updatedAt = updatedAt;
        this.summaries[i].damaged = damaged;
        exist = true;
        break;
      }
    }
    if (!exist) {
      const summary: MindMapSummary = { id: id, title: title, subject: subject, updatedAt: updatedAt, damaged: damaged };
      this.summaries.unshift(summary);
    }
    this.flushSummaries();
  }

  markDamaged(id: string): void {
    for (let i = 0; i < this.summaries.length; i++) {
      if (this.summaries[i].id === id) {
        this.summaries[i].damaged = true;
        break;
      }
    }
    this.flushSummaries();
  }

  // ---------- 学习闭环数据（Preferences） ----------
  async loadLearningFromPref(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      const ev = (await this.pref.get(KEY_LEARNING_EVENTS, '[]')) as string;
      this.events = (ev && ev.length > 0) ? (JSON.parse(ev) as LearningEvent[]) : [];
      const wb = (await this.pref.get(KEY_WRONG_BOOK, '[]')) as string;
      this.wrongItems = (wb && wb.length > 0) ? (JSON.parse(wb) as WrongItem[]) : [];
      const vb = (await this.pref.get(KEY_VOCAB_BOOK, '[]')) as string;
      this.vocabItems = (vb && vb.length > 0) ? (JSON.parse(vb) as VocabItem[]) : [];
    } catch (err) {
      this.events = [];
      this.wrongItems = [];
      this.vocabItems = [];
    }
  }

  private async flushLearning(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(KEY_LEARNING_EVENTS, JSON.stringify(this.events));
      await this.pref.put(KEY_WRONG_BOOK, JSON.stringify(this.wrongItems));
      await this.pref.put(KEY_VOCAB_BOOK, JSON.stringify(this.vocabItems));
      await this.pref.flush();
    } catch (err) {
      Logger.error('StorageService', `flush learning failed: ${JSON.stringify(err)}`);
    }
  }

  addLearningEvent(ev: LearningEvent): void {
    this.events.push(ev);
    this.flushLearning();
  }

  getLearningEvents(): LearningEvent[] {
    return this.events;
  }

  getEventsByMap(mapId: string): LearningEvent[] {
    const result: LearningEvent[] = [];
    for (let i = 0; i < this.events.length; i++) {
      if (this.events[i].mapId === mapId) {
        result.push(this.events[i]);
      }
    }
    return result;
  }

  addWrongItem(item: WrongItem): void {
    // 同一节点去重，保留最新一次答错
    this.wrongItems = this.wrongItems.filter((w) => w.nodeId !== item.nodeId);
    this.wrongItems.unshift(item);
    this.flushLearning();
  }

  removeWrongItem(id: string): void {
    this.wrongItems = this.wrongItems.filter((w) => w.id !== id);
    this.flushLearning();
  }

  getWrongItems(): WrongItem[] {
    return this.wrongItems;
  }

  addVocabItem(item: VocabItem): void {
    this.vocabItems.unshift(item);
    this.flushLearning();
  }

  removeVocabItem(id: string): void {
    this.vocabItems = this.vocabItems.filter((v) => v.id !== id);
    this.flushLearning();
  }

  getVocabItems(): VocabItem[] {
    return this.vocabItems;
  }

  /** 按当前导图聚合学习统计 */
  computeStudyStats(map: MindMap): StudyStats {
    const result: StudyStats = {
      studyDayCount: 0,
      streakDays: 0,
      totalEvents: this.events.length,
      masteredCount: 0,
      totalCount: map ? map.nodes.length : 0,
      masteryRate: 0,
      dueReviewCount: 0,
      todayEventCount: 0
    };
    // 天数集合与连续打卡
    const daySet: string[] = [];
    for (let i = 0; i < this.events.length; i++) {
      const d = this.events[i].date;
      if (daySet.indexOf(d) < 0) {
        daySet.push(d);
      }
    }
    result.studyDayCount = daySet.length;
    result.streakDays = StorageService.computeStreak(daySet);
    // 导图内掌握度与待复习
    if (map) {
      const now = Date.now();
      let mastered = 0;
      let due = 0;
      for (let i = 0; i < map.nodes.length; i++) {
        const n = map.nodes[i];
        if (n.mastery === MasteryLevel.KNOWN) {
          mastered++;
        }
        if (n.nextReviewAt > 0 && n.nextReviewAt <= now) {
          due++;
        }
      }
      result.masteredCount = mastered;
      result.totalCount = map.nodes.length;
      result.masteryRate = map.nodes.length > 0 ? mastered / map.nodes.length : 0;
      result.dueReviewCount = due;
    }
    // 今日学习事件数（复习 / 自测 / 标记掌握 均计入）
    const cur = new Date();
    const todayKey = `${cur.getFullYear()}-${StorageService.pad2(cur.getMonth() + 1)}-${StorageService.pad2(cur.getDate())}`;
    let todayCount = 0;
    for (let i = 0; i < this.events.length; i++) {
      if (this.events[i].date === todayKey) {
        todayCount++;
      }
    }
    result.todayEventCount = todayCount;
    return result;
  }

  private static computeStreak(days: string[]): number {
    if (days.length === 0) {
      return 0;
    }
    const set = new Set<string>();
    for (let i = 0; i < days.length; i++) {
      set.add(days[i]);
    }
    let streak = 0;
    const cur = new Date();
    // 从今天往前数，遇到缺失即中断
    for (let step = 0; step < 3660; step++) {
      const y = cur.getFullYear();
      const m = cur.getMonth() + 1;
      const d = cur.getDate();
      const key = `${y}-${StorageService.pad2(m)}-${StorageService.pad2(d)}`;
      if (set.has(key)) {
        streak++;
        cur.setDate(cur.getDate() - 1);
      } else if (step === 0) {
        // 今天还没学，从昨天起算
        cur.setDate(cur.getDate() - 1);
      } else {
        break;
      }
    }
    return streak;
  }

  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  // ---------- 最近打开 ----------
  async setRecent(id: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(KEY_RECENT, id);
      await this.pref.flush();
    } catch (err) {
      Logger.error('StorageService', `setRecent failed: ${JSON.stringify(err)}`);
    }
  }

  async loadRecent(): Promise<string> {
    if (!this.pref) {
      return '';
    }
    try {
      const raw = (await this.pref.get(KEY_RECENT, '')) as string;
      return raw ? raw : '';
    } catch (err) {
      return '';
    }
    return '';
  }

  // ---------- 全量数据（RDB） ----------
  async saveMap(map: MindMap): Promise<boolean> {
    const payload = map.toJson();
    let savedToRdb = false;
    if (this.rdb && this.ready) {
      try {
        const values: relationalStore.ValuesBucket = {
          'id': map.id,
          'payload': payload,
          'updated_at': map.updatedAt
        };
        const predicates = new relationalStore.RdbPredicates(TABLE_MAPS);
        predicates.equalTo('id', map.id);
        const query = await this.rdb.query(predicates);
        const count = query.rowCount;
        query.close();
        if (count > 0) {
          await this.rdb.update(values, predicates);
        } else {
          await this.rdb.insert(TABLE_MAPS, values);
        }
        savedToRdb = true;
      } catch (err) {
        Logger.error('StorageService', `saveMap rdb failed: ${JSON.stringify(err)}`);
      }
    }
    // 偏好兜底：RDB 不可用时仍保证导图可打开
    let savedToPref = false;
    if (this.pref) {
      try {
        await this.pref.put(KEY_MAP_PREFIX + map.id, payload);
        await this.pref.flush();
        savedToPref = true;
      } catch (err) {
        Logger.error('StorageService', `saveMap pref backup failed: ${JSON.stringify(err)}`);
      }
    }
    this.updateSummary(map.id, map.title, map.subject, map.updatedAt, false);
    return savedToRdb || savedToPref;
  }

  /** 读取导图；损坏则标记 damaged 并返回 undefined */
  async loadMap(id: string): Promise<MindMap | undefined> {
    if (!this.rdb || !this.ready) {
      return undefined;
    }
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_MAPS);
      predicates.equalTo('id', id);
      const resultSet = await this.rdb.query(predicates);
      let payload = '';
      if (resultSet.rowCount > 0 && resultSet.goToFirstRow()) {
        const idx = resultSet.getColumnIndex('payload');
        if (idx >= 0) {
          payload = resultSet.getString(idx);
        }
      }
      resultSet.close();
      if (payload.length === 0) {
        return undefined;
      }
      const map = MindMap.fromJson(payload);
      if (!map) {
        this.markDamaged(id);
        loggerDamaged(id);
        return undefined;
      }
      const validation = map.validate();
      if (!validation.ok) {
        this.markDamaged(id);
        loggerDamaged(id);
        return undefined;
      }
      return map;
    } catch (err) {
      Logger.error('StorageService', `loadMap failed: ${JSON.stringify(err)}`);
      this.markDamaged(id);
      return undefined;
    }
  }

  async deleteMap(id: string): Promise<void> {
    if (this.rdb && this.ready) {
      try {
        const predicates = new relationalStore.RdbPredicates(TABLE_MAPS);
        predicates.equalTo('id', id);
        await this.rdb.delete(predicates);
      } catch (err) {
        Logger.error('StorageService', `deleteMap failed: ${JSON.stringify(err)}`);
      }
    }
    if (this.pref) {
      try {
        await this.pref.delete(KEY_MAP_PREFIX + id);
        await this.pref.flush();
      } catch (err) {
        Logger.error('StorageService', `deleteMap pref backup failed: ${JSON.stringify(err)}`);
      }
    }
    this.summaries = this.summaries.filter((s) => s.id !== id);
    await this.flushSummaries();
    const recent = await this.loadRecent();
    if (recent === id) {
      if (this.pref) {
        await this.pref.delete(KEY_RECENT);
        await this.pref.flush();
      }
    }
  }

  async loadAllMapIds(): Promise<string[]> {
    if (!this.rdb || !this.ready) {
      return [];
    }
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_MAPS);
      const resultSet = await this.rdb.query(predicates);
      const ids: string[] = [];
      while (resultSet.goToNextRow()) {
        const idx = resultSet.getColumnIndex('id');
        if (idx >= 0) {
          ids.push(resultSet.getString(idx));
        }
      }
      resultSet.close();
      return ids;
    } catch (err) {
      Logger.error('StorageService', `loadAllMapIds failed: ${JSON.stringify(err)}`);
      return [];
    }
  }
}

function loggerDamaged(id: string): void {
  Logger.warn('StorageService', `map damaged, marked: ${id}`);
}