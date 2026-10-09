/**
 * AIService 统一抽象接口（AI 接入族唯一出口）。
 * 所有方法返回强类型联合 AIResult<T>，杜绝 any。
 */
import { MindMap } from '../model/MindMap';
import { NodeRichContent } from '../model/MindNode';

/** AI 错误码 */
export enum AIErrorCode {
  TIMEOUT,
  NETWORK,
  AUTH,
  INVALID_OUTPUT,
  UPSTREAM
}

export interface AIError {
  code: AIErrorCode;
  message: string;
  retryable: boolean;
}

/** 通用结果联合类型（services 层） */
export type AIResult<T> = AIResultSuccess<T> | AIResultFailure;

export interface AIResultSuccess<T> {
  ok: true;
  data: T;
}

export interface AIResultFailure {
  ok: false;
  error: AIError;
}

/** 流式处理回调 */
export type StreamHandler<T> = (chunk: T) => void;

/** 导图生成请求 */
export interface MindMapGenRequest {
  query: string;
  subject: string;
  book: string;
}

/** 导图生成流式块 */
export interface MindMapStreamChunk {
  text: string;
  done: boolean;
}

/** 导图生成响应（已校验的导图实体 + 原始 JSON） */
export interface MindMapGenResponse {
  rawJson: string;
  map: MindMap;
}

/** 对话历史消息 */
export interface AgentMessage {
  role: string; // 'user' | 'assistant'
  content: string;
}

/** Agent 对话请求：携带当前导图 JSON + 对话历史 + 新指令 */
export interface AgentChatRequest {
  mapJson: string;
  history: AgentMessage[];
  instruction: string;
}

/** Agent 流式块 */
export interface AgentStreamChunk {
  delta: string;
  done: boolean;
}

/** Patch 操作类型（AI 契约 spec 6.4） */
export type PatchOpType = 'add' | 'remove' | 'rename' | 'move' | 'restyle' | 'layout' | 'updateDetail' | 'patchRichContent';

export interface PatchStyleTarget {
  color?: string;
  shape?: string;
}

/** 单条增量修改指令 */
export interface MapPatchOp {
  op: PatchOpType;
  nodeId?: string;
  parentId?: string;
  text?: string;
  type?: string;
  index?: number;
  layout?: string;
  style?: PatchStyleTarget;
  detail?: string;
  reason?: string;
  /** 学科化富内容补丁（op='patchRichContent' 时必填），遵循追加语义 */
  richContent?: NodeRichContent;
  /** 富内容补丁模式：append=不覆盖、只追加（默认）；replace=整体替换 */
  richMode?: 'replace' | 'append';
}

/** Agent 对话响应 */
export interface AgentChatResponse {
  reply: string;
  ops: MapPatchOp[];
}

/** 例句生成请求 */
export interface ExamplesRequest {
  word: string;
}

/** 例句条目 */
export interface ExampleItem {
  id: string;
  english: string;
  chinese: string;
  level: string; // 中考 | 高考
  analysis: string;
}

/** 例句响应 */
export interface ExamplesResponse {
  word: string;
  examples: ExampleItem[];
}

/** 测验题目类型：挖空 / 问答 / 看父背子 / 看子想父 */
export type QuizKind = 'cloze' | 'qa' | 'recall_children' | 'recall_parent';

/** 单道自测题 */
export interface QuizQuestion {
  id: string;
  kind: QuizKind;
  nodeId: string;
  /** 题干 */
  prompt: string;
  /** 标准答案（recall 类为逗号分隔的要点） */
  answer: string;
  /** 选择题选项（cloze 可为空） */
  options?: string[];
  /** 提示（无密钥 Mock 模式也每题携带） */
  hint?: string;
}

/** 自测生成请求 */
export interface QuizRequest {
  /** 当前导图 JSON */
  mapJson: string;
  /** 指定节点（缺省=全图自动抽样） */
  nodeIds?: string[];
  /** 聚焦的单个节点（与 nodeIds 二选一优先） */
  nodeId?: string;
  /** 题目数量上限 */
  limit?: number;
  /** 难度（1~5，供实现侧抽样 / 提示用） */
  difficulty?: number;
}

