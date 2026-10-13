/**
 * HomePage —— 首页（创作分区）：知识点输入与导图生成。
 * Wave 9：下沉为「首页/创作」Tab，底部 TabBar 由 Index 统一控制（tabKey / onTabChange 注入）。
 * 学习中心、每日打卡、复习优先级、一起学等入口已拆分到对应分区 Hub 页。
 */
import { promptAction } from '@kit.ArkUI';
import { SUBJECTS, NodeType } from '../model/Constants';
import { getTemplateMindMap, listTemplates, TemplateItem } from '../model/Templates';
import { AIConfig } from '../services/AIConfig';
import { AIResultFailure } from '../services/AIService';
import { AIServiceFactory } from '../services/AIServiceFactory';
import { MindMapStore } from '../services/MindMapStore';
import { StudyInsightService } from '../services/StudyInsightService';
import { ContinueService, ContinueSession } from '../services/ContinueService';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { Logger } from '../utils/Logger';
import { BottomTabBar } from '../components/BottomTabBar';

@Component
export struct HomePage {
  @Prop tabKey: number = 0;
  onTabChange: (index: number) => void = () => {};

  @State query: string = '';
  @State selectedSubjectIndex: number = 0;
  @State book: string = '';
  @State generating: boolean = false;
  @State streamText: string = '';
  @State hasMap: boolean = false;

  // 为你推荐（按薄弱点推荐下一个该学的节点）
  @State recommendId: string = '';
  @State recommendText: string = '';
  @State recommendType: NodeType = NodeType.GENERAL;
  @State recommendReason: string = '';

  // Wave 12：跨设备续学（上次学习会话）
  @State continueSession: ContinueSession | undefined = undefined;

