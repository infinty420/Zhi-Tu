/**
 * 导图节点领域对象。
 * id 全局唯一不可变；text≤100；parentId 根节点为 null，禁止循环引用；
 * userEdited 为运行时标记（不持久化），支撑「保留用户编辑」语义。
 *
 * 富内容分两层（并列扩展，互不干扰）：
 *   - rich      : NodeRichMedia  —— 媒体附件（图片/公式字符串/链接/标签，v1.2）
 *   - richContent: NodeRichContent —— 学科化结构化富内容（Phase X 新增）
 */
import { MasteryLevel, NodeShape, NodeType, TEXT_MAX_LEN } from './Constants';
import { MindMap } from './MindMap';

/** 节点样式 */
export interface NodeStyle {
  color: string;
  shape: NodeShape;
}

/** 节点链接（富内容引用） */
export interface NodeLink {
  title: string;
  url: string;
}

export interface NodeImage {
  /** 本地沙箱路径或 base64 data URL；为空表示仅有文字说明 */
  path: string;
  caption: string;
}

/** v1.2 媒体富内容：图片 / 公式(字符串) / 超链接 / 标签（保留，与学科化富内容并列） */
export interface NodeRichMedia {
  images: NodeImage[];
  /** LaTeX 风格公式字符串（如 x^2+1），前端按公式展示 */
  formula: string;
  links: NodeLink[];
  /** 标签数组，如 ["易错", "中考高频"] */
  tags: string[];
}

// ===================== 学科化富内容（Phase X） =====================

/** 要点层级：核心 / 拓展 / 考点 */
export type KeyPointLevel = 'core' | 'extended' | 'exam';
/** 要点来源：AI 生成 / 用户手写 / 旧数据迁移 */
export type KeyPointSource = 'ai' | 'user' | 'migrate';

/** 核心要点（keyPoints 槽位） */
export interface KeyPointItem {
  id: string;
  text: string;
  level: KeyPointLevel;
  memorized: boolean;
  addedBy: KeyPointSource;
}

/** 公式变量说明（如 a、b、c 的含义） */
export interface FormulaVar {
  name: string;
  meaning: string;
}

/** 公式条目（formulas 槽位） */
export interface FormulaItem {
  id: string;
  /** LaTeX 风格表达式，用于公式渲染 */
  latexText: string;
  /** 纯文本等价式（兜底显示 / 可被 FuncParser 解析） */
  plainText: string;
  /** 变量说明 */
  variables: FormulaVar[];
  /** 公式含义说明 */
  meaning: string;
}

/** 例题条目（examples 槽位） */
export interface RichExampleItem {
  id: string;
  question: string;
  answer: string;
  /** 难度星级 1~5 */
  difficulty: number;
  /** 来源（教材/真题/自编） */
  source: string;
}

/** 易错点条目（misconceptions 槽位） */
export interface MisconceptionItem {
  id: string;
  /** 常见错误表述 */
  wrong: string;
  /** 正确表述 */
  correct: string;
  /** 为何会错 */
  whyWrong: string;
}

// ----- 7 个学科专项子结构 -----

/** 语文学科专项内容 */
export interface ChineseContent {
  /** 诗词正文 */
  poem: string;
  author: string;
  dynasty: string;
  /** 文言断句（按句拆分） */
  punctuation: string[];
  /** 修辞标签 */
  rhetoric: string[];
  /** 注释/赏析 */
  notes: string[];
}

/** 历史学科专项内容 */
export interface HistoryEventItem {
  year: string;
  title: string;
  desc: string;
}
export interface HistoryContent {
  events: HistoryEventItem[];
}

/** 地理学科专项内容 */
export interface GeoCoord {
  name: string;
  /** 归一化横 0~1 */
  x: number;
  /** 归一化纵 0~1 */
  y: number;
  note: string;
}
export interface GeographyContent {
  region: string;
  coords: GeoCoord[];
}

/** 化学学科专项内容 */
export interface ChemistryContent {
  /** 原始方程式（可含空格占位待配平） */
  equation: string;
  /** 是否已配平 */
  balanced: boolean;
  reactants: string[];
  products: string[];
  /** 实验现象描述 */
  phenomenon: string;
}

/** 生物学科专项内容 */
export interface BioHierarchyItem {
  /** 层级名（如 细胞/组织/器官） */
  level: string;
  name: string;
  desc: string;
}
export interface BiologyContent {
  hierarchy: BioHierarchyItem[];
}

/** 政治学科专项内容 */
export interface PoliticsContent {
  viewpointFor: string;
  viewpointAgainst: string;
  currentAffairs: string[];
}

/** 英语学科专项内容 */
export interface EnglishExampleItem {
  english: string;
  chinese: string;
}
export interface EnglishContent {
  word: string;
  phonetic: string;
  examples: EnglishExampleItem[];
}

