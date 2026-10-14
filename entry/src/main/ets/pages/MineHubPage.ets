/**
 * MineHubPage —— 我的分区：个人卡 / 入口 / 成就墙 / 设置。
 * Wave 9：从原首页「云端」入口与成就能力整合出来的「我的」Tab Hub。
 * 2026-10-14 UI 重构：个人卡 + 图标入口 + 三列成就徽章网格 + 列表式设置，去冗杂。
 */
import { promptAction } from '@kit.ArkUI';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { AchievementService, AchievementView } from '../services/AchievementService';
import { MindMapStore } from '../services/MindMapStore';
import { BottomTabBar } from '../components/BottomTabBar';

@Component
export struct MineHubPage {
  @Prop tabKey: number = 3;
  onTabChange: (index: number) => void = () => {};

  @State achievements: AchievementView[] = [];
  @State unlockedCount: number = 0;
  @State streakDays: number = 0;
  @State studyDayCount: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    const svc = AchievementService.getInstance();
    this.achievements = svc.listAchievements();
    this.unlockedCount = svc.unlockedCount();
    const stats = MindMapStore.getInstance().getStudyStats();
    this.streakDays = stats.streakDays;
    this.studyDayCount = stats.studyDayCount;
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 个人卡
          this.profileCard()

          // 图标入口
          Row({ space: 10 }) {
            this.entryTile('云端账户', '同步与备份', '云', '#185fa5', '#e6f1fb', () => {
              DeepLinkRouter.push('AccountPage');
            })
            this.entryTile('我的导图', '管理与导入', '图', '#0f6e56', '#e1f5ee', () => {
              DeepLinkRouter.push('MyMapsPage');
            })
          }
          .width('100%')

          // 成就墙
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('成就墙')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.zhitu_text_primary'))
                .layoutWeight(1)
              // 总进度条
              Column() {
                Column()
                  .width(`${Math.round(this.unlockedCount / this.achievements.length * 100)}%`)
                  .height(5)
                  .backgroundColor('#1d9e75')
                  .borderRadius(3)
              }
              .width(96)
              .height(5)
              .backgroundColor('#eef0f4')
              .borderRadius(3)
              Text(`${this.unlockedCount}/${this.achievements.length}`)
                .fontSize(11)
                .fontColor('#8a94a6')
            }
            .width('100%')

            Grid() {
              ForEach(this.achievements, (a: AchievementView) => {
                GridItem() {
                  Column({ space: 6 }) {
                    Text(a.icon)
                      .fontSize(16)
                      .width(30)
                      .height(30)
                      .borderRadius(15)
                      .textAlign(TextAlign.Center)
                      .backgroundColor(a.unlocked ? '#1d9e75' : '#d9dde3')
                      .fontColor(a.unlocked ? '#ffffff' : '#8a94a6')
                    Text(a.title)
                      .fontSize(12)
                      .fontColor(a.unlocked ? '#0f6e56' : '#8a94a6')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    // 进度条
                    Row() {
                      Row()
                        .width(`${Math.round(a.progress * 100)}%`)
                        .height(3)
                        .backgroundColor(a.unlocked ? '#1d9e75' : '#b4b2a9')
                        .borderRadius(2)
                    }
                    .width('100%')
                    .height(3)
                    .backgroundColor(a.unlocked ? '#c9ead9' : '#e7eaef')
                    .borderRadius(2)
                  }
                  .alignItems(HorizontalAlign.Center)
                  .padding(8)
                  .width('100%')
                  .height(74)
                  .backgroundColor(a.unlocked ? '#eaf7f0' : '#f7f8fa')
                  .borderRadius(10)
                  .border(a.unlocked ? { width: 1, color: '#1d9e75' } : { width: 0.5, color: '#e5e8ef' })
                  .onClick(() => {
                    promptAction.showToast({
                      message: `${a.title}：${a.desc}（${a.current}/${a.threshold}）`
                    });
                  })
                }
              }, (a: AchievementView) => a.id)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
            .width('100%')
            .height(Math.ceil(this.achievements.length / 3) * 74 + (Math.ceil(this.achievements.length / 3) - 1) * 8)
            .scrollBar(BarState.Off)
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          // 设置 / 关于（列表式）
          Column({ space: 0 }) {
            this.listRow('设置', '设', '#534ab7', '#eeedfe', () => {
              promptAction.showToast({ message: '设置即将上线' });
            })
            Divider()
              .color('#eef0f4')
              .height(0.5)
            this.listRow('关于智图', '关', '#854f0b', '#faeeda', () => {
              promptAction.showToast({ message: '智图 · AI 思维导图学习平台' });
            })
          }
          .padding({ left: 14, right: 12 })
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          Text('你的学习数据本地加密存储，安心使用')
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
  profileCard() {
    Row({ space: 12 }) {
      Column() {
        Text('智')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0f6e56')
      }
      .width(46)
      .height(46)
      .borderRadius(23)
      .backgroundColor('#e1f5ee')
      .align(Alignment.Center)
      Column({ space: 2 }) {
        Text('智图学习者')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
        Text(`已解锁 ${this.unlockedCount}/${this.achievements.length} 成就 · 连续学习 ${this.streakDays} 天`)
          .fontSize(12)
          .fontColor('#9fe1cb')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Column() {
        Text('›')
          .fontSize(12)
          .fontColor('#0f6e56')
          .fontWeight(FontWeight.Medium)
      }
      .width(26)
      .height(26)
      .borderRadius(13)
      .backgroundColor('#ffffff')
      .align(Alignment.Center)
      .onClick(() => {
        DeepLinkRouter.push('AccountPage');
      })
    }
    .padding(16)
    .width('100%')
    .backgroundColor('#0f6e56')
    .borderRadius(14)
  }

  @Builder
  entryTile(label: string, sub: string, glyph: string, color: string, tint: string, onTap: () => void) {
    Row({ space: 10 }) {
      Column() {
        Text(glyph)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(color)
      }
      .width(34)
      .height(34)
      .borderRadius(9)
      .backgroundColor(tint)
      .align(Alignment.Center)
      Column({ space: 1 }) {
        Text(label)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a2333')
        Text(sub)
          .fontSize(11)
          .fontColor('#8a94a6')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .padding(12)
    .backgroundColor($r('app.color.zhitu_bg_card'))
    .borderRadius(12)
    .border({ width: 0.5, color: '#e5e8ef' })
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  @Builder
  listRow(label: string, glyph: string, color: string, tint: string, onTap: () => void) {
    Row({ space: 10 }) {
      Column() {
        Text(glyph)
          .fontSize(12)
          .fontColor(color)
      }
      .width(26)
      .height(26)
      .borderRadius(8)
      .backgroundColor(tint)
      .align(Alignment.Center)
      Text(label)
        .fontSize(13)
        .fontColor('#1a2333')
        .layoutWeight(1)
      Text('›')
        .fontSize(14)
        .fontColor('#b4b2a9')
    }
    .padding({ top: 12, bottom: 12 })
    .width('100%')
    .onClick(onTap)
  }
}
