/**
 * ChineseNodePanel —— 语文学科专项面板（诗词/作者/断句/修辞/赏析）。
 * 纯静态展示 + [+AI补充]；不引入新依赖。
 */
import { ChineseContent } from '../model/MindNode';

@Component
export struct ChineseNodePanel {
  @Prop content: ChineseContent = {
    poem: '', author: '', dynasty: '', punctuation: [], rhetoric: [], notes: []
  };
  onAi: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('📖 语文 · 诗文赏析')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#f9f0ff')
          .fontColor('#722ed1')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')
      if (this.content.poem.length > 0) {
        Text(this.content.poem)
          .fontSize(15)
          .fontColor('#1a2333')
          .width('100%')
        if (this.content.author.length > 0 || this.content.dynasty.length > 0) {
          Text(`${this.content.dynasty}${this.content.dynasty.length > 0 && this.content.author.length > 0 ? ' · ' : ''}${this.content.author}`)
            .fontSize(12)
            .fontColor('#8a94a6')
            .width('100%')
        }
      }
      if (this.content.punctuation.length > 0) {
        Column({ space: 2 }) {
          ForEach(this.content.punctuation, (line: string) => {
            Text(line)
              .fontSize(13)
              .fontColor('#4a5468')
              .width('100%')
          }, (line: string, idx: number) => `${idx}_${line}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      if (this.content.rhetoric.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.content.rhetoric, (t: string) => {
            Text(t)
              .fontSize(12)
              .fontColor('#722ed1')
              .backgroundColor('#f9f0ff')
              .borderRadius(8)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .margin({ right: 6, bottom: 6 })
          }, (t: string) => t)
        }
        .width('100%')
      }
      if (this.content.notes.length > 0) {
        Column({ space: 2 }) {
          ForEach(this.content.notes, (n: string) => {
            Text('· ' + n)
              .fontSize(13)
              .fontColor('#4a5468')
              .width('100%')
          }, (n: string, idx: number) => `${idx}_${n}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      if (this.content.poem.length === 0 && this.content.notes.length === 0) {
        Text('暂无诗文内容，点「+ AI补充」让 AI 生成赏析')
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
