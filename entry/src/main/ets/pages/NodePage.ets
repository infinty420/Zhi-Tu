/**
 * NodePage —— 通用节点「学习详情」页（NavDestination，深链 general）。
 * 内容维度全面升级（Phase Z）：在原有面包屑/状态/掌握度/编辑/自测之上，
 * 把节点 detail 之外的新增学科化富内容（NodeRichContent）拆成区块化卡片呈现：
 *   要点卡 / 公式卡（含函数图像预览）/ 例题 / 易错点 / 学科专项面板 / AI 讲解。
 * 每个区块均带 [+ AI补充]，通过 MindMapStore.updateRichContent（追加语义）落笔；
 * AI 讲解的引用节点可点击在页内切换（不压栈新 NavDestination）。
 *
 * 方向约束：未新增弹窗/动效/主题/NavDestination/依赖；复用 FuncParser 与现有 store。
 */
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MasteryLevel, NodeType } from '../model/Constants';
import { MindNode, NodeLink, NodeRichContent, KeyPointItem, FormulaItem, FormulaVar, RichExampleItem, MisconceptionItem, KeyPointLevel, emptyNodeRichContent } from '../model/MindNode';
import { MindMap } from '../model/MindMap';
import { VocabItem } from '../model/StudyModels';
import { MindMapStore } from '../services/MindMapStore';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { QAService, QAAnswer } from '../services/QAService';
import { AIService, TutorMode, TutorChunk, QuizQuestion, SimilarQuizRequest } from '../services/AIService';
import { AIServiceFactory } from '../services/AIServiceFactory';
import { AIConfig } from '../services/AIConfig';
import { QuizService } from '../services/QuizService';
import { ReviewScheduler } from '../services/ReviewScheduler';
import { ContentQualityChecker } from '../services/ContentQualityChecker';
import { AICacheService } from '../services/AICacheService';
import { AppContextHolder } from '../utils/AppContext';
import { GenUid } from '../utils/GenUid';

import { NodeMathPlotCard } from '../components/NodeMathPlotCard';
import { ChineseNodePanel } from '../components/ChineseNodePanel';
import { HistoryNodePanel } from '../components/HistoryNodePanel';
import { GeographyNodePanel } from '../components/GeographyNodePanel';
import { ChemistryNodePanel } from '../components/ChemistryNodePanel';
import { BiologyNodePanel } from '../components/BiologyNodePanel';
import { PoliticsNodePanel } from '../components/PoliticsNodePanel';
import { EnglishNodePanel } from '../components/EnglishNodePanel';
import { PhysicsNodePanel } from '../components/PhysicsNodePanel';

/** 下属知识点条目（子节点浏览） */
interface ChildItem {
  id: string;
  text: string;
  type: NodeType;
}

@Component
export struct NodePage {
  @State nodeId: string = '';
  @State nodeText: string = '';
  @State nodeType: NodeType = NodeType.GENERAL;
  @State detailLines: string[] = [];
  @State tags: string[] = [];
  @State links: NodeLink[] = [];
  @State formula: string = '';
  @State imagePaths: string[] = [];
  @State mastery: MasteryLevel = MasteryLevel.UNSET;
  @State reviewCount: number = 0;
  @State wrongCount: number = 0;
  @State nextReviewAt: number = 0;
  @State mapTitle: string = '';
  @State parentTitle: string = '';
  @State childItems: ChildItem[] = [];

  /** Phase Z：学科化富内容状态（节点详情页核心数据） */
  @State rc: NodeRichContent = emptyNodeRichContent();

  @State showEditor: boolean = false;
  @State editText: string = '';
  @State editDetail: string = '';

  @State showAi: boolean = false;
  @State aiAnswer: string = '';
  @State aiRefs: string[] = [];

  @State showQuiz: boolean = false;
  @State quizInput: string = '';
  @State quizResult: string = '';

  // ---------- Wave 1：AI 逐点辅导（讲细一点 / 换个说法 / 出相似题） ----------
  @State showTutor: boolean = false;
  @State tutorText: string = '';
  @State tutorLoading: boolean = false;
  @State tutorModeLabel: string = '';

  @State showSimilar: boolean = false;
  @State similarQuestions: QuizQuestion[] = [];
  @State similarInput: string = '';
  @State similarResult: string = '';
  @State similarCoverage: string = '';

  // ---------- Wave 4：离线优先（AI 结果缓存命中角标） ----------
  @State tutorFromCache: boolean = false;
  @State similarFromCache: boolean = false;

  // ---------- Wave 1：下一步建议（基于复习排队 + 掌握度） ----------
  @State suggestText: string = '';

  aboutToAppear(): void {
    const link = DeepLinkRouter.currentLink();
    this.nodeType = link.nodeType;
    const snap = MindMapStore.getInstance().currentSnapshot();
    const node: MindNode | undefined = snap && link.nodeId.length > 0 ? snap.findNode(link.nodeId) : undefined;
    if (node) {
      this.nodeId = node.id;
    } else {
      this.nodeId = '';
      this.nodeText = link.payload && link.payload.length > 0 ? link.payload : '节点详情';
    }
    this.refresh();
  }

