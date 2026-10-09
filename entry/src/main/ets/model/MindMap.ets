/**
 * 导图文档领域对象。
 * 含唯一 id/title/subject/book/layout/theme/updatedAt，结构校验（唯一根、无环、parentId 引用存在）。
 */
import { DEFAULT_LAYOUT, DEFAULT_NODE_COLOR, DEFAULT_THEME, Layout, MasteryLevel, NodeShape, NodeType, TITLE_MAX_LEN, ValidationResult, failValidation, okValidation } from './Constants';
import { MindNode, NodeImage, NodeLink, NodeRichContent, NodeRichMedia, NodeStyle, KeyPointItem, FormulaItem, FormulaVar, RichExampleItem, MisconceptionItem, ChineseContent, HistoryContent, HistoryEventItem, GeographyContent, GeoCoord, ChemistryContent, BiologyContent, BioHierarchyItem, PoliticsContent, EnglishContent, EnglishExampleItem, emptyNodeRichContent, emptyChineseContent, emptyHistoryContent, emptyGeographyContent, emptyChemistryContent, emptyBiologyContent, emptyPoliticsContent, emptyEnglishContent } from './MindNode';

/** JSON 序列化用的节点结构 */
interface MindNodeJson {
  id: string;
  text: string;
  parentId: string | null;
  type: NodeType;
  detail: string;
  style: NodeStyle;
  collapsed: boolean;
  mastery: MasteryLevel;
  nextReviewAt: number;
  reviewCount: number;
  wrongCount: number;
  rich: NodeRichMedia;
  richContent: NodeRichContent;
}

/** JSON 序列化用的导图结构 */
interface MindMapDocJson {
  id: string;
  title: string;
  subject: string;
  book: string;
  layout: Layout;
  theme: string;
  updatedAt: number;
  nodes: MindNodeJson[];
}

/** JSON 反序列化用的节点结构（字段可能缺失，用 ESObject 兜底） */
interface MindNodeRaw {
  id: ESObject;
  text: ESObject;
  parentId: ESObject;
  type: ESObject;
  detail: ESObject;
  style: ESObject;
  collapsed: ESObject;
  mastery: ESObject;
  nextReviewAt: ESObject;
  reviewCount: ESObject;
  wrongCount: ESObject;
  rich: ESObject;
  richContent: ESObject;
}

/** JSON 反序列化用的导图结构 */
interface MindMapRaw {
  id: ESObject;
  title: ESObject;
  subject: ESObject;
  book: ESObject;
  layout: ESObject;
  theme: ESObject;
  updatedAt: ESObject;
  nodes: ESObject[];
}

/** 节点样式原始结构 */
interface NodeStyleRaw {
  color: ESObject;
  shape: ESObject;
}

/** 富内容原始结构（字段可能缺失，用 ESObject 兜底） */
interface RawImage {
  path?: ESObject;
  caption?: ESObject;
}

interface RawLink {
  title?: ESObject;
  url?: ESObject;
}

interface RawRich {
  images?: ESObject[];
  formula?: ESObject;
  links?: ESObject[];
  tags?: ESObject[];
}

/** 学科化富内容原始结构（字段可能缺失，用 ESObject 兜底） */
interface RawRichContent {
  keyPoints?: ESObject[];
  formulas?: ESObject[];
  examples?: ESObject[];
  misconceptions?: ESObject[];
  references?: ESObject[];
  chinese?: ESObject;
  history?: ESObject;
  geography?: ESObject;
  chemistry?: ESObject;
  biology?: ESObject;
  politics?: ESObject;
  english?: ESObject;
}

interface RawChinese { poem?: ESObject; author?: ESObject; dynasty?: ESObject; punctuation?: ESObject[]; rhetoric?: ESObject[]; notes?: ESObject[]; }
interface RawHistory { events?: ESObject[]; }
interface RawGeo { region?: ESObject; coords?: ESObject[]; }
interface RawChem { equation?: ESObject; balanced?: ESObject; reactants?: ESObject[]; products?: ESObject[]; phenomenon?: ESObject; }
interface RawBio { hierarchy?: ESObject[]; }
interface RawPolitics { viewpointFor?: ESObject; viewpointAgainst?: ESObject; currentAffairs?: ESObject[]; }
interface RawEnglish { word?: ESObject; phonetic?: ESObject; examples?: ESObject[]; }
interface RawFormula { variables?: ESObject[]; }

