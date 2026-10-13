/**
 * PoliticsNodePanel —— 政治学科专项面板（正/反观点 + 时事）。
 * 纯静态展示 + [+AI补充]；不引入新依赖。
 */
import { PoliticsContent } from '../model/MindNode';

@Component
export struct PoliticsNodePanel {
  @Prop content: PoliticsContent = { viewpointFor: '', viewpointAgainst: '', currentAffairs: [] };
  onAi: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('⚖ 政治 · 观点与时事')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#fff1f0')
          .fontColor('#cf1322')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')
      if (this.content.viewpointFor.length > 0) {
        Row({ space: 6 }) {
          Text('正方')
            .fontSize(12)
            .fontColor('#389e0d')
            .fontWeight(FontWeight.Bold)
          Text(this.content.viewpointFor)
            .fontSize(13)
            .fontColor('#1a2333')
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      if (this.content.viewpointAgainst.length > 0) {
        Row({ space: 6 }) {
          Text('反方')
            .fontSize(12)
            .fontColor('#cf1322')
            .fontWeight(FontWeight.Bold)
          Text(this.content.viewpointAgainst)
            .fontSize(13)
            .fontColor('#1a2333')
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      if (this.content.currentAffairs.length > 0) {
        Column({ space: 2 }) {
          Text('时事链接')
            .fontSize(11)
            .fontColor('#8a94a6')
          ForEach(this.content.currentAffairs, (a: string) => {
            Text('· ' + a)
              .fontSize(13)
              .fontColor('#4a5468')
              .width('100%')
          }, (a: string) => a)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      if (this.content.viewpointFor.length === 0 && this.content.viewpointAgainst.length === 0) {
        Text('暂无观点内容，点「+ AI补充」让 AI 生成辨析')
          .fontSize(12)
          .fontColor('#b0b9c9')
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(12)
    .backgroundColor('#ffffff')
    .width('100%')
  }
}
