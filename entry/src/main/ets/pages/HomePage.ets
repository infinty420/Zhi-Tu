/**
 * HomePage —— 首页：知识点输入与导图生成。
 * 支持自由输入 / 学科+参考书目；空输入拦截、加载态防重复提交、失败降级重试。
 */
import { promptAction } from '@kit.ArkUI';
import { SUBJECTS, NodeType } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';
import { getTemplateMindMap, listTemplates, TemplateItem } from '../model/Templates';
import { AIConfig } from '../services/AIConfig';
import { AIResultFailure } from '../services/AIService';
import { AIServiceFactory } from '../services/AIServiceFactory';
import { MindMapStore } from '../services/MindMapStore';
import { StudyInsightService } from '../services/StudyInsightService';
import { ReviewScheduler } from '../services/ReviewScheduler';
import { MasteryPredictor } from '../services/MasteryPredictor';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { AchievementService } from '../services/AchievementService';
import { Logger } from '../utils/Logger';

/** 首页待复习优先级卡片项（Wave 5：按掌握度预测排序） */
interface DueItem {
  nodeId: string;
  text: string;
  type: NodeType;
  /** 预测掌握度百分比 0~100 */
  masteryPct: number;
  /** 是否已逾期 */
  urgent: boolean;
}

/** 排序用的中间结构（含节点引用与优先级分） */
interface DueScored {
  n: MindNode;
  pct: number;
  urgent: boolean;
  pr: number;
}

@Component
export struct HomePage {
  @State query: string = '';
  @State selectedSubjectIndex: number = 0;
  @State book: string = '';
  @State generating: boolean = false;
  @State streamText: string = '';
  @State dueReviewCount: number = 0;
  @State hasMap: boolean = false;
  @State streakDays: number = 0;
  @State todayEventCount: number = 0;
  @State todayProgress: number = 0; // 0~1 今日复习完成度

  // Wave 7：每日打卡（显式打卡 streak，区别于基于学习事件的连续学习天数）
  @State checkInStreak: number = 0;
  @State checkedInToday: boolean = false;

  // Wave 2：自适应学习路径 · 为你推荐（按薄弱点推荐下一个该学的节点）
  @State recommendId: string = '';
  @State recommendText: string = '';
  @State recommendType: NodeType = NodeType.GENERAL;
  @State recommendReason: string = '';

