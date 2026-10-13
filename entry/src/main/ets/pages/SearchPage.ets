/**
 * 全局搜索与 AI 问答（v2.0 一起学 · 搜索与问答；Wave 4 升级为跨源搜索）。
 * 一次关键词同时检索：我的导图（标题/学科）→ 全部导图节点（含非当前导图）→ 错题本 → 市场（社区精选 + 我的发布）；
 * AI 问答：基于当前导图内容的 Mock 关键词检索问答。
 */
import { promptAction } from '@kit.ArkUI';
import { MindMapStore, MindMapSummary } from '../services/MindMapStore';
import { MindMap } from '../model/MindMap';
import { ModelFailure, NodeType } from '../model/Constants';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { MarketService } from '../services/MarketService';
import { getMarketMindMap, listMarket, MarketItem } from '../model/MarketTemplates';
import { QAService, QAAnswer } from '../services/QAService';

interface MapHit {
  id: string;
  title: string;
  subject: string;
}

interface NodeHit {
  mapId: string;
  mapTitle: string;
  nodeId: string;
  nodeText: string;
  nodeType: NodeType;
}

interface WrongHit {
  id: string;
  mapId: string;
  nodeId: string;
  nodeText: string;
  question: string;
}

interface MarketHit {
  id: string;
  title: string;
  subject: string;
  author: string;
  /** 是否来自「我的发布」 */
  mine: boolean;
}

@Component
export struct SearchPage {
  @State query: string = '';
  @State mapHits: MapHit[] = [];
  @State nodeHits: NodeHit[] = [];
  @State wrongHits: WrongHit[] = [];
  @State marketHits: MarketHit[] = [];
  @State searching: boolean = false;
  @State qaQuestion: string = '';
  @State qaAnswer: string = '';
  @State qaRefs: string[] = [];

  private async doSearch(): Promise<void> {
    const q = this.query.trim();
    this.mapHits = [];
    this.nodeHits = [];
    this.wrongHits = [];
    this.marketHits = [];
    if (q.length === 0) {
      return;
    }
    this.searching = true;
    const lower = q.toLowerCase();
    const store = MindMapStore.getInstance();
    // 1) 我的导图（标题 / 学科）
    const summaries: MindMapSummary[] = store.list();
    for (let i = 0; i < summaries.length; i++) {
      const s = summaries[i];
      if (s.title.toLowerCase().includes(lower) || s.subject.toLowerCase().includes(lower)) {
        this.mapHits.push({ id: s.id, title: s.title, subject: s.subject });
      }
    }
    // 2) 全部导图节点（当前导图 + 其余导图只读加载）
    const snap = store.currentSnapshot();
    if (snap) {
      this.collectNodes(snap, lower);
    }
    for (let i = 0; i < summaries.length; i++) {
      const s = summaries[i];
      if (s.damaged) {
        continue;
      }
      if (snap && s.id === snap.id) {
        continue;
      }
      const map = await store.peekMap(s.id);
      if (map) {
        this.collectNodes(map, lower);
      }
    }
    // 3) 错题本
    const wrongs = store.getWrongItems();
    for (let i = 0; i < wrongs.length; i++) {
      const w = wrongs[i];
      if (w.nodeText.toLowerCase().includes(lower) || w.question.toLowerCase().includes(lower) || w.answer.toLowerCase().includes(lower)) {
        this.wrongHits.push({ id: w.id, mapId: w.mapId, nodeId: w.nodeId, nodeText: w.nodeText, question: w.question });
      }
    }
    // 4) 市场（社区精选 + 我的发布）
    const builtins: MarketItem[] = listMarket();
    for (let i = 0; i < builtins.length; i++) {
      const it = builtins[i];
      if (it.title.toLowerCase().includes(lower) || it.subject.toLowerCase().includes(lower) || it.summary.toLowerCase().includes(lower)) {
        this.marketHits.push({ id: it.id, title: it.title, subject: it.subject, author: it.author, mine: false });
      }
    }
    await MarketService.getInstance().init();
    const mine = MarketService.getInstance().listUser();
    for (let i = 0; i < mine.length; i++) {
      const it = mine[i];
      if (it.title.toLowerCase().includes(lower) || it.subject.toLowerCase().includes(lower) || it.summary.toLowerCase().includes(lower)) {
        this.marketHits.push({ id: it.id, title: it.title, subject: it.subject, author: it.author, mine: true });
      }
    }
    this.searching = false;
  }

  /** 收集一张导图内命中的节点 */
  private collectNodes(map: MindMap, lower: string): void {
    for (let i = 0; i < map.nodes.length; i++) {
      const n = map.nodes[i];
      if (n.text.toLowerCase().includes(lower) || n.detail.toLowerCase().includes(lower)) {
        this.nodeHits.push({ mapId: map.id, mapTitle: map.title, nodeId: n.id, nodeText: n.text, nodeType: n.type });
      }
    }
  }

  private openMap(id: string): void {
    MindMapStore.getInstance().openMapById(id).then((ok: boolean) => {
      if (ok) {
        DeepLinkRouter.push('MindMapPage');
      } else {
        promptAction.showToast({ message: '打开失败' });
      }
    });
  }

  /** 打开指定导图的指定节点 */
  private openNode(hit: NodeHit): void {
    MindMapStore.getInstance().openMapById(hit.mapId).then((ok: boolean) => {
      if (ok) {
        DeepLinkRouter.route(hit.nodeId, hit.nodeType, hit.nodeText);
      } else {
        promptAction.showToast({ message: '打开失败' });
      }
    });
  }

