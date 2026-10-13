/**
 * StatsPage —— 学习统计与打卡（NavDestination，v1.1）。
 * 展示学习天数、连续打卡、掌握节点数、掌握率、今日待复习，数据来自 StorageService 聚合。
 */

import { promptAction } from '@kit.ArkUI';
import { MindMapStore } from '../services/MindMapStore';
import { StudyStats } from '../model/StudyModels';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { StudyInsightService, WeakPointItem, SubjectWeakProfile } from '../services/StudyInsightService';
import { StudyReportService, StudyReport } from '../services/StudyReportService';
import { MasteryPredictor } from '../services/MasteryPredictor';
import { AccountService } from '../services/AccountService';
import { AchievementService, AchievementView } from '../services/AchievementService';
import { NodeType, NODE_TYPE_LABEL } from '../model/Constants';

/** 记忆保持预测项（Wave 5：保持率越低越该复习） */
interface RetainItem {
  nodeId: string;
  text: string;
  /** 当前记忆保持率百分比 0~100 */
  retainPct: number;
}

/** 日历单元格（Wave 10） */
interface CalCell {
  day: number;
  date: string;
  dueCount: number;
}

/** 选中日的待复习项（Wave 10） */
interface DueCalItem {
  text: string;
  type: NodeType;
}