  // Wave 5：今日复习优先级（按掌握度预测排序，Top3）
  @State dueItems: DueItem[] = [];
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
    this.dueReviewCount = this.store.dueReviewCount();
    const now = Date.now();
    const stats = this.store.getStudyStats();
    this.streakDays = stats.streakDays;
    this.todayEventCount = stats.todayEventCount;
    // 今日复习完成度 = 已完成 / (已完成 + 仍待复习)，两者皆 0 时为 0
    const done = stats.todayEventCount;
    const remain = stats.dueReviewCount;
    this.todayProgress = (done + remain) > 0 ? done / (done + remain) : 0;
    // 自适应推荐：按薄弱点/待复习给出下一个该学的节点
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
    // Wave 5：对待复习节点按「紧急度 × 重要度 + 遗忘风险」排序，取前 3
    this.dueItems = this.computeDueItems(snap, now);
    // Wave 7：刷新每日打卡状态
    const ci = AchievementService.getInstance().getCheckIn();
    this.checkInStreak = ci.streak;
    this.checkedInToday = ci.checkedInToday;
  }

  private async doCheckIn(): Promise<void> {
    const view = await AchievementService.getInstance().checkInToday();
    this.checkInStreak = view.streak;
    this.checkedInToday = view.checkedInToday;
    promptAction.showToast({ message: view.checkedInToday ? `打卡成功，连续 ${view.streak} 天 🔥` : '今天已打卡' });
  }

  private computeDueItems(snap: MindMap | undefined, now: number): DueItem[] {
    if (!snap) {
      return [];
    }
    const due = ReviewScheduler.dueNodes(snap);
    if (due.length === 0) {
      return [];
    }
    const scored: DueScored[] = [];
    for (let i = 0; i < due.length; i++) {
      const n: MindNode = due[i];
      const pct = Math.round(MasteryPredictor.masteryScore(n, now) * 100);
      const urgent = n.nextReviewAt > 0 && n.nextReviewAt <= now;
      scored.push({ n: n, pct: pct, urgent: urgent, pr: MasteryPredictor.priority(n, now) });
    }
    scored.sort((a: DueScored, b: DueScored) => b.pr - a.pr);
    const max = Math.min(3, scored.length);
    const out: DueItem[] = [];
    for (let i = 0; i < max; i++) {
      const s = scored[i];
      out.push({ nodeId: s.n.id, text: s.n.text, type: s.n.type, masteryPct: s.pct, urgent: s.urgent });
    }
    return out;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        // 顶部品牌区
        Row() {
          Text($r('app.string.home_title'))
            .fontSize($r('app.float.large_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
          Blank()
          Button('云端')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.zhitu_primary'))
            .height($r('app.float.hit_min_size'))
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              DeepLinkRouter.push('AccountPage');
            })
          Button($r('app.string.home_my_maps'))
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.zhitu_primary'))
            .height($r('app.float.hit_min_size'))
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              DeepLinkRouter.push('MyMapsPage');
            })
        }
        .width('100%')

        Text($r('app.string.home_subtitle'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.zhitu_text_secondary'))
          .width('100%')

        // 打卡角标 + 今日学习进度条（Phase 5.4）
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text(this.streakDays > 0 ? `🔥 连续打卡 ${this.streakDays} 天` : '📍 今天还没打卡')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1a2333')
              .layoutWeight(1)
            if (this.todayEventCount > 0) {
              Text(`今日 ${this.todayEventCount} 次学习`)
                .fontSize(12)
                .fontColor('#8a94a6')
            }
          }
          .width('100%')
          Row() {
            Stack() {
              Rect()
                .width('100%')
                .height(10)
                .radius(5)
                .fill('#eef1f6')
              Rect()
                .width(`${Math.round(this.todayProgress * 100)}%`)
                .height(10)
                .radius(5)
                .fill('#13c2c2')
            }
            .width('100%')
            .height(10)
          }
          .width('100%')
          Text(this.dueReviewCount > 0
            ? `今日待复习 ${this.dueReviewCount} 个，已完成 ${Math.round(this.todayProgress * 100)}%`
            : (this.todayProgress >= 1 ? '今日复习已全部完成 🎉' : '今天还没有复习安排，去学一学吧'))
            .fontSize(12)
            .fontColor('#8a94a6')
            .width('100%')
        }
        .padding(14)
        .backgroundColor($r('app.color.zhitu_bg_card'))
        .borderRadius($r('app.float.card_round_corner'))
        .width('100%')

        // Wave 7：每日打卡卡
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text('📅 每日打卡')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.zhitu_text_primary'))
              .layoutWeight(1)
            Text(this.checkInStreak > 0 ? `已连续打卡 ${this.checkInStreak} 天` : '还没开始打卡')
              .fontSize(12)
              .fontColor('#8a94a6')
          }
          .width('100%')
          Row({ space: 10 }) {
            Text(this.checkedInToday
              ? '今天已打卡，明天再来 ✅'
              : '打卡记录今天的学习，养成习惯 🔥')
              .fontSize(13)
              .fontColor('#1a2333')
              .layoutWeight(1)
            Button(this.checkedInToday ? '已打卡' : '今日打卡')
              .height(34)
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor(this.checkedInToday ? '#8a94a6' : '#fa8c16')
              .enabled(!this.checkedInToday)
              .onClick(() => {
                this.doCheckIn();
              })
          }
          .width('100%')
        }
        .padding(14)
        .backgroundColor($r('app.color.zhitu_bg_card'))
        .borderRadius($r('app.float.card_round_corner'))
        .width('100%')

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

        // 学习中心入口（v1.1 学习闭环）
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text($r('app.string.home_study_hub'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.zhitu_text_primary'))
              .layoutWeight(1)
            if (this.dueReviewCount > 0) {
              Text(`今日待复习 ${this.dueReviewCount}`)
                .fontSize(12)
                .fontColor('#ffffff')
                .backgroundColor('#fa8c16')
                .borderRadius(10)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            }
          }
          .width('100%')

          Row({ space: 10 }) {
            this.hubButton($r('app.string.home_start_study'), '#1677ff', () => {
              if (!this.hasMap) {
                promptAction.showToast({ message: $r('app.string.home_no_map_tip') });
                return;
              }
              DeepLinkRouter.pushWithParam('StudyPage', this.store.currentId());
            })
            this.hubButton($r('app.string.home_stats'), '#13c2c2', () => {
              DeepLinkRouter.push('StatsPage');
            })
            this.hubButton($r('app.string.home_wrong_book'), '#722ed1', () => {
              DeepLinkRouter.push('WrongBookPage');
            })
          }
          .width('100%')
        }
        .padding(16)
        .backgroundColor($r('app.color.zhitu_bg_card'))
        .borderRadius($r('app.float.card_round_corner'))
        .width('100%')

        // Wave 2：自适应学习路径 · 为你推荐
        if (this.recommendId.length > 0) {
          Column({ space: 8 }) {
            Row() {
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

        // Wave 5：今日复习优先级（按掌握度预测排序，Top3）
        if (this.dueItems.length > 0) {
          Column({ space: 8 }) {
            Row() {
              Text('今日复习优先级')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.zhitu_text_primary'))
                .layoutWeight(1)
              Text(`共 ${this.dueReviewCount} 项待复习`)
                .fontSize(12)
                .fontColor('#8a94a6')
            }
            .width('100%')
            ForEach(this.dueItems, (d: DueItem) => {
              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  Text(d.text)
                    .fontSize(14)
                    .fontColor('#1a2333')
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (d.urgent) {
                    Text('逾期')
                      .fontSize(11)
                      .fontColor('#ffffff')
                      .backgroundColor('#cf1322')
                      .borderRadius(8)
                      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  }
                  Text(`${d.masteryPct}%`)
                    .fontSize(12)
                    .fontColor(d.masteryPct >= 70 ? '#52c41a' : (d.masteryPct >= 40 ? '#fa8c16' : '#cf1322'))
                }
                .width('100%')
                Stack({ alignContent: Alignment.Start }) {
                  Rect()
                    .width('100%')
                    .height(6)
                    .radius(3)
                    .fill('#eef1f6')
                  Rect()
                    .width(`${d.masteryPct}%`)
                    .height(6)
                    .radius(3)
                    .fill(d.masteryPct >= 70 ? '#52c41a' : (d.masteryPct >= 40 ? '#fa8c16' : '#cf1322'))
                }
                .width('100%')
                .height(6)
                Button('去复习')
                  .height(26)
                  .fontSize(11)
                  .backgroundColor('#1677ff')
                  .onClick(() => {
                    DeepLinkRouter.route(d.nodeId, d.type, d.text);
                  })
              }
              .padding(12)
              .backgroundColor('#ffffff')
              .borderRadius(10)
              .width('100%')
            }, (d: DueItem) => d.nodeId)
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')
        }

        // 一起学入口（v2.0 云端 / 分享 / 市场 / 班级 / 搜索）
        Column({ space: 10 }) {
          Text('一起学（v2.0）')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
            .width('100%')
          Row({ space: 10 }) {
            Button('分享')
              .height(40)
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor('#1677ff')
              .layoutWeight(1)
              .onClick(() => {
                DeepLinkRouter.push('SharePage');
              })
            Button('精品市场')
              .height(40)
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor('#13c2c2')
              .layoutWeight(1)
              .onClick(() => {
                DeepLinkRouter.push('MarketPage');
              })
          }
          .width('100%')
          Row({ space: 10 }) {
            Button('我的班级')
              .height(40)
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor('#722ed1')
              .layoutWeight(1)
              .onClick(() => {
                DeepLinkRouter.push('ClassPage');
              })
            Button('全局搜索')
              .height(40)
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor('#fa8c16')
              .layoutWeight(1)
              .onClick(() => {
                DeepLinkRouter.push('SearchPage');
              })
          }
          .width('100%')
          Row({ space: 10 }) {
            Button('📷 拍照识题')
              .height(40)
              .fontSize(14)
              .fontColor('#ffffff')
              .backgroundColor('#13c2c2')
              .layoutWeight(1)
              .onClick(() => {
                DeepLinkRouter.push('PhotoQuizPage');
              })
          }
          .width('100%')
        }
        .padding(16)
        .backgroundColor($r('app.color.zhitu_bg_card'))
        .borderRadius($r('app.float.card_round_corner'))
        .width('100%')

        // 考点模板库（v1.2 降低空白输入门槛）
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
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
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

  @Builder
  hubButton(label: Resource, color: string, onTap: () => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(14)
        .fontColor('#ffffff')
    }
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(color)
    .borderRadius(12)
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
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