  private store: MindMapStore = MindMapStore.getInstance();
  private templates: TemplateItem[] = listTemplates();
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = this.store.subscribe(() => {
      this.refreshHub();
    });
    this.refreshHub();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private refreshHub(): void {
    this.hasMap = this.store.hasCurrent();
    this.continueSession = ContinueService.getInstance().get();
    const snap = this.store.currentSnapshot();
    const next = snap ? StudyInsightService.recommendNext(snap, this.store.getWrongItems()) : undefined;
    if (next) {
      this.recommendId = next.nodeId;
      this.recommendText = next.nodeText;
      this.recommendType = next.nodeType;
      this.recommendReason = next.reason;
    } else {
      this.recommendId = '';
      this.recommendText = '';
      this.recommendReason = '';
    }
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          // 品牌区
          Text($r('app.string.home_title'))
            .fontSize($r('app.float.large_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
            .width('100%')
          Text($r('app.string.home_subtitle'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.zhitu_text_secondary'))
            .width('100%')

          // Wave 12：继续上次学习（跨设备续学入口）
          if (this.continueSession) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text('🔁 继续上次学习')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.zhitu_text_primary'))
                  .layoutWeight(1)
                Text(this.relTime(this.continueSession.ts))
                  .fontSize(12)
                  .fontColor('#8a94a6')
              }
              .width('100%')
              Text(this.continueSession.title)
                .fontSize(14)
                .fontColor('#1a2333')
                .fontWeight(FontWeight.Medium)
                .width('100%')
              if (this.continueSession.nodeText.length > 0) {
                Text(`上次停留：${this.continueSession.nodeText}`)
                  .fontSize(12)
                  .fontColor('#4a5468')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              Row({ space: 10 }) {
                Button('继续学习')
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(14)
                  .backgroundColor('#13c2c2')
                  .onClick(() => {
                    this.resumeLast();
                  })
                Button('清除记录')
                  .height(38)
                  .fontSize(13)
                  .fontColor('#8a94a6')
                  .backgroundColor('#f3f4f6')
                  .onClick(() => {
                    this.clearContinue();
                  })
              }
              .width('100%')
            }
            .padding(16)
            .backgroundColor('#e6fffb')
            .borderRadius($r('app.float.card_round_corner'))
            .width('100%')
          }

          // 输入卡片
          Column({ space: 12 }) {
            TextInput({ placeholder: $r('app.string.home_input_placeholder'), text: this.query })
              .height($r('app.float.hit_min_size'))
              .onChange((value: string) => {
                this.query = value;
              })
            Row({ space: 8 }) {
              Text($r('app.string.home_subject_label'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.zhitu_text_secondary'))
              Select(this.subjectOptions())
                .selected(this.selectedSubjectIndex)
                .value(this.subjectLabels()[this.selectedSubjectIndex])
                .font({ size: 15 })
                .onSelect((index: number) => {
                  this.selectedSubjectIndex = index;
                })
            }
            .width('100%')

            TextInput({ placeholder: $r('app.string.home_book_placeholder'), text: this.book })
              .height($r('app.float.hit_min_size'))
              .onChange((value: string) => {
                this.book = value;
              })

            Button(this.generating ? $r('app.string.home_generating') : $r('app.string.home_generate'))
              .width('100%')
              .height(48)
              .fontSize($r('app.float.body_font_size'))
              .enabled(!this.generating)
              .backgroundColor($r('app.color.zhitu_primary'))
              .onClick(() => {
                this.generate();
              })
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))

          // 生成进度 / 错误区
          if (this.generating) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(28)
                .height(28)
                .color($r('app.color.zhitu_primary'))
              Text($r('app.string.home_generating'))
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.zhitu_text_secondary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }

          if (this.streamText.length > 0 && !this.generating) {
            Text(this.streamText.length > 120 ? this.streamText.substring(0, 120) + '…' : this.streamText)
              .fontSize($r('app.float.caption_font_size'))
              .fontColor($r('app.color.zhitu_text_secondary'))
              .width('100%')
              .maxLines(3)
          }

          // 为你推荐
          if (this.recommendId.length > 0) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text('为你推荐')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.zhitu_text_primary'))
                  .layoutWeight(1)
                Button('去学习')
                  .height(30)
                  .fontSize(13)
                  .backgroundColor('#1677ff')
                  .onClick(() => {
                    DeepLinkRouter.route(this.recommendId, this.recommendType, this.recommendText);
                  })
              }
              .width('100%')
              Text(this.recommendText)
                .fontSize(14)
                .fontColor('#1a2333')
                .width('100%')
              Text(this.recommendReason)
                .fontSize(12)
                .fontColor('#8a94a6')
                .width('100%')
            }
            .padding(16)
            .backgroundColor($r('app.color.zhitu_bg_card'))
            .borderRadius($r('app.float.card_round_corner'))
            .width('100%')
          }

