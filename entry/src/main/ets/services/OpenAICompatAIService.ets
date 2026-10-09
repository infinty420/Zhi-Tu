/**
 * OpenAICompatAIService —— 基于 @kit.NetworkKit http 的 OpenAI chat/completions 兼容实现。
 * 配置化 endpoint，密钥经配置文件注入；超时/网络/鉴权/上游错误映射为 AIError（retryable 语义正确）。
 * 采用完整响应 + 本地增量拆分模拟流式（保证前端流式打字 UI 一致）。
 */
import { http } from '@kit.NetworkKit';
import { AIConfig } from './AIConfig';
import { AIError, AIErrorCode, AIResult, AIResultFailure, AgentChatRequest, AgentChatResponse, AgentStreamChunk, AIService, ExampleItem, ExamplesRequest, ExamplesResponse, MapPatchOp, MindMapGenRequest, MindMapGenResponse, MindMapStreamChunk, PatchOpType, PatchStyleTarget, QuizGradeRequest, QuizGradeResponse, QuizQuestion, QuizKind, QuizRequest, QuizResponse, RichContentGenRequest, RichContentGenResponse, SimilarQuizRequest, StreamHandler, TutorChunk, TutorMode, TutorRequest, TutorResponse, aiFailure, aiSuccess } from './AIService';
import { AIResponseValidator } from './AIResponseValidator';
import { MindMap } from '../model/MindMap';
import { NodeRichContent } from '../model/MindNode';
import { Logger } from '../utils/Logger';

const TAG = 'OpenAICompat';

/** OpenAI chat/completions 请求消息 */
interface ChatMessage {
  role: string;
  content: string;
}

/** OpenAI chat/completions 请求体 */
interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  stream: boolean;
}

/** OpenAI 响应消息体 */
interface ChatResponseMessage {
  content?: string;
}

/** OpenAI 响应 choice */
interface ChatResponseChoice {
  message?: ChatResponseMessage;
  text?: string;
}

/** OpenAI chat/completions 响应体 */
interface ChatResponseBody {
  choices?: ChatResponseChoice[];
}

/** AI 返回的 patch 指令原始 JSON 结构 */
interface RawPatchOpJson {
  op?: string;
  nodeId?: string;
  parentId?: string;
  text?: string;
  type?: string;
  index?: number;
  layout?: string;
  style?: PatchStyleTarget;
  detail?: string;
  reason?: string;
  richContent?: ESObject;
  richMode?: string;
}

/** AI 返回的例句原始 JSON 结构 */
interface RawExampleJson {
  english?: string;
  chinese?: string;
  level?: string;
  analysis?: string;
}

/** AI 返回的测验题原始 JSON 结构 */
interface RawQuizJson {
  id?: string;
  kind?: string;
  nodeId?: string;
  prompt?: string;
  answer?: string;
  options?: string[];
}

/** AI 返回的判分结果原始 JSON 结构 */
interface RawGradeJson {
  correct?: boolean | string;
  score?: number | string;
  explanation?: string;
}

