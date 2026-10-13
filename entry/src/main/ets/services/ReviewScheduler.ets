/**
 * ReviewScheduler —— 轻量间隔复习调度（v1.1）。
 * 简化艾宾浩斯：答错 / 标记模糊的节点按 1/2/4/7 天阶梯排入复习；
 * 复习消项后推进阶梯，超出阶梯则清除待复习标记。
 */

import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';

const DAY_MS = 24 * 3600 * 1000;

export class ReviewScheduler {
  /** 复习间隔阶梯（天） */
  static readonly INTERVALS: number[] = [1, 2, 4, 7];

  /** 为节点排入下一次复习（基于已复习次数选取阶梯间隔） */
  static scheduleNext(node: MindNode): void {
    const idx = Math.min(node.reviewCount, ReviewScheduler.INTERVALS.length - 1);
    const days = ReviewScheduler.INTERVALS[idx];
    node.nextReviewAt = Date.now() + days * DAY_MS;
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