          // 智能创作：拍照识题
          Column({ space: 10 }) {
            Text('智能创作')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.zhitu_text_primary'))
              .width('100%')
            Button('📷 拍照识题')
              .width('100%')
              .height(40)
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor('#13c2c2')
              .onClick(() => {
                DeepLinkRouter.push('PhotoQuizPage');
              })
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          // 考点模板库
          Column({ space: 10 }) {
            Text($r('app.string.home_templates'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.zhitu_text_primary'))
              .width('100%')
            Column({ space: 8 }) {
              ForEach(this.templates, (tpl: TemplateItem) => {
                Row({ space: 10 }) {
                  Column({ space: 2 }) {
                    Text(tpl.title)
                      .fontSize(14)
                      .fontColor('#1a2333')
                      .fontWeight(FontWeight.Medium)
                    Text(tpl.summary)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button($r('app.string.template_use'))
                    .height(30)
                    .fontSize(13)
                    .backgroundColor('#1677ff')
                    .onClick(() => {
                      this.useTemplate(tpl.id);
                    })
                }
                .padding(12)
                .backgroundColor('#f3f8ff')
                .borderRadius(10)
                .width('100%')
              }, (tpl: TemplateItem) => tpl.id)
            }
            .width('100%')
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          Text('输入一个知识点，长出一张会思考的图')
            .fontSize($r('app.float.caption_font_size'))
            .fontColor($r('app.color.zhitu_text_secondary'))
        }
        .padding($r('app.float.margin_l'))
        .width('100%')
        .backgroundColor($r('app.color.zhitu_bg_canvas'))
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      BottomTabBar({ selectedTab: this.tabKey, onTabChange: this.onTabChange })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.zhitu_bg_canvas'))
  }

  /** Wave 12：继续上次学习 */
  private async resumeLast(): Promise<void> {
    const s = ContinueService.getInstance().get();
    if (!s) {
      return;
    }
    const ok = await this.store.openMapById(s.mapId);
    if (!ok) {
      promptAction.showToast({ message: '导图不存在，可能已删除' });
      await ContinueService.getInstance().clear();
      this.refreshHub();
      return;
    }
    if (s.nodeId && s.nodeId.length > 0) {
      DeepLinkRouter.route(s.nodeId, NodeType.GENERAL, s.nodeText);
    } else {
      DeepLinkRouter.push('MindMapPage');
    }
  }

  private async clearContinue(): Promise<void> {
    await ContinueService.getInstance().clear();
    this.refreshHub();
    promptAction.showToast({ message: '已清除续学记录' });
  }

  private relTime(ts: number): string {
    const diff = Date.now() - ts;
    const min = Math.floor(diff / 60000);
    if (min < 1) {
      return '刚刚';
    }
    if (min < 60) {
      return `${min} 分钟前`;
    }
    const hr = Math.floor(min / 60);
    if (hr < 24) {
      return `${hr} 小时前`;
    }
    return `${Math.floor(hr / 24)} 天前`;
  }

  private subjectLabels(): string[] {
    const labels: string[] = [];
    for (let i = 0; i < SUBJECTS.length; i++) {
      labels.push(SUBJECTS[i].label);
    }
    return labels;
  }

  private subjectOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < SUBJECTS.length; i++) {
      const opt: SelectOption = { value: SUBJECTS[i].label };
      options.push(opt);
    }
    return options;
  }

  /** 模板一键建图：以模板导图新建（不覆盖已有），跳转编辑页 */
  private useTemplate(id: string): void {
    const map = getTemplateMindMap(id);
    if (!map) {
      promptAction.showToast({ message: $r('app.string.template_invalid') });
      return;
    }
    const imported = this.store.importAsNew(map.toJson());
    if (imported.ok) {
      DeepLinkRouter.push('MindMapPage');
    } else {
      promptAction.showToast({ message: $r('app.string.template_invalid') });
    }
  }

  private async generate(): Promise<void> {
    const query = this.query.trim();
    if (query.length === 0) {
      promptAction.showToast({ message: $r('app.string.home_empty_input_tip') });
      return;
    }
    if (this.generating) {
      return;
    }
    this.generating = true;
    this.streamText = '';
    Logger.aiRequest('HomePage', 'request', 'generateMindMap');
    try {
      const config = AIConfig.load();
      const svc = AIServiceFactory.create(config);
      const subjectCode = SUBJECTS.length > 0 && this.selectedSubjectIndex >= 0
        ? SUBJECTS[this.selectedSubjectIndex].code
        : '';
      const res = await svc.generateMindMap(
        { query: query, subject: subjectCode, book: this.book.trim() },
        (chunk) => {
          this.streamText += chunk.text;
        });
      if (res.ok) {
        const imported = this.store.importAsNew(res.data.map.toJson());
        if (imported.ok) {
          Logger.aiRequest('HomePage', 'success', 'map created');
          this.generating = false;
          DeepLinkRouter.push('MindMapPage');
          return;
        }
        promptAction.showToast({ message: $r('app.string.home_invalid_output') });
      } else {
        const failure: AIResultFailure = res as AIResultFailure;
        Logger.aiRequest('HomePage', 'failed', failure.error.message);
        promptAction.showToast({ message: $r('app.string.home_generate_failed') });
        this.streamText = '生成失败，请重试';
      }
    } catch (err) {
      Logger.aiRequest('HomePage', 'failed', JSON.stringify(err));
      promptAction.showToast({ message: $r('app.string.home_generate_failed') });
    }
    this.generating = false;
  }
}
