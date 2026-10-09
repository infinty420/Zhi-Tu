/**
 * MindMapPage —— 思维导图主界面（NavDestination）。
 * 组装工具栏（布局/主题/重新生成/导出）+ MindMapCanvas 画布 + 节点编辑栏 + AgentPanel。
 */
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { Layout, MasteryLevel, NodeShape, NodeType, THEMES } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MindNode, NodeLink } from '../model/MindNode';
import { MindMapCanvas, MindMapCanvasController } from '../components/MindMapCanvas';
import { AgentPanel } from '../components/AgentPanel';
import { AIResult, AIResultFailure, TutorChunk, TutorMode, TutorRequest, TutorResponse } from '../services/AIService';
import { MindMapStore } from '../services/MindMapStore';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { AIConfig } from '../services/AIConfig';
import { AIServiceFactory } from '../services/AIServiceFactory';
import { ExportService } from '../services/ExportService';
import { Logger } from '../utils/Logger';

@Component
export struct MindMapPage {
  @State statusBarHeight: number = 0;
  @State mapSnapshot: MindMap | undefined = undefined;
  @State selectedId: string = '';
  @State agentVisible: boolean = false;
  @State showRename: boolean = false;
  @State showDetail: boolean = false;
  @State showStyle: boolean = false;
  @State renameText: string = '';
  @State detailText: string = '';
  @State showRich: boolean = false;
  @State formulaText: string = '';
  @State tagsText: string = '';
  @State linkTitle: string = '';
  @State linkUrl: string = '';
  @State generating: boolean = false;
  @State tutorVisible: boolean = false;
  @State tutorText: string = '';
  @State tutorLoading: boolean = false;
  @State tutorModeLabel: string = '';
  private store: MindMapStore = MindMapStore.getInstance();
  private canvasController: MindMapCanvasController = new MindMapCanvasController();
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = this.store.subscribe((snapshot) => {
      this.mapSnapshot = snapshot;
      this.syncSelected();
    });
    const snap = this.store.currentSnapshot();
    this.mapSnapshot = snap;
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private syncSelected(): void {
    if (!this.mapSnapshot) {
      this.selectedId = '';
      return;
    }
    if (this.selectedId.length > 0 && !this.mapSnapshot.findNode(this.selectedId)) {
      this.selectedId = '';
    }
  }

  private get selectedNode(): MindNode | undefined {
    if (!this.mapSnapshot || this.selectedId.length === 0) {
      return undefined;
    }
    return this.mapSnapshot.findNode(this.selectedId);
  }

  private typeLabel(type: NodeType): string {
    if (type === NodeType.MATH) {
      return '数学';
    } else if (type === NodeType.PHYSICS) {
      return '物理';
    } else if (type === NodeType.ENGLISH) {
      return '英语';
    }
    return '普通';
  }

  private async regenerate(restructure: boolean): Promise<void> {
    if (this.generating) {
      return;
    }
    const snap = this.mapSnapshot;
    if (!snap) {
      return;
    }
    this.generating = true;
    promptAction.showToast({ message: restructure ? '正在换一种结构生成…' : '正在重新生成…' });
    try {
      const config = AIConfig.load();
      const svc = AIServiceFactory.create(config);
      const query = restructure ? `${snap.title}（换一种结构）` : snap.title;
      const res = await svc.generateMindMap(
        { query: query, subject: snap.subject, book: snap.book },
        () => {
        });
      if (res.ok) {
        const imported = this.store.importAsNew(res.data.map.toJson());
        if (imported.ok) {
          promptAction.showToast({ message: '已生成新导图' });
        }
      } else {
        const failure: AIResultFailure = res as AIResultFailure;
        promptAction.showToast({ message: `生成失败：${failure.error.message}` });
      }
    } catch (err) {
      Logger.aiRequest('MindMapPage', 'failed', JSON.stringify(err));
      promptAction.showToast({ message: '生成失败，请重试' });
    }
    this.generating = false;
  }

  private async exportImage(): Promise<void> {
    const pixel = this.canvasController.capture();
    if (!pixel) {
      promptAction.showToast({ message: '画布尚未就绪' });
      return;
    }
    const title = this.mapSnapshot ? this.mapSnapshot.title : 'mindmap';
    const r = await ExportService.savePixelMap(pixel, title);
    if (r.path.length > 0) {
      promptAction.showToast({ message: `图片已保存：${r.path}` });
    } else {
      promptAction.showToast({ message: '导出失败，请检查存储空间' });
    }
  }

