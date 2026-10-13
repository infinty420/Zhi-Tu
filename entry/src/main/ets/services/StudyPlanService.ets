/**
 * StudyPlanService —— 每周学习计划自动排程（Wave 11 个性化 AI）。
 * 纯计算聚合：基于待复习节点（ReviewScheduler）+ 薄弱点（StudyInsightService），
 * 把学习任务按"就近到期优先、其余按薄弱度补齐"摊到未来 7 天，供学习 Hub 展示「本周学习计划」。
 * 不新增存储、不依赖 ArkUI，与 ReviewSummaryService / StudyInsightService 风格一致。
 */
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { NodeType } from '../model/Constants';
import { ReviewScheduler } from './ReviewScheduler';
import { StudyInsightService, WeakPointItem } from './StudyInsightService';
import { WrongItem } from '../model/StudyModels';

/** 单条计划任务 */
export interface PlanTask {
  nodeId: string;
  nodeText: string;
  nodeType: NodeType;
  /** 任务标签：今日到期 / 已逾期 / 薄弱巩固 / 自由复习 */
  tag: string;
}

/** 某一天的学习计划 */
export interface PlanDay {
  /** 距今天第几天（0=今天） */
  index: number;
  /** 展示标签：今天 / 明天 / 周三 … */
  label: string;
  /** 当天日期（0 点时间戳） */
  date: number;
  tasks: PlanTask[];
}

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_DAYS = 7;
const DAILY_CAP = 3;

export class StudyPlanService {
  /**
   * 生成未来 7 天学习计划。
   * @param snap 当前导图快照（无则空计划）
   * @param wrongItems 错题本（用于薄弱点）
   * @param now 当前时间戳
   */
  static buildWeekPlan(snap: MindMap | undefined, wrongItems: WrongItem[], now: number): PlanDay[] {
    const startToday = StudyPlanService.startOfDay(now);
    const days: PlanDay[] = [];
    for (let i = 0; i < WEEK_DAYS; i++) {
      days.push({
        index: i,
        label: StudyPlanService.labelOf(i, now),
        date: startToday + i * DAY_MS,
        tasks: []
      });
    }
    if (!snap) {
      return days;
    }

    // 1) 待复习节点：按到期日就近分配到对应天（逾期一律今天）
    const due: MindNode[] = ReviewScheduler.dueNodes(snap);
    const dueIdSet = new Set<string>();
    for (let i = 0; i < due.length; i++) {
      const n = due[i];
      dueIdSet.add(n.id);
      let dayIdx = 0;
      if (n.nextReviewAt > 0) {
        const diff = n.nextReviewAt - startToday;
        dayIdx = diff <= 0 ? 0 : Math.min(WEEK_DAYS - 1, Math.floor(diff / DAY_MS));
      }
      days[dayIdx].tasks.push({ nodeId: n.id, nodeText: n.text, nodeType: n.type, tag: n.nextReviewAt > 0 && n.nextReviewAt <= now ? '已逾期' : '今日到期' });
    }

    // 2) 薄弱点（未到期的）按薄弱度补齐到各天空闲槽位
    const weak: WeakPointItem[] = StudyInsightService.buildWeakPoints(snap, wrongItems)
      .filter((w: WeakPointItem) => !dueIdSet.has(w.nodeId));
    let wi = 0;
    for (let d = 0; d < WEEK_DAYS && wi < weak.length; d++) {
      while (days[d].tasks.length < DAILY_CAP && wi < weak.length) {
        const w = weak[wi];
        wi++;
        days[d].tasks.push({ nodeId: w.nodeId, nodeText: w.nodeText, nodeType: w.nodeType, tag: '薄弱巩固' });
      }
    }

    return days;
  }

  /** 把某天所有任务数求和（用于概览） */
  static totalTasks(days: PlanDay[]): number {
    let n = 0;
    for (let i = 0; i < days.length; i++) {
      n += days[i].tasks.length;
    }
    return n;
  }

  private static startOfDay(ts: number): number {
    const d = new Date(ts);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }

  private static labelOf(offset: number, now: number): string {
    if (offset === 0) {
      return '今天';
    }
    if (offset === 1) {
      return '明天';
    }
    const d = new Date(now + offset * DAY_MS);
    const names = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return names[d.getDay()];
  }
}
