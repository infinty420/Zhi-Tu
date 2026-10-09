/**
 * StudyInsightService —— 学情洞察（Wave 2：个性化自适应）。
 * 在既有学习闭环数据（掌握度 / 错题本 / 复习排队）之上做纯计算聚合，不新增存储、无 UI 依赖：
 *   - 薄弱点：按「错题次数 + 是否到期 + 掌握度」打分排序；
 *   - 学情画像：按节点学科类型分组统计薄弱数与掌握率；
 *   - 自适应推荐：挑出最该复习的下一个节点；
 *   - 智能组卷：错题本按遗忘衰减（越久没练越优先）去重组卷。
 */
import { MasteryLevel, NODE_TYPE_LABEL, NodeType } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { WrongItem } from '../model/StudyModels';
import { QuizQuestion } from './AIService';

/** 单个薄弱知识点 */
export interface WeakPointItem {
  nodeId: string;
  nodeText: string;
  nodeType: NodeType;
  /** 累计答错次数（来自错题本） */
  wrongCount: number;
  mastery: MasteryLevel;
  /** 是否已到复习时间 */
  due: boolean;
  /** 薄弱度评分（越高越该优先复习） */
  score: number;
}

/** 按学科分组的学情画像 */
export interface SubjectWeakProfile {
  nodeType: NodeType;
  label: string;
  total: number;
  /** 薄弱节点数（有过错或未掌握） */
  weakCount: number;
  /** 掌握率 0~1 */
  masteryRate: number;
}

/** 自适应学习路径推荐项 */
export interface NextRecommendation {
  nodeId: string;
  nodeText: string;
  nodeType: NodeType;
  /** 推荐理由（展示给学生的解释） */
  reason: string;
}

export class StudyInsightService {
  /** 统计每个节点的累计答错次数 */
  static countWrongByNode(items: WrongItem[]): Map<string, number> {
    const counts = new Map<string, number>();
    for (let i = 0; i < items.length; i++) {
      const id = items[i].nodeId;
      const cur = counts.get(id);
      counts.set(id, cur === undefined ? 1 : cur + 1);
    }
    return counts;
  }

  /** 单节点薄弱度评分：错题权重最高，其次到期、不会、模糊 */
  private static scoreOf(wrongCount: number, due: boolean, mastery: MasteryLevel): number {
    let s = wrongCount * 10;
    if (due) {
      s += 5;
    }
    if (mastery === MasteryLevel.UNKNOWN) {
      s += 3;
    } else if (mastery === MasteryLevel.FUZZY) {
      s += 2;
    } else if (mastery === MasteryLevel.UNSET) {
      s += 1;
    }
    return s;
  }

  /** 构建薄弱点清单（按薄弱度降序） */
  static buildWeakPoints(map: MindMap, wrongItems: WrongItem[]): WeakPointItem[] {
    const counts = StudyInsightService.countWrongByNode(wrongItems);
    const now = Date.now();
    const list: WeakPointItem[] = [];
    for (let i = 0; i < map.nodes.length; i++) {
      const n: MindNode = map.nodes[i];
      const wrongCount = counts.get(n.id) === undefined ? 0 : (counts.get(n.id) as number);
      const due = n.nextReviewAt > 0 && n.nextReviewAt <= now;
      const score = StudyInsightService.scoreOf(wrongCount, due, n.mastery);
      // 只保留真正「薄弱」的节点：错过、未掌握或已到期
      if (wrongCount > 0 || due || n.mastery === MasteryLevel.UNKNOWN || n.mastery === MasteryLevel.FUZZY) {
        list.push({
          nodeId: n.id,
          nodeText: n.text,
          nodeType: n.type,
          wrongCount: wrongCount,
          mastery: n.mastery,
          due: due,
          score: score
        });
      }
    }
    list.sort((a: WeakPointItem, b: WeakPointItem) => b.score - a.score);
    return list;
  }

