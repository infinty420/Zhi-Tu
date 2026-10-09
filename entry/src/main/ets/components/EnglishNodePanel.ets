/**
 * EnglishNodePanel —— 英语学科专项面板（单词/音标/例句）。
 * Wave 4：例句自检（遮住中文口译 → 对答案 → 重合度判分）+ 例句收藏到生词本。
 * 纯 ArkUI 文本组件，不引入富文本新依赖；判分只做本地字符重合度计算，不新增服务依赖。
 */
import { EnglishContent, EnglishExampleItem } from '../model/MindNode';

/** 去掉空白与常见中英标点，便于做字符级重合比较 */
function normalizeText(s: string): string {
  const skip = [' ', '\n', '\t', ',', '.', '!', '?', ';', '，', '。', '！', '？', '；', '、', '：', ':', '"', '\'', '“', '”'];
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s.charAt(i);
    if (skip.indexOf(c) >= 0) {
      continue;
    }
    out += c;
  }
  return out;
}

/** 用户译文相对参考答案的字符重合度 0~1（按参考答案长度归一） */
function overlapRatio(user: string, answer: string): number {
  const a = normalizeText(user);
  const b = normalizeText(answer);
  if (a.length === 0 || b.length === 0) {
    return 0;
  }
  const pool: string[] = [];
  for (let i = 0; i < b.length; i++) {
    pool.push(b.charAt(i));
  }
  let hit = 0;
  for (let i = 0; i < a.length; i++) {
    const idx = pool.indexOf(a.charAt(i));
    if (idx >= 0) {
      hit++;
      pool.splice(idx, 1);
    }
  }
  return hit / b.length;
}

@Component
export struct EnglishNodePanel {
  @Prop content: EnglishContent = { word: '', phonetic: '', examples: [] };
  onAi: () => void = () => {};
  /** 收藏例句到生词本（页面层统一写入 store） */
  onCollect: (english: string, chinese: string) => void = () => {};
  /** 例句自检结果回传（true=通过），页面层据此更新掌握度 / 复习排队 */
  onSelfTest: (correct: boolean) => void = () => {};
  /** 正在自检的例句下标（-1 表示未开始） */
  @State stIndex: number = -1;
  @State stInput: string = '';
  @State stResult: string = '';
  @State stPassed: boolean = false;

  private startTest(idx: number): void {
    this.stIndex = idx;
    this.stInput = '';
    this.stResult = '';
    this.stPassed = false;
  }

  private submitTest(answer: string): void {
    const ratio = overlapRatio(this.stInput, answer);
    const passed = ratio >= 0.5;
    this.stPassed = passed;
    this.stResult = `重合度 ${Math.round(ratio * 100)}%${passed ? ' · 通过' : ' · 还需巩固'}｜参考：${answer}`;
    this.onSelfTest(passed);
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('🔤 英语 · 词汇')
          .fontSize(14)
          .fontColor('#5f6b7f')
          .layoutWeight(1)
        Button('+ AI补充')
          .height(28)
          .fontSize(12)
          .backgroundColor('#fff0f6')
          .fontColor('#eb2f96')
          .onClick(() => {
            this.onAi();
          })
      }
      .width('100%')
      if (this.content.word.length > 0) {
        Row({ space: 8 }) {
          Text(this.content.word)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
          if (this.content.phonetic.length > 0) {
            Text(this.content.phonetic)
              .fontSize(13)
              .fontColor('#8a94a6')
              .fontStyle(FontStyle.Italic)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      if (this.content.examples.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.content.examples, (ex: EnglishExampleItem, idx: number) => {
            Column({ space: 6 }) {
              Text(ex.english)
                .fontSize(14)
                .fontColor('#1a2333')
                .width('100%')
              if (this.stIndex !== idx) {
                Text(ex.chinese)
                  .fontSize(12)
                  .fontColor('#4a5468')
                  .width('100%')
              }
              Row({ space: 8 }) {
                Button(this.stIndex === idx ? '结束自检' : '自检')
                  .height(26)
                  .fontSize(11)
                  .backgroundColor('#eb2f96')
                  .onClick(() => {
                    if (this.stIndex === idx) {
                      this.stIndex = -1;
                      this.stInput = '';
                      this.stResult = '';
                    } else {
                      this.startTest(idx);
                    }
                  })
                Button('收藏')
                  .height(26)
                  .fontSize(11)
                  .backgroundColor('#13c2c2')
                  .onClick(() => {
                    this.onCollect(ex.english, ex.chinese);
                  })
              }
              .width('100%')

              if (this.stIndex === idx) {
                if (this.stResult.length === 0) {
                  TextInput({ placeholder: '遮住中文，写出你的翻译', text: this.stInput })
                    .height(40)
                    .width('100%')
                    .onChange((v: string) => {
                      this.stInput = v;
                    })
                  Button('对答案')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#1677ff')
                    .onClick(() => {
                      this.submitTest(ex.chinese);
                    })
                } else {
                  Text(this.stResult)
                    .fontSize(12)
                    .fontColor(this.stPassed ? '#52c41a' : '#cf1322')
                    .width('100%')
                  Button('再练一次')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#f0f3f8')
                    .fontColor('#4a5468')
                    .onClick(() => {
                      this.startTest(idx);
                    })
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(8)
            .borderRadius(8)
            .backgroundColor('#fff0f6')
          }, (ex: EnglishExampleItem, idx: number) => `${idx}_${ex.english}`)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      if (this.content.word.length === 0) {
        Text('暂无词汇内容，点「+ AI补充」让 AI 生成')
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
