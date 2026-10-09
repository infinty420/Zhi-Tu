/**
 * AchievementService —— 学习激励引擎（Wave 7，纯本地）。
 * 职责：
 *  1) 每日打卡：记录最近打卡日与连续打卡天数（独立 streak，不依赖学习事件）。
 *  2) 成就墙：基于学习统计实时推导 14 项成就（连续学习 / 累计学习 / 自测 / 复习 / 掌握），
 *     无需额外存储，依据 MindMapStore 的 StudyStats 与 LearningEvent 实时计算。
 * 持久化只保存打卡状态（streak / 最近打卡日），走 Preferences。
 */

import { preferences } from '@kit.ArkData';
import { LearningEventType } from '../model/StudyModels';
import { AppContextHolder } from '../utils/AppContext';
import { MindMapStore } from './MindMapStore';
import { Logger } from '../utils/Logger';

const PREF_NAME = 'zhitu_achievement';
const KEY_STREAK = 'zhitu_checkin_streak';
const KEY_LAST = 'zhitu_checkin_last';

/** 成就定义 */
export interface Achievement {
  id: string;
  title: string;
  icon: string;
  desc: string;
  metric: 'streak' | 'studyDays' | 'quiz' | 'review' | 'mastered';
  threshold: number;
}

/** 成就展示视图（UI 直接使用） */
export interface AchievementView {
  id: string;
  title: string;
  icon: string;
  desc: string;
  unlocked: boolean;
  progress: number; // 0~1
  current: number;
  threshold: number;
}

/** 打卡视图 */
export interface CheckInView {
  checkedInToday: boolean;
  streak: number;
  lastCheckInDate: string;
}

/** 成就判定指标（由学习统计实时聚合） */
interface AchievementMetrics {
  streak: number;
  studyDays: number;
  quiz: number;
  review: number;
  mastered: number;
}

const DEFS: Achievement[] = [
  { id: 'streak_3', title: '三天打鱼', icon: '🔥', desc: '连续学习 3 天', metric: 'streak', threshold: 3 },
  { id: 'streak_7', title: '一周不辍', icon: '🔥', desc: '连续学习 7 天', metric: 'streak', threshold: 7 },
  { id: 'streak_30', title: '月月精进', icon: '🏆', desc: '连续学习 30 天', metric: 'streak', threshold: 30 },
  { id: 'study_1', title: '初学乍练', icon: '🌱', desc: '累计学习 1 天', metric: 'studyDays', threshold: 1 },
  { id: 'study_10', title: '小有积累', icon: '📚', desc: '累计学习 10 天', metric: 'studyDays', threshold: 10 },
  { id: 'study_50', title: '学富五车', icon: '🎓', desc: '累计学习 50 天', metric: 'studyDays', threshold: 50 },
  { id: 'quiz_10', title: '自测达人', icon: '✏️', desc: '完成自测 10 次', metric: 'quiz', threshold: 10 },
  { id: 'quiz_50', title: '百炼成钢', icon: '🧠', desc: '完成自测 50 次', metric: 'quiz', threshold: 50 },
  { id: 'quiz_200', title: '题海王者', icon: '👑', desc: '完成自测 200 次', metric: 'quiz', threshold: 200 },
  { id: 'review_10', title: '温故知新', icon: '🔁', desc: '完成复习 10 次', metric: 'review', threshold: 10 },
  { id: 'review_50', title: '复习有方', icon: '📅', desc: '完成复习 50 次', metric: 'review', threshold: 50 },
  { id: 'master_10', title: '初窥门径', icon: '⭐', desc: '掌握知识点 10 个', metric: 'mastered', threshold: 10 },
  { id: 'master_50', title: '融会贯通', icon: '💡', desc: '掌握知识点 50 个', metric: 'mastered', threshold: 50 },
  { id: 'master_100', title: '学霸附体', icon: '🌟', desc: '掌握知识点 100 个', metric: 'mastered', threshold: 100 }
];

