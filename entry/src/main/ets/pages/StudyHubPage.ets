/**
 * StudyHubPage —— 学习分区：复习 / 统计 / 错题 / 每日打卡 / 复习优先级。
 * Wave 9：从原首页拆分出来的「学习」Tab Hub，进入子页面时底栏随本页一起被覆盖隐藏。
 */
import { promptAction } from '@kit.ArkUI';
import { MindMapStore } from '../services/MindMapStore';
import { StudyInsightService } from '../services/StudyInsightService';
import { ReviewSummaryService, DueItem } from '../services/ReviewSummaryService';
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
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          Text('学习中心')
            .fontSize($r('app.float.large_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
            .width('100%')

          // 今日进度 banner
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
              this.tile('开始学习', '#1677ff', () => {
                if (!this.hasMap) {
                  promptAction.showToast({ message: $r('app.string.home_no_map_tip') });
                  return;
                }
                DeepLinkRouter.pushWithParam('StudyPage', this.store.currentId());
              })
              this.tile('学习统计', '#13c2c2', () => {
                DeepLinkRouter.push('StatsPage');
              })
              this.tile('错题本', '#722ed1', () => {
                DeepLinkRouter.push('WrongBookPage');
              })
            }
            .width('100%')
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
    .backgroundColor($r('app.color.zhitu_bg_canvas'))
  }

  @Builder
  tile(label: string, color: string, onTap: () => void) {
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
}