  /** 导入市场条目（社区精选 / 我的发布） */
  private importMarket(hit: MarketHit): void {
    let json = '';
    if (hit.mine) {
      json = MarketService.getInstance().getPayload(hit.id);
    } else {
      const map = getMarketMindMap(hit.id);
      json = map ? map.toJson() : '';
    }
    if (json.length === 0) {
      promptAction.showToast({ message: '内容已失效' });
      return;
    }
    const res = MindMapStore.getInstance().importAsNew(json);
    if (res.ok) {
      promptAction.showToast({ message: `已导入：${hit.title}` });
      DeepLinkRouter.push('MindMapPage');
    } else {
      const fail: ModelFailure = res as ModelFailure;
      promptAction.showToast({ message: `导入失败：${fail.message}` });
    }
  }

  private doAsk(): void {
    const snap = MindMapStore.getInstance().currentSnapshot();
    const ans: QAAnswer = QAService.getInstance().ask(this.qaQuestion, snap);
    this.qaAnswer = ans.answer;
    this.qaRefs = ans.refs;
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Text('全局搜索')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a2333')
          .alignSelf(ItemAlign.Start)
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索导图 / 节点 / 错题 / 市场', text: this.query })
            .layoutWeight(1)
            .height(44)
            .onChange((v: string) => {
              this.query = v;
            })
            .onSubmit(() => {
              this.doSearch();
            })
          Button(this.searching ? '搜索中' : '搜索')
            .height(44)
            .backgroundColor('#1677ff')
            .enabled(!this.searching)
            .onClick(() => {
              this.doSearch();
            })
        }
        .width('100%')

        if (this.mapHits.length > 0) {
          this.sectionTitle(`我的导图（${this.mapHits.length}）`)
          List() {
            ForEach(this.mapHits, (h: MapHit) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(h.title)
                      .fontSize(15)
                      .fontColor('#1a2333')
                    Text(h.subject)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button('打开')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#1677ff')
                    .onClick(() => {
                      this.openMap(h.id);
                    })
                }
                .padding(10)
              }
            }, (h: MapHit) => h.id)
          }
          .width('100%')
          .height(110)
        }

        if (this.nodeHits.length > 0) {
          this.sectionTitle(`知识点（${this.nodeHits.length}）`)
          List() {
            ForEach(this.nodeHits, (h: NodeHit) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(h.nodeText)
                      .fontSize(15)
                      .fontColor('#1a2333')
                    Text(`来自《${h.mapTitle}》`)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button('打开')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#13c2c2')
                    .onClick(() => {
                      this.openNode(h);
                    })
                }
                .padding(10)
              }
            }, (h: NodeHit) => `${h.mapId}_${h.nodeId}`)
          }
          .width('100%')
          .height(140)
        }

        if (this.wrongHits.length > 0) {
          this.sectionTitle(`错题本（${this.wrongHits.length}）`)
          List() {
            ForEach(this.wrongHits, (h: WrongHit) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(h.nodeText)
                      .fontSize(14)
                      .fontColor('#1a2333')
                    Text(h.question)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button('去复习')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#fa8c16')
                    .onClick(() => {
                      this.openNode({ mapId: h.mapId, mapTitle: '', nodeId: h.nodeId, nodeText: h.nodeText, nodeType: NodeType.GENERAL });
                    })
                }
                .padding(10)
              }
            }, (h: WrongHit) => h.id)
          }
          .width('100%')
          .height(120)
        }

        if (this.marketHits.length > 0) {
          this.sectionTitle(`市场（${this.marketHits.length}）`)
          List() {
            ForEach(this.marketHits, (h: MarketHit) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 3 }) {
                    Text(h.title)
                      .fontSize(14)
                      .fontColor('#1a2333')
                    Text(`${h.subject} · ${h.author}${h.mine ? ' · 我的发布' : ''}`)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button('导入')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#52c41a')
                    .onClick(() => {
                      this.importMarket(h);
                    })
                }
                .padding(10)
              }
            }, (h: MarketHit) => `${h.mine ? 'mine' : 'mkt'}_${h.id}`)
          }
          .width('100%')
          .height(120)
        }

        if (this.query.trim().length > 0 && !this.searching && this.mapHits.length === 0 && this.nodeHits.length === 0 && this.wrongHits.length === 0 && this.marketHits.length === 0) {
          Text('没有找到相关内容，换个关键词试试')
            .fontSize(13)
            .fontColor('#b0b9c9')
            .width('100%')
        }

        Divider()
          .color('#eef2f7')
          .width('100%')

        Text('AI 问答（基于当前导图）')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1a2333')
          .alignSelf(ItemAlign.Start)
        Row({ space: 8 }) {
          TextInput({ placeholder: '问导图里的任何内容', text: this.qaQuestion })
            .layoutWeight(1)
            .height(44)
            .onChange((v: string) => {
              this.qaQuestion = v;
            })
            .onSubmit(() => {
              this.doAsk();
            })
          Button('提问')
            .height(44)
            .backgroundColor('#722ed1')
            .onClick(() => {
              this.doAsk();
            })
        }
        .width('100%')

        if (this.qaAnswer.length > 0) {
          Column({ space: 8 }) {
            Text(this.qaAnswer)
              .fontSize(14)
              .fontColor('#1a2333')
              .width('100%')
            if (this.qaRefs.length > 0) {
              Text(`引用：${this.qaRefs.join('、')}`)
                .fontSize(12)
                .fontColor('#8a94a6')
                .width('100%')
            }
          }
          .padding(12)
          .backgroundColor('#f9f0ff')
          .borderRadius(12)
          .width('100%')
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
    }
    .title('搜索')
    .width('100%')
    .height('100%')
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor('#1a2333')
      .alignSelf(ItemAlign.Start)
      .width('100%')
  }
}
