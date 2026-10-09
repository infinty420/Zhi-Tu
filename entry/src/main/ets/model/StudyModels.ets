/**
 * 学习闭环数据模型（v1.1）。
 * 仅承载数据结构，不依赖 services / ArkUI，便于 model 与 storage 两层复用。
 */

import { MasteryLevel } from './Constants';

/** 学习事件类型 */
export enum LearningEventType {
  STUDY = 'study', // 学习模式下标记掌握度
  QUIZ = 'quiz', // 自测作答
  REVIEW = 'review' // 复习消项
}

/** 单次学习事件（按日聚合统计的原子记录） */
export interface LearningEvent {
  id: string;
  mapId: string;
  nodeId: string;
  date: string; // YYYY-MM-DD
  type: LearningEventType;
  mastery: MasteryLevel;
  correct?: boolean;
}

/** 错题本条目 */
export interface WrongItem {
  id: string;
  mapId: string;
  nodeId: string;
  nodeText: string;
  question: string;
  answer: string;
  userAnswer: string;
  createdAt: number;
}

/** 生词本条目（英语例句收藏沉淀） */
export interface VocabItem {
  id: string;
  english: string;
  chinese: string;
  analysis: string;
  createdAt: number;
}

/** 学习统计快照 */
export interface StudyStats {
  studyDayCount: number; // 累计学习天数（去重）
  streakDays: number; // 连续打卡天数
  totalEvents: number;
  masteredCount: number; // 当前导图中标记「会」的节点数
  totalCount: number; // 当前导图节点总数
  masteryRate: number; // 掌握率 0~1
  dueReviewCount: number; // 今日待复习数
  todayEventCount: number; // 今日学习事件数（复习/自测/标记掌握）
}