const SYSTEM_MINDMAP_PROMPT =
  '你是中学学科思维导图生成助手。根据用户输入的知识点生成结构化思维导图。' +
  '只返回 JSON，不要任何解释，格式为：' +
  '{"title":"...","layout":"tree-h|tree-v|radial","theme":"ocean|forest|sunset","nodes":[' +
  '{"id":"n1","text":"...","parentId":null|"nX","type":"general|math|physics|english","detail":"...",' +
  '"style":{"color":"#rrggbb","shape":"rect|round|ellipse"},"collapsed":false,' +
  '"richContent":{"keyPoints":[{"id":"kp1","text":"...","level":"core|extended|exam","memorized":false,"addedBy":"ai"}],' +
  '"formulas":[{"id":"f1","latexText":"...","plainText":"...","variables":[{"name":"","meaning":""}],"meaning":""}],' +
  '"examples":[{"id":"ex1","question":"...","answer":"...","difficulty":3,"source":""}],' +
  '"misconceptions":[{"id":"mc1","wrong":"...","correct":"...","whyWrong":""}],' +
  '"references":[{"title":"...","url":"..."}],' +
  '"chinese":{"poem":"","author":"","dynasty":"","punctuation":[],"rhetoric":[],"notes":[]},' +
  '"history":{"events":[{"year":"","title":"","desc":""}]},' +
  '"geography":{"region":"","coords":[{"name":"","x":0,"y":0,"note":""}]},' +
  '"chemistry":{"equation":"","balanced":false,"reactants":[],"products":[],"phenomenon":""},' +
  '"biology":{"hierarchy":[{"level":"","name":"","desc":""}]},' +
  '"politics":{"viewpointFor":"","viewpointAgainst":"","currentAffairs":[]},' +
  '"english":{"word":"","phonetic":"","examples":[{"english":"","chinese":""}]}}}]}。' +
  'richContent 为重点/常考节点补充学科化内容：math/physics 节点务必给 formulas 与 keyPoints，' +
  'english 节点给 english(word/phonetic/examples)，易混点给 misconceptions，相关史料给 history，' +
  '凡无对应学科内容时该槽位给空结构即可。根节点 parentId 必须为 null，禁止循环引用。';

const SYSTEM_RICH_PROMPT =
  '你是中学学科内容助手。针对单个知识点节点，生成学科化富内容 JSON。' +
  '只返回 JSON 对象，不要解释，格式：' +
  '{"keyPoints":[{"id":"kp1","text":"...","level":"core|extended|exam","memorized":false,"addedBy":"ai"}],' +
  '"formulas":[{"id":"f1","latexText":"...","plainText":"...","variables":[{"name":"","meaning":""}],"meaning":""}],' +
  '"examples":[{"id":"ex1","question":"...","answer":"...","difficulty":3,"source":""}],' +
  '"misconceptions":[{"id":"mc1","wrong":"...","correct":"...","whyWrong":""}],' +
  '"references":[{"title":"...","url":"..."}],' +
  '"chinese":{"poem":"","author":"","dynasty":"","punctuation":[],"rhetoric":[],"notes":[]},' +
  '"history":{"events":[{"year":"","title":"","desc":""}]},' +
  '"geography":{"region":"","coords":[{"name":"","x":0,"y":0,"note":""}]},' +
  '"chemistry":{"equation":"","balanced":false,"reactants":[],"products":[],"phenomenon":""},' +
  '"biology":{"hierarchy":[{"level":"","name":"","desc":""}]},' +
  '"politics":{"viewpointFor":"","viewpointAgainst":"","currentAffairs":[]},' +
  '"english":{"word":"","phonetic":"","examples":[{"english":"","chinese":""}]}}。' +
  'math/physics 节点给 formulas 与 keyPoints；english 节点给 english(word/phonetic/examples)；' +
  '易混点给 misconceptions；相关史料给 history；无对应学科内容时该槽位给空结构。';

const SYSTEM_PATCH_PROMPT =
  '你是思维导图协同编辑助手。根据用户的自然语言指令，对传入的导图生成增量修改指令。' +
  '只返回 JSON 数组，不要解释。每个元素格式：' +
  '{"op":"add|remove|rename|move|restyle|layout|updateDetail","nodeId":"...","parentId":"...",' +
  '"text":"...","type":"general|math|physics|english","layout":"tree-h|tree-v|radial",' +
  '"style":{"color":"#rrggbb","shape":"rect|round|ellipse"},"detail":"...","reason":"说明"}。' +
  '仅引用已存在节点；不得生成会破坏树结构或形成环的指令；layout 指令返回单个 op。';

const SYSTEM_EXAMPLE_PROMPT =
  '你是中学英语例句助手。根据单词生成 3-5 条难度分级（中考/高考）例句。' +
  '只返回 JSON 数组，不要解释。每个元素：' +
  '{"english":"英文原句","chinese":"中文翻译","level":"中考|高考","analysis":"划词解析"}。';