@Component
export struct StatsPage {
  @State stats: StudyStats = {
    studyDayCount: 0,
    streakDays: 0,
    totalEvents: 0,
    masteredCount: 0,
    totalCount: 0,
    masteryRate: 0,
    dueReviewCount: 0,
    todayEventCount: 0,
    focusMinutes: 0
  };
  @State hasMap: boolean = false;
  // Wave 2：学情画像 / 薄弱点
  @State weak: WeakPointItem[] = [];
  @State profile: SubjectWeakProfile[] = [];
  // Wave 4：学情报告（周报 / 月报，家长视角）
  @State report: StudyReport | undefined = undefined;
  @State reportDays: number = 7;
  // Wave 5：记忆保持预测（按保持率升序，最易忘的优先）
  @State retainItems: RetainItem[] = [];
  // Wave 7：成就墙
  @State achievements: AchievementView[] = [];
  // Wave 10：复习日历
  @State calYear: number = 0;
  @State calMonth: number = 0;
  @State calCells: CalCell[] = [];
  @State selectedDate: string = '';
  @State selectedDueItems: DueCalItem[] = [];
  @State calRows: number = 0;
  private dueBucket: Map<string, DueCalItem[]> = new Map();
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
    this.stats = this.store.getStudyStats();
    this.hasMap = this.store.hasCurrent();
    const now = Date.now();
    const snap = this.store.currentSnapshot();
    if (snap) {
      const all = StudyInsightService.buildWeakPoints(snap, this.store.getWrongItems());
      // 只展示最薄弱的前 5 个，避免长列表
      this.weak = all.length > 5 ? all.slice(0, 5) : all;
      this.profile = StudyInsightService.buildSubjectProfile(snap, all);
      // Wave 5：记忆保持预测 —— 已复习过的节点按保持率升序，取最易忘的前 6
      const list: RetainItem[] = [];
      for (let i = 0; i < snap.nodes.length; i++) {
        const n = snap.nodes[i];
        if (n.lastReviewedAt > 0) {
          const pct = Math.round(MasteryPredictor.retention(n, now) * 100);
          list.push({ nodeId: n.id, text: n.text, retainPct: pct });
        }
      }
      list.sort((a: RetainItem, b: RetainItem) => a.retainPct - b.retainPct);
      this.retainItems = list.length > 6 ? list.slice(0, 6) : list;
    } else {
      this.weak = [];
      this.profile = [];
      this.retainItems = [];
    }
    this.report = StudyReportService.build(this.store.getLearningEvents(), this.store.getWrongItems(), this.reportDays);
    // Wave 7：成就墙（实时依据学习统计推导）
    this.achievements = AchievementService.getInstance().listAchievements();
    // Wave 10：复习日历（保留已选月份，首次进入初始化为当前月）
    if (this.calYear === 0) {
      const now = new Date();
      this.buildCalendar(now.getFullYear(), now.getMonth());
    } else {
      this.buildCalendar(this.calYear, this.calMonth);
    }
  }

  private pad2(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }

  private typeLabel(t: NodeType): string {
    const l = NODE_TYPE_LABEL.get(t);
    return l === undefined ? '' : l;
  }

  /** 构建某月的日历单元格，并按节点 nextReviewAt 聚合「当日待复习」 */
  private buildCalendar(year: number, month: number): void {
    this.calYear = year;
    this.calMonth = month;
    const snap = this.store.currentSnapshot();
    const bucket: Map<string, DueCalItem[]> = new Map();
    if (snap) {
      for (let i = 0; i < snap.nodes.length; i++) {
        const n = snap.nodes[i];
        if (n.nextReviewAt > 0) {
          const d = new Date(n.nextReviewAt);
          if (d.getFullYear() === year && d.getMonth() === month) {
            const key = `${year}-${this.pad2(month + 1)}-${this.pad2(d.getDate())}`;
            let arr = bucket.get(key);
            if (!arr) {
              arr = [];
              bucket.set(key, arr);
            }
            arr.push({ text: n.text, type: n.type });
          }
        }
      }
    }
    this.dueBucket = bucket;
    const first = new Date(year, month, 1);
    const startW = first.getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const cells: CalCell[] = [];
    for (let i = 0; i < startW; i++) {
      cells.push({ day: 0, date: `e${i}`, dueCount: 0 });
    }
    for (let d = 1; d <= daysInMonth; d++) {
      const key = `${year}-${this.pad2(month + 1)}-${this.pad2(d)}`;
      const arr = bucket.get(key);
      cells.push({ day: d, date: key, dueCount: arr ? arr.length : 0 });
    }
    this.calCells = cells;
    this.calRows = Math.ceil(cells.length / 7);
    if (this.selectedDate.length === 0) {
      const now = new Date();
      this.selectedDate = `${now.getFullYear()}-${this.pad2(now.getMonth() + 1)}-${this.pad2(now.getDate())}`;
    }
    this.refreshSelected();
  }

  private refreshSelected(): void {
    const arr = this.dueBucket.get(this.selectedDate);
    this.selectedDueItems = arr ? arr : [];
  }

  private selectDay(c: CalCell): void {
    if (c.day === 0) {
      return;
    }
    this.selectedDate = c.date;
    this.refreshSelected();
  }

  private prevMonth(): void {
    let y = this.calYear;
    let m = this.calMonth - 1;
    if (m < 0) {
      m = 11;
      y = y - 1;
    }
    this.buildCalendar(y, m);
  }

  private nextMonth(): void {
    let y = this.calYear;
    let m = this.calMonth + 1;
    if (m > 11) {
      m = 0;
      y = y + 1;
    }
    this.buildCalendar(y, m);
  }

  /** 切换周报 / 月报 */
  private switchReport(days: number): void {
    this.reportDays = days;
    this.report = StudyReportService.build(this.store.getLearningEvents(), this.store.getWrongItems(), days);
  }

  private get masteryPercent(): number {
    return Math.round(this.stats.masteryRate * 100);
  }

  @Builder
  calDayCell(c: CalCell) {
    Column() {
      Text(c.day === 0 ? '' : `${c.day}`)
        .fontSize(13)
        .fontColor(c.day === 0 ? '#00000000' : (c.date === this.selectedDate ? '#ffffff' : '#1a2333'))
      if (c.dueCount > 0) {
        Text(`${c.dueCount}`)
          .fontSize(10)
          .fontColor(c.date === this.selectedDate ? '#ffffff' : '#fa8c16')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(c.day === 0 ? Color.Transparent : (c.date === this.selectedDate ? '#1677ff' : (c.dueCount > 0 ? '#fff4e6' : '#f3f4f6')))
    .onClick(() => {
      this.selectDay(c);
    })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {
          Row({ space: 8 }) {
            Button($r('app.string.nav_back'))
              .height(32)
              .fontSize(14)
              .backgroundColor('#1677ff')
              .onClick(() => {
                DeepLinkRouter.pop();
              })
            Text($r('app.string.stats_title'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1a2333')
          }
          .padding(12)
          .width('100%')

          if (!this.hasMap) {
            Text($r('app.string.stats_no_map'))
              .fontSize(14)
              .fontColor('#8a94a6')
              .padding(12)
              .width('100%')
          }

          // 统计卡片 2 列
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              this.statCard($r('app.string.stats_study_days'), `${this.stats.studyDayCount}`)
              this.statCard($r('app.string.stats_streak'), `${this.stats.streakDays}`)
            }
            .width('100%')

            Row({ space: 12 }) {
              this.statCard($r('app.string.stats_due_review'), `${this.stats.dueReviewCount}`)
              this.statCard($r('app.string.stats_mastered'), `${this.stats.masteredCount}`)
            }
            .width('100%')

            Row({ space: 12 }) {
              this.statCard($r('app.string.stats_total_nodes'), `${this.stats.totalCount}`)
              this.statCard($r('app.string.stats_mastery_rate'), `${this.masteryPercent}%`)
            }
            .width('100%')
          }
          .padding({ left: 16, right: 16 })
          .width('100%')

          // Wave 4：学情报告（周报 / 月报，家长视角）
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text(AccountService.getInstance().getRole() === 'parent' ? '学情报告 · 家长视角' : '学情报告')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
                .layoutWeight(1)
              Button('周报')
                .height(28)
                .fontSize(12)
                .backgroundColor(this.reportDays === 7 ? '#1677ff' : '#f0f3f8')
                .fontColor(this.reportDays === 7 ? '#ffffff' : '#4a5468')
                .onClick(() => {
                  this.switchReport(7);
                })
              Button('月报')
                .height(28)
                .fontSize(12)
                .backgroundColor(this.reportDays === 30 ? '#1677ff' : '#f0f3f8')
                .fontColor(this.reportDays === 30 ? '#ffffff' : '#4a5468')
                .onClick(() => {
                  this.switchReport(30);
                })
            }
            .width('100%')
            if (this.report) {
              Text(this.report.summary)
                .fontSize(13)
                .fontColor('#4a5468')
                .width('100%')
              ForEach(StudyReportService.toLines(this.report), (line: string) => {
                Text(line)
                  .fontSize(12)
                  .fontColor('#8a94a6')
                  .width('100%')
              }, (line: string) => line)
            }
          }
          .padding(12)
          .backgroundColor('#ffffff')
          .borderRadius(12)
          .margin({ left: 16, right: 16 })
          .width('100%')

          // Wave 2：学情画像 · 按学科分组的薄弱情况
          if (this.profile.length > 0) {
            Column({ space: 10 }) {
              Text('学情画像 · 薄弱点')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
                .width('100%')
              ForEach(this.profile, (p: SubjectWeakProfile) => {
                Column({ space: 4 }) {
                  Row() {
                    Text(p.label)
                      .fontSize(13)
                      .fontColor('#1a2333')
                      .layoutWeight(1)
                    Text(`薄弱 ${p.weakCount} / 共 ${p.total}`)
                      .fontSize(11)
                      .fontColor('#8a94a6')
                  }
                  .width('100%')
                  Stack({ alignContent: Alignment.Start }) {
                    Rect()
                      .width('100%')
                      .height(6)
                      .radius(3)
                      .fill('#eef1f6')
                    Rect()
                      .width(`${Math.round(p.masteryRate * 100)}%`)
                      .height(6)
                      .radius(3)
                      .fill(p.weakCount > 0 ? '#fa8c16' : '#52c41a')
                  }
                  .width('100%')
                  .height(6)
                }
                .padding(10)
                .backgroundColor('#ffffff')
                .borderRadius(10)
                .width('100%')
              }, (p: SubjectWeakProfile) => String(p.nodeType))
            }
            .padding({ left: 16, right: 16 })
            .width('100%')
          }

          // Wave 2：最薄弱的知识点清单（前 5）
          if (this.weak.length > 0) {
            Column({ space: 8 }) {
              Text('优先攻克')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
                .width('100%')
              ForEach(this.weak, (w: WeakPointItem) => {
                Row({ space: 8 }) {
                  Text(w.nodeText)
                    .fontSize(13)
                    .fontColor('#1a2333')
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (w.wrongCount > 0) {
                    Text(`错 ${w.wrongCount} 次`)
                      .fontSize(11)
                      .fontColor('#cf1322')
                  }
                  if (w.due) {
                    Text('待复习')
                      .fontSize(11)
                      .fontColor('#d48806')
                  }
                  Button('去学')
                    .height(26)
                    .fontSize(11)
                    .backgroundColor('#1677ff')
                    .onClick(() => {
                      DeepLinkRouter.route(w.nodeId, w.nodeType, w.nodeText);
                    })
                }
                .width('100%')
                .padding(10)
                .backgroundColor('#ffffff')
                .borderRadius(10)
              }, (w: WeakPointItem) => w.nodeId)
            }
            .padding({ left: 16, right: 16 })
            .width('100%')
          }

          // Wave 5：记忆保持预测（保持率越低越该复习）
          if (this.retainItems.length > 0) {
            Column({ space: 10 }) {
              Text('记忆保持预测')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
                .width('100%')
              ForEach(this.retainItems, (r: RetainItem) => {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text(r.text)
                      .fontSize(13)
                      .fontColor('#1a2333')
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${r.retainPct}%`)
                      .fontSize(12)
                      .fontColor(r.retainPct >= 70 ? '#52c41a' : (r.retainPct >= 40 ? '#fa8c16' : '#cf1322'))
                  }
                  .width('100%')
                  Stack({ alignContent: Alignment.Start }) {
                    Rect()
                      .width('100%')
                      .height(6)
                      .radius(3)
                      .fill('#eef1f6')
                    Rect()
                      .width(`${r.retainPct}%`)
                      .height(6)
                      .radius(3)
                      .fill(r.retainPct >= 70 ? '#52c41a' : (r.retainPct >= 40 ? '#fa8c16' : '#cf1322'))
                  }
                  .width('100%')
                  .height(6)
                }
                .padding(10)
                .backgroundColor('#ffffff')
                .borderRadius(10)
                .width('100%')
              }, (r: RetainItem) => r.nodeId)
            }
            .padding({ left: 16, right: 16 })
            .width('100%')
          }

          // Wave 10：复习日历
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('复习日历')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.zhitu_text_primary'))
                .layoutWeight(1)
              Text(this.stats.focusMinutes > 0 ? `累计专注 ${Math.round(this.stats.focusMinutes)} 分钟` : '')
                .fontSize(12)
                .fontColor('#8a94a6')
            }
            .width('100%')
            Row({ space: 8 }) {
              Button('‹')
                .width(36)
                .height(36)
                .fontSize(18)
                .backgroundColor('#eef1f6')
                .fontColor('#1a2333')
                .onClick(() => {
                  this.prevMonth();
                })
              Text(`${this.calYear}年${this.calMonth + 1}月`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1a2333')
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
              Button('›')
                .width(36)
                .height(36)
                .fontSize(18)
                .backgroundColor('#eef1f6')
                .fontColor('#1a2333')
                .onClick(() => {
                  this.nextMonth();
                })
            }
            .width('100%')
            Row({ space: 0 }) {
              ForEach(['日', '一', '二', '三', '四', '五', '六'], (w: string) => {
                Text(w)
                  .fontSize(12)
                  .fontColor('#8a94a6')
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
              }, (w: string) => w)
            }
            .width('100%')
            Grid() {
              ForEach(this.calCells, (c: CalCell) => {
                GridItem() {
                  this.calDayCell(c)
                }
              }, (c: CalCell) => `${c.date}`)
            }
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
            .rowsGap(6)
            .columnsGap(6)
            .height(this.calRows * 46)
            .width('100%')

            // 选中日待复习清单
            Column({ space: 6 }) {
              Text(this.selectedDate.length > 0 ? `${this.selectedDate} 待复习` : '待复习')
                .fontSize(13)
                .fontColor('#1a2333')
                .fontWeight(FontWeight.Bold)
              if (this.selectedDueItems.length === 0) {
                Text('当天没有排定的复习')
                  .fontSize(12)
                  .fontColor('#8a94a6')
              } else {
                ForEach(this.selectedDueItems, (it: DueCalItem) => {
                  Row({ space: 8 }) {
                    Text(it.text)
                      .fontSize(13)
                      .fontColor('#1a2333')
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.typeLabel(it.type))
                      .fontSize(11)
                      .fontColor('#8a94a6')
                  }
                  .width('100%')
                }, (it: DueCalItem) => it.text + it.type)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          // Wave 7：成就墙
          if (this.achievements.length > 0) {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Text('成就墙')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1a2333')
                  .layoutWeight(1)
                Text(`${AchievementService.getInstance().unlockedCount()} / ${this.achievements.length}`)
                  .fontSize(12)
                  .fontColor('#8a94a6')
              }
              .width('100%')
              ForEach(this.achievements, (a: AchievementView) => {
                Row({ space: 10 }) {
                  Text(a.unlocked ? a.icon : '🔒')
                    .fontSize(20)
                    .opacity(a.unlocked ? 1 : 0.45)
                  Column({ space: 2 }) {
                    Row({ space: 6 }) {
                      Text(a.title)
                        .fontSize(13)
                        .fontColor(a.unlocked ? '#1a2333' : '#8a94a6')
                        .layoutWeight(1)
                      Text(a.unlocked ? '已解锁' : `${a.current}/${a.threshold}`)
                        .fontSize(11)
                        .fontColor(a.unlocked ? '#52c41a' : '#8a94a6')
                    }
                    .width('100%')
                    Text(a.desc)
                      .fontSize(11)
                      .fontColor('#8a94a6')
                      .width('100%')
                    Stack({ alignContent: Alignment.Start }) {
                      Rect()
                        .width('100%')
                        .height(5)
                        .radius(2.5)
                        .fill('#eef1f6')
                      Rect()
                        .width(`${Math.round(a.progress * 100)}%`)
                        .height(5)
                        .radius(2.5)
                        .fill(a.unlocked ? '#52c41a' : '#1677ff')
                    }
                    .width('100%')
                    .height(5)
                    .margin({ top: 2 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .padding(10)
                .backgroundColor('#ffffff')
                .borderRadius(10)
                .width('100%')
              }, (a: AchievementView) => a.id)
            }
            .padding({ left: 16, right: 16 })
            .width('100%')
          }

        }
        .width('100%')
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }

  @Builder
  statCard(label: Resource, value: string) {
    Column({ space: 8 }) {
      Text(value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1677ff')
      Text(label)
        .fontSize(13)
        .fontColor('#8a94a6')
    }
    .padding(16)
    .backgroundColor('#ffffff')
    .borderRadius(14)
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}
