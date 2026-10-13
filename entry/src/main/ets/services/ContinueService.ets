/**
 * ContinueService —— 跨设备续学（Wave 12）。
 * 记录「上次学习会话」：当前导图 id、最近停留的节点、导图标题、时间戳。
 * 本地以 Preferences 持久化；真机跨设备续学应替换为：
 *   - 账户维度分布式 KV（@ohos.data.distributedKVStore）随登录账号漫游；或
 *   - 分布式流转能力（@ohos.continuation.abilityMigration）在设备间迁移当前 Ability。
 * 这里用本地存储 + synced 标记模拟，对外接口与真机一致，便于后续平滑替换。
 */
import { preferences } from '@kit.ArkData';
import { AppContextHolder } from '../utils/AppContext';
import { Logger } from '../utils/Logger';

const PREF_NAME = 'zhitu_continue';
const KEY_SESSION = 'zhitu_continue_session';

/** 上次学习会话快照 */
export interface ContinueSession {
  mapId: string;
  nodeId: string;
  title: string;
  /** 最近停留节点的文本（便于首页展示） */
  nodeText: string;
  /** 记录时间戳 */
  ts: number;
  /** 是否已同步到云端（真机对应分布式 KV 回写） */
  synced: boolean;
}

export class ContinueService {
  private static _instance: ContinueService | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private ready: boolean = false;
  private cache: ContinueSession | undefined = undefined;

  static getInstance(): ContinueService {
    if (ContinueService._instance === undefined) {
      ContinueService._instance = new ContinueService();
    }
    return ContinueService._instance;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const raw = (await this.pref.get(KEY_SESSION, '')) as string;
      this.cache = raw && raw.length > 0 ? this.parse(raw) : undefined;
      this.ready = true;
    } catch (err) {
      Logger.error('ContinueService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  private parse(raw: string): ContinueSession | undefined {
    try {
      const o = JSON.parse(raw) as ContinueSession;
      if (o && o.mapId) {
        return o;
      }
      return undefined;
    } catch (e) {
      return undefined;
    }
  }

  /** 记录一次进度（打开导图或停留在某节点时调用） */
  async save(mapId: string, nodeId: string, title: string, nodeText: string): Promise<void> {
    if (!mapId || mapId.length === 0) {
      return;
    }
    const prev = this.cache;
    const next: ContinueSession = {
      mapId: mapId,
      nodeId: nodeId.length > 0 ? nodeId : (prev ? prev.nodeId : ''),
      title: title.length > 0 ? title : (prev ? prev.title : ''),
      nodeText: nodeText.length > 0 ? nodeText : (prev ? prev.nodeText : ''),
      ts: Date.now(),
      synced: false
    };
    this.cache = next;
    await this.persist();
  }

  /** 读取上次会话（无则返回 undefined） */
  get(): ContinueSession | undefined {
    return this.cache;
  }

  /** 清空续学记录 */
  async clear(): Promise<void> {
    this.cache = undefined;
    if (this.pref) {
      try {
        await this.pref.delete(KEY_SESSION);
        await this.pref.flush();
      } catch (err) {
        Logger.error('ContinueService', `clear failed: ${JSON.stringify(err)}`);
      }
    }
  }

  /** 标记为已同步（真机对应分布式 KV 回写成功） */
  async markSynced(): Promise<void> {
    if (this.cache) {
      this.cache.synced = true;
      await this.persist();
    }
  }

  private async persist(): Promise<void> {
    if (!this.pref || !this.cache) {
      return;
    }
    try {
      await this.pref.put(KEY_SESSION, JSON.stringify(this.cache));
      await this.pref.flush();
    } catch (err) {
      Logger.error('ContinueService', `persist failed: ${JSON.stringify(err)}`);
    }
  }
}