const SYSTEM_QUIZ_PROMPT =
  '你是中学学习测验生成助手。根据思维导图生成自测题。' +
  '只返回 JSON 数组，不要解释。每个元素：' +
  '{"id":"q1","kind":"cloze|qa|recall_children|recall_parent","nodeId":"节点id",' +
  '"prompt":"题干","answer":"标准答案要点，多个要点用中文顿号分隔","options":["A","B"]}。' +
  'recall_children=看父背子（列出子节点要点），recall_parent=看子想父（写出所属上级），qa=简述该节点。';

const SYSTEM_SIMILAR_PROMPT =
  '你是中学学习测验生成助手。针对给定知识点节点，出 1-2 道「相似题/变式题」：与题干考点一致但情境或问法不同，用于巩固该知识点。' +
  '只返回 JSON 数组，不要解释。每个元素：' +
  '{"id":"q1","kind":"qa","nodeId":"节点id","prompt":"题干","answer":"标准答案要点，多个要点用中文顿号分隔","options":["A","B"]}。';

const SYSTEM_GRADE_PROMPT =
  '你是中学学习判分助手。给定题目标准答案与用户作答，判断是否正确并给出解析。' +
  '只返回 JSON 对象，不要解释：' +
  '{"correct":true/false,"score":0~100,"explanation":"解析或参考答案"}。';

const SYSTEM_TUTOR_PROMPT =
  '你是中学学科辅导老师。针对单个导图节点，按指定模式给出讲解：' +
  'explain=讲细一点（拆解要点、举例子、给记忆技巧）；similar=出两道相似题并给提示；rephrase=换个通俗说法帮助理解。' +
  '直接返回讲解文本，不要 JSON、不要多余解释。';

export class OpenAICompatAIService implements AIService {
  private config: AIConfig;

  constructor(config: AIConfig) {
    this.config = config;
  }