/** 自测生成响应 */
export interface QuizResponse {
  questions: QuizQuestion[];
}

/** 相似题生成请求（基于某节点出相似/变式题，可经 QuizService 判分） */
export interface SimilarQuizRequest {
  /** 节点 id */
  nodeId: string;
  /** 节点标题 */
  nodeText: string;
  /** 节点要点/详情 */
  nodeDetail?: string;
  /** 节点学科类型（如 math/physics），用于考点模板匹配 */
  subject?: string;
  /** 难度 1~5 */
  difficulty?: number;
  /** 生成数量上限 */
  limit?: number;
}

/** 判分请求 */
export interface QuizGradeRequest {
  question: QuizQuestion;
  /** 用户作答文本 */
  userAnswer: string;
}

/** 判分响应 */
export interface QuizGradeResponse {
  correct: boolean;
  /** 0~100 */
  score: number;
  /** 解析 / 正确答案说明 */
  explanation: string;
}

/** AI 逐点辅导模式：讲细一点 / 出两道相似题 / 换个说法 */
export type TutorMode = 'explain' | 'similar' | 'rephrase';

/** 逐点辅导请求 */
export interface TutorRequest {
  /** 节点标题 */
  nodeText: string;
  /** 节点要点（detail） */
  nodeDetail: string;
  /** 节点学科类型 */
  nodeType: string;
  /** 辅导模式 */
  mode: TutorMode;
}

/** 逐点辅导流式块 */
export interface TutorChunk {
  text: string;
  done: boolean;
}

/** 逐点辅导响应（完整文本） */
export interface TutorResponse {
  text: string;
}

/** 学科化富内容生成请求：针对单个节点补充要点/公式/例题/易错点/学科专项槽位 */
export interface RichContentGenRequest {
  /** 节点标题 */
  nodeText: string;
  /** 节点要点（detail） */
  nodeDetail: string;
  /** 节点学科类型 */
  nodeType: string;
  /** 所属学科（如 math/physics/english），用于学科专项槽位产出 */
  subject?: string;
}

/** 学科化富内容生成响应 */
export interface RichContentGenResponse {
  nodeText: string;
  rich: NodeRichContent;
}

/** AIService 抽象接口 */
export interface AIService {
  generateMindMap(req: MindMapGenRequest, onStream: StreamHandler<MindMapStreamChunk>): Promise<AIResult<MindMapGenResponse>>;
  chatPatch(req: AgentChatRequest, onStream: StreamHandler<AgentStreamChunk>): Promise<AIResult<AgentChatResponse>>;
  generateExamples(req: ExamplesRequest): Promise<AIResult<ExamplesResponse>>;
  generateQuiz(req: QuizRequest): Promise<AIResult<QuizResponse>>;
  /** 出相似题：基于某节点生成可判分的相似/变式自测题（复用 QuizService 判分） */
  generateSimilarQuiz(req: SimilarQuizRequest): Promise<AIResult<QuizResponse>>;
  gradeAnswer(req: QuizGradeRequest): Promise<AIResult<QuizGradeResponse>>;
  tutorNode(req: TutorRequest, onStream: StreamHandler<TutorChunk>): Promise<AIResult<TutorResponse>>;
  /** 针对单个节点生成学科化富内容（要点/公式/例题/易错点/学科专项槽位） */
  generateRichContentForNode(req: RichContentGenRequest): Promise<AIResult<RichContentGenResponse>>;
}

/** 错误便捷构造函数 */
export function aiError(code: AIErrorCode, message: string, retryable: boolean): AIError {
  return { code: code, message: message, retryable: retryable };
}

export function aiFailure(code: AIErrorCode, message: string, retryable: boolean): AIResultFailure {
  return { ok: false, error: aiError(code, message, retryable) };
}

export function aiSuccess<T>(data: T): AIResultSuccess<T> {
  return { ok: true, data: data };
}