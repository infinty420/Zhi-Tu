/**
 * StudyReportService —— 学情报告（Wave 4 · 家长端/周报月报）。
 * 纯计算：以 LearningEvent + WrongItem 为输入，产出近 N 天（7 / 30）的结构化报告与一句话摘要，
 * 不新增存储、不依赖 ArkUI；事件与错题均来自 StorageService 既有数据。
 */
import { LearningEvent, LearningEventType, WrongItem } from '../model/StudyModels';

/** 学情报告 */
export interface StudyReport {
  /** 周期标签，如「近 7 天」 */
  rangeLabel: string;
  /** 周期内学习事件总数 */
  eventCount: number;
  /** 覆盖的学习天数 */
  activeDays: number;
  /** 自测次数 */
  quizCount: number;
  /** 自测正确次数 */
  correctCount: number;
  /** 自测正确率 0~1（无自测时为 -1，表示不适用） */
  correctRate: number;
  /** 复习消项次数 */
  reviewCount: number;
  /** 周期内新增错题数 */
  wrongAdded: number;
  /** 高频错题知识点（前 3，顿号分隔） */
  topWrongText: string;
  /** 一句话结论 + 建议 */
  summary: string;
}

export class StudyReportService {
  /** 生成近 days 天的学情报告 */
  static build(events: LearningEvent[], wrongItems: WrongItem[], days: number): StudyReport {
    const span = days > 0 ? days : 7;
    const startKey = StudyReportService.dateKeyBefore(span);
    let eventCount = 0;
    let quizCount = 0;
    let correctCount = 0;
    let reviewCount = 0;
    const daySet: string[] = [];
    for (let i = 0; i < events.length; i++) {
      const ev = events[i];
      if (ev.date < startKey) {
        continue;
      }
      eventCount++;
      if (daySet.indexOf(ev.date) < 0) {
        daySet.push(ev.date);
      }
      if (ev.type === LearningEventType.QUIZ) {
        quizCount++;
        if (ev.correct === true) {
          correctCount++;
        }
      }
      if (ev.type === LearningEventType.REVIEW) {
        reviewCount++;
      }
    }
    let wrongAdded = 0;
    const counter: string[] = [];
    const counts: number[] = [];
    const startTs = Date.now() - span * 24 * 60 * 60 * 1000;
    for (let i = 0; i < wrongItems.length; i++) {
      const w = wrongItems[i];
      if (w.createdAt < startTs) {
        continue;
      }
      wrongAdded++;
      const idx = counter.indexOf(w.nodeText);
      if (idx >= 0) {
        counts[idx] = counts[idx] + 1;
      } else {
        counter.push(w.nodeText);
        counts.push(1);
      }
    }
    // 高频错题取前 3（简单选择排序，数据量小）
    const top: string[] = [];
    for (let k = 0; k < 3 && counter.length > 0; k++) {
      let best = 0;
      for (let i = 1; i < counts.length; i++) {
        if (counts[i] > counts[best]) {
          best = i;
        }
      }
      top.push(counter[best]);
      counter.splice(best, 1);
      counts.splice(best, 1);
    }
    const correctRate = quizCount > 0 ? correctCount / quizCount : -1;
    const report: StudyReport = {
      rangeLabel: `近 ${span} 天`,
      eventCount: eventCount,
      activeDays: daySet.length,
      quizCount: quizCount,
      correctCount: correctCount,
      correctRate: correctRate,
      reviewCount: reviewCount,
      wrongAdded: wrongAdded,
      topWrongText: top.join('、'),
      summary: ''
    };
    report.summary = StudyReportService.composeSummary(report);
    return report;
  }

  /** 一句话结论 + 下一步建议 */
  private static composeSummary(r: StudyReport): string {
    if (r.eventCount === 0) {
      return `${r.rangeLabel}还没有学习记录。建议从首页「今日待复习」开始，每天完成一组复习。`;
    }
    const rateText = r.correctRate >= 0 ? `自测正确率 ${Math.round(r.correctRate * 100)}%` : '暂无自测记录';
    let advice = '节奏稳定，可用「出相似题」做变式提升。';
    if (r.correctRate >= 0 && r.correctRate < 0.6) {
      advice = '正确率偏低，建议先回到节点详情看「AI 讲解」，再做错题组卷。';
    } else if (r.wrongAdded > 0) {
      advice = `新增 ${r.wrongAdded} 道错题，建议做一次「错题组卷」集中攻克。`;
    }
    return `${r.rangeLabel}共 ${r.eventCount} 次学习，覆盖 ${r.activeDays} 天，${rateText}，复习 ${r.reviewCount} 次。${advice}`;
  }

  /** 报告明细（多行，供页面直接展示 / 分享） */
  static toLines(r: StudyReport): string[] {
    const lines: string[] = [];
    lines.push(`${r.rangeLabel}学习事件：${r.eventCount} 次`);
    lines.push(`覆盖天数：${r.activeDays} 天`);
    lines.push(`自测：${r.quizCount} 次，正确 ${r.correctCount} 次`);
    lines.push(`复习消项：${r.reviewCount} 次`);
    lines.push(`新增错题：${r.wrongAdded} 道`);
    if (r.topWrongText.length > 0) {
      lines.push(`高频错题：${r.topWrongText}`);
    }
    return lines;
  }

  /** days 天前的日期键（YYYY-MM-DD，可直接做字符串比较） */
  private static dateKeyBefore(days: number): string {
    const d = new Date();
    d.setDate(d.getDate() - days);
    const y = d.getFullYear();
    const m = d.getMonth() + 1;
    const day = d.getDate();
    return `${y}-${m < 10 ? '0' + m : m}-${day < 10 ? '0' + day : day}`;
  }
}
