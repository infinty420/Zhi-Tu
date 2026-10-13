/**
 * 师生协作数据模型（v2.0 一起学 · 师生协作）。
 */

/** 学生 */
export interface Student {
  id: string;
  name: string;
}

/** 作业 */
export interface Assignment {
  id: string;
  title: string;
  /** 截止时间（毫秒时间戳） */
  dueAt: number;
  /** 已提交的学生 id 列表 */
  submittedIds: string[];
}

/** 学生回传的学情快照（本地 Mock：由本机学习数据生成） */
export interface ClassInsight {
  studentId: string;
  studentName: string;
  /** 当前导图掌握率 0~1 */
  masteryRate: number;
  /** 薄弱知识点数量 */
  weakCount: number;
  /** 薄弱点摘要（前 3 个知识点，顿号分隔） */
  weakText: string;
  /** 回传时间 */
  updatedAt: number;
}

/** 班级 */
export interface ClassRoom {
  id: string;
  name: string;
  teacher: string;
  /** 邀请码（Mock） */
  code: string;
  students: Student[];
  assignments: Assignment[];
  createdAt: number;
  /** 学情回传记录（旧数据无此字段，缺省为空） */
  insights?: ClassInsight[];
}
