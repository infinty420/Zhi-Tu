/**
 * AI 问答服务（v2.0，Mock）。本地关键词检索当前导图节点，合成答案并给出引用节点。
 * 默认离线可用，无需密钥；真实环境可替换为远端大模型接口（保持 ask 签名一致）。
 */

import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';

/** 问答答案 */
export interface QAAnswer {
  answer: string;
  /** 命中的节点文本（引用） */
  refs: string[];
}

/** 关键词命中的节点与得分（问答检索内部使用） */
interface ScoreHit {
  node: MindNode;
  score: number;
}

export class QAService {
  private static _instance: QAService | undefined = undefined;

  static getInstance(): QAService {
    if (QAService._instance === undefined) {
      QAService._instance = new QAService();
    }
    return QAService._instance;
  }

  /** 提问：基于当前导图内容作答 */
  ask(question: string, map: MindMap | undefined): QAAnswer {
    const q = question.trim();
    if (q.length === 0) {
      return { answer: '请输入你的问题，例如「二次函数有哪些性质？」', refs: [] };
    }
    if (!map || map.nodes.length === 0) {
      return { answer: '当前还没有导图内容。先在首页生成一张导图，再来问它吧。', refs: [] };
    }
    const hits = QAService.matchNodes(q, map.nodes);
    if (hits.length === 0) {
      return {
        answer: `在《${map.title}》里没有找到和「${q}」直接相关的内容。试试换一个关键词，或问导图里的某个分支。`,
        refs: []
      };
    }
    const refs: string[] = [];
    const lines: string[] = [];
    for (let i = 0; i < hits.length && i < 5; i++) {
      const n = hits[i];
      refs.push(n.text);
      const detail = n.detail && n.detail.length > 0 ? n.detail : '（暂无要点）';
      lines.push(`· ${n.text}：${detail}`);
    }
    let prefix = '';
    if (hits.length > 5) {
      prefix = `（相关节点较多，仅展示前 ${5} 个）\n`;
    }
    return {
      answer: `根据《${map.title}》，与「${q}」相关的内容有：\n${prefix}${lines.join('\n')}`,
      refs: refs
    };
  }

  private static matchNodes(q: string, nodes: MindNode[]): MindNode[] {
    const lower = q.toLowerCase();
    const scored: ScoreHit[] = [];
    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i];
      const text = n.text.toLowerCase();
      const detail = n.detail.toLowerCase();
      let score = 0;
      if (text === lower) {
        score += 10;
      } else if (text.includes(lower)) {
        score += 5;
      } else if (lower.includes(text) && text.length > 1) {
        score += 3;
      }
      if (detail.includes(lower)) {
        score += 2;
      }
      // 中文逐字命中
      for (let k = 0; k < q.length; k++) {
        const ch = q.charAt(k);
        if (ch.trim().length > 0 && (text.includes(ch) || detail.includes(ch))) {
          score += 1;
        }
      }
      if (score > 0) {
        scored.push({ node: n, score: score });
      }
    }
    scored.sort((a, b) => b.score - a.score);
    const out: MindNode[] = [];
    for (let i = 0; i < scored.length; i++) {
      out.push(scored[i].node);
    }
    return out;
  }
}
