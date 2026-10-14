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
        Column({ space: 14 }) {
          Text('一起学')
            .fontSize($r('app.float.large_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.zhitu_text_primary'))
            .width('100%')
          Text('把导图分享出去，看看同学和老师怎么学')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.zhitu_text_secondary'))
            .width('100%')

          // 分享 banner（强调态）
          Row({ space: 12 }) {
            Column() {
              Text('分')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1677ff')
            }
            .width(38)
            .height(38)
            .borderRadius(11)
            .backgroundColor('#e6f1fb')
            .align(Alignment.Center)
            Column({ space: 2 }) {
              Text('分享导图，解锁班级排行')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#1a2333')
              Text('把你的学习成果分享到班级与社区')
                .fontSize(11)
                .fontColor('#8a94a6')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button('去分享')
              .height(32)
              .fontSize(13)
              .fontColor('#ffffff')
              .backgroundColor('#1677ff')
              .onClick(() => {
                DeepLinkRouter.push('SharePage');
              })
          }
          .padding(14)
          .backgroundColor('#f2f8ff')
          .borderRadius(14)
          .border({ width: 0.5, color: '#b8d8fb' })
          .width('100%')

          // 四个入口（2x2 图标卡网格）
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              this.communityTile('精品市场', '优质模板', '市', '#0f6e56', '#e1f5ee', false, () => {
                DeepLinkRouter.push('MarketPage');
              })
              this.communityTile('我的班级', '学情排行', '班', '#722ed1', '#eeedfe', false, () => {
                DeepLinkRouter.push('ClassPage');
              })
            }
            .width('100%')
            Row({ space: 10 }) {
              this.communityTile('全局搜索', '找好图', '搜', '#854f0b', '#faeeda', false, () => {
                DeepLinkRouter.push('SearchPage');
              })
              this.communityTile('分享导图', '一键分享', '享', '#1677ff', '#e6f1fb', true, () => {
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
  communityTile(label: string, sub: string, glyph: string, color: string, tint: string, emphasize: boolean, onTap: () => void) {
    Row({ space: 10 }) {
      Column() {
        Text(glyph)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(color)
      }
      .width(34)
      .height(34)
      .borderRadius(10)
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
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(14)
        .fontColor('#b4b2a9')
    }
    .padding(12)
    .backgroundColor(emphasize ? '#f2f8ff' : '#f3f4f6')
    .borderRadius(12)
    .border(emphasize ? { width: 1, color: '#1677ff' } : { width: 0.5, color: '#e5e8ef' })
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }
}
