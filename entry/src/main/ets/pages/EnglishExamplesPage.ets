/**
 * EnglishExamplesPage —— 英语例句专项子界面（NavDestination，深链 english）。
 * AI 生成分级例句（英文/翻译/划词解析）、语音朗读、收藏回填；Mock 降级离线可用。
 */
import { promptAction } from '@kit.ArkUI';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { ExampleItem } from '../services/AIService';
import { AIConfig } from '../services/AIConfig';
import { AIServiceFactory } from '../services/AIServiceFactory';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { MindMapStore } from '../services/MindMapStore';
import { VocabItem } from '../model/StudyModels';
import { AppContextHolder } from '../utils/AppContext';
import { Logger } from '../utils/Logger';

@Component
export struct EnglishExamplesPage {
  @State examples: ExampleItem[] = [];
  @State loading: boolean = false;
  @State failed: boolean = false;
  @State favoriteIds: string[] = [];
  @State ttsAvailable: boolean = false;
  @State nodeId: string = '';
  @State nodeTitle: string = '英语例句';
  private word: string = '';
  private ttsEngine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private store: MindMapStore = MindMapStore.getInstance();

  aboutToAppear(): void {
    this.initTts();
    const link = DeepLinkRouter.currentLink();
    this.nodeId = link.nodeId;
    this.nodeTitle = link.payload && link.payload.length > 0 ? link.payload : '英语例句';
    this.word = link.payload ? link.payload : '';
    this.loadExamples();
  }

  aboutToDisappear(): void {
    if (this.ttsEngine) {
      try {
        this.ttsEngine.shutdown();
      } catch (err) {
        // 忽略释放异常
      }
      this.ttsEngine = undefined;
      this.ttsAvailable = false;
    }
  }

  private initTts(): void {
    try {
      const initParams: textToSpeech.CreateEngineParams = {
        language: 'en-US',
        person: 0,
        online: 1
      };
      textToSpeech.createEngine(initParams, (err, data) => {
        if (!err && data) {
          this.ttsEngine = data;
          this.ttsAvailable = true;
        } else {
          this.ttsAvailable = false;
        }
      });
    } catch (err) {
      this.ttsAvailable = false;
    }
  }

  private async loadExamples(): Promise<void> {
    this.loading = true;
    this.failed = false;
    try {
      const config = AIConfig.load();
      const svc = AIServiceFactory.create(config);
      const res = await svc.generateExamples({ word: this.word });
      if (res.ok) {
        this.examples = res.data.examples;
        this.syncFavoritesFromVocab();
      } else {
        this.failed = true;
      }
    } catch (err) {
      Logger.error('EnglishExamplesPage', `load failed ${JSON.stringify(err)}`);
      this.failed = true;
    }
    this.loading = false;
  }

  private speak(english: string): void {
    if (!this.ttsEngine || !this.ttsAvailable) {
      promptAction.showToast({ message: '当前设备暂不支持语音朗读' });
      return;
    }
    try {
      const extraParam: Record<string, Object> = {
        'languageContext': 'en-US'
      };
      const speakParams: textToSpeech.SpeakParams = {
        requestId: 'zhitu_example_1',
        extraParams: extraParam
      };
      this.ttsEngine.speak(english, speakParams);
    } catch (err) {
      this.ttsAvailable = false;
      promptAction.showToast({ message: '当前设备暂不支持语音朗读' });
    }
  }

  /** 与本地生词本对齐当前例句收藏状态（去重按 英文+中文） */
  private syncFavoritesFromVocab(): void {
    const vocab: VocabItem[] = this.store.getVocabItems();
    const fav: string[] = [];
    for (let i = 0; i < this.examples.length; i++) {
      const ex = this.examples[i];
      let matched = false;
      for (let j = 0; j < vocab.length; j++) {
        if (vocab[j].english === ex.english && vocab[j].chinese === ex.chinese) {
          matched = true;
          break;
        }
      }
      if (matched) {
        fav.push(ex.id);
      }
    }
    this.favoriteIds = fav;
  }

