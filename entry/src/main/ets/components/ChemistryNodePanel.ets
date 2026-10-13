/**
 * ChemistryNodePanel —— 化学学科专项面板（方程式/配平/反应物产物/现象）。
 * 纯静态展示 + [+AI补充]；方程式以文本呈现，不接入化学绘图新依赖。
 */
import { ChemistryContent } from '../model/MindNode';

@Component
export struct ChemistryNodePanel {
  @Prop content: ChemistryContent = {
    equation: '', balanced: false, reactants: [], products: [], phenomenon: ''
  };
  onAi: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('⚗ 化学 · 方程式')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#f6ffed')
          .fontColor('#389e0d')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')
      if (this.content.equation.length > 0) {
        Row({ space: 8 }) {
          Text(this.content.equation)
            .fontSize(15)
            .fontFamily('monospace')
            .fontColor('#1a2333')
            .layoutWeight(1)
          Text(this.content.balanced ? '已配平' : '待配平')
            .fontSize(11)
            .fontColor(this.content.balanced ? '#389e0d' : '#d48806')
            .backgroundColor(this.content.balanced ? '#f6ffed' : '#fffbe6')
            .borderRadius(8)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      if (this.content.reactants.length > 0 || this.content.products.length > 0) {
        Row({ space: 8 }) {
          if (this.content.reactants.length > 0) {
            Column({ space: 2 }) {
              Text('反应物')
                .fontSize(11)
                .fontColor('#8a94a6')
              ForEach(this.content.reactants, (r: string) => {
                Text(r)
                  .fontSize(13)
                  .fontColor('#1a2333')
              }, (r: string) => r)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          if (this.content.products.length > 0) {
            Column({ space: 2 }) {
              Text('生成物')
                .fontSize(11)
                .fontColor('#8a94a6')
              ForEach(this.content.products, (p: string) => {
                Text(p)
                  .fontSize(13)
                  .fontColor('#1a2333')
              }, (p: string) => p)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      if (this.content.phenomenon.length > 0) {
        Text(`实验现象：${this.content.phenomenon}`)
          .fontSize(13)
          .fontColor('#4a5468')
          .width('100%')
      }
      if (this.content.equation.length === 0) {
        Text('暂无方程式内容，点「+ AI补充」让 AI 生成')
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
