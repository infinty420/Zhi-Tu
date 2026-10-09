/**
 * BiologyNodePanel —— 生物学科专项面板（结构层级：细胞/组织/器官…）。
 * 纯静态展示 + [+AI补充]；不引入新依赖。
 */
import { BiologyContent, BioHierarchyItem } from '../model/MindNode';

@Component
export struct BiologyNodePanel {
  @Prop content: BiologyContent = { hierarchy: [] };
  onAi: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('🧬 生物 · 结构层级')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#fcffe6')
          .fontColor('#7cb305')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')
      if (this.content.hierarchy.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.content.hierarchy, (item: BioHierarchyItem, idx: number) => {
            Row({ space: 8 }) {
              Text(item.level)
                .fontSize(12)
                .fontColor('#7cb305')
                .fontWeight(FontWeight.Bold)
                .width(64)
              Column({ space: 2 }) {
                Text(item.name)
                  .fontSize(14)
                  .fontColor('#1a2333')
                  .width('100%')
                if (item.desc.length > 0) {
                  Text(item.desc)
                    .fontSize(12)
                    .fontColor('#4a5468')
                    .width('100%')
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (item: BioHierarchyItem, idx: number) => `${idx}_${item.level}_${item.name}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      } else {
        Text('暂无结构层级内容，点「+ AI补充」让 AI 整理')
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