  /** 收藏即沉淀到生词本（再次点击取消收藏并移除） */
  private toggleFavorite(item: ExampleItem): void {
    const idx = this.favoriteIds.indexOf(item.id);
    if (idx >= 0) {
      const next = this.favoriteIds.slice();
      next.splice(idx, 1);
      this.favoriteIds = next;
      this.store.removeVocabItem(`voc_${item.id}`);
    } else {
      const next = this.favoriteIds.slice();
      next.push(item.id);
      this.favoriteIds = next;
      const vocab: VocabItem = {
        id: `voc_${item.id}`,
        english: item.english,
        chinese: item.chinese,
        analysis: item.analysis,
        createdAt: Date.now()
      };
      this.store.addVocabItem(vocab);
    }
  }

  private backfillFavorites(): void {
    if (this.favoriteIds.length === 0) {
      promptAction.showToast({ message: '尚未收藏例句' });
      return;
    }
    const favEx: ExampleItem[] = [];
    for (let i = 0; i < this.favoriteIds.length; i++) {
      for (let j = 0; j < this.examples.length; j++) {
        if (this.examples[j].id === this.favoriteIds[i]) {
          favEx.push(this.examples[j]);
          break;
        }
      }
    }
    let content = `收藏例句（${this.word}）：`;
    for (let i = 0; i < favEx.length; i++) {
      content += `\n${i + 1}. ${favEx[i].english}（${favEx[i].chinese}）`;
    }
    DeepLinkRouter.backfill(this.nodeId, content);
    promptAction.showToast({ message: '已回填到节点备注' });
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          Button('返回')
            .height(32)
            .fontSize(14)
            .backgroundColor('#1677ff')
            .onClick(() => {
              DeepLinkRouter.pop();
            })
          Text('英语例句')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Button('收藏并回填')
            .height(32)
            .fontSize(13)
            .backgroundColor('#722ed1')
            .onClick(() => {
              this.backfillFavorites();
            })
        }
        .padding(12)
        .width('100%')

        Text(this.word.length > 30 ? this.word.substring(0, 30) + '…' : this.word)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1677ff')
          .padding(8)
          .width('100%')

        if (this.loading) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color('#1677ff')
            Text('正在生成例句…')
              .fontSize(14)
              .fontColor('#8a94a6')
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 40 })
        } else if (this.failed) {
          Column({ space: 12 }) {
            Text('例句生成失败，请重试')
              .fontSize(14)
              .fontColor('#f5222d')
            Button('重试')
              .backgroundColor('#1677ff')
              .onClick(() => {
                this.loadExamples();
              })
          }
          .width('100%')
          .margin({ top: 40 })
        } else if (this.examples.length === 0) {
          Text('暂无内容')
            .fontSize(14)
            .fontColor('#8a94a6')
            .margin({ top: 40 })
            .width('100%')
            .textAlign(TextAlign.Center)
        } else {
          List({ space: 10 }) {
            ForEach(this.examples, (item: ExampleItem) => {
              ListItem() {
                Column({ space: 6 }) {
                  Row({ space: 6 }) {
                    Text(item.level)
                      .fontSize(12)
                      .fontColor('#ffffff')
                      .backgroundColor(item.level === '高考' ? '#eb2f96' : '#00b96b')
                      .borderRadius(8)
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    Blank()
                    Button(this.favoriteIds.indexOf(item.id) >= 0 ? '已收藏' : '收藏')
                      .height(28)
                      .fontSize(12)
                      .backgroundColor(this.favoriteIds.indexOf(item.id) >= 0 ? '#faad14' : '#d9d9d9')
                      .onClick(() => {
                        this.toggleFavorite(item);
                      })
                    Button('朗读')
                      .height(28)
                      .fontSize(12)
                      .backgroundColor(this.ttsAvailable ? '#1677ff' : '#d9d9d9')
                      .enabled(this.ttsAvailable)
                      .onClick(() => {
                        this.speak(item.english);
                      })
                  }
                  Text(item.english)
                    .fontSize(16)
                    .fontColor('#1a2333')
                    .width('100%')
                  Text(item.chinese)
                    .fontSize(14)
                    .fontColor('#8a94a6')
                    .width('100%')
                  Text(item.analysis)
                    .fontSize(13)
                    .fontColor('#1677ff')
                    .backgroundColor('#e6f4ff')
                    .borderRadius(8)
                    .padding(8)
                    .width('100%')
                }
                .padding(12)
                .backgroundColor('#ffffff')
                .borderRadius(12)
              }
            }, (item: ExampleItem) => item.id)
          }
          .layoutWeight(1)
          .padding(12)
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }
}