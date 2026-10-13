/**
 * CommunityHubPage —— 社区分区：精品市场 / 我的班级 / 全局搜索 / 分享。
 * Wave 9：从原首页「一起学」拆分出来的「社区」Tab Hub。
 */
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { BottomTabBar } from '../components/BottomTabBar';

@Component
export struct CommunityHubPage {
  @Prop tabKey: number = 2;
  onTabChange: (index: number) => void = () => {};

  build() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          Text('一起学')
            .fontSize($r('app.float.large_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
            .width('100%')
          Text('把导图分享出去，看看同学和老师怎么学')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.zhitu_text_secondary'))
            .width('100%')

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              this.tile('精品市场', '#13c2c2', () => {
                DeepLinkRouter.push('MarketPage');
              })
              this.tile('我的班级', '#722ed1', () => {
                DeepLinkRouter.push('ClassPage');
              })
            }
            .width('100%')
            Row({ space: 10 }) {
              this.tile('全局搜索', '#fa8c16', () => {
                DeepLinkRouter.push('SearchPage');
              })
              this.tile('分享导图', '#1677ff', () => {
                DeepLinkRouter.push('SharePage');
              })
            }
            .width('100%')
          }
          .padding(16)
          .backgroundColor($r('app.color.zhitu_bg_card'))
          .borderRadius($r('app.float.card_round_corner'))
          .width('100%')

          Text('社区能力将在云端版本中持续增强')
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
    .height(64)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(color)
    .borderRadius(12)
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }
}
