/**
 * ContentQualityChecker —— 学科化富内容轻量质量校验（Phase X）。
 * 作为 AI 生产端的质量兜底：校验富内容必填字段，返回缺失字段清单。
 * 不依赖 UI，纯 model 层类型判断。
 */
import { NodeRichContent, KeyPointItem, FormulaItem, RichExampleItem, MisconceptionItem } from '../model/MindNode';
import { QuizQuestion, QuizResponse } from './AIService';
import { quizMatchesTemplate } from '../model/ExamPointTemplates';

/** 考点模板命中率结果 */
export interface TemplateCoverage {
  /** 命中考点模板的题数 */
  covered: number;
  /** 总题数 */
  total: number;
  /** 命中率 0~1 */
  ratio: number;
}

export interface QualityReport {
  ok: boolean;
  /** 缺失/不合规的字段路径清单（如 'formulas[0].latexText'） */
  missing: string[];
}

export class ContentQualityChecker {
  /** 校验整体富内容，返回缺失字段清单（空数组=合格） */
  static check(rich: NodeRichContent): QualityReport {
    const missing: string[] = [];
    ContentQualityChecker.checkKeyPoints(rich.keyPoints, missing);
    ContentQualityChecker.checkFormulas(rich.formulas, missing);
    ContentQualityChecker.checkExamples(rich.examples, missing);
    ContentQualityChecker.checkMisconceptions(rich.misconceptions, missing);
    return { ok: missing.length === 0, missing: missing };
  }

  private static checkKeyPoints(items: KeyPointItem[], missing: string[]): void {
    for (let i = 0; i < items.length; i++) {
      if (!items[i].text || items[i].text.length === 0) {
        missing.push(`keyPoints[${i}].text`);
      }
    }
  }

  private static checkFormulas(items: FormulaItem[], missing: string[]): void {
    for (let i = 0; i < items.length; i++) {
      const f = items[i];
      if (!f.latexText || f.latexText.length === 0) {
        missing.push(`formulas[${i}].latexText`);
      }
      if (!f.plainText || f.plainText.length === 0) {
        missing.push(`formulas[${i}].plainText`);
      }
    }
  }

  private static checkExamples(items: RichExampleItem[], missing: string[]): void {
    for (let i = 0; i < items.length; i++) {
      const e = items[i];
      if (!e.question || e.question.length === 0) {
        missing.push(`examples[${i}].question`);
      }
      if (!e.answer || e.answer.length === 0) {
        missing.push(`examples[${i}].answer`);
      }
    }
  }

  private static checkMisconceptions(items: MisconceptionItem[], missing: string[]): void {
    for (let i = 0; i < items.length; i++) {
      const m = items[i];
      if (!m.wrong || m.wrong.length === 0) {
        missing.push(`misconceptions[${i}].wrong`);
      }
      if (!m.correct || m.correct.length === 0) {
        missing.push(`misconceptions[${i}].correct`);
      }
    }
  }

  /**
   * 计算自测题对学科考点模板的命中率（考点模板库质量信号）。
   * 题干或答案命中任一学科考点关键词即记为命中；返回命中率 ratio。
   */
  static checkQuizTemplateCoverage(quiz: QuizResponse, subject: string): TemplateCoverage {
    const questions: QuizQuestion[] = quiz.questions;
    let covered = 0;
    for (let i = 0; i < questions.length; i++) {
      const text = `${questions[i].prompt} ${questions[i].answer}`;
      if (quizMatchesTemplate(text, subject)) {
        covered++;
      }
    }
    const total = questions.length;
    return { covered: covered, total: total, ratio: total > 0 ? covered / total : 0 };
  }
}
