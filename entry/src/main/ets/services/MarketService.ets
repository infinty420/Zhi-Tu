/**
 * 市场 UGC 服务（Wave 3）。用户可把本机导图发布到「我的发布」，并再次导入为新的本地导图。
 * 持久化：Preferences（zhitu_market），与内置精品模板（MarketTemplates）互不干扰。
 */
import { preferences } from '@kit.ArkData';
import { MarketUserItem } from '../model/MarketTemplates';
import { AppContextHolder } from '../utils/AppContext';
import { GenUid } from '../utils/GenUid';
import { Logger } from '../utils/Logger';

const PREF_NAME = 'zhitu_market';
const KEY_LIST = 'zhitu_market_user_items';

interface MarketUserItemRaw {
  id: ESObject;
  title: ESObject;
  author: ESObject;
  subject: ESObject;
  summary: ESObject;
  downloads: ESObject;
  payload: ESObject;
  createdAt: ESObject;
}

export class MarketService {
  private static _instance: MarketService | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private items: MarketUserItem[] = [];
  private ready: boolean = false;

  static getInstance(): MarketService {
    if (MarketService._instance === undefined) {
      MarketService._instance = new MarketService();
    }
    return MarketService._instance;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const raw = (await this.pref.get(KEY_LIST, '[]')) as string;
      this.items = MarketService.parseList(raw);
      this.ready = true;
    } catch (err) {
      Logger.error('MarketService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  private static parseList(raw: string): MarketUserItem[] {
    try {
      const arr = JSON.parse(raw) as MarketUserItemRaw[];
      if (!arr || arr.length === 0) {
        return [];
      }
      const out: MarketUserItem[] = [];
      for (let i = 0; i < arr.length; i++) {
        const r = arr[i];
        out.push({
          id: MarketService.str(r.id),
          title: MarketService.str(r.title),
          author: MarketService.str(r.author),
          subject: MarketService.str(r.subject),
          summary: MarketService.str(r.summary),
          downloads: MarketService.num(r.downloads),
          payload: MarketService.str(r.payload),
          createdAt: MarketService.num(r.createdAt)
        });
      }
      return out;
    } catch (err) {
      return [];
    }
  }

  private static str(v: ESObject): string {
    if (v === null || v === undefined) {
      return '';
    }
    return String(v);
  }

  private static num(v: ESObject): number {
    if (v === null || v === undefined) {
      return 0;
    }
    return Number(v);
  }

  private async persist(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(KEY_LIST, JSON.stringify(this.items));
      await this.pref.flush();
    } catch (err) {
      Logger.error('MarketService', `persist failed: ${JSON.stringify(err)}`);
    }
  }

  /** 我发布的导图（最新在前） */
  listUser(): MarketUserItem[] {
    return this.items;
  }

  /** 发布当前导图（返回新条目） */
  async publish(title: string, author: string, subject: string, summary: string, payload: string): Promise<MarketUserItem> {
    await this.init();
    const item: MarketUserItem = {
      id: GenUid.next('mk'),
      title: title.length > 0 ? title : '未命名导图',
      author: author.length > 0 ? author : '我',
      subject: subject.length > 0 ? subject : '综合',
      summary: summary.length > 0 ? summary : '用户发布的导图',
      downloads: 0,
      payload: payload,
      createdAt: Date.now()
    };
    this.items.unshift(item);
    await this.persist();
    return item;
  }

  /** 取导图 JSON（导入用） */
  getPayload(id: string): string {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        return this.items[i].payload;
      }
    }
    return '';
  }

  /** 导入一次记一次下载 */
  async bumpDownloads(id: string): Promise<void> {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        this.items[i].downloads = this.items[i].downloads + 1;
        await this.persist();
        return;
      }
    }
  }

  async remove(id: string): Promise<boolean> {
    const before = this.items.length;
    this.items = this.items.filter((it) => it.id !== id);
    if (this.items.length === before) {
      return false;
    }
    await this.persist();
    return true;
  }
}
