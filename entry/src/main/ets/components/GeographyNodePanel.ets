/**
 * GeographyNodePanel —— 地理学科专项面板（区域 + 坐标点列表）。
 * 坐标以归一化（0~1）呈现，纯文本/列表展示，不接入地图 Kit。
 */
import { GeographyContent, GeoCoord } from '../model/MindNode';

@Component
export struct GeographyNodePanel {
  @Prop content: GeographyContent = { region: '', coords: [] };
  onAi: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('🗺 地理 · 区域与坐标')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#e6fffb')
          .fontColor('#08979c')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')
      if (this.content.region.length > 0) {
        Text(`区域：${this.content.region}`)
          .fontSize(13)
          .fontColor('#1a2333')
          .width('100%')
      }
      if (this.content.coords.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.content.coords, (c: GeoCoord, idx: number) => {
            Row({ space: 6 }) {
              Text(c.name)
                .fontSize(13)
                .fontColor('#1a2333')
                .layoutWeight(1)
              if (c.note.length > 0) {
                Text(c.note)
                  .fontSize(11)
                  .fontColor('#8a94a6')
                  .layoutWeight(1)
              }
              Text(`(${this.fmt(c.x)}, ${this.fmt(c.y)})`)
                .fontSize(11)
                .fontColor('#08979c')
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }, (c: GeoCoord, idx: number) => `${idx}_${c.name}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      } else {
        Text('暂无地理坐标内容，点「+ AI补充」让 AI 整理')
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

  private fmt(v: number): string {
    return v.toFixed(2);
  }
}