/** 学科化富内容容器（节点详情页核心数据，Phase X 新增） */
export interface NodeRichContent {
  keyPoints: KeyPointItem[];
  formulas: FormulaItem[];
  examples: RichExampleItem[];
  misconceptions: MisconceptionItem[];
  references: NodeLink[];
  // 学科专项槽位
  chinese: ChineseContent;
  history: HistoryContent;
  geography: GeographyContent;
  chemistry: ChemistryContent;
  biology: BiologyContent;
  politics: PoliticsContent;
  english: EnglishContent;
}

// ----- 学科化富内容默认值工厂 -----

export function emptyChineseContent(): ChineseContent {
  return { poem: '', author: '', dynasty: '', punctuation: [], rhetoric: [], notes: [] };
}
export function emptyHistoryContent(): HistoryContent {
  return { events: [] };
}
export function emptyGeographyContent(): GeographyContent {
  return { region: '', coords: [] };
}
export function emptyChemistryContent(): ChemistryContent {
  return { equation: '', balanced: false, reactants: [], products: [], phenomenon: '' };
}
export function emptyBiologyContent(): BiologyContent {
  return { hierarchy: [] };
}
export function emptyPoliticsContent(): PoliticsContent {
  return { viewpointFor: '', viewpointAgainst: '', currentAffairs: [] };
}
export function emptyEnglishContent(): EnglishContent {
  return { word: '', phonetic: '', examples: [] };
}

export function emptyNodeRichContent(): NodeRichContent {
  return {
    keyPoints: [],
    formulas: [],
    examples: [],
    misconceptions: [],
    references: [],
    chinese: emptyChineseContent(),
    history: emptyHistoryContent(),
    geography: emptyGeographyContent(),
    chemistry: emptyChemistryContent(),
    biology: emptyBiologyContent(),
    politics: emptyPoliticsContent(),
    english: emptyEnglishContent()
  };
}

export class MindNode {
  id: string = '';
  text: string = '';
  parentId: string | null = null;
  type: NodeType = NodeType.GENERAL;
  detail: string = '';
  style: NodeStyle = { color: '#1677ff', shape: NodeShape.ROUND };
  collapsed: boolean = false;
  /** 运行时标记：是否被用户手动编辑，patch 应用时以追加/合并方式落笔 */
  userEdited: boolean = false;

  // ---------- v1.1 学习闭环字段 ----------
  /** 掌握度（会 / 模糊 / 不会），默认未标记 */
  mastery: MasteryLevel = MasteryLevel.UNSET;
  /** 下次复习时间戳（毫秒），0 表示无需复习 */
  nextReviewAt: number = 0;
  /** 已进入复习队列的次数（用于 1/2/4/7 天间隔阶梯） */
  reviewCount: number = 0;
  /** 答错累计次数 */
  wrongCount: number = 0;
  /** 最近一次复习时间戳（毫秒），0 表示从未复习（Phase X 新增） */
  lastReviewedAt: number = 0;

  // ---------- v1.2 媒体富内容（图片/公式字符串/链接/标签） ----------
  rich: NodeRichMedia = { images: [], formula: '', links: [], tags: [] };

  // ---------- Phase X 学科化富内容容器 ----------
  richContent: NodeRichContent = emptyNodeRichContent();

  constructor() {
  }

  static create(id: string, text: string, parentId: string | null, type: NodeType = NodeType.GENERAL): MindNode {
    const node = new MindNode();
    node.id = id;
    node.text = text;
    node.parentId = parentId;
    node.type = type;
    return node;
  }

  /** 获取当前节点在指定导图中的子节点列表（保持数组顺序） */
  childrenOf(map: MindMap): MindNode[] {
    if (!map || map.nodes.length === 0) {
      return [];
    }
    const children: MindNode[] = [];
    for (let i = 0; i < map.nodes.length; i++) {
      const n = map.nodes[i];
      if (n.parentId === this.id) {
        children.push(n);
      }
    }
    return children;
  }

  /** 判断当前节点是否为 otherId 节点的后代（用于环检测） */
  isDescendantOf(map: MindMap, otherId: string): boolean {
    if (!map || this.id === otherId) {
      return false;
    }
    let current: MindNode | undefined = map.findNode(this.id);
    let guard = 0;
    while (current && current.parentId && guard < map.nodes.length + 1) {
      if (current.parentId === otherId) {
        return true;
      }
      current = map.findNode(current.parentId);
      guard++;
    }
    return false;
  }

  /** 文本长度校验 */
  static isTextValid(text: string): boolean {
    return text.length > 0 && text.length <= TEXT_MAX_LEN;
  }
}
