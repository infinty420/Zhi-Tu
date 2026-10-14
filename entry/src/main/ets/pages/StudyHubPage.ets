/**
 * StudyHubPage —— 学习分区：复习 / 统计 / 错题 / 每日打卡 / 复习优先级。
 * Wave 9：从原首页拆分出来的「学习」Tab Hub，进入子页面时底栏随本页一起被覆盖隐藏。
 */
import { promptAction } from '@kit.ArkUI';
import { MindMapStore } from '../services/MindMapStore';
import { StudyInsightService } from '../services/StudyInsightService';
import { ReviewSummaryService, DueItem } from '../services/ReviewSummaryService';
import { StudyPlanService, PlanDay, PlanTask } from '../services/StudyPlanService';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { AchievementService } from '../services/AchievementService';
import { BottomTabBar } from '../components/BottomTabBar';

@Component
export struct StudyHubPage {
  @Prop tabKey: number = 1;
  onTabChange: (index: number) => void = () => {};

  @State dueReviewCount: number = 0;
  @State streakDays: number = 0;
  @State todayEventCount: number = 0;
  @State todayProgress: number = 0;
  @State checkInStreak: number = 0;
  @State checkedInToday: boolean = false;
  @State hasMap: boolean = false;
  @State dueItems: DueItem[] = [];
  // Wave 11：本周学习计划
  @State weekPlan: PlanDay[] = [];
  // Wave 10：专注模式（番茄钟）
  @State focusing: boolean = false;
  @State focusRemaining: number = 0;
  @State focusTotal: number = 0;
  private focusTimer: number = 0;
  private store: MindMapStore = MindMapStore.getInstance();
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = this.store.subscribe(() => {
      this.refresh();
    });
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
    this.clearFocus();
  }

  private formatTime(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m < 10 ? '0' + m : m}:${s < 10 ? '0' + s : s}`;
  }

  private startFocus(minutes: number): void {
    this.clearFocus();
    this.focusTotal = minutes * 60;
    this.focusRemaining = minutes * 60;
    this.focusing = true;
    this.focusTimer = setInterval(() => {
      this.focusRemaining = this.focusRemaining - 1;
      if (this.focusRemaining <= 0) {
        this.finishFocus(true);
      }
    }, 1000) as number;
  }

  private finishFocus(natural: boolean): void {
    const elapsed = this.focusTotal - Math.max(0, this.focusRemaining);
    this.clearFocus();
    const usedMin = Math.max(1, Math.ceil(elapsed / 60));
    this.store.recordFocus(usedMin);
    this.focusing = false;
    promptAction.showToast({ message: `专注 ${usedMin} 分钟已记录 🍅` });
    this.refresh();
  }

  private clearFocus(): void {
    if (this.focusTimer > 0) {
      clearInterval(this.focusTimer);
      this.focusTimer = 0;
    }
  }

  private refresh(): void {
    this.hasMap = this.store.hasCurrent();
    this.dueReviewCount = this.store.dueReviewCount();
    const stats = this.store.getStudyStats();
    this.streakDays = stats.streakDays;
    this.todayEventCount = stats.todayEventCount;
    const done = stats.todayEventCount;
    const remain = stats.dueReviewCount;
    this.todayProgress = (done + remain) > 0 ? done / (done + remain) : 0;
    const now = Date.now();
    this.dueItems = ReviewSummaryService.computeDueItems(this.store.currentSnapshot(), now, 3);
    this.weekPlan = StudyPlanService.buildWeekPlan(this.store.currentSnapshot(), this.store.getWrongItems(), now);
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

  build() {
    Stack() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
          Text('学习中心')
            .fontSize($r('app.float.large_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
            .width('100%')

          // 今日进度 banner（hero 指标卡）
          Column({ space: 12 }) {
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
            // 三项指标
            Row({ space: 8 }) {
              this.statBlock(`${this.dueReviewCount}`, '待复习')
              this.statBlock(`${this.todayEventCount}`, '今日已学')
              this.statBlock(`${this.streakDays}`, '连续(天)')
            }
            .width('100%')
            // 进度条
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

          // 每日打卡
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

          // 学习工具入口
          Column({ space: 12 }) {
            Text('学习工具')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.zhitu_text_primary'))
              .width('100%')
            Row({ space: 10 }) {
              this.toolTile('开始学习', '学', '#1677ff', '#e6f1fb', () => {
                if (!this.hasMap) {
                  promptAction.showToast({ message: $r('app.string.home_no_map_tip') });
                  return;
                }
                DeepLinkRouter.pushWithParam('StudyPage', this.store.currentId());
              })
              this.toolTile('学习统计', '统', '#0f6e56', '#e1f5ee', () => {
                DeepLinkRouter.push('StatsPage');
              })
              this.toolTile('错题本', '错', '#722ed1', '#eeedfe', () => {
                DeepLinkRouter.push('WrongBookPage');
              })
            }
            .width('100%')
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          // Wave 10：专注模式
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('🍅 专注模式')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.zhitu_text_primary'))
                .layoutWeight(1)
              if (this.focusing) {
                Text(this.formatTime(this.focusRemaining))
                  .fontSize(14)
                  .fontColor('#fa8c16')
                  .fontWeight(FontWeight.Bold)
              }
            }
            .width('100%')
            if (!this.focusing) {
              Row({ space: 10 }) {
                this.toolTile('专注 15 分', '15', '#fa8c16', '#faeedf', () => {
                  this.startFocus(15);
                })
                this.toolTile('专注 25 分', '25', '#fa8c16', '#faeedf', () => {
                  this.startFocus(25);
                })
                this.toolTile('专注 45 分', '45', '#fa8c16', '#faeedf', () => {
                  this.startFocus(45);
                })
              }
              .width('100%')
              Text('开始专注后自动计时，结束时记录学习时长')
                .fontSize(12)
                .fontColor('#8a94a6')
                .width('100%')
            } else {
              Button('结束并保存')
                .width('100%')
                .height(40)
                .fontSize(14)
                .backgroundColor('#1677ff')
                .onClick(() => {
                  this.finishFocus(false);
                })
            }
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          // 今日复习优先级
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
                .padding(12)
                .backgroundColor('#ffffff')
                .borderRadius(10)
                .onClick(() => {
                  DeepLinkRouter.route(d.nodeId, d.type, d.text);
                })
              }, (d: DueItem) => d.nodeId)
            }
            .padding(16)
            .backgroundColor($r('app.color.zhitu_bg_card'))
            .borderRadius($r('app.float.card_round_corner'))
            .width('100%')
          }

          // Wave 11：本周学习计划（自动排程）
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('🗓️ 本周学习计划')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.zhitu_text_primary'))
                .layoutWeight(1)
              Text(`共 ${StudyPlanService.totalTasks(this.weekPlan)} 项`)
                .fontSize(12)
                .fontColor('#8a94a6')
            }
            .width('100%')
            if (this.weekPlan.length === 0 || StudyPlanService.totalTasks(this.weekPlan) === 0) {
              Text('打开或生成导图后，这里会按到期与薄弱点自动排出 7 天计划')
                .fontSize(13)
                .fontColor('#8a94a6')
                .width('100%')
            } else {
              Scroll() {
                Row({ space: 10 }) {
                  ForEach(this.weekPlan, (day: PlanDay) => {
                    Column({ space: 6 }) {
                      Row() {
                        Text(day.label)
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(day.index === 0 ? '#1677ff' : '#1a2333')
                        if (day.index === 0) {
                          Text('今天')
                            .fontSize(10)
                            .fontColor('#ffffff')
                            .backgroundColor('#1677ff')
                            .borderRadius(6)
                            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                        }
                      }
                      .width('100%')
                      if (day.tasks.length === 0) {
                        Text('轻松一日')
                          .fontSize(12)
                          .fontColor('#b0b9c9')
                      } else {
                        Column({ space: 6 }) {
                          ForEach(day.tasks, (t: PlanTask) => {
                            Column({ space: 3 }) {
                              Row({ space: 4 }) {
                                Text(t.tag)
                                  .fontSize(10)
                                  .fontColor(t.tag === '已逾期' ? '#ffffff' : '#d48806')
                                  .backgroundColor(t.tag === '已逾期' ? '#cf1322' : '#fff7e6')
                                  .borderRadius(6)
                                  .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                              }
                              .width('100%')
                              Text(t.nodeText)
                                .fontSize(13)
                                .fontColor('#1a2333')
                                .maxLines(2)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                .width('100%')
                            }
                            .alignItems(HorizontalAlign.Start)
                            .padding(8)
                            .backgroundColor('#ffffff')
                            .borderRadius(8)
                            .width('100%')
                            .onClick(() => {
                              DeepLinkRouter.route(t.nodeId, t.nodeType, t.nodeText);
                            })
                          }, (t: PlanTask) => `${day.index}_${t.nodeId}`)
                        }
                        .width('100%')
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .padding(10)
                    .backgroundColor('#eef6ff')
                    .borderRadius(10)
                    .width(140)
                  }, (day: PlanDay) => `${day.index}`)
                }
                .width('100%')
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          Text('坚持每天复习，让记忆生根')
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
      if (this.focusing) {
        Column() {
          Column({ space: 20 }) {
            Text('🍅 专注中')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1a2333')
            Text(this.formatTime(this.focusRemaining))
              .fontSize(48)
              .fontWeight(FontWeight.Bold)
              .fontColor('#fa8c16')
            Text('保持专注，时间会给你答案')
              .fontSize(14)
              .fontColor('#8a94a6')
            Button('结束并保存')
              .width('60%')
              .height(44)
              .fontSize(15)
              .backgroundColor('#1677ff')
              .onClick(() => {
                this.finishFocus(false);
              })
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#ffffff')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.zhitu_bg_canvas'))
  }

  @Builder
  statBlock(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.zhitu_text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor('#8a94a6')
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  toolTile(label: string, glyph: string, color: string, tint: string, onTap: () => void) {
    Column({ space: 8 }) {
      Column() {
        Text(glyph)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(color)
      }
      .width(40)
      .height(40)
      .borderRadius(12)
      .backgroundColor(tint)
      .align(Alignment.Center)
      Text(label)
        .fontSize(12)
        .fontColor('#1a2333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding(10)
    .backgroundColor('#f3f4f6')
    .borderRadius(12)
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }
}