  /** 按学科类型聚合学情画像 */
  static buildSubjectProfile(map: MindMap, weak: WeakPointItem[]): SubjectWeakProfile[] {
    const totals = new Map<string, number>();
    const weakSet = new Set<string>();
    for (let i = 0; i < map.nodes.length; i++) {
      const t: string = map.nodes[i].type;
      const cur = totals.get(t);
      totals.set(t, cur === undefined ? 1 : cur + 1);
    }
    for (let i = 0; i < weak.length; i++) {
      weakSet.add(weak[i].nodeId);
    }
    const profiles: SubjectWeakProfile[] = [];
    const keys: string[] = [];
    totals.forEach((value: number, key: string) => {
      keys.push(key);
    });
    for (let i = 0; i < keys.length; i++) {
      const type = keys[i] as NodeType;
      let total = 0;
      let weakCount = 0;
      for (let j = 0; j < map.nodes.length; j++) {
        const n: MindNode = map.nodes[j];
        if (n.type !== type) {
          continue;
        }
        total++;
        if (weakSet.has(n.id)) {
          weakCount++;
        }
      }
      const label = NODE_TYPE_LABEL.get(type);
      profiles.push({
        nodeType: type,
        label: label === undefined ? String(type) : label,
        total: total,
        weakCount: weakCount,
        masteryRate: total > 0 ? (total - weakCount) / total : 0
      });
    }
    profiles.sort((a: SubjectWeakProfile, b: SubjectWeakProfile) => b.weakCount - a.weakCount);
    return profiles;
  }

  /** 自适应推荐下一个该学的节点（薄弱点优先；无薄弱项则推荐未掌握节点） */
  static recommendNext(map: MindMap, wrongItems: WrongItem[]): NextRecommendation | undefined {
    const weak = StudyInsightService.buildWeakPoints(map, wrongItems);
    if (weak.length > 0) {
      const top = weak[0];
      let reason = '';
      if (top.wrongCount > 0) {
        reason = `累计答错 ${top.wrongCount} 次，${top.due ? '且已到复习时间' : '建议优先攻克'}`;
      } else if (top.due) {
        reason = '已到复习时间，趁忘记前巩固一次';
      } else {
        reason = '该知识点尚未掌握，建议先过一遍';
      }
      return { nodeId: top.nodeId, nodeText: top.nodeText, nodeType: top.nodeType, reason: reason };
    }
    for (let i = 0; i < map.nodes.length; i++) {
      const n: MindNode = map.nodes[i];
      if (n.mastery === MasteryLevel.UNSET || n.mastery === MasteryLevel.UNKNOWN) {
        return {
          nodeId: n.id,
          nodeText: n.text,
          nodeType: n.type,
          reason: '本导图暂无薄弱项，建议继续推进未掌握的知识点'
        };
      }
    }
    return undefined;
  }

  /**
   * 智能组卷：错题本按遗忘衰减组一套复习卷。
   * 同一节点只取最近一次错题（去重），越久没练的越优先（遗忘曲线）。
   */
  static composeWrongBookQuiz(items: WrongItem[], limit: number): QuizQuestion[] {
    if (!items || items.length === 0) {
      return [];
    }
    const latest = new Map<string, WrongItem>();
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      const cur = latest.get(it.nodeId);
      if (cur === undefined || it.createdAt > cur.createdAt) {
        latest.set(it.nodeId, it);
      }
    }
    const list: WrongItem[] = [];
    latest.forEach((value: WrongItem) => {
      list.push(value);
    });
    // 越久没复习越优先（createdAt 升序）
    list.sort((a: WrongItem, b: WrongItem) => a.createdAt - b.createdAt);
    const out: QuizQuestion[] = [];
    const max = limit > 0 ? limit : 5;
    for (let i = 0; i < list.length && out.length < max; i++) {
      const it = list[i];
      const last = it.userAnswer && it.userAnswer.length > 0 ? `你上次的作答：${it.userAnswer}` : '提示：先回忆定义再作答';
      out.push({
        id: `wb_${it.nodeId}`,
        kind: 'qa',
        nodeId: it.nodeId,
        prompt: it.question,
        answer: it.answer,
        hint: last
      });
    }
    return out;
  }
}
