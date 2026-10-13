/**
 * ReviewSummaryService —— 复习优先级聚合（Wave 9 抽取复用）。
 * 原 HomePage 内联的 DueItem / computeDueItems 逻辑上移，供首页 Hub 与学习 Hub 共用，避免重复。
 */
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { NodeType } from '../model/Constants';
import { ReviewScheduler } from './ReviewScheduler';
import { MasteryPredictor } from './MasteryPredictor';

/** 待复习优先级卡片项（按掌握度预测排序） */
export interface DueItem {
  nodeId: string;
  text: string;
  type: NodeType;
  /** 预测掌握度百分比 0~100 */
  masteryPct: number;
  /** 是否已逾期 */
  urgent: boolean;
}

interface DueScored {
  n: MindNode;
  pct: number;
  urgent: boolean;
  pr: number;
}

export class ReviewSummaryService {
  /** 对待复习节点按「紧急度 × 重要度 + 遗忘风险」排序，取前 limit 个 */
  static computeDueItems(snap: MindMap | undefined, now: number, limit: number = 3): DueItem[] {
    if (!snap) {
      return [];
    }
    const due = ReviewScheduler.dueNodes(snap);
    if (due.length === 0) {
      return [];
    }
    const scored: DueScored[] = [];
    for (let i = 0; i < due.length; i++) {
      const n: MindNode = due[i];
      const pct = Math.round(MasteryPredictor.masteryScore(n, now) * 100);
      const urgent = n.nextReviewAt > 0 && n.nextReviewAt <= now;
      scored.push({ n: n, pct: pct, urgent: urgent, pr: MasteryPredictor.priority(n, now) });
    }
    scored.sort((a: DueScored, b: DueScored) => b.pr - a.pr);
    const max = Math.min(limit, scored.length);
    const out: DueItem[] = [];
    for (let i = 0; i < max; i++) {
      const s = scored[i];
      out.push({ nodeId: s.n.id, text: s.n.text, type: s.n.type, masteryPct: s.pct, urgent: s.urgent });
    }
    return out;
  }
}