export class MindMap {
  id: string = '';
  title: string = '';
  subject: string = '';
  book: string = '';
  nodes: MindNode[] = [];
  layout: Layout = Layout.TREE_H;
  theme: string = DEFAULT_THEME;
  updatedAt: number = 0;

  constructor() {
  }

  static create(id: string, title: string,
    subject: string = '',
    book: string = '',
    layout: Layout = Layout.TREE_H,
    theme: string = DEFAULT_THEME): MindMap {
    const map = new MindMap();
    map.id = id;
    map.title = title.length > TITLE_MAX_LEN ? title.substring(0, TITLE_MAX_LEN) : title;
    map.subject = subject;
    map.book = book;
    map.layout = layout;
    map.theme = theme;
    map.updatedAt = Date.now();
    return map;
  }

  findNode(id: string): MindNode | undefined {
    if (!id || this.nodes.length === 0) {
      return undefined;
    }
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].id === id) {
        return this.nodes[i];
      }
    }
    return undefined;
  }

  rootNode(): MindNode | undefined {
    if (this.nodes.length === 0) {
      return undefined;
    }
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].parentId === null) {
        return this.nodes[i];
      }
    }
    return undefined;
  }

  /** 结构合法性校验：唯一根、无环、parentId 引用存在、字段完整 */
  validate(): ValidationResult {
    const errors: string[] = [];
    if (!this.id || this.id.length === 0) {
      errors.push('id 缺失');
    }
    if (!this.title || this.title.length === 0) {
      errors.push('title 缺失');
    } else if (this.title.length > TITLE_MAX_LEN) {
      errors.push('title 超过 50 字符');
    }
    if (this.nodes.length === 0) {
      errors.push('nodes 为空');
      return failValidation(errors);
    }
    let rootCount = 0;
    const seen = new Set<string>();
    for (let i = 0; i < this.nodes.length; i++) {
      const node = this.nodes[i];
      if (!node.id || node.id.length === 0) {
        errors.push('存在无 id 节点');
        continue;
      }
      if (seen.has(node.id)) {
        errors.push(`节点 id 重复：${node.id}`);
        continue;
      }
      seen.add(node.id);
      if (node.parentId === null) {
        rootCount++;
      } else if (!this.findNode(node.parentId)) {
        errors.push(`节点 ${node.id} 的父节点 ${node.parentId} 不存在`);
      }
    }
    if (rootCount === 0) {
      errors.push('缺少根节点');
    } else if (rootCount > 1) {
      errors.push(`存在多个根节点：${rootCount}`);
    }
    // 环检测：沿 parentId 链探测
    for (let i = 0; i < this.nodes.length && errors.length === 0; i++) {
      const node = this.nodes[i];
      let current = this.findNode(node.id);
      let guard = 0;
      while (current && current.parentId && guard < this.nodes.length + 1) {
        if (current.parentId === node.id) {
          errors.push(`节点 ${node.id} 形成循环引用`);
          break;
        }
        current = this.findNode(current.parentId);
        guard++;
      }
    }
    if (errors.length > 0) {
      return failValidation(errors);
    }
    const warnings: string[] = [];
    MindMap.collectRichContentWarnings(this, warnings);
    return { ok: true, errors: [], warnings: warnings };
  }

  /** 富内容宽松校验：仅收集非阻断告警（不阻止加载） */
  private static collectRichContentWarnings(map: MindMap, warnings: string[]): void {
    for (let i = 0; i < map.nodes.length; i++) {
      const rc = map.nodes[i].richContent;
      if (!rc) {
        continue;
      }
      for (let k = 0; k < rc.keyPoints.length; k++) {
        if (!rc.keyPoints[k].text || rc.keyPoints[k].text.length === 0) {
          warnings.push(`节点 ${map.nodes[i].id} 的要点文本为空`);
        }
      }
      for (let f = 0; f < rc.formulas.length; f++) {
        const fi = rc.formulas[f];
        if (!fi.latexText || fi.latexText.length === 0 || !fi.plainText || fi.plainText.length === 0) {
          warnings.push(`节点 ${map.nodes[i].id} 的公式缺少 latexText 或 plainText`);
        }
      }
      for (let e = 0; e < rc.examples.length; e++) {
        const ei = rc.examples[e];
        if (!ei.question || ei.question.length === 0 || !ei.answer || ei.answer.length === 0) {
          warnings.push(`节点 ${map.nodes[i].id} 的例题缺少 question 或 answer`);
        }
      }
      for (let m = 0; m < rc.misconceptions.length; m++) {
        const mi = rc.misconceptions[m];
        if (!mi.wrong || mi.wrong.length === 0 || !mi.correct || mi.correct.length === 0) {
          warnings.push(`节点 ${map.nodes[i].id} 的易错点缺少 wrong 或 correct`);
        }
      }
    }
  }

  /** 克隆导图（深拷贝 nodes，用于快照） */
  clone(): MindMap {
    const cloned = new MindMap();
    cloned.id = this.id;
    cloned.title = this.title;
    cloned.subject = this.subject;
    cloned.book = this.book;
    cloned.layout = this.layout;
    cloned.theme = this.theme;
    cloned.updatedAt = this.updatedAt;
    cloned.nodes = [];
    for (let i = 0; i < this.nodes.length; i++) {
      const src = this.nodes[i];
      const dst = new MindNode();
      dst.id = src.id;
      dst.text = src.text;
      dst.parentId = src.parentId;
      dst.type = src.type;
      dst.detail = src.detail;
      const dstStyle: NodeStyle = { color: src.style.color, shape: src.style.shape };
      dst.style = dstStyle;
      dst.collapsed = src.collapsed;
      dst.userEdited = src.userEdited;
      dst.mastery = src.mastery;
      dst.nextReviewAt = src.nextReviewAt;
      dst.reviewCount = src.reviewCount;
      dst.wrongCount = src.wrongCount;
      dst.rich = MindMap.cloneRich(src.rich);
      dst.richContent = MindMap.cloneRichContent(src.richContent);
      cloned.nodes.push(dst);
    }
    return cloned;
  }

  /** 序列化为符合 spec 6.4-1 的 JSON 字符串（title/layout/theme/nodes 固定顺序） */
  toJson(): string {
    const nodeArr: MindNodeJson[] = [];
    for (let i = 0; i < this.nodes.length; i++) {
      const n = this.nodes[i];
      const style: NodeStyle = { color: n.style.color, shape: n.style.shape };
        const item: MindNodeJson = {
          id: n.id,
          text: n.text,
          parentId: n.parentId,
          type: n.type,
          detail: n.detail,
          style: style,
          collapsed: n.collapsed,
          mastery: n.mastery,
          nextReviewAt: n.nextReviewAt,
          reviewCount: n.reviewCount,
          wrongCount: n.wrongCount,
          rich: n.rich,
          richContent: n.richContent
        };
      nodeArr.push(item);
    }
    const obj: MindMapDocJson = {
      id: this.id,
      title: this.title,
      subject: this.subject,
      book: this.book,
      layout: this.layout,
      theme: this.theme,
      updatedAt: this.updatedAt,
      nodes: nodeArr
    };
    return JSON.stringify(obj);
  }

  /** 从 JSON 字符串反序列化（未校验，调用方负责校验） */
  static fromJson(text: string): MindMap | undefined {
    try {
      const obj = JSON.parse(text) as MindMapRaw;
      if (obj === null || obj === undefined) {
        return undefined;
      }
      const map = new MindMap();
      map.id = MindMap.readString(obj.id);
      map.title = MindMap.readString(obj.title);
      map.subject = MindMap.readString(obj.subject);
      map.book = MindMap.readString(obj.book);
      map.layout = MindMap.parseLayout(MindMap.readString(obj.layout));
      map.theme = MindMap.readString(obj.theme);
      const tsRaw: ESObject = obj.updatedAt;
      map.updatedAt = tsRaw !== null && tsRaw !== undefined ? Number(tsRaw) : Date.now();
      map.nodes = [];
      const rawNodes: ESObject[] = obj.nodes;
      if (rawNodes) {
        for (let i = 0; i < rawNodes.length; i++) {
          const rn = rawNodes[i] as MindNodeRaw;
          const node = new MindNode();
          node.id = MindMap.readString(rn.id);
          node.text = MindMap.readString(rn.text);
          const pidRaw: ESObject = rn.parentId;
          node.parentId = (pidRaw === null || pidRaw === undefined || pidRaw === '') ? null : MindMap.readString(pidRaw);
          node.type = MindMap.parseNodeType(MindMap.readString(rn.type));
          node.detail = MindMap.readString(rn.detail);
          const styleObj = rn.style as NodeStyleRaw;
          const nodeStyle: NodeStyle = {
            color: MindMap.parseColor(styleObj),
            shape: MindMap.parseShape(styleObj)
          };
          node.style = nodeStyle;
          const collapsedRaw: ESObject = rn.collapsed;
          node.collapsed = collapsedRaw !== null && collapsedRaw !== undefined && collapsedRaw === true;
          // v1.1 学习字段：旧数据缺失时给默认值，避免被判为异常
          node.mastery = MindMap.parseMastery(rn.mastery);
          const nextRaw: ESObject = rn.nextReviewAt;
          node.nextReviewAt = nextRaw !== null && nextRaw !== undefined ? Number(nextRaw) : 0;
          const rcRaw: ESObject = rn.reviewCount;
          node.reviewCount = rcRaw !== null && rcRaw !== undefined ? Number(rcRaw) : 0;
          const wcRaw: ESObject = rn.wrongCount;
          node.wrongCount = wcRaw !== null && wcRaw !== undefined ? Number(wcRaw) : 0;
          // v1.2 媒体富内容：旧数据缺失时给默认值，避免被判为异常
          node.rich = MindMap.parseRich(rn.rich);
          // Phase X 学科化富内容：向后兼容，旧数据缺省给空默认
          node.richContent = MindMap.parseRichContent(rn.richContent);
          // 自动迁移：旧节点只有 detail 且富内容要点为空 → 注入到 keyPoints[0]
          if (node.detail.length > 0 && node.richContent.keyPoints.length === 0) {
            node.richContent.keyPoints.push({
              id: 'mig_' + node.id,
              text: node.detail,
              level: 'core',
              memorized: false,
              addedBy: 'migrate'
            });
          }
          map.nodes.push(node);
        }
      }
      return map;
    } catch (err) {
      return undefined;
    }
  }

  private static readString(value: ESObject): string {
    if (value === null || value === undefined) {
      return '';
    }
    return String(value);
  }

  private static readNumber(value: ESObject, def: number = 0): number {
    if (value === null || value === undefined) {
      return def;
    }
    const n: number = Number(value);
    return isNaN(n) ? def : n;
  }

  private static readBool(value: ESObject): boolean {
    return value === true;
  }

  private static parseNodeType(value: string): NodeType {
    if (value === 'math') {
      return NodeType.MATH;
    } else if (value === 'physics') {
      return NodeType.PHYSICS;
    } else if (value === 'english') {
      return NodeType.ENGLISH;
    } else if (value === 'history') {
      return NodeType.HISTORY;
    } else if (value === 'geo') {
      return NodeType.GEO;
    } else if (value === 'chem') {
      return NodeType.CHEM;
    } else if (value === 'bio') {
      return NodeType.BIO;
    }
    return NodeType.GENERAL;
  }

  private static parseMastery(value: ESObject): MasteryLevel {
    if (value === null || value === undefined) {
      return MasteryLevel.UNSET;
    }
    const s = String(value);
    if (s === 'known') {
      return MasteryLevel.KNOWN;
    } else if (s === 'fuzzy') {
      return MasteryLevel.FUZZY;
    } else if (s === 'unknown') {
      return MasteryLevel.UNKNOWN;
    }
    return MasteryLevel.UNSET;
  }

  /** 深拷贝媒体富内容（防止 clone 后共享引用） */
  private static cloneRich(rich: NodeRichMedia): NodeRichMedia {
    const images: NodeImage[] = [];
    for (let i = 0; i < rich.images.length; i++) {
      images.push({ path: rich.images[i].path, caption: rich.images[i].caption });
    }
    const links: NodeLink[] = [];
    for (let i = 0; i < rich.links.length; i++) {
      links.push({ title: rich.links[i].title, url: rich.links[i].url });
    }
    const tags: string[] = [];
    for (let i = 0; i < rich.tags.length; i++) {
      tags.push(rich.tags[i]);
    }
    return { images: images, formula: rich.formula, links: links, tags: tags };
  }

  /** 解析媒体富内容：缺失/类型不符时给空默认，保证旧数据兼容 */
  private static parseRich(value: ESObject): NodeRichMedia {
    const empty: NodeRichMedia = { images: [], formula: '', links: [], tags: [] };
    if (value === null || value === undefined) {
      return empty;
    }
    const raw = value as RawRich;
    const images: NodeImage[] = [];
    if (raw.images !== null && raw.images !== undefined) {
      const arr: ESObject[] = raw.images;
      for (let i = 0; i < arr.length; i++) {
        const it = arr[i] as RawImage;
        images.push({
          path: MindMap.readString(it.path),
          caption: MindMap.readString(it.caption)
        });
      }
    }
    const links: NodeLink[] = [];
    if (raw.links !== null && raw.links !== undefined) {
      const arr: ESObject[] = raw.links;
      for (let i = 0; i < arr.length; i++) {
        const it = arr[i] as RawLink;
        links.push({
          title: MindMap.readString(it.title),
          url: MindMap.readString(it.url)
        });
      }
    }
    const tags: string[] = [];
    if (raw.tags !== null && raw.tags !== undefined) {
      const arr: ESObject[] = raw.tags;
      for (let i = 0; i < arr.length; i++) {
        tags.push(String(arr[i]));
      }
    }
    return {
      images: images,
      formula: MindMap.readString(raw.formula),
      links: links,
      tags: tags
    };
  }

  /** 深拷贝学科化富内容（防止 clone 后共享引用） */
  private static cloneRichContent(rich: NodeRichContent): NodeRichContent {
    const kps: KeyPointItem[] = [];
    for (let i = 0; i < rich.keyPoints.length; i++) {
      const k = rich.keyPoints[i];
      kps.push({ id: k.id, text: k.text, level: k.level, memorized: k.memorized, addedBy: k.addedBy });
    }
    const fps: FormulaItem[] = [];
    for (let i = 0; i < rich.formulas.length; i++) {
      const f = rich.formulas[i];
      const vars: FormulaVar[] = [];
      for (let j = 0; j < f.variables.length; j++) {
        const v = f.variables[j];
        vars.push({ name: v.name, meaning: v.meaning });
      }
      fps.push({ id: f.id, latexText: f.latexText, plainText: f.plainText, variables: vars, meaning: f.meaning });
    }
    const exs: RichExampleItem[] = [];
    for (let i = 0; i < rich.examples.length; i++) {
      const e = rich.examples[i];
      exs.push({ id: e.id, question: e.question, answer: e.answer, difficulty: e.difficulty, source: e.source });
    }
    const mcs: MisconceptionItem[] = [];
    for (let i = 0; i < rich.misconceptions.length; i++) {
      const m = rich.misconceptions[i];
      mcs.push({ id: m.id, wrong: m.wrong, correct: m.correct, whyWrong: m.whyWrong });
    }
    const refs: NodeLink[] = [];
    for (let i = 0; i < rich.references.length; i++) {
      const r = rich.references[i];
      refs.push({ title: r.title, url: r.url });
    }
    return {
      keyPoints: kps,
      formulas: fps,
      examples: exs,
      misconceptions: mcs,
      references: refs,
      chinese: MindMap.cloneChinese(rich.chinese),
      history: MindMap.cloneHistory(rich.history),
      geography: MindMap.cloneGeography(rich.geography),
      chemistry: MindMap.cloneChemistry(rich.chemistry),
      biology: MindMap.cloneBiology(rich.biology),
      politics: MindMap.clonePolitics(rich.politics),
      english: MindMap.cloneEnglish(rich.english)
    };
  }

  private static cloneChinese(c: ChineseContent): ChineseContent {
    const punct: string[] = [];
    for (let i = 0; i < c.punctuation.length; i++) {
      punct.push(c.punctuation[i]);
    }
    const rhet: string[] = [];
    for (let i = 0; i < c.rhetoric.length; i++) {
      rhet.push(c.rhetoric[i]);
    }
    const notes: string[] = [];
    for (let i = 0; i < c.notes.length; i++) {
      notes.push(c.notes[i]);
    }
    return { poem: c.poem, author: c.author, dynasty: c.dynasty, punctuation: punct, rhetoric: rhet, notes: notes };
  }

  private static cloneHistory(h: HistoryContent): HistoryContent {
    const evs: HistoryEventItem[] = [];
    for (let i = 0; i < h.events.length; i++) {
      const e = h.events[i];
      evs.push({ year: e.year, title: e.title, desc: e.desc });
    }
    return { events: evs };
  }

  private static cloneGeography(g: GeographyContent): GeographyContent {
    const coords: GeoCoord[] = [];
    for (let i = 0; i < g.coords.length; i++) {
      const c = g.coords[i];
      coords.push({ name: c.name, x: c.x, y: c.y, note: c.note });
    }
    return { region: g.region, coords: coords };
  }

  private static cloneChemistry(c: ChemistryContent): ChemistryContent {
    const rs: string[] = [];
    for (let i = 0; i < c.reactants.length; i++) {
      rs.push(c.reactants[i]);
    }
    const ps: string[] = [];
    for (let i = 0; i < c.products.length; i++) {
      ps.push(c.products[i]);
    }
    return { equation: c.equation, balanced: c.balanced, reactants: rs, products: ps, phenomenon: c.phenomenon };
  }

  private static cloneBiology(b: BiologyContent): BiologyContent {
    const hs: BioHierarchyItem[] = [];
    for (let i = 0; i < b.hierarchy.length; i++) {
      const it = b.hierarchy[i];
      hs.push({ level: it.level, name: it.name, desc: it.desc });
    }
    return { hierarchy: hs };
  }

  private static clonePolitics(p: PoliticsContent): PoliticsContent {
    const ca: string[] = [];
    for (let i = 0; i < p.currentAffairs.length; i++) {
      ca.push(p.currentAffairs[i]);
    }
    return { viewpointFor: p.viewpointFor, viewpointAgainst: p.viewpointAgainst, currentAffairs: ca };
  }

  private static cloneEnglish(e: EnglishContent): EnglishContent {
    const exs: EnglishExampleItem[] = [];
    for (let i = 0; i < e.examples.length; i++) {
      const it = e.examples[i];
      exs.push({ english: it.english, chinese: it.chinese });
    }
    return { word: e.word, phonetic: e.phonetic, examples: exs };
  }

  /** 解析学科化富内容：缺失/类型不符时给空默认，保证旧数据兼容 */
  private static parseRichContent(value: ESObject): NodeRichContent {
    const empty = emptyNodeRichContent();
    if (value === null || value === undefined) {
      return empty;
    }
    const raw = value as RawRichContent;
    return {
      keyPoints: MindMap.parseKeyPoints(raw.keyPoints),
      formulas: MindMap.parseFormulas(raw.formulas),
      examples: MindMap.parseExamples(raw.examples),
      misconceptions: MindMap.parseMisconceptions(raw.misconceptions),
      references: MindMap.parseLinks(raw.references),
      chinese: MindMap.parseChinese(raw.chinese),
      history: MindMap.parseHistory(raw.history),
      geography: MindMap.parseGeography(raw.geography),
      chemistry: MindMap.parseChemistry(raw.chemistry),
      biology: MindMap.parseBiology(raw.biology),
      politics: MindMap.parsePolitics(raw.politics),
      english: MindMap.parseEnglish(raw.english)
    };
  }

  /** 公开：解析学科化富内容（供 AI 富内容生成 / patchRichContent 反序列化复用，避免重复解析逻辑） */
  public static parseNodeRichContent(value: ESObject): NodeRichContent {
    return MindMap.parseRichContent(value);
  }

  /** 公开：从 JSON 文本解析学科化富内容 */
  public static parseNodeRichContentFromJson(json: string): NodeRichContent {
    if (!json || json.length === 0) {
      return emptyNodeRichContent();
    }
    try {
      const value: ESObject = JSON.parse(json);
      return MindMap.parseRichContent(value);
    } catch (err) {
      return emptyNodeRichContent();
    }
  }

  private static parseKeyPoints(value: ESObject[] | undefined): KeyPointItem[] {
    const out: KeyPointItem[] = [];
    if (!value) {
      return out;
    }
    for (let i = 0; i < value.length; i++) {
      const it: ESObject = value[i];
      const id = MindMap.readString(it.id);
      const text = MindMap.readString(it.text);
      if (text.length === 0) {
        continue;
      }
      const level = MindMap.readString(it.level);
      out.push({
        id: id.length > 0 ? id : ('kp_' + i),
        text: text,
        level: level === 'extended' ? 'extended' : (level === 'exam' ? 'exam' : 'core'),
        memorized: it.memorized === true,
        addedBy: MindMap.readString(it.addedBy) === 'user' ? 'user' : (MindMap.readString(it.addedBy) === 'migrate' ? 'migrate' : 'ai')
      });
    }
    return out;
  }

  private static parseFormulas(value: ESObject[] | undefined): FormulaItem[] {
    const out: FormulaItem[] = [];
    if (!value) {
      return out;
    }
    for (let i = 0; i < value.length; i++) {
      const it: ESObject = value[i];
      const latex = MindMap.readString(it.latexText);
      const plain = MindMap.readString(it.plainText);
      if (latex.length === 0 && plain.length === 0) {
        continue;
      }
      const vars: FormulaVar[] = [];
      const rawF = it as RawFormula;
      const rawVars: ESObject[] | undefined = rawF.variables;
      if (rawVars) {
        for (let j = 0; j < rawVars.length; j++) {
          const v: ESObject = rawVars[j];
          vars.push({ name: MindMap.readString(v.name), meaning: MindMap.readString(v.meaning) });
        }
      }
      out.push({
        id: MindMap.readString(it.id).length > 0 ? MindMap.readString(it.id) : ('f_' + i),
        latexText: latex,
        plainText: plain,
        variables: vars,
        meaning: MindMap.readString(it.meaning)
      });
    }
    return out;
  }

  private static parseExamples(value: ESObject[] | undefined): RichExampleItem[] {
    const out: RichExampleItem[] = [];
    if (!value) {
      return out;
    }
    for (let i = 0; i < value.length; i++) {
      const it: ESObject = value[i];
      const q = MindMap.readString(it.question);
      const a = MindMap.readString(it.answer);
      if (q.length === 0 && a.length === 0) {
        continue;
      }
      out.push({
        id: MindMap.readString(it.id).length > 0 ? MindMap.readString(it.id) : ('ex_' + i),
        question: q,
        answer: a,
        difficulty: MindMap.readNumber(it.difficulty, 3),
        source: MindMap.readString(it.source)
      });
    }
    return out;
  }

  private static parseMisconceptions(value: ESObject[] | undefined): MisconceptionItem[] {
    const out: MisconceptionItem[] = [];
    if (!value) {
      return out;
    }
    for (let i = 0; i < value.length; i++) {
      const it: ESObject = value[i];
      const wrong = MindMap.readString(it.wrong);
      const correct = MindMap.readString(it.correct);
      if (wrong.length === 0 && correct.length === 0) {
        continue;
      }
      out.push({
        id: MindMap.readString(it.id).length > 0 ? MindMap.readString(it.id) : ('mc_' + i),
        wrong: wrong,
        correct: correct,
        whyWrong: MindMap.readString(it.whyWrong)
      });
    }
    return out;
  }

  private static parseLinks(value: ESObject[] | undefined): NodeLink[] {
    const out: NodeLink[] = [];
    if (!value) {
      return out;
    }
    for (let i = 0; i < value.length; i++) {
      const it: ESObject = value[i];
      const url = MindMap.readString(it.url);
      if (url.length === 0) {
        continue;
      }
      out.push({ title: MindMap.readString(it.title), url: url });
    }
    return out;
  }

  private static parseChinese(value: ESObject): ChineseContent {
    const empty = emptyChineseContent();
    if (value === null || value === undefined) {
      return empty;
    }
    const raw = value as RawChinese;
    const punct: string[] = [];
    if (raw.punctuation) {
      for (let i = 0; i < raw.punctuation.length; i++) {
        punct.push(MindMap.readString(raw.punctuation[i]));
      }
    }
    const rhet: string[] = [];
    if (raw.rhetoric) {
      for (let i = 0; i < raw.rhetoric.length; i++) {
        rhet.push(MindMap.readString(raw.rhetoric[i]));
      }
    }
    const notes: string[] = [];
    if (raw.notes) {
      for (let i = 0; i < raw.notes.length; i++) {
        notes.push(MindMap.readString(raw.notes[i]));
      }
    }
    return {
      poem: MindMap.readString(raw.poem),
      author: MindMap.readString(raw.author),
      dynasty: MindMap.readString(raw.dynasty),
      punctuation: punct,
      rhetoric: rhet,
      notes: notes
    };
  }

  private static parseHistory(value: ESObject): HistoryContent {
    const out: HistoryEventItem[] = [];
    if (value === null || value === undefined) {
      return { events: out };
    }
    const raw = value as RawHistory;
    if (raw.events) {
      for (let i = 0; i < raw.events.length; i++) {
        const it: ESObject = raw.events[i];
        out.push({ year: MindMap.readString(it.year), title: MindMap.readString(it.title), desc: MindMap.readString(it.desc) });
      }
    }
    return { events: out };
  }

  private static parseGeography(value: ESObject): GeographyContent {
    const coords: GeoCoord[] = [];
    if (value === null || value === undefined) {
      return { region: '', coords: coords };
    }
    const raw = value as RawGeo;
    if (raw.coords) {
      for (let i = 0; i < raw.coords.length; i++) {
        const it: ESObject = raw.coords[i];
        coords.push({
          name: MindMap.readString(it.name),
          x: MindMap.readNumber(it.x, 0),
          y: MindMap.readNumber(it.y, 0),
          note: MindMap.readString(it.note)
        });
      }
    }
    return { region: MindMap.readString(raw.region), coords: coords };
  }

  private static parseChemistry(value: ESObject): ChemistryContent {
    const empty = emptyChemistryContent();
    if (value === null || value === undefined) {
      return empty;
    }
    const raw = value as RawChem;
    const rs: string[] = [];
    if (raw.reactants) {
      for (let i = 0; i < raw.reactants.length; i++) {
        rs.push(MindMap.readString(raw.reactants[i]));
      }
    }
    const ps: string[] = [];
    if (raw.products) {
      for (let i = 0; i < raw.products.length; i++) {
        ps.push(MindMap.readString(raw.products[i]));
      }
    }
    return {
      equation: MindMap.readString(raw.equation),
      balanced: MindMap.readBool(raw.balanced),
      reactants: rs,
      products: ps,
      phenomenon: MindMap.readString(raw.phenomenon)
    };
  }

  private static parseBiology(value: ESObject): BiologyContent {
    const out: BioHierarchyItem[] = [];
    if (value === null || value === undefined) {
      return { hierarchy: out };
    }
    const raw = value as RawBio;
    if (raw.hierarchy) {
      for (let i = 0; i < raw.hierarchy.length; i++) {
        const it: ESObject = raw.hierarchy[i];
        out.push({ level: MindMap.readString(it.level), name: MindMap.readString(it.name), desc: MindMap.readString(it.desc) });
      }
    }
    return { hierarchy: out };
  }

  private static parsePolitics(value: ESObject): PoliticsContent {
    const ca: string[] = [];
    if (value === null || value === undefined) {
      return { viewpointFor: '', viewpointAgainst: '', currentAffairs: ca };
    }
    const raw = value as RawPolitics;
    if (raw.currentAffairs) {
      for (let i = 0; i < raw.currentAffairs.length; i++) {
        ca.push(MindMap.readString(raw.currentAffairs[i]));
      }
    }
    return { viewpointFor: MindMap.readString(raw.viewpointFor), viewpointAgainst: MindMap.readString(raw.viewpointAgainst), currentAffairs: ca };
  }

  private static parseEnglish(value: ESObject): EnglishContent {
    const exs: EnglishExampleItem[] = [];
    if (value === null || value === undefined) {
      return { word: '', phonetic: '', examples: exs };
    }
    const raw = value as RawEnglish;
    if (raw.examples) {
      for (let i = 0; i < raw.examples.length; i++) {
        const it: ESObject = raw.examples[i];
        exs.push({ english: MindMap.readString(it.english), chinese: MindMap.readString(it.chinese) });
      }
    }
    return { word: MindMap.readString(raw.word), phonetic: MindMap.readString(raw.phonetic), examples: exs };
  }

  private static parseLayout(value: string): Layout {
    if (value === 'tree-v') {
      return Layout.TREE_V;
    } else if (value === 'radial') {
      return Layout.RADIAL;
    }
    return Layout.TREE_H;
  }

  private static parseShape(value: NodeStyleRaw): NodeShape {
    if (value === null || value === undefined) {
      return NodeShape.ROUND;
    }
    const str = MindMap.readString(value.shape);
    if (str === 'rect') {
      return NodeShape.RECT;
    } else if (str === 'ellipse') {
      return NodeShape.ELLIPSE;
    }
    return NodeShape.ROUND;
  }

  private static parseColor(value: NodeStyleRaw): string {
    if (value === null || value === undefined) {
      return DEFAULT_NODE_COLOR;
    }
    const color = MindMap.readString(value.color);
    return color.length > 0 ? color : DEFAULT_NODE_COLOR;
  }
}