  private async exportJson(): Promise<void> {
    const snap = this.mapSnapshot;
    if (!snap) {
      return;
    }
    const json = ExportService.exportMapToJson(snap);
    const r = await ExportService.saveJsonToFiles(json, snap.title);
    if (r.path.length > 0) {
      promptAction.showToast({ message: `JSON 已导出：${r.path}` });
    } else {
      promptAction.showToast({ message: '导出失败，请检查存储空间' });
    }
  }

  private confirmDelete(): void {
    const node = this.selectedNode;
    const snap = this.mapSnapshot;
    if (!node || !snap) {
      return;
    }
    if (node.parentId === null) {
      promptAction.showToast({ message: '根节点不可删除' });
      return;
    }
    const hasChildren = node.childrenOf(snap).length > 0;
    if (!hasChildren) {
      this.store.removeNode(node.id, false);
      return;
    }
    AlertDialog.show({
      message: '该节点含子节点，删除将级联删除其全部子节点，确认删除？',
      primaryButton: {
        value: '删除',
        fontColor: '#f5222d',
        action: () => {
          this.store.removeNode(node.id, true);
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  private toggleTheme(): void {
    const snap = this.mapSnapshot;
    if (!snap) {
      return;
    }
    const idx = THEMES.indexOf(snap.theme);
    const next = THEMES[(idx + 1) % THEMES.length];
    this.store.setTheme(next);
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          // 工具栏
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Button($r('app.string.nav_back'))
                .height(32)
                .fontSize(14)
                .backgroundColor('#1677ff')
                .onClick(() => {
                  DeepLinkRouter.pop();
                })
              Text(this.mapSnapshot ? this.mapSnapshot.title : $r('app.string.map_title'))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Button($r('app.string.study_mode'))
                .height(32)
                .fontSize(14)
                .backgroundColor('#13c2c2')
                .onClick(() => {
                  if (this.mapSnapshot) {
                    DeepLinkRouter.pushWithParam('StudyPage', this.mapSnapshot.id);
                  } else {
                    DeepLinkRouter.pop();
                  }
                })
              Button('AI 助手')
                .height(32)
                .fontSize(14)
                .backgroundColor(this.agentVisible ? '#faad14' : '#1677ff')
                .onClick(() => {
                  this.agentVisible = !this.agentVisible;
                })
            }
            .width('100%')

            Scroll() {
              Row({ space: 6 }) {
                this.layoutChip($r('app.string.map_layout_tree_h'), this.mapSnapshot !== undefined && this.mapSnapshot.layout === Layout.TREE_H, () => {
                  this.store.setLayout(Layout.TREE_H);
                })
                this.layoutChip($r('app.string.map_layout_tree_v'), this.mapSnapshot !== undefined && this.mapSnapshot.layout === Layout.TREE_V, () => {
                  this.store.setLayout(Layout.TREE_V);
                })
                this.layoutChip($r('app.string.map_layout_radial'), this.mapSnapshot !== undefined && this.mapSnapshot.layout === Layout.RADIAL, () => {
                  this.store.setLayout(Layout.RADIAL);
                })
                Button($r('app.string.map_theme'))
                  .height(28)
                  .fontSize(13)
                  .backgroundColor('#722ed1')
                  .onClick(() => {
                    this.toggleTheme();
                  })
                Button($r('app.string.home_restructure'))
                  .height(28)
                  .fontSize(13)
                  .backgroundColor('#00b96b')
                  .enabled(!this.generating)
                  .onClick(() => {
                    this.regenerate(true);
                  })
                Button($r('app.string.home_retry'))
                  .height(28)
                  .fontSize(13)
                  .backgroundColor('#eb2f96')
                  .enabled(!this.generating)
                  .onClick(() => {
                    this.regenerate(false);
                  })
                Button($r('app.string.map_export_image'))
                  .height(28)
                  .fontSize(13)
                  .backgroundColor('#fa8c16')
                  .onClick(() => {
                    this.exportImage();
                  })
                Button($r('app.string.map_export_json'))
                  .height(28)
                  .fontSize(13)
                  .backgroundColor('#8a94a6')
                  .onClick(() => {
                    this.exportJson();
                  })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .padding(8)
          .backgroundColor('#ffffff')
          .width('100%')

          // 画布
          if (this.mapSnapshot) {
            Column() {
              MindMapCanvas({
                mapId: this.mapSnapshot.id,
                controller: this.canvasController,
                onSelectNode: (id: string) => {
                  this.selectedId = id;
                },
                onEnterNode: (id: string) => {
                  this.onEnterNode(id);
                }
              })
                .layoutWeight(1)

              if (this.selectedNode !== undefined) {
                this.editBar(this.selectedNode!)
              }
            }
            .layoutWeight(1)
          } else {
            Column() {
              Blank()
              Text('当前没有可编辑的导图\n请返回首页生成一张')
                .fontSize(15)
                .fontColor('#8a94a6')
                .textAlign(TextAlign.Center)
              Blank()
            }
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')

        // Agent 对话抽屉
        if (this.agentVisible) {
          Column() {
            AgentPanel({
              mapSnapshot: this.mapSnapshot,
              onClose: () => {
                this.agentVisible = false;
              }
            })
          }
          .width('100%')
          .height('62%')
          .position({ x: 0, y: '38%' })
          .backgroundColor('#ffffff')
          .borderRadius({ topLeft: 16, topRight: 16 })
          .shadow({ radius: 20, color: '#66000000', offsetY: -4 })
        }

        // 编辑弹窗
        if (this.showRename) {
          this.renameDialog()
        }
        if (this.showDetail) {
          this.detailDialog()
        }
        if (this.showStyle) {
          this.styleDialog()
        }
        if (this.showRich) {
          this.richDialog()
        }
        if (this.tutorVisible) {
          this.tutorDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }

  @Builder
  layoutChip(text: Resource, active: boolean, onTap: () => void) {
    Text(text)
      .fontSize(13)
      .fontColor(active ? '#ffffff' : '#1a2333')
      .backgroundColor(active ? '#1677ff' : '#e6f4ff')
      .borderRadius(16)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .height(28)
      .onClick(onTap)
  }

  @Builder
  editBar(node: MindNode) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(node.text)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a2333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.typeLabel(node.type))
          .fontSize(12)
          .fontColor('#1677ff')
          .backgroundColor('#e6f4ff')
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      Row({ space: 6 }) {
        Button($r('app.string.map_add_child'))
          .height(30)
          .fontSize(13)
          .backgroundColor('#1677ff')
          .onClick(() => {
            this.store.addNode(this.selectedId, '新分支', NodeType.GENERAL);
          })
        Button($r('app.string.map_rename'))
          .height(30)
          .fontSize(13)
          .backgroundColor('#00b96b')
          .onClick(() => {
            this.renameText = node.text;
            this.showRename = true;
          })
        Button($r('app.string.map_edit_detail'))
          .height(30)
          .fontSize(13)
          .backgroundColor('#722ed1')
          .onClick(() => {
            this.detailText = node.detail;
            this.showDetail = true;
          })
        Button($r('app.string.map_edit_style'))
          .height(30)
          .fontSize(13)
          .backgroundColor('#fa8c16')
          .onClick(() => {
            this.showStyle = true;
          })
        Button(node.collapsed ? $r('app.string.map_expand') : $r('app.string.map_collapse'))
          .height(30)
          .fontSize(13)
          .backgroundColor('#8a94a6')
          .onClick(() => {
            this.store.setCollapsed(this.selectedId, !node.collapsed);
          })
        Button($r('app.string.map_delete'))
          .height(30)
          .fontSize(13)
          .backgroundColor('#f5222d')
          .onClick(() => {
            this.confirmDelete();
          })
        if (node.type !== NodeType.GENERAL) {
          Button($r('app.string.map_enter'))
            .height(30)
            .fontSize(13)
            .backgroundColor('#eb2f96')
            .onClick(() => {
              this.onEnterNode(node.id);
            })
        }
        Button($r('app.string.map_rich'))
          .height(30)
          .fontSize(13)
          .backgroundColor('#722ed1')
          .onClick(() => {
            this.openRich();
          })
      }
      Row({ space: 6 }) {
        this.typeChip($r('app.string.map_type_general'), node.type === NodeType.GENERAL, () => {
          this.store.retypeNode(this.selectedId, NodeType.GENERAL);
        })
        this.typeChip($r('app.string.map_type_math'), node.type === NodeType.MATH, () => {
          this.store.retypeNode(this.selectedId, NodeType.MATH);
        })
        this.typeChip($r('app.string.map_type_physics'), node.type === NodeType.PHYSICS, () => {
          this.store.retypeNode(this.selectedId, NodeType.PHYSICS);
        })
        this.typeChip($r('app.string.map_type_english'), node.type === NodeType.ENGLISH, () => {
            this.store.retypeNode(this.selectedId, NodeType.ENGLISH);
          })
        this.typeChip($r('app.string.map_type_history'), node.type === NodeType.HISTORY, () => {
          this.store.retypeNode(this.selectedId, NodeType.HISTORY);
        })
        this.typeChip($r('app.string.map_type_geo'), node.type === NodeType.GEO, () => {
          this.store.retypeNode(this.selectedId, NodeType.GEO);
        })
        this.typeChip($r('app.string.map_type_chem'), node.type === NodeType.CHEM, () => {
          this.store.retypeNode(this.selectedId, NodeType.CHEM);
        })
        this.typeChip($r('app.string.map_type_bio'), node.type === NodeType.BIO, () => {
          this.store.retypeNode(this.selectedId, NodeType.BIO);
        })
        Text($r('app.string.mastery_label'))
          .fontSize(12)
          .fontColor('#8a94a6')
          .margin({ top: 4 })
        Row({ space: 6 }) {
          this.masteryChip($r('app.string.mastery_known'), node.mastery === MasteryLevel.KNOWN, '#52c41a', () => {
            this.store.setMastery(this.selectedId, MasteryLevel.KNOWN);
          })
          this.masteryChip($r('app.string.mastery_fuzzy'), node.mastery === MasteryLevel.FUZZY, '#faad14', () => {
            this.store.setMastery(this.selectedId, MasteryLevel.FUZZY);
          })
          this.masteryChip($r('app.string.mastery_unknown'), node.mastery === MasteryLevel.UNKNOWN, '#f5222d', () => {
            this.store.setMastery(this.selectedId, MasteryLevel.UNKNOWN);
          })
        }
        // 逐点辅导（v1.2 AI 教学）
        Row({ space: 6 }) {
          Button($r('app.string.tutor_explain'))
            .height(30)
            .fontSize(12)
            .backgroundColor('#1677ff')
            .onClick(() => {
              this.openTutor(node, 'explain');
            })
          Button($r('app.string.tutor_similar'))
            .height(30)
            .fontSize(12)
            .backgroundColor('#13c2c2')
            .onClick(() => {
              this.openTutor(node, 'similar');
            })
          Button($r('app.string.tutor_rephrase'))
            .height(30)
            .fontSize(12)
            .backgroundColor('#722ed1')
            .onClick(() => {
              this.openTutor(node, 'rephrase');
            })
        }
        .margin({ top: 6 })
      }
    }
    .padding(10)
    .backgroundColor('#ffffff')
    .border({ width: 1, color: '#e6ebf2' })
    .borderRadius(12)
    .shadow({ radius: 12, color: '#1a233314', offsetY: -2 })
    .width('100%')
  }

  @Builder
  typeChip(label: Resource, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(12)
      .fontColor(active ? '#ffffff' : '#1a2333')
      .backgroundColor(active ? '#722ed1' : '#f3f8ff')
      .borderRadius(12)
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .onClick(onTap)
  }

  @Builder
  masteryChip(label: Resource, active: boolean, color: string, onTap: () => void) {
    Text(label)
      .fontSize(12)
      .fontColor(active ? '#ffffff' : '#1a2333')
      .backgroundColor(active ? color : '#f3f8ff')
      .borderRadius(12)
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .onClick(onTap)
  }

  private onEnterNode(id: string): void {
    const snap = this.mapSnapshot;
    if (!snap) {
      return;
    }
    const node = snap.findNode(id);
    if (!node) {
      return;
    }
    const payload = node.detail && node.detail.length > 0 ? `${node.text}：${node.detail}` : node.text;
    DeepLinkRouter.route(id, node.type, payload);
  }

  @Builder
  renameDialog() {
    Column({ space: 12 }) {
      Text('重命名节点')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      TextInput({ placeholder: '请输入新名称', text: this.renameText })
        .height(44)
        .onChange((value: string) => {
          this.renameText = value;
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#8a94a6')
          .onClick(() => {
            this.showRename = false;
          })
        Button('确定')
          .layoutWeight(1)
          .backgroundColor('#1677ff')
          .onClick(() => {
            const text = this.renameText.trim();
            if (text.length > 0) {
              this.store.renameNode(this.selectedId, text);
            }
            this.showRename = false;
          })
      }
    }
    .padding(16)
    .width('86%')
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .position({ x: '7%', y: '35%' })
  }

  @Builder
  detailDialog() {
    Column({ space: 12 }) {
      Text('要点详情')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      TextArea({ placeholder: '填写节点要点/备注，深链回填内容将追加到此处', text: this.detailText })
        .height(140)
        .onChange((value: string) => {
          this.detailText = value;
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#8a94a6')
          .onClick(() => {
            this.showDetail = false;
          })
        Button('保存')
          .layoutWeight(1)
          .backgroundColor('#1677ff')
          .onClick(() => {
            this.store.updateDetail(this.selectedId, this.detailText, 'replace');
            this.showDetail = false;
          })
      }
    }
    .padding(16)
    .width('86%')
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .position({ x: '7%', y: '30%' })
  }

  /** 打开富内容编辑器：回填当前节点富内容到编辑字段 */
  private openRich(): void {
    const node = this.selectedNode;
    if (!node) {
      return;
    }
    this.formulaText = node.rich.formula;
    this.tagsText = node.rich.tags.join('，');
    this.linkTitle = '';
    this.linkUrl = '';
    this.showRich = true;
  }

  /** 打开 AI 逐点辅导（v1.2） */
  private openTutor(node: MindNode, mode: TutorMode): void {
    this.tutorModeLabel = mode === 'explain' ? '讲细一点' : (mode === 'similar' ? '出两道相似题' : '换个说法');
    this.tutorText = '';
    this.tutorLoading = true;
    this.tutorVisible = true;
    const config = AIConfig.load();
    const svc = AIServiceFactory.create(config);
    svc.tutorNode(
      { nodeText: node.text, nodeDetail: node.detail, nodeType: node.type.toString(), mode: mode },
      (chunk: TutorChunk) => {
        if (!chunk.done) {
          this.tutorText += chunk.text;
        } else {
          this.tutorLoading = false;
        }
      }
    ).then((res: AIResult<TutorResponse>) => {
      if (!res.ok) {
        const failure: AIResultFailure = res as AIResultFailure;
        promptAction.showToast({ message: `辅导生成失败：${failure.error.message}` });
        this.tutorLoading = false;
      }
    }).catch((err: Error) => {
      Logger.aiRequest('MindMapPage', 'tutor failed', JSON.stringify(err));
      this.tutorLoading = false;
    });
  }

  @Builder
  richDialog() {
    Column({ space: 10 }) {
      Text('节点富内容')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Text('公式（如 x^2+1）')
        .fontSize(13)
        .fontColor('#8a94a6')
        .alignSelf(ItemAlign.Start)
      TextInput({ placeholder: 'LaTeX 风格公式', text: this.formulaText })
        .height(38)
        .onChange((value: string) => {
          this.formulaText = value;
        })
      Text('标签（逗号分隔，如 易错，中考高频）')
        .fontSize(13)
        .fontColor('#8a94a6')
        .alignSelf(ItemAlign.Start)
      TextInput({ placeholder: '标签', text: this.tagsText })
        .height(38)
        .onChange((value: string) => {
          this.tagsText = value;
        })
      Text('添加超链接')
        .fontSize(13)
        .fontColor('#8a94a6')
        .alignSelf(ItemAlign.Start)
      Row({ space: 6 }) {
        TextInput({ placeholder: '标题', text: this.linkTitle })
          .layoutWeight(1)
          .height(36)
          .onChange((value: string) => {
            this.linkTitle = value;
          })
        TextInput({ placeholder: 'URL', text: this.linkUrl })
          .layoutWeight(1)
          .height(36)
          .onChange((value: string) => {
            this.linkUrl = value;
          })
        Button('+')
          .height(36)
          .onClick(() => {
            this.addRichLink();
          })
      }
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor('#8a94a6')
          .onClick(() => {
            this.showRich = false;
          })
        Button('保存')
          .layoutWeight(1)
          .backgroundColor('#1677ff')
          .onClick(() => {
            this.saveRich();
          })
      }
    }
    .padding(16)
    .width('88%')
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .position({ x: '6%', y: '22%' })
  }

  private addRichLink(): void {
    const node = this.selectedNode;
    if (!node || this.linkTitle.trim().length === 0) {
      return;
    }
    const link: NodeLink = { title: this.linkTitle.trim(), url: this.linkUrl.trim() };
    const links = node.rich.links;
    links.push(link);
    this.store.updateRich(this.selectedId, {
      images: node.rich.images,
      formula: this.formulaText,
      links: links,
      tags: this.parseTags(this.tagsText)
    });
    this.linkTitle = '';
    this.linkUrl = '';
  }

  private parseTags(text: string): string[] {
    if (text.trim().length === 0) {
      return [];
    }
    const parts = text.split(/[，,]/);
    const tags: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const t = parts[i].trim();
      if (t.length > 0) {
        tags.push(t);
      }
    }
    return tags;
  }

  private saveRich(): void {
    const node = this.selectedNode;
    if (!node) {
      this.showRich = false;
      return;
    }
    this.store.updateRich(this.selectedId, {
      images: node.rich.images,
      formula: this.formulaText,
      links: node.rich.links,
      tags: this.parseTags(this.tagsText)
    });
    this.showRich = false;
  }

  @Builder
  tutorDialog() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(`AI 逐点辅导 · ${this.tutorModeLabel}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button('关闭')
          .height(32)
          .fontSize(13)
          .backgroundColor('#8a94a6')
          .onClick(() => {
            this.tutorVisible = false;
          })
      }
      .width('100%')
      if (this.tutorLoading) {
        Row({ space: 8 }) {
          Text('正在生成讲解…')
            .fontSize(14)
            .fontColor('#8a94a6')
          if (this.tutorText.length > 0) {
            Text(this.tutorText)
              .fontSize(14)
              .fontColor('#1a2333')
              .width('100%')
              .maxLines(3)
          }
        }
        .width('100%')
      } else {
        Scroll() {
          Text(this.tutorText)
            .fontSize(15)
            .fontColor('#1a2333')
            .width('100%')
            .lineSpacing(LengthMetrics.fp(4))
        }
        .height(280)
        .width('100%')
      }
    }
    .padding(16)
    .width('90%')
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .position({ x: '5%', y: '18%' })
  }

  @Builder
  styleDialog() {
    Column({ space: 12 }) {
      Text('节点样式')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Text('颜色')
        .fontSize(14)
        .fontColor('#8a94a6')
      Row({ space: 10 }) {
        ForEach(['#1677ff', '#00b96b', '#fa8c16', '#722ed1', '#eb2f96', '#13c2c2'], (c: string) => {
          Circle({ width: 34, height: 34 })
            .fill(c)
            .stroke('#e6ebf2')
            .strokeWidth(2)
            .onClick(() => {
              this.store.restyleNode(this.selectedId, { color: c });
            })
        }, (c: string) => c)
      }
      Text('形状')
        .fontSize(14)
        .fontColor('#8a94a6')
      Row({ space: 10 }) {
        this.shapeChip('矩形', NodeShape.RECT)
        this.shapeChip('圆角矩形', NodeShape.ROUND)
        this.shapeChip('椭圆', NodeShape.ELLIPSE)
      }
      Button('完成')
        .width('100%')
        .backgroundColor('#1677ff')
        .onClick(() => {
          this.showStyle = false;
        })
    }
    .padding(16)
    .width('86%')
    .backgroundColor('#ffffff')
    .borderRadius(16)
    .position({ x: '7%', y: '25%' })
  }

  @Builder
  shapeChip(label: string, shape: NodeShape) {
    Text(label)
      .fontSize(13)
      .backgroundColor('#f3f8ff')
      .borderRadius(8)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .onClick(() => {
        this.store.restyleNode(this.selectedId, { shape: shape });
      })
  }
}