  /** 从最新快照重读节点状态（标记掌握度/编辑/判分/补充后调用） */
  private refresh(): void {
    const store = MindMapStore.getInstance();
    const snap: MindMap | undefined = store.currentSnapshot();
    const node: MindNode | undefined = snap && this.nodeId.length > 0 ? snap.findNode(this.nodeId) : undefined;
    if (!node) {
      return;
    }
    this.nodeText = node.text;
    this.nodeType = node.type;
    const lines: string[] = node.detail.split('\n');
    const kept: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t.length > 0) {
        kept.push(t);
      }
    }
    this.detailLines = kept;
    this.tags = node.rich.tags;
    this.links = node.rich.links;
    this.formula = node.rich.formula;
    const imgs: string[] = [];
    for (let i = 0; i < node.rich.images.length; i++) {
      if (node.rich.images[i].path.length > 0) {
        imgs.push(node.rich.images[i].path);
      }
    }
    this.imagePaths = imgs;
    this.mastery = node.mastery;
    this.reviewCount = node.reviewCount;
    this.wrongCount = node.wrongCount;
    this.nextReviewAt = node.nextReviewAt;
    this.rc = this.dedupeRich(node.richContent);
    this.mapTitle = snap ? snap.title : '';
    const parent: MindNode | undefined = node.parentId && snap ? snap.findNode(node.parentId) : undefined;
    this.parentTitle = parent ? parent.text : '';
    const kids = node.childrenOf(snap ? snap : new MindMap());
    const items: ChildItem[] = [];
    for (let i = 0; i < kids.length; i++) {
      items.push({ id: kids[i].id, text: kids[i].text, type: kids[i].type });
    }
    this.childItems = items;
    // Wave 1：下一步建议（基于复习排队 + 掌握度）
    this.suggestText = this.buildSuggestion(snap, node);
  }

  /** 展示层去重：历史数据里反复点「AI 补充」会堆出重复条目，展示时按文本保留首条 */
  private dedupeRich(src: NodeRichContent): NodeRichContent {
    const out: NodeRichContent = emptyNodeRichContent();
    out.keyPoints = src.keyPoints.filter((p: KeyPointItem, i: number): boolean =>
      src.keyPoints.findIndex((q: KeyPointItem): boolean => q.text.trim() === p.text.trim()) === i);
    out.formulas = src.formulas.filter((p: FormulaItem, i: number): boolean =>
      src.formulas.findIndex((q: FormulaItem): boolean => q.plainText === p.plainText && q.latexText === p.latexText) === i);
    out.examples = src.examples.filter((p: RichExampleItem, i: number): boolean =>
      src.examples.findIndex((q: RichExampleItem): boolean => q.question.trim() === p.question.trim()) === i);
    out.misconceptions = src.misconceptions.filter((p: MisconceptionItem, i: number): boolean =>
      src.misconceptions.findIndex((q: MisconceptionItem): boolean => q.wrong.trim() === p.wrong.trim()) === i);
    out.references = src.references;
    out.chinese = src.chinese;
    out.history = src.history;
    out.geography = src.geography;
    out.chemistry = src.chemistry;
    out.biology = src.biology;
    out.politics = src.politics;
    out.english = src.english;
    return out;
  }

  /** 页内切换：点击 AI 讲解引用节点时，直接重渲染本页（不压栈新 NavDestination） */
  private switchToNode(id: string): void {
    if (id.length === 0 || id === this.nodeId) {
      return;
    }
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (!snap || !snap.findNode(id)) {
      promptAction.showToast({ message: '未在当前导图中找到该引用节点' });
      return;
    }
    this.nodeId = id;
    this.refresh();
  }

  /** 按节点文本反查 id（AI ref 是文本，需映射到节点） */
  private findNodeIdByText(text: string): string {
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (snap) {
      for (let i = 0; i < snap.nodes.length; i++) {
        if (snap.nodes[i].text === text) {
          return snap.nodes[i].id;
        }
      }
    }
    return '';
  }

  /** 打开外链：拉起系统浏览器；url 缺 scheme 时自动补 https:// */
  private async openExternal(url: string): Promise<void> {
    if (!url || url.length === 0) {
      return;
    }
    const full = url.startsWith('http://') || url.startsWith('https://') ? url : `https://${url}`;
    try {
      await AppContextHolder.get().openLink(full);
    } catch (err) {
      promptAction.showToast({ message: `打开失败：${full}` });
    }
  }

  private typeLabel(): string {
    if (this.nodeType === NodeType.MATH) {
      return '数学';
    } else if (this.nodeType === NodeType.PHYSICS) {
      return '物理';
    } else if (this.nodeType === NodeType.ENGLISH) {
      return '英语';
    } else if (this.nodeType === NodeType.HISTORY) {
      return '历史';
    } else if (this.nodeType === NodeType.GEO) {
      return '地理';
    } else if (this.nodeType === NodeType.CHEM) {
      return '化学';
    } else if (this.nodeType === NodeType.BIO) {
      return '生物';
    }
    return '普通节点';
  }

  private masteryLabel(): string {
    if (this.mastery === MasteryLevel.KNOWN) {
      return '会';
    } else if (this.mastery === MasteryLevel.FUZZY) {
      return '模糊';
    } else if (this.mastery === MasteryLevel.UNKNOWN) {
      return '不会';
    }
    return '未标记';
  }

  private levelText(level: KeyPointLevel): string {
    if (level === 'core') {
      return '核心';
    } else if (level === 'exam') {
      return '考点';
    }
    return '拓展';
  }

  private levelColor(level: KeyPointLevel): string {
    if (level === 'core') {
      return '#1677ff';
    } else if (level === 'exam') {
      return '#d48806';
    }
    return '#722ed1';
  }

  /** 学科代码（用于 AI 富内容生成请求） */
  private subjectCode(): string {
    if (this.nodeType === NodeType.MATH) {
      return 'math';
    } else if (this.nodeType === NodeType.PHYSICS) {
      return 'physics';
    } else if (this.nodeType === NodeType.ENGLISH) {
      return 'english';
    } else if (this.nodeType === NodeType.HISTORY) {
      return 'history';
    } else if (this.nodeType === NodeType.GEO) {
      return 'geo';
    } else if (this.nodeType === NodeType.CHEM) {
      return 'chem';
    } else if (this.nodeType === NodeType.BIO) {
      return 'bio';
    }
    return '';
  }

  private formatTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d = new Date(ts);
    const mm = d.getMinutes() < 10 ? '0' + d.getMinutes() : `${d.getMinutes()}`;
    return `${d.getMonth() + 1}月${d.getDate()}日 ${d.getHours()}:${mm}`;
  }

  private markMastery(level: MasteryLevel): void {
    MindMapStore.getInstance().setMastery(this.nodeId, level);
    this.refresh();
    promptAction.showToast({ message: `已标记为「${level === MasteryLevel.KNOWN ? '会' : (level === MasteryLevel.FUZZY ? '模糊' : '不会')}」` });
  }

  /** AI 讲解本节点：基于当前导图检索合成讲解 + 引用 */
  private aiExplain(): void {
    const snap = MindMapStore.getInstance().currentSnapshot();
    const ans: QAAnswer = QAService.getInstance().ask(`请讲解「${this.nodeText}」`, snap);
    this.aiAnswer = ans.answer;
    this.aiRefs = ans.refs;
    this.showAi = true;
  }

  /** AI 补充学科化富内容：生成后按追加语义写入节点（不覆盖已有要点/公式）；与已有内容逐条去重 */
  private async aiSupplementRich(): Promise<void> {
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (!snap) {
      return;
    }
    const node = snap.findNode(this.nodeId);
    if (!node) {
      return;
    }
    const config = AIConfig.load();
    const svc: AIService = AIServiceFactory.create(config);
    try {
      const res = await svc.generateRichContentForNode({
        nodeText: node.text,
        nodeDetail: node.detail,
        nodeType: node.type,
        subject: this.subjectCode()
      });
      if (res.ok) {
        // 去重：与节点已有内容（文本级）相同的条目不再追加，避免反复点击堆出一屏重复卡
        const cur = node.richContent;
        const inc = res.data.rich;
        const kp = inc.keyPoints.filter((p) => !cur.keyPoints.some((q) => q.text.trim() === p.text.trim()));
        const fm = inc.formulas.filter((p) => !cur.formulas.some((q) => q.plainText === p.plainText || q.latexText === p.latexText));
        const ex = inc.examples.filter((p) => !cur.examples.some((q) => q.question.trim() === p.question.trim()));
        const mc = inc.misconceptions.filter((p) => !cur.misconceptions.some((q) => q.wrong.trim() === p.wrong.trim()));
        if (kp.length + fm.length + ex.length + mc.length === 0) {
          promptAction.showToast({ message: 'AI 内容与已有内容重复，未重复添加' });
          return;
        }
        const patch: Partial<NodeRichContent> = {};
        if (kp.length > 0) {
          patch.keyPoints = kp;
        }
        if (fm.length > 0) {
          patch.formulas = fm;
        }
        if (ex.length > 0) {
          patch.examples = ex;
        }
        if (mc.length > 0) {
          patch.misconceptions = mc;
        }
        MindMapStore.getInstance().updateRichContent(this.nodeId, patch, 'append');
        this.refresh();
        promptAction.showToast({ message: `已补充 ${kp.length + fm.length + ex.length + mc.length} 条内容` });
      } else {
        promptAction.showToast({ message: 'AI 补充失败，请稍后再试' });
      }
    } catch (err) {
      promptAction.showToast({ message: 'AI 补充失败，请稍后再试' });
    }
  }

  /** 快速自测：提交答案，按与要点的字符重合度判分（本地 Mock 判分） */
  private submitQuiz(): void {
    const user = this.quizInput.trim();
    if (user.length < 2) {
      promptAction.showToast({ message: '请输入至少 2 个字的答案' });
      return;
    }
    const answer = this.detailLines.join(' ');
    let hit = 0;
    for (let i = 0; i < user.length; i++) {
      const ch = user.charAt(i);
      if (ch.trim().length > 0 && answer.includes(ch)) {
        hit++;
      }
    }
    const correct = answer.length > 0 && hit / user.length >= 0.4;
    MindMapStore.getInstance().recordQuiz(this.nodeId, correct, `「${this.nodeText}」的要点是什么？`, answer, user);
    this.quizResult = correct
      ? '回答正确！已标记为「会」并清除复习排队。'
      : '未通过，已标记为「不会」并加入错题本与复习队列。';
    this.refresh();
  }

  /** Wave 1：讲细一点 / 换个说法（复用 AIService.tutorNode 流式讲解） */
  private async runTutor(mode: TutorMode, label: string): Promise<void> {
    this.showTutor = true;
    this.tutorLoading = true;
    this.tutorText = '';
    this.tutorModeLabel = label;
    const config = AIConfig.load();
    const svc: AIService = AIServiceFactory.create(config);
    try {
      const res = await svc.tutorNode({
        nodeText: this.nodeText,
        nodeDetail: this.detailLines.join('\n'),
        nodeType: this.nodeType,
        mode: mode
      }, (chunk: TutorChunk) => {
        if (!chunk.done) {
          this.tutorText += chunk.text;
        }
      });
      // Wave 4：判断是否来自离线缓存
      this.tutorFromCache = AICacheService.getInstance().consumeLastHit();
      if (!res.ok) {
        this.tutorText = '辅导生成失败，请稍后再试。';
      }
    } catch (err) {
      this.tutorText = '辅导生成失败，请稍后再试。';
    } finally {
      this.tutorLoading = false;
    }
  }

  /** Wave 1：出相似题（生成可判分题目，并展示考点模板命中率） */
  private async runSimilarQuiz(): Promise<void> {
    this.showSimilar = true;
    this.similarInput = '';
    this.similarResult = '';
    this.similarCoverage = '';
    const config = AIConfig.load();
    const svc: AIService = AIServiceFactory.create(config);
    try {
      const res = await svc.generateSimilarQuiz({
        nodeId: this.nodeId,
        nodeText: this.nodeText,
        nodeDetail: this.detailLines.join('\n'),
        subject: this.subjectCode(),
        difficulty: 3,
        limit: 1
      });
      // Wave 4：判断是否来自离线缓存
      this.similarFromCache = AICacheService.getInstance().consumeLastHit();
      if (res.ok && res.data.questions.length > 0) {
        this.similarQuestions = res.data.questions;
        const cov = ContentQualityChecker.checkQuizTemplateCoverage(res.data, this.subjectCode());
        this.similarCoverage = cov.total > 0 ? `考点模板命中率：${Math.round(cov.ratio * 100)}%（${cov.covered}/${cov.total}）` : '';
      } else {
        this.similarQuestions = [];
        this.similarCoverage = '';
        promptAction.showToast({ message: '相似题生成失败，请稍后再试' });
      }
    } catch (err) {
      this.similarQuestions = [];
      this.similarCoverage = '';
      promptAction.showToast({ message: '相似题生成失败，请稍后再试' });
    }
  }

  /** Wave 1：相似题判分（复用 QuizService，结果归集经 NodeLearnService → MindMapStore） */
  private submitSimilar(): void {
    if (this.similarQuestions.length === 0) {
      return;
    }
    const q = this.similarQuestions[0];
    const user = this.similarInput.trim();
    if (user.length < 2) {
      promptAction.showToast({ message: '请输入至少 2 个字的答案' });
      return;
    }
    const quiz = new QuizService();
    const grade = quiz.grade(q, user);
    quiz.recordResult(this.nodeId, grade.correct, q.prompt, q.answer, user);
    this.similarResult = grade.correct
      ? `回答正确（${grade.score} 分）！已标记为「会」并清除复习排队。`
      : `未通过（${grade.score} 分）。${grade.explanation} 已加入错题本与复习队列。`;
    this.refresh();
  }

  /** Wave 1：生成下一步复习建议（基于复习排队 + 掌握度） */
  private buildSuggestion(snap: MindMap | undefined, node: MindNode): string {
    if (!snap) {
      return '打开或生成一张导图后，这里会给出下一步复习建议。';
    }
    const isDue = node.nextReviewAt > 0 && node.nextReviewAt <= Date.now();
    const due = ReviewScheduler.dueNodes(snap);
    if (isDue) {
      return `本知识点已到复习时间，建议先做一道「相似题」巩固（见下方 AI 逐点辅导）。`;
    }
    if (due.length > 0) {
      return `本导图还有 ${due.length} 个知识点待复习，建议优先处理最早到期的「${due[0].text}」，或给本节点做一次自测。`;
    }
    const mk = this.masteryLabel();
    if (mk === '未标记' || mk === '不会') {
      return `本知识点尚未掌握，建议先看「AI 讲解」理解，再用「快速自测 / 相似题」检验。`;
    }
    return `当前没有待复习项，掌握度良好。可用「出相似题」做变式练习，进一步巩固。`;
  }

  /** Wave 4：英语例句收藏到生词本（经 store 命令层落盘） */
  private collectVocab(english: string, chinese: string): void {
    const word = this.rc.english.word.length > 0 ? this.rc.english.word : this.nodeText;
    const item: VocabItem = {
      id: GenUid.nextWrongId(),
      english: english,
      chinese: chinese,
      analysis: `${word} · 例句收藏`,
      createdAt: Date.now()
    };
    MindMapStore.getInstance().addVocabItem(item);
    promptAction.showToast({ message: '已收藏到生词本' });
  }

  /** Wave 4：例句自检结果回传（通过=标记会，未过=模糊并入复习队列） */
  private recordEnglishSelfTest(passed: boolean): void {
    const store = MindMapStore.getInstance();
    store.setMastery(this.nodeId, passed ? MasteryLevel.KNOWN : MasteryLevel.FUZZY);
    this.refresh();
    promptAction.showToast({ message: passed ? '自检通过，已标记为「会」' : '未通过，已排入复习队列' });
  }

  private saveEdit(): void {
    const t = this.editText.trim();
    if (t.length === 0) {
      promptAction.showToast({ message: '标题不能为空' });
      return;
    }
    const store = MindMapStore.getInstance();
    store.renameNode(this.nodeId, t);
    store.updateDetail(this.nodeId, this.editDetail.trim(), 'replace');
    this.showEditor = false;
    this.refresh();
    promptAction.showToast({ message: '已保存' });
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          // ---------- 头部：返回 + 面包屑 + 编辑 ----------
          Row({ space: 8 }) {
            Button('返回')
              .height(32)
              .fontSize(14)
              .backgroundColor('#1677ff')
              .onClick(() => {
                DeepLinkRouter.pop();
              })
            Column({ space: 2 }) {
              Text(this.mapTitle.length > 0 ? `${this.mapTitle}${this.parentTitle.length > 0 ? ' · ' + this.parentTitle : ''}` : '节点详情')
                .fontSize(12)
                .fontColor('#8a94a6')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.nodeText)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button('编辑')
              .height(32)
              .fontSize(14)
              .backgroundColor('#ffffff')
              .fontColor('#1677ff')
              .border({ width: 1, color: '#1677ff' })
              .onClick(() => {
                this.editText = this.nodeText;
                this.editDetail = this.detailLines.join('\n');
                this.showEditor = !this.showEditor;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // ---------- 编辑面板 ----------
          if (this.showEditor) {
            Column({ space: 8 }) {
              TextInput({ text: this.editText, placeholder: '节点标题' })
                .fontSize(15)
                .width('100%')
                .onChange((v: string) => {
                  this.editText = v;
                })
              TextArea({ text: this.editDetail, placeholder: '要点详情（每行一条）' })
                .fontSize(14)
                .height(110)
                .width('100%')
                .onChange((v: string) => {
                  this.editDetail = v;
                })
              Button('保存')
                .width('100%')
                .height(38)
                .backgroundColor('#1677ff')
                .onClick(() => {
                  this.saveEdit();
                })
            }
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#ffffff')
            .width('100%')
          }

          // ---------- 状态徽章行 ----------
          Row({ space: 6 }) {
            Text(this.typeLabel())
              .fontSize(12)
              .fontColor('#1677ff')
              .backgroundColor('#e6f4ff')
              .borderRadius(8)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            Text(`掌握度：${this.masteryLabel()}`)
              .fontSize(12)
              .fontColor(this.mastery === MasteryLevel.KNOWN ? '#389e0d' : (this.mastery === MasteryLevel.UNSET ? '#8a94a6' : '#d48806'))
              .backgroundColor(this.mastery === MasteryLevel.KNOWN ? '#f6ffed' : '#fffbe6')
              .borderRadius(8)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            Text(`复习 ${this.reviewCount} 次 · 答错 ${this.wrongCount} 次`)
              .fontSize(11)
              .fontColor('#8a94a6')
          }
          .width('100%')
          if (this.nextReviewAt > 0) {
            Text(`下次复习：${this.formatTime(this.nextReviewAt)}`)
              .fontSize(12)
              .fontColor('#8a94a6')
              .width('100%')
          }

          // ---------- Wave 1：下一步建议（基于复习排队 + 掌握度） ----------
          Column({ space: 6 }) {
            Row() {
              Text('下一步建议')
                .fontSize(14)
                .fontColor('#5f6b7f')
                .layoutWeight(1)
              if (this.suggestText.indexOf('相似题') >= 0) {
                Button('去出相似题')
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#e6f4ff')
                  .fontColor('#1677ff')
                  .onClick(() => {
                    this.runSimilarQuiz();
                  })
              }
            }
            .width('100%')
            Text(this.suggestText)
              .fontSize(13)
              .fontColor('#1a2333')
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .borderRadius(12)
          .backgroundColor('#fff7e6')
          .width('100%')

          // ---------- 要点卡片区块 ----------
          Column({ space: 6 }) {
            Row() {
              Text('要点')
                .fontSize(14)
                .fontColor('#5f6b7f')
                .layoutWeight(1)
              Text(`共 ${this.rc.keyPoints.length} 条`)
                .fontSize(12)
                .fontColor('#b0b9c9')
              Button('+ AI补充')
                .height(28)
                .fontSize(12)
                .backgroundColor('#e6f4ff')
                .fontColor('#1677ff')
                .margin({ left: 8 })
                .onClick(() => {
                  this.aiSupplementRich();
                })
            }
            .width('100%')
            if (this.rc.keyPoints.length > 0) {
              ForEach(this.rc.keyPoints, (kp: KeyPointItem) => {
                Row({ space: 8 }) {
                  Text(this.levelText(kp.level))
                    .fontSize(11)
                    .fontColor(this.levelColor(kp.level))
                    .backgroundColor('#f0f5ff')
                    .borderRadius(6)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  Text(kp.text)
                    .fontSize(14)
                    .fontColor('#1a2333')
                    .layoutWeight(1)
                  Text(kp.memorized ? '已记住' : '标记记住')
                    .fontSize(11)
                    .fontColor(kp.memorized ? '#389e0d' : '#8a94a6')
                    .onClick(() => {
                      MindMapStore.getInstance().markKeyPointMemorized(this.nodeId, kp.id, !kp.memorized);
                      this.refresh();
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding(10)
                .borderRadius(10)
                .backgroundColor('#ffffff')
              }, (kp: KeyPointItem) => kp.id)
            } else {
              Text('还没有要点，点「+ AI补充」让 AI 先补充一版')
                .fontSize(13)
                .fontColor('#b0b9c9')
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .borderRadius(12)
          .backgroundColor('#f5f8ff')
          .width('100%')

          // ---------- 公式卡片区块（含函数图像预览） ----------
          if (this.rc.formulas.length > 0) {
            Column({ space: 8 }) {
              Row() {
                Text('公式')
                  .fontSize(14)
                  .fontColor('#5f6b7f')
                  .layoutWeight(1)
                Button('+ AI补充')
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#e6f4ff')
                  .fontColor('#1677ff')
                  .onClick(() => {
                    this.aiSupplementRich();
                  })
              }
              .width('100%')
              ForEach(this.rc.formulas, (f: FormulaItem) => {
                Column({ space: 6 }) {
                  Text(f.latexText)
                    .fontSize(16)
                    .fontFamily('monospace')
                    .fontColor('#1a2333')
                    .width('100%')
                  if (f.meaning.length > 0) {
                    Text(f.meaning)
                      .fontSize(12)
                      .fontColor('#4a5468')
                      .width('100%')
                  }
                  if (f.variables.length > 0) {
                    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                      ForEach(f.variables, (v: FormulaVar) => {
                        Text(`${v.name}：${v.meaning}`)
                          .fontSize(11)
                          .fontColor('#534ab7')
                          .backgroundColor('#eeedfe')
                          .borderRadius(8)
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          .margin({ right: 6, bottom: 6 })
                      }, (v: FormulaVar) => v.name)
                    }
                    .width('100%')
                  }
                  // 仅对 y=f(x) 形式且含 x 的公式给出图像预览
                  if ((f.plainText.indexOf('y=') === 0 || f.plainText.indexOf('Y=') === 0) && f.plainText.indexOf('x') >= 0) {
                    NodeMathPlotCard({ expr: f.plainText })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .padding(10)
                .borderRadius(10)
                .backgroundColor('#ffffff')
                .width('100%')
              }, (f: FormulaItem) => f.id)
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#f5f8ff')
            .width('100%')
          }

          // ---------- 例题区块 ----------
          if (this.rc.examples.length > 0) {
            Column({ space: 8 }) {
              Row() {
                Text('例题')
                  .fontSize(14)
                  .fontColor('#5f6b7f')
                  .layoutWeight(1)
                Button('+ AI补充')
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#e6f4ff')
                  .fontColor('#1677ff')
                  .onClick(() => {
                    this.aiSupplementRich();
                  })
              }
              .width('100%')
              ForEach(this.rc.examples, (ex: RichExampleItem) => {
                Column({ space: 4 }) {
                  Text(ex.question)
                    .fontSize(14)
                    .fontColor('#1a2333')
                    .width('100%')
                  Text(`答：${ex.answer}`)
                    .fontSize(13)
                    .fontColor('#389e0d')
                    .width('100%')
                  Row() {
                    Text(`难度 ${ex.difficulty}/5`)
                      .fontSize(11)
                      .fontColor('#8a94a6')
                    if (ex.source.length > 0) {
                      Text(`来源：${ex.source}`)
                        .fontSize(11)
                        .fontColor('#8a94a6')
                        .margin({ left: 10 })
                    }
                  }
                  .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .padding(10)
                .borderRadius(10)
                .backgroundColor('#ffffff')
                .width('100%')
              }, (ex: RichExampleItem) => ex.id)
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#f5f8ff')
            .width('100%')
          }

          // ---------- 易错点区块 ----------
          if (this.rc.misconceptions.length > 0) {
            Column({ space: 8 }) {
              Row() {
                Text('易错点')
                  .fontSize(14)
                  .fontColor('#5f6b7f')
                  .layoutWeight(1)
                Button('+ AI补充')
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#e6f4ff')
                  .fontColor('#1677ff')
                  .onClick(() => {
                    this.aiSupplementRich();
                  })
              }
              .width('100%')
              ForEach(this.rc.misconceptions, (m: MisconceptionItem) => {
                Column({ space: 4 }) {
                  Text(`✗ ${m.wrong}`)
                    .fontSize(13)
                    .fontColor('#cf1322')
                    .width('100%')
                  Text(`✓ ${m.correct}`)
                    .fontSize(13)
                    .fontColor('#389e0d')
                    .width('100%')
                  if (m.whyWrong.length > 0) {
                    Text(`原因：${m.whyWrong}`)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                      .width('100%')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .padding(10)
                .borderRadius(10)
                .backgroundColor('#fff1f0')
                .width('100%')
              }, (m: MisconceptionItem) => m.id)
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .width('100%')
          }

          // ---------- 学科专项面板（仅当节点学科匹配或该槽位有内容时展示） ----------
          if (this.nodeType === NodeType.ENGLISH || this.rc.english.word.length > 0) {
            EnglishNodePanel({
              content: this.rc.english,
              onAi: () => this.aiSupplementRich(),
              onCollect: (en: string, cn: string) => this.collectVocab(en, cn),
              onSelfTest: (ok: boolean) => this.recordEnglishSelfTest(ok)
            })
          }
          if (this.nodeType === NodeType.HISTORY || this.rc.history.events.length > 0) {
            HistoryNodePanel({ content: this.rc.history, onAi: () => this.aiSupplementRich() })
          }
          if (this.nodeType === NodeType.GEO || this.rc.geography.coords.length > 0 || this.rc.geography.region.length > 0) {
            GeographyNodePanel({ content: this.rc.geography, onAi: () => this.aiSupplementRich() })
          }
          if (this.nodeType === NodeType.CHEM || this.rc.chemistry.equation.length > 0) {
            ChemistryNodePanel({ content: this.rc.chemistry, onAi: () => this.aiSupplementRich() })
          }
          if (this.nodeType === NodeType.BIO || this.rc.biology.hierarchy.length > 0) {
            BiologyNodePanel({ content: this.rc.biology, onAi: () => this.aiSupplementRich() })
          }
          if (this.rc.chinese.poem.length > 0 || this.rc.chinese.notes.length > 0) {
            ChineseNodePanel({ content: this.rc.chinese, onAi: () => this.aiSupplementRich() })
          }
          if (this.rc.politics.viewpointFor.length > 0 || this.rc.politics.viewpointAgainst.length > 0 || this.rc.politics.currentAffairs.length > 0) {
            PoliticsNodePanel({ content: this.rc.politics, onAi: () => this.aiSupplementRich() })
          }
          // 物理专项面板（仿真模型匹配 + 唤起 PhysicsSimPage），补齐九科内嵌呈现
          if (this.nodeType === NodeType.PHYSICS) {
            PhysicsNodePanel({ nodeId: this.nodeId, nodeText: this.nodeText, onAi: () => this.aiSupplementRich() })
          }

          // ---------- 原始要点（detail，与富内容并列，语义不变） ----------
          if (this.detailLines.length > 0) {
            Column({ space: 6 }) {
              Row() {
                Text('原始要点（detail）')
                  .fontSize(14)
                  .fontColor('#5f6b7f')
                  .layoutWeight(1)
                Button('+ AI补充')
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#e6f4ff')
                  .fontColor('#1677ff')
                  .onClick(() => {
                    this.aiSupplementRich();
                  })
              }
              .width('100%')
              ForEach(this.detailLines, (line: string) => {
                Text(line)
                  .fontSize(15)
                  .fontColor('#1a2333')
                  .width('100%')
              }, (line: string, idx: number) => `${idx}_${line}`)
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#ffffff')
            .width('100%')
          }

          // ---------- 掌握度标记栏 ----------
          Row({ space: 8 }) {
            Button('会')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontColor(this.mastery === MasteryLevel.KNOWN ? '#ffffff' : '#389e0d')
              .backgroundColor(this.mastery === MasteryLevel.KNOWN ? '#52c41a' : '#f6ffed')
              .onClick(() => {
                this.markMastery(MasteryLevel.KNOWN);
              })
            Button('模糊')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontColor(this.mastery === MasteryLevel.FUZZY ? '#ffffff' : '#d48806')
              .backgroundColor(this.mastery === MasteryLevel.FUZZY ? '#faad14' : '#fffbe6')
              .onClick(() => {
                this.markMastery(MasteryLevel.FUZZY);
              })
            Button('不会')
              .layoutWeight(1)
              .height(38)
              .fontSize(14)
              .fontColor(this.mastery === MasteryLevel.UNKNOWN ? '#ffffff' : '#cf1322')
              .backgroundColor(this.mastery === MasteryLevel.UNKNOWN ? '#f5222d' : '#fff1f0')
              .onClick(() => {
                this.markMastery(MasteryLevel.UNKNOWN);
              })
          }
          .width('100%')

          // ---------- 下属知识点（点击递归跳转子节点详情页） ----------
          if (this.childItems.length > 0) {
            Text('下属知识点（点击继续进入）')
              .fontSize(13)
              .fontColor('#8a94a6')
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.childItems, (item: ChildItem) => {
                Text(item.text)
                  .fontSize(13)
                  .fontColor('#534ab7')
                  .backgroundColor('#eeedfe')
                  .borderRadius(10)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    DeepLinkRouter.route(item.id, item.type, item.text);
                  })
              }, (item: ChildItem) => item.id)
            }
            .width('100%')
          }

          // ---------- 媒体公式 / 图片（v1.2 富媒体，与学科化富内容并列） ----------
          if (this.formula.length > 0) {
            Column({ space: 4 }) {
              Text('媒体公式')
                .fontSize(13)
                .fontColor('#8a94a6')
              Text(this.formula)
                .fontSize(16)
                .fontFamily('monospace')
                .fontColor('#1a2333')
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#ffffff')
            .width('100%')
          }
          if (this.imagePaths.length > 0) {
            ForEach(this.imagePaths, (p: string) => {
              Image(p)
                .width('100%')
                .height(150)
                .objectFit(ImageFit.Cover)
                .borderRadius(12)
            }, (p: string) => p)
          }

          // ---------- 链接卡片 ----------
          if (this.links.length > 0) {
            Text('链接')
              .fontSize(13)
              .fontColor('#8a94a6')
              .width('100%')
            ForEach(this.links, (lk: NodeLink) => {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(lk.title && lk.title.length > 0 ? lk.title : lk.url)
                    .fontSize(14)
                    .fontColor('#1677ff')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(lk.url)
                    .fontSize(11)
                    .fontColor('#b0b9c9')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('↗')
                  .fontSize(16)
                  .fontColor('#1677ff')
              }
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor('#ffffff')
              .onClick(() => {
                this.openExternal(lk.url);
              })
            }, (lk: NodeLink) => lk.title + '|' + lk.url)
          }

          // ---------- 标签 ----------
          if (this.tags.length > 0) {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.tags, (t: string) => {
                Text(t)
                  .fontSize(12)
                  .fontColor('#722ed1')
                  .backgroundColor('#f9f0ff')
                  .borderRadius(8)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .margin({ right: 6, bottom: 6 })
              }, (t: string) => t)
            }
            .width('100%')
          }

          // ---------- AI 讲解结果（引用节点可点击页内切换） ----------
          if (this.showAi) {
            Column({ space: 6 }) {
              Text('AI 讲解')
                .fontSize(14)
                .fontColor('#5f6b7f')
              Text(this.aiAnswer)
                .fontSize(14)
                .fontColor('#1a2333')
                .width('100%')
              if (this.aiRefs.length > 0) {
                Text('引用节点（点击在页内切换）：')
                  .fontSize(12)
                  .fontColor('#b0b9c9')
                  .width('100%')
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(this.aiRefs, (ref: string) => {
                    Text(ref)
                      .fontSize(12)
                      .fontColor('#1677ff')
                      .backgroundColor('#e6f4ff')
                      .borderRadius(10)
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        const id = this.findNodeIdByText(ref);
                        if (id.length > 0) {
                          this.switchToNode(id);
                        } else {
                          promptAction.showToast({ message: `未找到节点：${ref}` });
                        }
                      })
                  }, (ref: string) => ref)
                }
                .width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#f0f7ff')
            .width('100%')
          }

          // ---------- 快速自测 ----------
          if (this.showQuiz) {
            Column({ space: 8 }) {
              Text(`自测：「${this.nodeText}」的要点是什么？`)
                .fontSize(14)
                .fontColor('#1a2333')
                .width('100%')
              TextArea({ text: this.quizInput, placeholder: '写下你的答案…' })
                .fontSize(14)
                .height(80)
                .width('100%')
                .onChange((v: string) => {
                  this.quizInput = v;
                })
              Button('提交答案')
                .width('100%')
                .height(38)
                .backgroundColor('#1677ff')
                .onClick(() => {
                  this.submitQuiz();
                })
              if (this.quizResult.length > 0) {
                Text(this.quizResult)
                  .fontSize(13)
                  .fontColor('#d48806')
                  .width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(12)
            .backgroundColor('#ffffff')
            .width('100%')
          }

          // ---------- Wave 1：AI 逐点辅导（讲细一点 / 换个说法 / 出相似题） ----------
          Column({ space: 8 }) {
            Text('AI 逐点辅导')
              .fontSize(14)
              .fontColor('#5f6b7f')
              .width('100%')
            Row({ space: 8 }) {
              Button('讲细一点')
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .backgroundColor('#1677ff')
                .onClick(() => {
                  this.runTutor('explain', '讲细一点');
                })
              Button('换个说法')
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .fontColor('#1677ff')
                .backgroundColor('#ffffff')
                .border({ width: 1, color: '#1677ff' })
                .onClick(() => {
                  this.runTutor('rephrase', '换个说法');
                })
              Button('出相似题')
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .fontColor('#1677ff')
                .backgroundColor('#ffffff')
                .border({ width: 1, color: '#1677ff' })
                .onClick(() => {
                  this.runSimilarQuiz();
                })
            }
            .width('100%')

            // 讲细一点 / 换个说法 结果（流式）
            if (this.showTutor) {
              Column({ space: 4 }) {
                Row() {
                  Text(this.tutorModeLabel.length > 0 ? this.tutorModeLabel : 'AI 辅导')
                    .fontSize(13)
                    .fontColor('#1677ff')
                    .layoutWeight(1)
                  if (this.tutorFromCache) {
                    Text('离线缓存')
                      .fontSize(11)
                      .fontColor('#d48806')
                      .backgroundColor('#fff7e6')
                      .borderRadius(8)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  }
                  if (this.tutorLoading) {
                    Text('生成中…')
                      .fontSize(12)
                      .fontColor('#8a94a6')
                  }
                }
                .width('100%')
                Text(this.tutorText.length > 0 ? this.tutorText : '（AI 正在生成讲解…）')
                  .fontSize(14)
                  .fontColor('#1a2333')
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .borderRadius(10)
              .backgroundColor('#f0f7ff')
              .width('100%')
            }

            // 出相似题 结果（可判分）
            if (this.showSimilar) {
              Column({ space: 8 }) {
                if (this.similarFromCache) {
                  Text('离线缓存 · 断网也能练')
                    .fontSize(11)
                    .fontColor('#d48806')
                    .backgroundColor('#fff7e6')
                    .borderRadius(8)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                }
                if (this.similarCoverage.length > 0) {
                  Text(this.similarCoverage)
                    .fontSize(12)
                    .fontColor('#d48806')
                    .width('100%')
                }
                if (this.similarQuestions.length > 0) {
                  ForEach(this.similarQuestions, (q: QuizQuestion) => {
                    Column({ space: 6 }) {
                      Text(q.prompt)
                        .fontSize(14)
                        .fontColor('#1a2333')
                        .width('100%')
                      if (q.hint && q.hint.length > 0) {
                        Text(`💡 ${q.hint}`)
                          .fontSize(12)
                          .fontColor('#8a94a6')
                          .width('100%')
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .padding(8)
                    .borderRadius(8)
                    .backgroundColor('#ffffff')
                    .width('100%')
                  }, (q: QuizQuestion) => q.id)
                  TextArea({ text: this.similarInput, placeholder: '写下你的答案…' })
                    .fontSize(14)
                    .height(80)
                    .width('100%')
                    .onChange((v: string) => {
                      this.similarInput = v;
                    })
                  Button('提交判分')
                    .width('100%')
                    .height(38)
                    .backgroundColor('#1677ff')
                    .onClick(() => {
                      this.submitSimilar();
                    })
                  if (this.similarResult.length > 0) {
                    Text(this.similarResult)
                      .fontSize(13)
                      .fontColor('#d48806')
                      .width('100%')
                  }
                } else {
                  Text('暂无相似题，请稍后重试')
                    .fontSize(13)
                    .fontColor('#b0b9c9')
                    .width('100%')
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding(10)
              .borderRadius(10)
              .backgroundColor('#f5f8ff')
              .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .borderRadius(12)
          .backgroundColor('#ffffff')
          .width('100%')

          // ---------- 底部操作 ----------
          Row({ space: 8 }) {
            Button('AI 讲解本节点')
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .backgroundColor('#1677ff')
              .onClick(() => {
                this.aiExplain();
              })
            Button(this.showQuiz ? '收起自测' : '快速自测')
              .layoutWeight(1)
              .height(42)
              .fontSize(14)
              .fontColor('#1677ff')
              .backgroundColor('#ffffff')
              .border({ width: 1, color: '#1677ff' })
              .onClick(() => {
                this.showQuiz = !this.showQuiz;
                this.quizResult = '';
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }
}
