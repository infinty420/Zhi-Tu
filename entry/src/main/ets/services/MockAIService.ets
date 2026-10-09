/**
 * MockAIService —— 内置样例数据，保证无密钥/离线时「输入→出图→编辑→深链」主链路可跑通。
 * 提供流式回调模拟（分片回调，模拟前端流式打字效果）。
 */
import { Layout, NodeShape, NodeType, SUBJECTS } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { AIErrorCode, AIResult, AgentChatRequest, AgentChatResponse, AgentStreamChunk, AIService, ExampleItem, ExamplesRequest, ExamplesResponse, MapPatchOp, MindMapGenRequest, MindMapGenResponse, MindMapStreamChunk, QuizGradeRequest, QuizGradeResponse, QuizQuestion, QuizRequest, QuizResponse, RichContentGenRequest, RichContentGenResponse, SimilarQuizRequest, StreamHandler, TutorChunk, TutorRequest, TutorResponse, aiFailure, aiSuccess } from './AIService';
import { AIResponseValidator } from './AIResponseValidator';
import { NodeRichContent, NodeStyle, KeyPointItem, FormulaItem, RichExampleItem, MisconceptionItem, NodeLink, emptyNodeRichContent, emptyChineseContent, emptyHistoryContent, emptyGeographyContent, emptyBiologyContent, emptyEnglishContent, emptyChemistryContent, emptyPoliticsContent } from '../model/MindNode';
import { matchExamTemplate } from '../model/ExamPointTemplates';

interface MockNodeDef {
  id: string;
  text: string;
  parentId: string | null;
  type: NodeType;
  detail: string;
  style: NodeStyle;
}

