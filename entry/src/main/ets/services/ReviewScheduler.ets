/**
 * ReviewScheduler —— 间隔复习调度（v2.0，Wave 5）。
 * 在 v1.1 固定阶梯（1/2/4/7 天）基础上引入 MasteryPredictor：
 *   - scheduleNext 改用「记忆稳定度」推导的动态间隔（稳定度随复习次数↑、答错次数↓、掌握度↑）；
 *   - 写入 lastReviewedAt（供掌握度预测与遗忘曲线使用）；
 *   - dueNodes / dueCount 沿用，作为待复习的「是否到期」判定。
 */

import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { MasteryPredictor } from './MasteryPredictor';

const DAY_MS = 24 * 3600 * 1000;

export class ReviewScheduler {
  /** 复习间隔阶梯（天，作为稳定度下限参考，v1.1 兼容） */
  static readonly INTERVALS: number[] = [1, 2, 4, 7];

  /** 为节点排入下一次复习：动态间隔 = 记忆稳定度（天），并刷新最近复习时间 */
  static scheduleNext(node: MindNode): void {
    const days = MasteryPredictor.nextIntervalDays(node);
    node.nextReviewAt = Date.now() + days * DAY_MS;
    node.lastReviewedAt = Date.now();
    node.reviewCount = node.reviewCount + 1;
  }

  /** 清除复习排队（已掌握） */
  static clear(node: MindNode): void {
    node.nextReviewAt = 0;
    node.reviewCount = 0;
  }

  /** 取当前待复习（nextReviewAt>0 且已到期）的节点 */
  static dueNodes(map: MindMap): MindNode[] {
    const result: MindNode[] = [];
    if (!map) {
      return result;
    }
    const now = Date.now();
    for (let i = 0; i < map.nodes.length; i++) {
      const n = map.nodes[i];
      if (n.nextReviewAt > 0 && n.nextReviewAt <= now) {
        result.push(n);
      }
    }
    return result;
  }

  /** 当前导图待复习数量 */
  static dueCount(map: MindMap): number {
    return ReviewScheduler.dueNodes(map).length;
  }
}
