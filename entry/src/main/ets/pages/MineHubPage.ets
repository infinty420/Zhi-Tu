/**
 * MineHubPage —— 我的分区：账户 / 我的导图 / 成就墙 / 设置。
 * Wave 9：从原首页「云端」入口与成就能力整合出来的「我的」Tab Hub。
 */
import { promptAction } from '@kit.ArkUI';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { AchievementService, AchievementView } from '../services/AchievementService';
import { BottomTabBar } from '../components/BottomTabBar';

@Component
export struct MineHubPage {
  @Prop tabKey: number = 3;
  onTabChange: (index: number) => void = () => {};

  @State achievements: AchievementView[] = [];
  @State unlockedCount: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.achievements = AchievementService.getInstance().listAchievements();
    this.unlockedCount = AchievementService.getInstance().unlockedCount();
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          Text('我的')
            .fontSize($r('app.float.large_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
            .width('100%')

          // 账户 / 我的导图
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              this.tile('云端账户', '#1677ff', () => {
                DeepLinkRouter.push('AccountPage');
              })
              this.tile('我的导图', '#13c2c2', () => {
                DeepLinkRouter.push('MyMapsPage');
              })
            }
            .width('100%')
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          // 成就墙
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('成就墙')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.zhitu_text_primary'))
                .layoutWeight(1)
              Text(`已解锁 ${this.unlockedCount} / ${this.achievements.length}`)
                .fontSize(12)
                .fontColor('#8a94a6')
            }
            .width('100%')
            Column({ space: 8 }) {
              ForEach(this.achievements, (a: AchievementView) => {
                Row({ space: 10 }) {
                  Text(a.icon)
                    .fontSize(20)
                    .opacity(a.unlocked ? 1 : 0.35)
                  Column({ space: 2 }) {
                    Text(a.title)
                      .fontSize(14)
                      .fontColor(a.unlocked ? '#1a2333' : '#8a94a6')
                      .fontWeight(a.unlocked ? FontWeight.Bold : FontWeight.Normal)
                    Text(a.desc)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Text(`${a.current}/${a.threshold}`)
                    .fontSize(12)
                    .fontColor(a.unlocked ? '#52c41a' : '#8a94a6')
                }
                .padding(10)
                .backgroundColor(a.unlocked ? '#f0fff8' : '#f3f4f6')
                .borderRadius(10)
                .width('100%')
              }, (a: AchievementView) => a.id)
            }
            .width('100%')
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          // 设置 / 关于
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              this.tile('设置', '#722ed1', () => {
                promptAction.showToast({ message: '设置即将上线' });
              })
              this.tile('关于智图', '#fa8c16', () => {
                promptAction.showToast({ message: '智图 · AI 思维导图学习平台' });
              })
            }
            .width('100%')
          }
          .padding(16)
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
  tile(label: string, color: string, onTap: () => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(15)
        .fontColor('#ffffff')
    }
    .height(56)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(color)
    .borderRadius(12)
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }
}
