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

/** 记忆保持预测项（Wave 5：保持率越低越该复习） */
interface RetainItem {
  nodeId: string;
  text: string;
  /** 当前记忆保持率百分比 0~100 */
  retainPct: number;
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
    todayEventCount: 0
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
  }

  /** 切换周报 / 月报 */
  private switchReport(days: number): void {
    this.reportDays = days;
    this.report = StudyReportService.build(this.store.getLearningEvents(), this.store.getWrongItems(), days);
  }

  private get masteryPercent(): number {
    return Math.round(this.stats.masteryRate * 100);
  }

  build() {
    NavDestination() {
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

        Blank()
      }
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
