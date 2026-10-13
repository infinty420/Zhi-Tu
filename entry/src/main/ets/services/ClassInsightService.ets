/**
 * ClassInsightService —— 师生协作的学情聚合层（纯计算，不新增存储、不依赖 ArkUI）。
 * 1) 把本机学习数据折算成一份「学情快照」，供学生回传给班级；
 * 2) 把班级作业提交情况折算成完成率；
 * 3) 把多份回传快照折算成班级整体画像（平均掌握率 / 薄弱总量 / 典型薄弱点）。
 */
import { MasteryLevel } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { WrongItem } from '../model/StudyModels';
import { ClassInsight, ClassRoom } from '../model/ClassModels';
import { StudyInsightService } from './StudyInsightService';

/** 单份作业完成情况 */
export interface AssignmentProgress {
  id: string;
  title: string;
  submitted: number;
  total: number;
  /** 完成率 0~1 */
  rate: number;
}

/** 班级整体画像 */
export interface ClassSummary {
  /** 已回传学情的人数 */
  reportedCount: number;
  /** 平均掌握率 0~1 */
  avgMastery: number;
  /** 薄弱点总数 */
  weakTotal: number;
  /** 典型薄弱点（来自最薄弱的一份快照） */
  topWeakText: string;
}

export class ClassInsightService {
  /** 由本机学习数据生成学情快照 */
  static buildMyInsight(map: MindMap | undefined, wrongItems: WrongItem[], studentId: string, studentName: string): ClassInsight {
    let masteryRate = 0;
    let weakCount = 0;
    let weakText = '';
    if (map) {
      if (map.nodes.length > 0) {
        let known = 0;
        for (let i = 0; i < map.nodes.length; i++) {
          if (map.nodes[i].mastery === MasteryLevel.KNOWN) {
            known++;
          }
        }
        masteryRate = known / map.nodes.length;
      }
      const weak = StudyInsightService.buildWeakPoints(map, wrongItems);
      weakCount = weak.length;
      const top = weak.length > 3 ? weak.slice(0, 3) : weak;
      const texts: string[] = [];
      for (let i = 0; i < top.length; i++) {
        texts.push(top[i].nodeText);
      }
      weakText = texts.join('、');
    }
    return {
      studentId: studentId,
      studentName: studentName,
      masteryRate: masteryRate,
      weakCount: weakCount,
      weakText: weakText,
      updatedAt: Date.now()
    };
  }

  /** 班级各作业完成率 */
  static assignmentProgress(room: ClassRoom): AssignmentProgress[] {
    const total = room.students.length;
    const out: AssignmentProgress[] = [];
    for (let i = 0; i < room.assignments.length; i++) {
      const a = room.assignments[i];
      const submitted = a.submittedIds.length;
      out.push({
        id: a.id,
        title: a.title,
        submitted: submitted,
        total: total,
        rate: total > 0 ? submitted / total : 0
      });
    }
    return out;
  }

  /** 多份回传快照 → 班级整体画像 */
  static summarize(insights: ClassInsight[]): ClassSummary {
    if (insights.length === 0) {
      return { reportedCount: 0, avgMastery: 0, weakTotal: 0, topWeakText: '' };
    }
    let sum = 0;
    let weakTotal = 0;
    let worst: ClassInsight | undefined = undefined;
    for (let i = 0; i < insights.length; i++) {
      sum += insights[i].masteryRate;
      weakTotal += insights[i].weakCount;
      if (!worst || insights[i].weakCount > worst.weakCount) {
        worst = insights[i];
      }
    }
    return {
      reportedCount: insights.length,
      avgMastery: sum / insights.length,
      weakTotal: weakTotal,
      topWeakText: worst ? worst.weakText : ''
    };
  }

  /** 0~1 → 整数百分比 */
  static percent(rate: number): number {
    return Math.round(rate * 100);
  }
}
