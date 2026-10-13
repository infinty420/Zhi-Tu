/**
 * Mock 云端服务（v2.0）。以独立 Preferences 存储模拟云端：导图上传 / 列表 / 下载 / 删除。
 * 真实环境可替换为远端 HTTP 接口，对外接口保持一致。
 */
import { preferences } from '@kit.ArkData';
import { CloudMapMeta } from '../model/Account';
import { MindMap } from '../model/MindMap';
import { AppContextHolder } from '../utils/AppContext';
import { Logger } from '../utils/Logger';

const PREF_NAME = 'zhitu_cloud';
const KEY_INDEX = 'zhitu_cloud_index';
const KEY_PREFIX = 'zhitu_cloud_map_';

interface CloudRecord {
  meta: CloudMapMeta;
  payload: string;
}

export class CloudService {
  private static _instance: CloudService | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private ready: boolean = false;

  static getInstance(): CloudService {
    if (CloudService._instance === undefined) {
      CloudService._instance = new CloudService();
    }
    return CloudService._instance;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      this.ready = true;
    } catch (err) {
      Logger.error('CloudService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  /** 上传（或覆盖）一张导图到云端 */
  async upload(map: MindMap, owner: string, shared: boolean): Promise<void> {
    if (!this.pref) {
      return;
    }
    const meta: CloudMapMeta = {
      id: map.id,
      title: map.title,
      owner: owner,
      updatedAt: map.updatedAt,
      shared: shared
    };
    const record: CloudRecord = { meta: meta, payload: map.toJson() };
    try {
      await this.pref.put(KEY_PREFIX + map.id, JSON.stringify(record));
      await this.saveIndex(meta);
      await this.pref.flush();
    } catch (err) {
      Logger.error('CloudService', `upload failed: ${JSON.stringify(err)}`);
    }
  }

  /** 列出云端导图元信息 */
  async list(): Promise<CloudMapMeta[]> {
    if (!this.pref) {
      return [];
    }
    try {
      const raw = (await this.pref.get(KEY_INDEX, '[]')) as string;
      const arr = JSON.parse(raw) as CloudMapMeta[];
      return arr ? arr : [];
    } catch (err) {
      return [];
    }
  }

  /** 下载云端导图为本地 MindMap 对象 */
  async download(id: string): Promise<MindMap | undefined> {
    if (!this.pref) {
      return undefined;
    }
    try {
      const raw = (await this.pref.get(KEY_PREFIX + id, '')) as string;
      if (!raw || raw.length === 0) {
        return undefined;
      }
      const record = JSON.parse(raw) as CloudRecord;
      return MindMap.fromJson(record.payload);
    } catch (err) {
      Logger.error('CloudService', `download failed: ${JSON.stringify(err)}`);
      return undefined;
    }
  }

  async remove(id: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.delete(KEY_PREFIX + id);
      const list = await this.list();
      const next = list.filter((m) => m.id !== id);
      await this.pref.put(KEY_INDEX, JSON.stringify(next));
      await this.pref.flush();
    } catch (err) {
      Logger.error('CloudService', `remove failed: ${JSON.stringify(err)}`);
    }
  }

  private async saveIndex(meta: CloudMapMeta): Promise<void> {
    if (!this.pref) {
      return;
    }
    const list = await this.list();
    const filtered = list.filter((m) => m.id !== meta.id);
    filtered.unshift(meta);
    try {
      await this.pref.put(KEY_INDEX, JSON.stringify(filtered));
    } catch (err) {
      Logger.error('CloudService', `saveIndex failed: ${JSON.stringify(err)}`);
    }
  }
}