function pad(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

function fmtDate(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function todayStr(): string {
  return fmtDate(new Date());
}

function shiftDay(base: string, delta: number): string {
  const parts = base.split('-');
  const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  d.setDate(d.getDate() + delta);
  return fmtDate(d);
}

export class AchievementService {
  private static _instance: AchievementService | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  private ready: boolean = false;
  private streak: number = 0;
  private lastCheckInDate: string = '';

  static getInstance(): AchievementService {
    if (AchievementService._instance === undefined) {
      AchievementService._instance = new AchievementService();
    }
    return AchievementService._instance;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      const ctx = AppContextHolder.get();
      this.pref = await preferences.getPreferences(ctx, { name: PREF_NAME });
      this.streak = (await this.pref.get(KEY_STREAK, 0)) as number;
      this.lastCheckInDate = (await this.pref.get(KEY_LAST, '')) as string;
      this.ready = true;
    } catch (err) {
      Logger.error('AchievementService', `init failed: ${JSON.stringify(err)}`);
    }
  }

  /** 今日打卡：返回打卡视图（已打卡则返回当前状态，无副作用） */
  async checkInToday(): Promise<CheckInView> {
    const today = todayStr();
    if (this.lastCheckInDate === today) {
      return this.view();
    }
    const yesterday = shiftDay(today, -1);
    if (this.lastCheckInDate === yesterday) {
      this.streak = this.streak + 1;
    } else {
      this.streak = 1;
    }
    this.lastCheckInDate = today;
    await this.flush();
    return this.view();
  }

  /** 当前打卡视图 */
  getCheckIn(): CheckInView {
    return this.view();
  }

  private view(): CheckInView {
    const v: CheckInView = {
      checkedInToday: this.lastCheckInDate === todayStr(),
      streak: this.streak,
      lastCheckInDate: this.lastCheckInDate
    };
    return v;
  }

  /** 全部成就（实时依据学习统计推导解锁状态与进度） */
  listAchievements(): AchievementView[] {
    const m = this.metrics();
    const out: AchievementView[] = [];
    for (const def of DEFS) {
      const current = AchievementService.valueFor(def, m);
      const unlocked = current >= def.threshold;
      const progress = def.threshold <= 0 ? 1 : Math.min(1, current / def.threshold);
      const item: AchievementView = {
        id: def.id,
        title: def.title,
        icon: def.icon,
        desc: def.desc,
        unlocked: unlocked,
        progress: progress,
        current: current,
        threshold: def.threshold
      };
      out.push(item);
    }
    return out;
  }

  /** 已解锁成就数量（用于首页/统计页概览） */
  unlockedCount(): number {
    let n = 0;
    for (const a of this.listAchievements()) {
      if (a.unlocked) {
        n = n + 1;
      }
    }
    return n;
  }

  private metrics(): AchievementMetrics {
    const store = MindMapStore.getInstance();
    const stats = store.getStudyStats();
    const events = store.getLearningEvents();
    let quiz = 0;
    let review = 0;
    for (const e of events) {
      if (e.type === LearningEventType.QUIZ) {
        quiz = quiz + 1;
      } else if (e.type === LearningEventType.REVIEW) {
        review = review + 1;
      }
    }
    return {
      streak: stats.streakDays,
      studyDays: stats.studyDayCount,
      quiz: quiz,
      review: review,
      mastered: stats.masteredCount
    };
  }

  private static valueFor(def: Achievement, m: AchievementMetrics): number {
    switch (def.metric) {
      case 'streak':
        return m.streak;
      case 'studyDays':
        return m.studyDays;
      case 'quiz':
        return m.quiz;
      case 'review':
        return m.review;
      case 'mastered':
        return m.mastered;
      default:
        return 0;
    }
  }

  private async flush(): Promise<void> {
    if (!this.pref) {
      return;
    }
    try {
      await this.pref.put(KEY_STREAK, this.streak);
      await this.pref.put(KEY_LAST, this.lastCheckInDate);
      await this.pref.flush();
    } catch (err) {
      Logger.error('AchievementService', `flush failed: ${JSON.stringify(err)}`);
    }
  }
}
