/**
 * MasteryPredictor —— 掌握度预测引擎（Wave 5：智能复习引擎 2.0）。
 * 纯计算、零存储、无 UI 依赖；输入一个 MindNode + 当前时间戳，输出：
 *   - stabilityDays : 记忆稳定度（天），决定遗忘快慢；
 *   - retention     : 当前记忆保持率 0~1（艾宾浩斯指数衰减）；
 *   - masteryScore  : 综合掌握度评分 0~1（基线掌握度 × 实时保持率融合）；
 *   - importance    : 重要度 0~1（高频/易错/重点标签 + 要点数）；
 *   - priority      : 复习优先级（紧急度 × 重要度 + 遗忘风险），用于排序待复习。
 * 既被 ReviewScheduler 用来算动态复习间隔，也被首页/统计页用来排序与可视化。
 */
import { MasteryLevel } from '../model/Constants';
import { MindNode } from '../model/MindNode';

const DAY_MS = 24 * 3600 * 1000;

export class MasteryPredictor {
  /**
   * 记忆稳定度（天）。
   * 阶梯随成功复习次数递增（1/2/4/7/15/30），再乘掌握度系数、答错惩罚：
   * 已掌握更稳、模糊次之、不会/未标记偏弱；答错越多稳定度越低。
   */
  static stabilityDays(node: MindNode): number {
    const ladder = [1, 2, 4, 7, 15, 30];
    const idx = node.reviewCount < 0 ? 0 : (node.reviewCount >= ladder.length ? ladder.length - 1 : node.reviewCount);
    const base = ladder[idx];
    let masteryFactor = 0.7;
    if (node.mastery === MasteryLevel.KNOWN) {
      masteryFactor = 1.3;
    } else if (node.mastery === MasteryLevel.FUZZY) {
      masteryFactor = 1.0;
    } else if (node.mastery === MasteryLevel.UNKNOWN) {
      masteryFactor = 0.6;
    }
    const wrongPenalty = Math.max(0.3, 1 - node.wrongCount * 0.15);
    return base * masteryFactor * wrongPenalty;
  }

  /** 建议的下次复习间隔（天），下限 0.5 天避免过密 */
  static nextIntervalDays(node: MindNode): number {
    const stab = Math.max(0.5, MasteryPredictor.stabilityDays(node));
    return Math.max(0.5, Math.round(stab));
  }

  /** 当前记忆保持率 0~1（艾宾浩斯指数衰减；从未复习则按基线掌握度给初始值） */
  static retention(node: MindNode, now: number): number {
    if (node.lastReviewedAt <= 0) {
      if (node.mastery === MasteryLevel.KNOWN) {
        return 0.6;
      }
      if (node.mastery === MasteryLevel.FUZZY) {
        return 0.4;
      }
      return 0.2;
    }
    const elapsedDays = (now - node.lastReviewedAt) / DAY_MS;
    const s = Math.max(0.5, MasteryPredictor.stabilityDays(node));
    const r = Math.exp(-elapsedDays / s);
    return r < 0 ? 0 : (r > 1 ? 1 : r);
  }

  /** 综合掌握度评分 0~1：基线掌握度与实时保持率融合 */
  static masteryScore(node: MindNode, now: number): number {
    let base = 0.4;
    if (node.mastery === MasteryLevel.KNOWN) {
      base = 0.85;
    } else if (node.mastery === MasteryLevel.FUZZY) {
      base = 0.55;
    } else if (node.mastery === MasteryLevel.UNKNOWN) {
      base = 0.2;
    }
    const r = MasteryPredictor.retention(node, now);
    const score = 0.45 * base + 0.55 * r;
    return score < 0 ? 0 : (score > 1 ? 1 : score);
  }

  /** 重要度 0~1：高频/重点/易错标签优先，要点数轻微加成 */
  static importance(node: MindNode): number {
    let v = 0.5;
    const tags = node.rich.tags;
    for (let i = 0; i < tags.length; i++) {
      const t = tags[i];
      if (t.indexOf('高频') >= 0) {
        v = Math.max(v, 1.0);
      } else if (t.indexOf('重点') >= 0) {
        v = Math.max(v, 0.85);
      } else if (t.indexOf('易错') >= 0) {
        v = Math.max(v, 0.8);
      }
    }
    const kp = node.richContent.keyPoints.length;
    v = Math.min(1, v + Math.min(kp, 4) * 0.05);
    return v;
  }

  /**
   * 复习优先级（越大越该先复习）：
   *   紧急度（逾期最高、临近次之、无排期最低）× 重要度 + 遗忘风险。
   */
  static priority(node: MindNode, now: number): number {
    let urgency = 0;
    if (node.nextReviewAt <= 0) {
      urgency = 0.3;
    } else if (node.nextReviewAt <= now) {
      urgency = 1.5; // 已逾期
    } else {
      const waitDays = (node.nextReviewAt - now) / DAY_MS;
      urgency = waitDays >= 2 ? 0 : (1 - waitDays / 2);
    }
    const importance = MasteryPredictor.importance(node);
    const forgetRisk = 1 - MasteryPredictor.retention(node, now);
    return urgency * importance + forgetRisk * 0.3;
  }
}