export class MockAIService implements AIService {
  generateMindMap(req: MindMapGenRequest, onStream: StreamHandler<MindMapStreamChunk>): Promise<AIResult<MindMapGenResponse>> {
    const rawJson = this.pickMapJson(req.query, req.subject, req.book);
    return this.simulate((): AIResult<MindMapGenResponse> => {
      onStream({ text: rawJson, done: false });
      onStream({ text: '', done: true });
      const validated = AIResponseValidator.validateMindMapJson(rawJson);
      if (!validated.ok) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, 'Mock 数据异常', true);
      }
      const resp: MindMapGenResponse = { rawJson: rawJson, map: validated.data };
      return aiSuccess(resp);
    });
  }

  chatPatch(req: AgentChatRequest, onStream: StreamHandler<AgentStreamChunk>): Promise<AIResult<AgentChatResponse>> {
    const ops = this.pickOps(req.instruction);
    const reply = `（Mock）已解析指令：${req.instruction}，共 ${ops.length} 条变更。`;
    return this.simulate((): AIResult<AgentChatResponse> => {
      const half = Math.max(1, Math.floor(reply.length / 2));
      onStream({ delta: reply.substring(0, half), done: false });
      onStream({ delta: reply.substring(half), done: false });
      onStream({ delta: '', done: true });
      const resp: AgentChatResponse = { reply: reply, ops: ops };
      return aiSuccess(resp);
    });
  }

  generateExamples(req: ExamplesRequest): Promise<AIResult<ExamplesResponse>> {
    const items: ExampleItem[] = this.buildExamples(req.word);
    return this.simulate((): AIResult<ExamplesResponse> => {
      const resp: ExamplesResponse = { word: req.word, examples: items };
      return aiSuccess(resp);
    });
  }

  generateQuiz(req: QuizRequest): Promise<AIResult<QuizResponse>> {
    return this.simulate((): AIResult<QuizResponse> => {
      const map = MindMap.fromJson(req.mapJson);
      if (!map || map.nodes.length === 0) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, '测验生成失败：导图为空', true);
      }
      const limit = req.limit && req.limit > 0 ? req.limit : 6;
      const questions: QuizQuestion[] = [];
      const chosen = req.nodeIds && req.nodeIds.length > 0
        ? req.nodeIds.map((id) => map.findNode(id)).filter((n) => n !== undefined) as MindNode[]
        : map.nodes;
      for (let i = 0; i < chosen.length && questions.length < limit; i++) {
        const node = chosen[i];
        const children = node.childrenOf(map);
        if (children.length > 0) {
          const childTexts = children.map((c) => c.text);
          questions.push({
            id: `q_${node.id}_c`,
            kind: 'recall_children',
            nodeId: node.id,
            prompt: `请回忆「${node.text}」包含哪些要点 / 子节点？`,
            answer: childTexts.join('、'),
            hint: '提示：回忆该节点的直接子节点 / 关键要点。'
          });
        } else if (node.parentId !== null) {
          const parent = map.findNode(node.parentId);
          questions.push({
            id: `q_${node.id}_p`,
            kind: 'recall_parent',
            nodeId: node.id,
            prompt: `「${node.text}」属于哪个上级知识点？`,
            answer: parent ? parent.text : '',
            hint: '提示：找准父节点与归属关系。'
          });
        }
        if (node.detail && node.detail.length > 0) {
          questions.push({
            id: `q_${node.id}_d`,
            kind: 'qa',
            nodeId: node.id,
            prompt: `简述「${node.text}」：${node.detail.substring(0, 12)}…`,
            answer: node.detail,
            hint: '提示：按细节要点作答，关键词命中≥50% 即判对。'
          });
        }
        if (questions.length >= limit) {
          break;
        }
      }
      // 兜底：导图极小也至少出一题
      if (questions.length === 0 && map.nodes.length > 0) {
        const root = map.rootNode();
        if (root) {
          questions.push({
            id: `q_${root.id}_r`,
            kind: 'recall_children',
            nodeId: root.id,
            prompt: `请回忆「${root.text}」包含哪些要点？`,
            answer: root.childrenOf(map).map((c) => c.text).join('、'),
            hint: '提示：回忆根节点的直接子节点。'
          });
        }
      }
      const quizResp: QuizResponse = { questions: questions };
      return aiSuccess(quizResp);
    });
  }

  generateSimilarQuiz(req: SimilarQuizRequest): Promise<AIResult<QuizResponse>> {
    return this.simulate((): AIResult<QuizResponse> => {
      const t = req.nodeText ? req.nodeText : '该知识点';
      const d = req.nodeDetail && req.nodeDetail.length > 0 ? req.nodeDetail : t;
      const tmpl = matchExamTemplate(req.subject ? req.subject : '', t);
      const topicHint = tmpl && tmpl.hint.length > 0 ? tmpl.hint : '结合定义与例题巩固。';
      const limit = req.limit && req.limit > 0 ? req.limit : 1;
      const questions: QuizQuestion[] = [];
      // 变式一：换情境考同一考点（问答，关键词命中≥50% 判对，复用 QuizService 判分）
      questions.push({
        id: `sim_${req.nodeId}_1`,
        kind: 'qa',
        nodeId: req.nodeId,
        prompt: `（相似题·变式）关于「${t}」，请说明它与相近概念的区别或联系。`,
        answer: d,
        hint: `考点提示：${topicHint}`
      });
      if (limit >= 2) {
        questions.push({
          id: `sim_${req.nodeId}_2`,
          kind: 'qa',
          nodeId: req.nodeId,
          prompt: `（相似题·应用）请举一个生活/题目中的例子说明「${t}」的用法。`,
          answer: d,
          hint: `考点提示：${topicHint}`
        });
      }
      const quizResp: QuizResponse = { questions: questions };
      return aiSuccess(quizResp);
    });
  }

  /**
   * 无密钥/离线兜底：不做"一句套话"，而是基于节点自身 detail 与考点模板库
   * 生成结构化学习卡（定义要点 + 考法 + 公式 + 可背答案的例题 + 易错点），
   * 并由 NodePage 侧按文本去重后追加。
   */
  generateRichContentForNode(req: RichContentGenRequest): Promise<AIResult<RichContentGenResponse>> {
    return this.simulate((): AIResult<RichContentGenResponse> => {
      const t = req.nodeText ? req.nodeText : '该知识点';
      const subject = req.subject ? req.subject : '';
      const detail = req.nodeDetail ? req.nodeDetail.trim() : '';
      const tmpl = matchExamTemplate(subject, t);
      const hint = tmpl && tmpl.hint.length > 0 ? tmpl.hint : '先抓定义，再练一道典型例题，最后过一遍易错点。';
      const rich = emptyNodeRichContent();
      const seq = new Date().getTime().toString();
      let n = 0;
      const nextId = (tag: string): string => `ai_${seq}_${tag}_${n++}`;

      // 1) 要点：优先复用节点 detail 的实质内容，避免空话
      const detailLines = detail.split(/\n+/).map((s: string): string => s.trim()).filter((s: string): boolean => s.length > 0);
      if (detailLines.length > 0) {
        rich.keyPoints.push({ id: nextId('k'), text: `定义核心：${detailLines[0]}`, level: 'core', memorized: false, addedBy: 'ai' });
        for (let i = 1; i < detailLines.length && rich.keyPoints.length < 4; i++) {
          const line = detailLines[i].length > 42 ? detailLines[i].substring(0, 41) + '…' : detailLines[i];
          rich.keyPoints.push({ id: nextId('k'), text: line, level: 'core', memorized: false, addedBy: 'ai' });
        }
      } else {
        rich.keyPoints.push({ id: nextId('k'), text: `「${t}」是什么：它解决什么问题、适用条件是什么、常见的反面例子是什么`, level: 'core', memorized: false, addedBy: 'ai' });
        rich.keyPoints.push({ id: nextId('k'), text: `怎么记：把它与已会的相邻概念对比记忆（共同点 / 差异点各写一条）`, level: 'extended', memorized: false, addedBy: 'ai' });
      }
      // 2) 考法提示：来自学科考点模板库
      rich.keyPoints.push({ id: nextId('k'), text: `考法提示：${hint}`, level: 'exam', memorized: false, addedBy: 'ai' });

      // 3) 公式：detail 里含 "=" 的短行提升为公式条目（可进公式卡渲染）
      for (let i = 0; i < detailLines.length; i++) {
        const line = detailLines[i];
        if (line.includes('=') && line.length <= 60) {
          rich.formulas.push({ id: nextId('f'), latexText: line, plainText: line, variables: [], meaning: `「${t}」要点中的关系式` });
          break;
        }
      }

      // 4) 例题：答案必须是可背诵、可对照的实质内容（detail 全文）
      const coreAnswer = detailLines.length > 0 ? detailLines.join('；') : `「${t}」的定义、适用条件与一个典型例子（可在子节点里先补全再测）`;
      rich.examples.push({
        id: nextId('e'),
        question: `请说出「${t}」的 2~3 个核心要点（定义 / 条件 / 结论各一条）。`,
        answer: coreAnswer,
        difficulty: 2,
        source: 'AI 补充'
      });
      rich.examples.push({
        id: nextId('e'),
        question: `（应用）关于「${t}」：${hint}请结合一道题或一个生活现象说明。`,
        answer: coreAnswer,
        difficulty: 3,
        source: 'AI 补充'
      });

      // 5) 易错点：落在"学习方法"这个真实高频失分点上
      rich.misconceptions.push({
        id: nextId('m'),
        wrong: '只看笔记不动手默写，就以为已经掌握了',
        correct: `合上书默写「${t}」的要点，再对照查漏`,
        whyWrong: '看得懂不等于写得出，考试考的是输出'
      });

      if (req.subject === 'english' || req.nodeType === 'english') {
        rich.english = { word: t, phonetic: '', examples: [{ english: t, chinese: '（待补充释义）' }] };
      }
      const resp: RichContentGenResponse = { nodeText: t, rich: rich };
      return aiSuccess(resp);
    });
  }

  gradeAnswer(req: QuizGradeRequest): Promise<AIResult<QuizGradeResponse>> {
    return this.simulate((): AIResult<QuizGradeResponse> => {
      const answer = req.question.answer ? req.question.answer : '';
      const user = req.userAnswer ? req.userAnswer : '';
      if (answer.length === 0) {
        const emptyGrade: QuizGradeResponse = { correct: false, score: 0, explanation: '无标准答案可判' };
        return aiSuccess(emptyGrade);
      }
      // 以标点 / 中文顿号分割为标准要点
      const tokens = answer.split(/[，,、；;。\s/]+/).filter((t) => t.length > 0);
      const lowerUser = user.toLowerCase();
      let hit = 0;
      for (let i = 0; i < tokens.length; i++) {
        if (lowerUser.indexOf(tokens[i].toLowerCase()) >= 0) {
          hit++;
        }
      }
      const ratio = tokens.length > 0 ? hit / tokens.length : 0;
      const correct = ratio >= 0.5;
      const score = Math.round(ratio * 100);
      const explanation = correct
        ? '回答准确，已掌握该要点。'
        : `参考答案要点：${answer}`;
      const grade: QuizGradeResponse = { correct: correct, score: score, explanation: explanation };
      return aiSuccess(grade);
    });
  }

  /** 生成一个空导图（科目匹配） */
  buildEmptyMap(subjectCode: string): MindMap {
    return MindMap.create('mock_empty', '未命名导图', subjectCode, '');
  }

  private simulate<T>(work: () => AIResult<T>): Promise<AIResult<T>> {
    return new Promise<AIResult<T>>((resolve) => {
      setTimeout(() => {
        resolve(work());
      }, 30);
    });
  }

  private pickMapJson(query: string, subject: string, book: string): string {
    const q = query ? query : '';
    const s = subject ? subject : '';
    const combined = (q + s).toLowerCase();
    if (combined.includes('物理') || combined.includes('光') || combined.includes('折射') || combined.includes('physics')) {
      return this.refractionJson(book);
    }
    return this.quadraticJson(book);
  }

  // ---------- 样例一：二次函数 ----------
  private quadraticJson(book: string): string {
    const title = '二次函数';
    const nodes: MockNodeDef[] = [
      { id: 'r1', text: '二次函数', parentId: null, type: NodeType.MATH, detail: '形如 y=ax²+bx+c (a≠0) 的函数', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'c1', text: '定义与解析式', parentId: 'r1', type: NodeType.MATH, detail: '', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'c2', text: '图像与性质', parentId: 'r1', type: NodeType.MATH, detail: '抛物线', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'c3', text: '与一元二次方程', parentId: 'r1', type: NodeType.GENERAL, detail: '', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'c4', text: '实际应用', parentId: 'r1', type: NodeType.GENERAL, detail: '抛物线运动·最值问题', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'c5', text: '二次函数英文词汇', parentId: 'r1', type: NodeType.ENGLISH, detail: 'quadratic function', style: { color: '#eb2f96', shape: NodeShape.ROUND } },
      { id: 'g1', text: '一般式 y=ax²+bx+c', parentId: 'c1', type: NodeType.MATH, detail: '', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'g2', text: '顶点式 y=a(x-h)²+k', parentId: 'c1', type: NodeType.MATH, detail: '顶点 (h,k)', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'g3', text: '交点式 y=a(x-x₁)(x-x₂)', parentId: 'c1', type: NodeType.MATH, detail: '', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'p1', text: '开口方向由 a 决定', parentId: 'c2', type: NodeType.GENERAL, detail: 'a>0 开口向上，a<0 开口向下', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'p2', text: '顶点坐标', parentId: 'c2', type: NodeType.MATH, detail: '(-b/2a, (4ac-b²)/4a)', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'p3', text: '对称轴', parentId: 'c2', type: NodeType.MATH, detail: 'x=-b/2a', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'p4', text: '最值与增减性', parentId: 'c2', type: NodeType.GENERAL, detail: '抛物线', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'e1', text: '零点与求根公式', parentId: 'c3', type: NodeType.MATH, detail: 'x=(-b±√(b²-4ac))/2a', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'e2', text: '判别式 Δ=b²-4ac', parentId: 'c3', type: NodeType.MATH, detail: 'Δ>0 两个不同实根', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'a1', text: '抛物线运动轨迹', parentId: 'c4', type: NodeType.MATH, detail: '', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'a2', text: '利润最值问题', parentId: 'c4', type: NodeType.GENERAL, detail: '', style: { color: '#8a94a6', shape: NodeShape.ROUND } }
    ];
    const map = MindMap.create('mock_qf', title, 'math', book ? book : '人教版 九年级数学', Layout.TREE_H, 'ocean');
    const richMap = this.quadraticRichMap();
    map.nodes = nodes.map((n) => {
      const node = new MindNode();
      node.id = n.id;
      node.text = n.text;
      node.parentId = n.parentId;
      node.type = n.type;
      node.detail = n.detail;
      node.style = n.style;
      const rc = richMap.get(n.id);
      if (rc) {
        node.richContent = rc;
      }
      return node;
    });
    return map.toJson();
  }

  // ---------- 样例二：光的折射 ----------
  private refractionJson(book: string): string {
    const title = '光的折射';
    const nodes: MockNodeDef[] = [
      { id: 'r1', text: '光的折射', parentId: null, type: NodeType.PHYSICS, detail: '光从一种介质斜射入另一种介质时传播方向发生偏折', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'c1', text: '折射定律', parentId: 'r1', type: NodeType.PHYSICS, detail: '', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'c2', text: '折射率', parentId: 'r1', type: NodeType.PHYSICS, detail: '', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'c3', text: '全反射', parentId: 'r1', type: NodeType.PHYSICS, detail: '', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'c4', text: '生活中的折射', parentId: 'r1', type: NodeType.GENERAL, detail: '', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'c5', text: '光的折射英文词汇', parentId: 'r1', type: NodeType.ENGLISH, detail: 'refraction', style: { color: '#eb2f96', shape: NodeShape.ROUND } },
      { id: 'g1', text: '入射角与折射角', parentId: 'c1', type: NodeType.PHYSICS, detail: '', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'g2', text: '折射定律公式', parentId: 'c1', type: NodeType.MATH, detail: 'n₁sinθ₁=n₂sinθ₂', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'g3', text: '光路可逆', parentId: 'c1', type: NodeType.GENERAL, detail: '', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'p1', text: '定义 n=c/v', parentId: 'c2', type: NodeType.MATH, detail: '', style: { color: '#1677ff', shape: NodeShape.ROUND } },
      { id: 'p2', text: '介质与折射率比较', parentId: 'c2', type: NodeType.PHYSICS, detail: '空气≈1，水 1.33，玻璃 1.5', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'p3', text: '光的折射作图', parentId: 'c2', type: NodeType.PHYSICS, detail: '折射光线偏向法线', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'q1', text: '临界角', parentId: 'c3', type: NodeType.PHYSICS, detail: 'sinC=1/n', style: { color: '#00b96b', shape: NodeShape.ROUND } },
      { id: 'q2', text: '全反射条件', parentId: 'c3', type: NodeType.GENERAL, detail: '光密→光疏 且入射角>临界角', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'q3', text: '光纤通信应用', parentId: 'c3', type: NodeType.GENERAL, detail: '', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'w1', text: '筷子弯折现象', parentId: 'c4', type: NodeType.GENERAL, detail: '', style: { color: '#8a94a6', shape: NodeShape.ROUND } },
      { id: 'w2', text: '海市蜃楼', parentId: 'c4', type: NodeType.GENERAL, detail: '', style: { color: '#8a94a6', shape: NodeShape.ROUND } }
    ];
    const map = MindMap.create('mock_lr', title, 'physics', book ? book : '人教版 八年级物理 第四章', Layout.TREE_H, 'ocean');
    const richMap = this.refractionRichMap();
    map.nodes = nodes.map((n) => {
      const node = new MindNode();
      node.id = n.id;
      node.text = n.text;
      node.parentId = n.parentId;
      node.type = n.type;
      node.detail = n.detail;
      node.style = n.style;
      const rc = richMap.get(n.id);
      if (rc) {
        node.richContent = rc;
      }
      return node;
    });
    return map.toJson();
  }

  // ---------- 二次函数：学科化富内容 Mock ----------
  private quadraticRichMap(): Map<string, NodeRichContent> {
    const m = new Map<string, NodeRichContent>();

    const r1 = emptyNodeRichContent();
    const r1Kp: KeyPointItem[] = [
      { id: 'r1_k1', text: '定义：形如 y=ax²+bx+c 且 a≠0 的函数', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'r1_k2', text: '图像是一条抛物线，|a| 决定开口大小，a 的正负决定开口方向', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'r1_k3', text: '三大考法：图像与性质、与一元二次方程的关系、实际应用最值', level: 'exam', memorized: false, addedBy: 'ai' }
    ];
    const r1F: FormulaItem[] = [
      { id: 'r1_f1', latexText: 'y=ax^2+bx+c', plainText: 'y=ax^2+bx+c', variables: [{ name: 'a', meaning: '二次项系数，决定开口方向与形状大小' }, { name: 'b', meaning: '一次项系数' }, { name: 'c', meaning: '常数项，图像与 y 轴交点纵坐标' }], meaning: '一般式' },
      { id: 'r1_f2', latexText: 'x=-\\frac{b}{2a}', plainText: 'x=-b/2a', variables: [{ name: 'a', meaning: '二次项系数' }, { name: 'b', meaning: '一次项系数' }], meaning: '对称轴方程' },
      { id: 'r1_f3', latexText: '\\left(-\\frac{b}{2a},\\frac{4ac-b^2}{4a}\\right)', plainText: '(-b/2a,(4ac-b^2)/4a)', variables: [{ name: 'a', meaning: '二次项系数' }, { name: 'b', meaning: '一次项系数' }, { name: 'c', meaning: '常数项' }], meaning: '顶点坐标公式' }
    ];
    const r1E: RichExampleItem[] = [
      { id: 'r1_e1', question: '已知二次函数 y=x²-2x-3，求对称轴与顶点坐标，并判断开口方向。', answer: 'a=1>0 开口向上；对称轴 x=1；顶点 (1,-4)。', difficulty: 3, source: '教材例题' }
    ];
    const r1M: MisconceptionItem[] = [
      { id: 'r1_m1', wrong: 'a 越大，抛物线开口越大', correct: '|a| 越大，抛物线开口越小', whyWrong: '开口大小由系数绝对值决定，与正负无关' },
      { id: 'r1_m2', wrong: 'c=0 时图像不过原点', correct: 'c=0 时图像过原点 (0,0)', whyWrong: '常数项即 y 轴截距，c=0 即过原点' }
    ];
    const r1Ref: NodeLink[] = [{ title: '人教版 九年级数学下册 第二十六章', url: 'https://basic.smartedu.cn' }];
    r1.keyPoints = r1Kp;
    r1.formulas = r1F;
    r1.examples = r1E;
    r1.misconceptions = r1M;
    r1.references = r1Ref;
    r1.english = { word: 'quadratic function', phonetic: '/kwɒˈdrætɪk ˈfʌŋkʃən/', examples: [{ english: 'A quadratic function graphs as a parabola.', chinese: '二次函数的图像是一条抛物线。' }] };
    m.set('r1', r1);

    const c1 = emptyNodeRichContent();
    c1.keyPoints = [
      { id: 'c1_k1', text: '一般式 y=ax²+bx+c（a≠0）', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'c1_k2', text: '顶点式 y=a(x-h)²+k，顶点为 (h,k)', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'c1_k3', text: '交点式 y=a(x-x₁)(x-x₂)，x₁x₂ 为与 x 轴交点横坐标', level: 'extended', memorized: false, addedBy: 'ai' }
    ];
    c1.formulas = [
      { id: 'c1_f1', latexText: 'y=a(x-h)^2+k', plainText: 'y=a(x-h)^2+k', variables: [{ name: 'h', meaning: '顶点横坐标' }, { name: 'k', meaning: '顶点纵坐标（即最值）' }], meaning: '顶点式' },
      { id: 'c1_f2', latexText: 'y=a(x-x_1)(x-x_2)', plainText: 'y=a(x-x1)(x-x2)', variables: [{ name: 'x1', meaning: '一个零点横坐标' }, { name: 'x2', meaning: '另一个零点横坐标' }], meaning: '交点式' }
    ];
    m.set('c1', c1);

    const c2 = emptyNodeRichContent();
    c2.keyPoints = [
      { id: 'c2_k1', text: 'a>0 开口向上，a<0 开口向下', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'c2_k2', text: '对称轴 x=-b/2a，顶点是最值点', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'c2_k3', text: '增减性以对称轴为界：a>0 时左减右增', level: 'exam', memorized: false, addedBy: 'ai' }
    ];
    c2.formulas = [{ id: 'c2_f1', latexText: '\\left(-\\frac{b}{2a},\\frac{4ac-b^2}{4a}\\right)', plainText: '(-b/2a,(4ac-b^2)/4a)', variables: [], meaning: '顶点坐标' }];
    m.set('c2', c2);

    const e1 = emptyNodeRichContent();
    e1.keyPoints = [{ id: 'e1_k1', text: '令 y=0 即 ax²+bx+c=0，其根即图像与 x 轴交点横坐标', level: 'core', memorized: false, addedBy: 'ai' }];
    e1.formulas = [
      { id: 'e1_f1', latexText: 'x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}', plainText: 'x=(-b±√(b²-4ac))/2a', variables: [{ name: 'a', meaning: '二次项系数' }, { name: 'b', meaning: '一次项系数' }, { name: 'c', meaning: '常数项' }], meaning: '一元二次方程求根公式' },
      { id: 'e1_f2', latexText: '\\Delta=b^2-4ac', plainText: 'Δ=b²-4ac', variables: [], meaning: '判别式' }
    ];
    e1.misconceptions = [{ id: 'e1_m1', wrong: 'Δ<0 时无根', correct: '初中阶段只讨论实数根，Δ<0 时无实数根', whyWrong: '初中不引入复数，需注意学段边界' }];
    m.set('e1', e1);

    const e2 = emptyNodeRichContent();
    e2.keyPoints = [
      { id: 'e2_k1', text: 'Δ>0：两个不等实根（与 x 轴两交点）', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'e2_k2', text: 'Δ=0：两个相等实根（顶点落在 x 轴上）', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'e2_k3', text: 'Δ<0：无实根（与 x 轴无交点）', level: 'core', memorized: false, addedBy: 'ai' }
    ];
    e2.formulas = [{ id: 'e2_f1', latexText: '\\Delta=b^2-4ac', plainText: 'Δ=b²-4ac', variables: [], meaning: '判别式' }];
    m.set('e2', e2);

    const c4 = emptyNodeRichContent();
    c4.keyPoints = [
      { id: 'c4_k1', text: '实际问题中常求最值：利润=单件利润×销量', level: 'exam', memorized: false, addedBy: 'ai' },
      { id: 'c4_k2', text: '抛物线运动轨迹用二次函数建模', level: 'extended', memorized: false, addedBy: 'ai' }
    ];
    c4.examples = [{ id: 'c4_e1', question: '用长 20m 的篱笆靠墙围矩形菜地，怎样使面积最大？', answer: '设宽为 x，面积 S=x(20-2x)=-2x²+20x，顶点处 x=5 时 S 最大=50m²。', difficulty: 4, source: '中考真题' }];
    m.set('c4', c4);

    const c5 = emptyNodeRichContent();
    c5.keyPoints = [{ id: 'c5_k1', text: 'quadratic function 二次函数；parabola 抛物线', level: 'extended', memorized: false, addedBy: 'ai' }];
    c5.english = { word: 'quadratic function', phonetic: '/kwɒˈdrætɪk ˈfʌŋkʃən/', examples: [
      { english: 'The graph of a quadratic function is a parabola.', chinese: '二次函数的图像是抛物线。' },
      { english: 'When a>0, the parabola opens upward.', chinese: '当 a>0 时，抛物线开口向上。' }
    ] };
    m.set('c5', c5);

    return m;
  }

  // ---------- 光的折射：学科化富内容 Mock ----------
  private refractionRichMap(): Map<string, NodeRichContent> {
    const m = new Map<string, NodeRichContent>();

    const r1 = emptyNodeRichContent();
    r1.keyPoints = [
      { id: 'r1_k1', text: '光从一种介质斜射入另一种介质时传播方向发生偏折，这种现象叫光的折射', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'r1_k2', text: '折射光线、入射光线、法线在同一平面内；折射光线与入射光线分居法线两侧', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'r1_k3', text: '光从空气斜射入水/玻璃时折射角小于入射角；垂直入射不偏折', level: 'exam', memorized: false, addedBy: 'ai' }
    ];
    r1.formulas = [{ id: 'r1_f1', latexText: 'n_1\\sin\\theta_1=n_2\\sin\\theta_2', plainText: 'n1*sin(θ1)=n2*sin(θ2)', variables: [{ name: 'n1', meaning: '入射介质折射率' }, { name: 'n2', meaning: '折射介质折射率' }, { name: 'θ1', meaning: '入射角' }, { name: 'θ2', meaning: '折射角' }], meaning: '折射定律（斯涅尔定律）' }];
    r1.examples = [{ id: 'r1_e1', question: '把筷子斜插入水中，从水面上方看筷子为什么“弯折”？', answer: '光从水斜射入空气发生折射，折射角大于入射角，人眼逆着折射光线看去觉得筷子上翘。', difficulty: 2, source: '生活现象' }];
    r1.misconceptions = [{ id: 'r1_m1', wrong: '折射角总大于入射角', correct: '取决于光密/光疏介质：从光疏到光密折射角更小', whyWrong: '未区分介质折射率大小，方向判断需看相对折射率' }];
    r1.references = [{ title: '人教版 八年级物理上册 第四章', url: 'https://basic.smartedu.cn' }];
    r1.english = { word: 'refraction', phonetic: '/rɪˈfrækʃən/', examples: [{ english: 'Refraction makes a straw look bent in water.', chinese: '折射使水中的吸管看上去弯折了。' }] };
    m.set('r1', r1);

    const c1 = emptyNodeRichContent();
    c1.keyPoints = [
      { id: 'c1_k1', text: '折射光线、入射光线、法线三线共面', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'c1_k2', text: '空气中角（入射/折射）更大：空气↔水/玻璃时，空气中的角占优', level: 'exam', memorized: false, addedBy: 'ai' }
    ];
    c1.formulas = [{ id: 'c1_f1', latexText: 'n_1\\sin\\theta_1=n_2\\sin\\theta_2', plainText: 'n1*sinθ1=n2*sinθ2', variables: [{ name: 'n1', meaning: '入射介质折射率' }, { name: 'θ1', meaning: '入射角' }, { name: 'n2', meaning: '折射介质折射率' }, { name: 'θ2', meaning: '折射角' }], meaning: '折射定律' }];
    m.set('c1', c1);

    const c2 = emptyNodeRichContent();
    c2.keyPoints = [
      { id: 'c2_k1', text: '折射率 n=c/v，是介质固有属性，真空 n=1', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'c2_k2', text: '水 n≈1.33，玻璃 n≈1.5，空气 n≈1（记相对大小即可）', level: 'exam', memorized: false, addedBy: 'ai' }
    ];
    c2.formulas = [{ id: 'c2_f1', latexText: 'n=\\frac{c}{v}', plainText: 'n=c/v', variables: [{ name: 'c', meaning: '真空中光速' }, { name: 'v', meaning: '介质中光速' }], meaning: '折射率定义' }];
    m.set('c2', c2);

    const c3 = emptyNodeRichContent();
    c3.keyPoints = [
      { id: 'c3_k1', text: '全反射条件：光从光密介质射向光疏介质，且入射角大于临界角', level: 'core', memorized: false, addedBy: 'ai' },
      { id: 'c3_k2', text: '临界角 sinC=1/n（从介质射向空气时）', level: 'exam', memorized: false, addedBy: 'ai' }
    ];
    c3.formulas = [{ id: 'c3_f1', latexText: '\\sin C=\\frac{1}{n}', plainText: 'sinC=1/n', variables: [{ name: 'C', meaning: '临界角' }, { name: 'n', meaning: '介质折射率' }], meaning: '临界角公式' }];
    m.set('c3', c3);

    const c5 = emptyNodeRichContent();
    c5.keyPoints = [{ id: 'c5_k1', text: 'refraction 折射；refractive index 折射率', level: 'extended', memorized: false, addedBy: 'ai' }];
    c5.english = { word: 'refraction', phonetic: '/rɪˈfrækʃən/', examples: [
      { english: 'Light refraction bends the ray at the interface.', chinese: '光的折射使光线在界面处偏折。' },
      { english: 'Total internal reflection guides light in optical fiber.', chinese: '全反射在光纤中引导光传播。' }
    ] };
    m.set('c5', c5);

    return m;
  }

  private pickOps(instruction: string): MapPatchOp[] {
    const ins = instruction ? instruction : '';
    const ops: MapPatchOp[] = [];
    if (ins.includes('样式') || ins.includes('颜色') || ins.includes('圆角') || ins.includes('形状')) {
      ops.push({ op: 'restyle', nodeId: 'r1', style: { shape: 'round' }, reason: '按指令统一节点形状' });
      ops.push({ op: 'restyle', nodeId: 'c1', style: { color: '#00b96b' }, reason: '按指令调整颜色' });
      return ops;
    }
    if (ins.includes('布局') || ins.includes('放射') || ins.includes('树状')) {
      const layout = ins.includes('放射') ? 'radial' : (ins.includes('上下') ? 'tree-v' : 'tree-h');
      ops.push({ op: 'layout', layout: layout, reason: '按指令切换布局' });
      return ops;
    }
    if (ins.includes('补') || ins.includes('展') || ins.includes('增加') || ins.includes('新增') || ins.includes('分支')) {
      ops.push({ op: 'add', parentId: 'r1', text: '补充要点（记忆口诀）', type: 'general', reason: '按指令补充分支' });
      ops.push({ op: 'updateDetail', nodeId: 'c2', detail: '记忆口诀：a 定开口 h 定横 k 定纵', reason: '补充要点详情' });
      return ops;
    }
    // 默认：派生一个 add + 说明
    ops.push({ op: 'add', parentId: 'r1', text: '扩展分支', type: 'general', reason: 'Mock 默认添加分支' });
    return ops;
  }

  async tutorNode(req: TutorRequest, onStream: StreamHandler<TutorChunk>): Promise<AIResult<TutorResponse>> {
    const text = this.buildTutorText(req);
    return this.simulateStream(text, onStream, (full: string): AIResult<TutorResponse> => {
      return aiSuccess<TutorResponse>({ text: full });
    });
  }

  private buildTutorText(req: TutorRequest): string {
    const t = req.nodeText ? req.nodeText : '该知识点';
    const d = req.nodeDetail ? req.nodeDetail : '';
    if (req.mode === 'explain') {
      return `【讲细一点 · ${t}】\n${d.length > 0 ? d + '\n' : ''}要点拆解：①先理解核心定义；②结合实例记忆；③注意易混概念的区别。\n小技巧：用自己的话复述一遍，能讲清楚才算真正掌握。`;
    } else if (req.mode === 'similar') {
      return `【出两道相似题 · ${t}】\n1. 下列关于「${t}」的说法，正确的是？（请辨析概念边界）\n2. 若情境变为……，请说明「${t}」会如何变化？\n（提示：先回忆定义，再套用条件推导）`;
    }
    return `【换个说法 · ${t}】\n换个通俗讲法：${d.length > 0 ? d : '把抽象概念想象成生活里的具体事物'}，这样就更好记了。`;
  }

  private simulateStream(text: string, onStream: StreamHandler<TutorChunk>, done: (full: string) => AIResult<TutorResponse>): Promise<AIResult<TutorResponse>> {
    const segLen = 30;
    const total = Math.max(1, text.length);
    let pos = 0;
    while (pos < total) {
      const end = Math.min(pos + segLen, total);
      onStream({ text: text.substring(pos, end), done: false });
      pos = end;
    }
    onStream({ text: '', done: true });
    return new Promise<AIResult<TutorResponse>>((resolve) => {
      resolve(done(text));
    });
  }

  private buildExamples(word: string): ExampleItem[] {
    const w = word ? word : 'study';
    const items: ExampleItem[] = [];
    const ids = [1, 2, 3, 4];
    const dict: string[] = [
      'We should {w} hard every day to improve ourselves.',
      'Doing experiments is a good way to {w} science.',
      'Our teacher often encourages us to {w} in groups.',
      'The more you {w}, the more you will gain.'
    ];
    for (let i = 0; i < ids.length; i++) {
      const level = i < 2 ? '中考' : '高考';
      const raw = dict[i % dict.length];
      const english = raw.replace('{w}', w);
      items.push({
        id: `ex_${i}`,
        english: english,
        chinese: `中文翻译：${english.length > 20 ? english.substring(0, 20) : english}`,
        level: level,
        analysis: `重点解析：${w} 在此句中意为「${w}」，注意搭配与语境。`
      });
    }
    return items;
  }
}

/** 学科标签转换（供 mock 使用） */
export function subjectLabel(code: string): string {
  for (let i = 0; i < SUBJECTS.length; i++) {
    if (SUBJECTS[i].code === code) {
      return SUBJECTS[i].label;
    }
  }
  return code;
}