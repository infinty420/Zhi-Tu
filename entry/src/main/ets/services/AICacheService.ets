/**
 * AICacheService —— AI 结果本地缓存（Wave 4 离线优先）。
 * 联网成功时把结果按 bucket+key 写入 Preferences；联网失败时优先命中缓存，
 * 让「讲细一点 / 出相似题」等在断网场景下仍有内容可用（缓存命中不判为失败）。
 * 容量上限 MAX_ENTRIES，超出后淘汰最早写入的条目（Map 保持插入顺序）。
 */
import { preferences } from '@kit.ArkData';
import { AppContextHolder } from '../utils/AppContext';
import { Logger } from '../utils/Logger';

const PREF_NAME = 'zhitu_ai_cache';
const KEY_MAP = 'zhitu_ai_cache_map';
const MAX_ENTRIES = 200;

/** 缓存分组 */
export type AICacheBucket = 'tutor' | 'similar' | 'rich';

export class AICacheService {
  private static _instance: AICacheService | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private cache: Map<string, string> = new Map<string, string>();
  private ready: boolean = false;
  /** 最近一次读取是否命中缓存（供页面展示「离线缓存」角标） */
  private lastHit: boolean = false;

  static getInstance(): AICacheService {
    if (AICacheService._instance === undefined) {
      AICacheService._instance = new AICacheService();
    }
    return AICacheService._instance;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      const raw = (await this.pref.get(KEY_MAP, '[]')) as string;
      const arr = JSON.parse(raw) as string[][];
      if (arr && arr.length > 0) {
        for (let i = 0; i < arr.length; i++) {
          const pair = arr[i] as string[];
          if (pair && pair.length >= 2) {
            this.cache.set(String(pair[0]), String(pair[1]));
          }
        }
      }
      this.ready = true;
    } catch (err) {
      Logger.error('AICacheService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  private static bucketKey(bucket: string, key: string): string {
    return `${bucket}::${key}`;
  }

  /** 命中返回缓存内容，未命中返回空串 */
  get(bucket: string, key: string): string {
    const v = this.cache.get(AICacheService.bucketKey(bucket, key));
    if (v === undefined || v.length === 0) {
      this.lastHit = false;
      return '';
    }
    this.lastHit = true;
    return v;
  }

  async put(bucket: string, key: string, value: string): Promise<void> {
    if (value.length === 0) {
      return;
    }
    const bk = AICacheService.bucketKey(bucket, key);
    if (this.cache.has(bk)) {
      this.cache.delete(bk);
    }
    this.cache.set(bk, value);
    while (this.cache.size > MAX_ENTRIES) {
      const first = this.cache.keys().next();
      if (first.done) {
        break;
      }
      this.cache.delete(first.value);
    }
    await this.flush();
  }

  /** 取走「最近一次是否命中缓存」标记（读取后复位） */
  consumeLastHit(): boolean {
    const hit = this.lastHit;
    this.lastHit = false;
    return hit;
  }

  /** 标记命中（供缓存读取方显式置位） */
  markHit(): void {
    this.lastHit = true;
  }

  size(): number {
    return this.cache.size;
  }

  async clear(): Promise<void> {
    this.cache.clear();
    await this.flush();
  }

  private async flush(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      const pairs: string[][] = [];
      this.cache.forEach((v: string, k: string) => {
        pairs.push([k, v]);
      });
      await this.pref.put(KEY_MAP, JSON.stringify(pairs));
      await this.pref.flush();
    } catch (err) {
      Logger.error('AICacheService', `flush failed: ${JSON.stringify(err)}`);
    }
  }
}