  generateMindMap(req: MindMapGenRequest, onStream: StreamHandler<MindMapStreamChunk>): Promise<AIResult<MindMapGenResponse>> {
    Logger.aiRequest(TAG, 'request', `generateMindMap query=${req.query}`);
    const userContent = `知识点：${req.query}` + (req.subject ? `\n学科：${req.subject}` : '') + (req.book ? `\n参考教材：${req.book}` : '');
    return this.postChat(SYSTEM_MINDMAP_PROMPT, userContent).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        Logger.aiRequest(TAG, 'failed', failure.error.message);
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const rawText = aiRes.data;
      this.emitStreamText(rawText, (seg, done) => onStream({ text: seg, done }));
      const validated = AIResponseValidator.validateMindMapJson(rawText);
      if (!validated.ok) {
        const failure: AIResultFailure = validated as AIResultFailure;
        Logger.aiRequest(TAG, 'invalid-output', failure.error.message);
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      Logger.aiRequest(TAG, 'success', `nodes=${validated.data.nodes.length}`);
      const resp: MindMapGenResponse = { rawJson: validated.data.toJson(), map: validated.data };
      return aiSuccess(resp);
    });
  }

  chatPatch(req: AgentChatRequest, onStream: StreamHandler<AgentStreamChunk>): Promise<AIResult<AgentChatResponse>> {
    Logger.aiRequest(TAG, 'request', 'chatPatch');
    const userContent =
      `当前导图 JSON：\n${req.mapJson}\n\n对话历史：\n${req.history.length > 0 ? req.history.map((m) => `${m.role}: ${m.content}`).join('\n') : '（无）'}\n\n用户新指令：${req.instruction}`;
    return this.postChat(SYSTEM_PATCH_PROMPT, userContent).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        Logger.aiRequest(TAG, 'failed', failure.error.message);
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const rawText = aiRes.data;
      this.emitStreamText(rawText, (seg: string, done: boolean) => {
        const chunk: AgentStreamChunk = { delta: seg, done: done };
        onStream(chunk);
      });
      const opsResult = this.parseOps(rawText);
      if (!opsResult.ok) {
        const failure: AIResultFailure = opsResult as AIResultFailure;
        Logger.aiRequest(TAG, 'invalid-output', failure.error.message);
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      Logger.aiRequest(TAG, 'success', `ops=${opsResult.data.length}`);
      const resp: AgentChatResponse = { reply: '已根据指令生成修改方案。', ops: opsResult.data };
      return aiSuccess(resp);
    });
  }

  generateExamples(req: ExamplesRequest): Promise<AIResult<ExamplesResponse>> {
    Logger.aiRequest(TAG, 'request', `generateExamples word=${req.word}`);
    return this.postChat(SYSTEM_EXAMPLE_PROMPT, `单词/短语：${req.word}`).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        Logger.aiRequest(TAG, 'failed', failure.error.message);
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const items = this.parseExamples(aiRes.data);
      if (items.length === 0) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, '例句生成内容无法解析', true);
      }
      const resp: ExamplesResponse = { word: req.word, examples: items };
      return aiSuccess(resp);
    });
  }

  generateQuiz(req: QuizRequest): Promise<AIResult<QuizResponse>> {
    Logger.aiRequest(TAG, 'request', 'generateQuiz');
    return this.postChat(SYSTEM_QUIZ_PROMPT, `导图 JSON：\n${req.mapJson}`).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const questions = this.parseQuizzes(aiRes.data);
      if (questions.length === 0) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, '测验生成内容无法解析', true);
      }
      const quizResp: QuizResponse = { questions: questions };
      return aiSuccess(quizResp);
    });
  }

  generateSimilarQuiz(req: SimilarQuizRequest): Promise<AIResult<QuizResponse>> {
    Logger.aiRequest(TAG, 'request', 'generateSimilarQuiz');
    const subject = req.subject ? req.subject : '';
    const user = `节点：${req.nodeText}\n要点：${req.nodeDetail ? req.nodeDetail : ''}\n学科：${subject}`;
    return this.postChat(SYSTEM_SIMILAR_PROMPT, user).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const questions = this.parseQuizzes(aiRes.data);
      if (questions.length === 0) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, '相似题生成内容无法解析', true);
      }
      const quizResp: QuizResponse = { questions: questions };
      return aiSuccess(quizResp);
    });
  }

  gradeAnswer(req: QuizGradeRequest): Promise<AIResult<QuizGradeResponse>> {
    Logger.aiRequest(TAG, 'request', 'gradeAnswer');
    const user = `题目：${req.question.prompt}\n标准答案：${req.question.answer}\n用户作答：${req.userAnswer}`;
    return this.postChat(SYSTEM_GRADE_PROMPT, user).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const graded = this.parseGrade(aiRes.data);
      if (!graded) {
        return aiFailure(AIErrorCode.INVALID_OUTPUT, '判分结果无法解析', true);
      }
      return aiSuccess(graded);
    });
  }

  tutorNode(req: TutorRequest, onStream: StreamHandler<TutorChunk>): Promise<AIResult<TutorResponse>> {
    Logger.aiRequest(TAG, 'request', `tutorNode mode=${req.mode}`);
    const modeHint = req.mode === 'explain' ? '讲细一点' : (req.mode === 'similar' ? '出两道相似题' : '换个说法');
    const user = `节点：${req.nodeText}\n要点：${req.nodeDetail}\n学科类型：${req.nodeType}\n模式：${modeHint}`;
    return this.postChat(SYSTEM_TUTOR_PROMPT, user).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const rawText = aiRes.data;
      this.emitStreamText(rawText, (seg: string, done: boolean) => {
        const chunk: TutorChunk = { text: seg, done: done };
        onStream(chunk);
      });
      const resp: TutorResponse = { text: rawText };
      return aiSuccess(resp);
    });
  }

  generateRichContentForNode(req: RichContentGenRequest): Promise<AIResult<RichContentGenResponse>> {
    Logger.aiRequest(TAG, 'request', `generateRichContentForNode node=${req.nodeText}`);
    const subject = req.subject ? req.subject : '';
    const user =
      `节点：${req.nodeText}\n要点：${req.nodeDetail}\n学科类型：${req.nodeType}` +
      (subject.length > 0 ? `\n所属学科：${subject}` : '');
    return this.postChat(SYSTEM_RICH_PROMPT, user).then((aiRes: AIResult<string>) => {
      if (!aiRes.ok) {
        const failure: AIResultFailure = aiRes as AIResultFailure;
        Logger.aiRequest(TAG, 'failed', failure.error.message);
        return aiFailure(failure.error.code, failure.error.message, failure.error.retryable);
      }
      const jsonText = AIResponseValidator.extractJson(aiRes.data);
      const parsed: ESObject = JSON.parse(jsonText);
      const rich: NodeRichContent = MindMap.parseNodeRichContent(parsed);
      const resp: RichContentGenResponse = { nodeText: req.nodeText, rich: rich };
      return aiSuccess(resp);
    });
  }

  // ---------- 底层 HTTP 与解析 ----------
  private postChat(system: string, user: string): Promise<AIResult<string>> {
    return new Promise<AIResult<string>>((resolve) => {
      const httpRequest = http.createHttp();
      const header: Record<string, string> = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.config.apiKey}`
      };
      const messages: ChatMessage[] = [
        { role: 'system', content: system },
        { role: 'user', content: user }
      ];
      const body: ChatRequestBody = {
        model: this.config.model,
        messages: messages,
        temperature: 0.7,
        stream: false
      };
      httpRequest.request(this.config.endpoint, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      }).then((response: http.HttpResponse) => {
        httpRequest.destroy();
        const code = response.responseCode;
        if (code === 200) {
          let text = '';
          const result = response.result;
          if (typeof result === 'string') {
            text = result;
          } else {
            text = JSON.stringify(result);
          }
          const content = this.extractContent(text);
          if (!content || content.length === 0) {
            resolve(aiFailure(AIErrorCode.INVALID_OUTPUT, 'AI 返回内容为空', true));
            return;
          }
          resolve(aiSuccess(content));
          return;
        }
        if (code === 401 || code === 403) {
          resolve(aiFailure(AIErrorCode.AUTH, '鉴权失败，请检查 AI 密钥配置', false));
          return;
        }
        if (code >= 500) {
          resolve(aiFailure(AIErrorCode.UPSTREAM, `上游服务错误（${code}）`, true));
          return;
        }
        resolve(aiFailure(AIErrorCode.NETWORK, `请求失败（${code}）`, true));
      }).catch(() => {
        httpRequest.destroy();
        resolve(aiFailure(AIErrorCode.NETWORK, '网络请求失败，请检查网络连接', true));
      });
    });
  }

  /** 从 OpenAI 响应提取 content 文本 */
  private extractContent(responseText: string): string {
    try {
      const parsed = JSON.parse(responseText) as ChatResponseBody;
      const choices = parsed.choices;
      if (!choices || choices.length === 0) {
        return '';
      }
      const first = choices[0];
      if (first.message !== undefined && first.message !== null && first.message.content) {
        return first.message.content as string;
      }
      if (first.text) {
        return first.text as string;
      }
      return '';
    } catch (err) {
      return responseText;
    }
  }

  /** 本地增量拆分模拟流式（保证前端打字效果），回传分段文本与结束标志 */
  private emitStreamText(text: string, onChunk: (seg: string, done: boolean) => void): void {
    const segLen = 40;
    const total = Math.max(1, text.length);
    let pos = 0;
    while (pos < total) {
      const end = Math.min(pos + segLen, total);
      onChunk(text.substring(pos, end), false);
      pos = end;
    }
    onChunk('', true);
  }

  private parseOps(text: string): AIResult<MapPatchOp[]> {
    try {
      const jsonText = AIResponseValidator.extractJson(text);
      const arr = JSON.parse(jsonText) as RawPatchOpJson[];
      const ops: MapPatchOp[] = [];
      if (arr) {
        for (let i = 0; i < arr.length; i++) {
          const raw = arr[i];
          let styleObj: PatchStyleTarget | undefined = undefined;
          if (raw.style !== null && raw.style !== undefined) {
            styleObj = {
              color: this.optString(raw.style.color),
              shape: this.optString(raw.style.shape)
            };
          }
          const richMode: 'replace' | 'append' = raw.richMode === 'replace' ? 'replace' : 'append';
          const op: MapPatchOp = {
            op: (raw.op === undefined || raw.op === null ? 'rename' : raw.op) as PatchOpType,
            nodeId: this.optString(raw.nodeId),
            parentId: this.optString(raw.parentId),
            text: this.optString(raw.text),
            type: this.optString(raw.type),
            index: raw.index !== null && raw.index !== undefined ? Number(raw.index) : undefined,
            layout: this.optString(raw.layout),
            style: styleObj,
            detail: this.optString(raw.detail),
            reason: this.optString(raw.reason),
            richContent: raw.richContent ? MindMap.parseNodeRichContent(raw.richContent) : undefined,
            richMode: richMode
          };
          ops.push(op);
        }
      }
      return aiSuccess(ops);
    } catch (err) {
      return aiFailure(AIErrorCode.INVALID_OUTPUT, 'patch 解析失败', true);
    }
  }

  private parseExamples(text: string): ExampleItem[] {
    try {
      const jsonText = AIResponseValidator.extractJson(text);
      const arr = JSON.parse(jsonText) as RawExampleJson[];
      const items: ExampleItem[] = [];
      if (arr) {
        for (let i = 0; i < arr.length; i++) {
          const raw = arr[i];
          const item: ExampleItem = {
            id: `ai_ex_${i}`,
            english: this.optString(raw.english),
            chinese: this.optString(raw.chinese),
            level: this.optString(raw.level),
            analysis: this.optString(raw.analysis)
          };
          items.push(item);
        }
      }
      return items;
    } catch (err) {
      return [];
    }
  }

  /** 可选字符串字段安全取值：缺失/空返回 ''，非字符串转字符串 */
  private optString(value: string | number | boolean | null | undefined): string {
    if (value === null || value === undefined) {
      return '';
    }
    return String(value);
  }

  /** 解析 AI 返回的测验题数组（JSON 数组） */
  private parseQuizzes(text: string): QuizQuestion[] {
    try {
      const jsonText = AIResponseValidator.extractJson(text);
      const arr = JSON.parse(jsonText) as RawQuizJson[];
      const questions: QuizQuestion[] = [];
      if (arr) {
        for (let i = 0; i < arr.length; i++) {
          const raw = arr[i];
          const k = this.optString(raw.kind);
          let kindVal: QuizKind = 'cloze';
          if (k === 'qa') {
            kindVal = 'qa';
          } else if (k === 'recall_children') {
            kindVal = 'recall_children';
          } else if (k === 'recall_parent') {
            kindVal = 'recall_parent';
          }
          const q: QuizQuestion = {
            id: this.optString(raw.id),
            kind: kindVal,
            nodeId: this.optString(raw.nodeId),
            prompt: this.optString(raw.prompt),
            answer: this.optString(raw.answer),
            options: raw.options ? raw.options : undefined
          };
          questions.push(q);
        }
      }
      return questions;
    } catch (err) {
      return [];
    }
  }

  /** 解析 AI 返回的判分结果（JSON 对象） */
  private parseGrade(text: string): QuizGradeResponse | undefined {
    try {
      const jsonText = AIResponseValidator.extractJson(text);
      const obj = JSON.parse(jsonText) as RawGradeJson;
      if (!obj) {
        return undefined;
      }
      let correct = false;
      if (typeof obj.correct === 'boolean') {
        correct = obj.correct;
      } else {
        const s = String(obj.correct).toLowerCase();
        correct = s === 'true' || s === '1' || s === '是';
      }
      let score = typeof obj.score === 'number' ? obj.score : Number(obj.score);
      if (!Number.isFinite(score)) {
        score = correct ? 100 : 0;
      }
      const explanation = this.optString(obj.explanation);
      const resp: QuizGradeResponse = { correct: correct, score: score, explanation: explanation };
      return resp;
    } catch (err) {
      return undefined;
    }
  }
}