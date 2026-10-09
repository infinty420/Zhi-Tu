/**
 * QuizService —— 自测生成 + 本地判分门面（Phase 4.3）。
 * 复用 AIService.generateQuiz 出卷；判分走本地规则（挖空精确匹配、问答关键词匹配），
 * 不依赖大模型，保证无密钥也能判分。结果归集只经 NodeLearnService → MindMapStore。
 */
import { AIConfig } from './AIConfig';
import { AIService, QuizGradeResponse, QuizQuestion, QuizRequest } from './AIService';
import { AIServiceFactory } from './AIServiceFactory';
import { NodeLearnService } from './NodeLearnService';

export class QuizService {
  private learn: NodeLearnService = new NodeLearnService();

  /** 生成自测题（支持指定节点与难度，复用 AIService 契约） */
  async generate(req: QuizRequest): Promise<QuizQuestion[]> {
    const svc: AIService = AIServiceFactory.create(AIConfig.load());
    const res = await svc.generateQuiz(req);
    if (res.ok) {
      return res.data.questions;
    }
    return [];
  }

  /** 本地判分：挖空精确匹配；问答/回忆类关键词匹配（命中率≥50% 判对） */
  grade(q: QuizQuestion, userAnswer: string): QuizGradeResponse {
    const ua = (userAnswer ? userAnswer : '').trim();
    const std = (q.answer ? q.answer : '').trim();
    if (ua.length === 0) {
      return { correct: false, score: 0, explanation: `参考答案：${std}` };
    }
    if (ua === std) {
      return { correct: true, score: 100, explanation: '回答正确。' };
    }
    if (q.kind === 'cloze') {
      const ok = ua === std;
      return { correct: ok, score: ok ? 100 : 0, explanation: `参考答案：${std}` };
    }
    const keys = this.extractKeywords(std);
    let hit = 0;
    for (let i = 0; i < keys.length; i++) {
      if (ua.indexOf(keys[i]) >= 0) {
        hit++;
      }
    }
    const ratio = keys.length > 0 ? hit / keys.length : 0;
    const correct = ratio >= 0.5;
    return {
      correct: correct,
      score: Math.round(ratio * 100),
      explanation: `参考答案：${std}`
    };
  }

  /** 判分后归集：更新掌握度 / 错题本 / 复习排队（单一事实源） */
  recordResult(nodeId: string, correct: boolean, question: string, answer: string, userAnswer: string): void {
    this.learn.recordReviewResult(nodeId, correct, question, answer, userAnswer);
  }

  /** 抽取中文关键词（去停用字、长度≥2 的词） */
  private extractKeywords(text: string): string[] {
    const stop = ['的', '了', '是', '在', '和', '与', '或', '把', '被', '用', '对', '，', '。', '、', '；', '：', '（', '）', ' '];
    const words: string[] = [];
    let buf = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (stop.indexOf(ch) >= 0) {
        if (buf.length >= 2) {
          words.push(buf);
        }
        buf = '';
      } else {
        buf += ch;
      }
    }
    if (buf.length >= 2) {
      words.push(buf);
    }
    return words;
  }
}
