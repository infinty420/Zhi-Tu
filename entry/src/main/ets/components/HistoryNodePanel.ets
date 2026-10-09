/**
 * HistoryNodePanel —— 历史学科专项面板（时间轴事件：年份/事件/描述）。
 * 纯静态展示 + [+AI补充]；不引入新依赖。
 */
import { HistoryContent, HistoryEventItem } from '../model/MindNode';

@Component
export struct HistoryNodePanel {
  @Prop content: HistoryContent = { events: [] };
  onAi: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('🏛 历史 · 时间轴')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#fff7e6')
          .fontColor('#d48806')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')
      if (this.content.events.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.content.events, (ev: HistoryEventItem, idx: number) => {
            Row({ space: 8 }) {
              Text(ev.year)
                .fontSize(12)
                .fontColor('#d48806')
                .fontWeight(FontWeight.Bold)
                .width(56)
              Column({ space: 2 }) {
                Text(ev.title)
                  .fontSize(14)
                  .fontColor('#1a2333')
                  .width('100%')
                if (ev.desc.length > 0) {
                  Text(ev.desc)
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
            .border({ width: { left: 2 }, color: '#ffe7ba' })
            .padding({ left: 8 })
          }, (ev: HistoryEventItem, idx: number) => `${idx}_${ev.year}_${ev.title}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      } else {
        Text('暂无史料内容，点「+ AI补充」让 AI 整理时间轴')
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
