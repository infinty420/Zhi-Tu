/**
 * 常量与领域枚举定义。
 * 取值严格对应用户消息契约（spec 6.1-4、6.2-6/7）。
 */

/** 节点类型，决定深链目标 */
export enum NodeType {
  GENERAL = 'general',
  MATH = 'math',
  PHYSICS = 'physics',
  ENGLISH = 'english',
  HISTORY = 'history',
  GEO = 'geo',
  CHEM = 'chem',
  BIO = 'bio'
}

/** 节点类型 → 深链页面名（v1.2 学科引擎扩展） */
export const NODE_TYPE_PAGE: Map<NodeType, string> = new Map<NodeType, string>([
  [NodeType.MATH, 'MathPlotPage'],
  [NodeType.PHYSICS, 'PhysicsSimPage'],
  [NodeType.ENGLISH, 'EnglishExamplesPage'],
  [NodeType.HISTORY, 'HistoryTimelinePage'],
  [NodeType.GEO, 'GeoMapPage'],
  [NodeType.CHEM, 'ChemPage'],
  [NodeType.BIO, 'BioPage']
]);

/** 节点类型 → 学科引擎中文标签 */
export const NODE_TYPE_LABEL: Map<NodeType, string> = new Map<NodeType, string>([
  [NodeType.GENERAL, '普通'],
  [NodeType.MATH, '数学'],
  [NodeType.PHYSICS, '物理'],
  [NodeType.ENGLISH, '英语'],
  [NodeType.HISTORY, '历史'],
  [NodeType.GEO, '地理'],
  [NodeType.CHEM, '化学'],
  [NodeType.BIO, '生物']
]);

/** 布局方式 */
export enum Layout {
  TREE_H = 'tree-h',
  TREE_V = 'tree-v',
  RADIAL = 'radial'
}

/** 节点形状 */
export enum NodeShape {
  RECT = 'rect',
  ROUND = 'round',
  ELLIPSE = 'ellipse'
}

/** 掌握度等级（v1.1 学习闭环数据基座：会 / 模糊 / 不会） */
export enum MasteryLevel {
  UNSET = 'unset',
  KNOWN = 'known',
  FUZZY = 'fuzzy',
  UNKNOWN = 'unknown'
}

/** 预置主题标识（≥3 套） */
export const THEMES: string[] = ['ocean', 'forest', 'sunset'];

/** 主题 → 节点色板（供画笔使用） */
export const THEME_COLORS: Map<string, string[]> = new Map<string, string[]>([
  ['ocean', ['#1677ff', '#0bd1c0', '#2f54eb', '#13c2c2', '#597ef7', '#00b96b']],
  ['forest', ['#00b96b', '#52c41a', '#08979c', '#135200', '#389e0d', '#95de64']],
  ['sunset', ['#fa8c16', '#eb2f96', '#f5222d', '#faad14', '#d4380d', '#ff85c0']]
]);

/** 中学九科常量表（可扩展） */
export interface SubjectItem {
  code: string;
  label: string;
}

export const SUBJECTS: SubjectItem[] = [
  { code: 'chinese', label: '语文' },
  { code: 'math', label: '数学' },
  { code: 'english', label: '英语' },
  { code: 'physics', label: '物理' },
  { code: 'chemistry', label: '化学' },
  { code: 'biology', label: '生物' },
  { code: 'history', label: '历史' },
  { code: 'geography', label: '地理' },
  { code: 'politics', label: '政治' }
];

/** 文本长度约束（spec 6.1-2 text≤100，spec 6.2-2 title≤50） */
export const TEXT_MAX_LEN = 100;
export const TITLE_MAX_LEN = 50;

export const DEFAULT_NODE_COLOR = '#1677ff';
export const DEFAULT_LAYOUT = 'tree-h';
export const DEFAULT_THEME = 'ocean';

/** 模型校验统一结果（model 层轻量结果，避免依赖 services） */
export interface ValidationResult {
  ok: boolean;
  errors: string[];
  /** 非阻断告警（如富内容字段不完整），不影响加载 */
  warnings: string[];
}

/** 通用结果联合类型（model 层） */
export type ModelResult<T> = ModelSuccess<T> | ModelFailure;

export interface ModelSuccess<T> {
  ok: true;
  data: T;
}

export interface ModelFailure {
  ok: false;
  message: string;
}

export function okResult<T>(data: T): ModelResult<T> {
  return { ok: true, data: data } as ModelSuccess<T>;
}

export function failResult<T>(message: string): ModelResult<T> {
  return { ok: false, message: message } as ModelResult<T>;
}

/** 校验结果便捷构造 */
export function okValidation(): ValidationResult {
  return { ok: true, errors: [], warnings: [] };
}

export function failValidation(errors: string[]): ValidationResult {
  return { ok: false, errors: errors, warnings: [] };
}