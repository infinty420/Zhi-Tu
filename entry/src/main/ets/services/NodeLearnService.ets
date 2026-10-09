/**
 * NodeLearnService —— 节点学习命令封装（Phase 4.5）。
 * 仅调用 MindMapStore 命令层，不直连 StorageService；所有写入走 store 的 300ms 防抖持久化。
 */
import { MindMapStore } from './MindMapStore';
import { MasteryLevel } from '../model/Constants';

export class NodeLearnService {
  private store: MindMapStore = MindMapStore.getInstance();

  /** 标记节点掌握度（三色：会 / 模糊 / 不会） */
  markMastery(nodeId: string, mastery: MasteryLevel): void {
    this.store.setMastery(nodeId, mastery);
  }

  /** 记录一次自测 / 复习结果：correct 标记会并清队列；错误标记不会、进错题本、排复习 */
  recordReviewResult(nodeId: string, correct: boolean, question: string, answer: string, userAnswer: string): void {
    this.store.recordQuiz(nodeId, correct, question, answer, userAnswer);
  }

  /** 手动加入错题本（复用 recordQuiz 的答错分支，保证单一事实源） */
  addToWrongBook(nodeId: string, question: string, answer: string, userAnswer: string): void {
    this.store.recordQuiz(nodeId, false, question, answer, userAnswer);
  }
}
