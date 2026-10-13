/**
 * PhotoQuizPage —— 拍照识题（Wave 8 起，端侧 OCR，无云依赖）。
 * 流程：相册多选 → ImageSource 解码为 PixelMap → CoreVisionKit 端侧文本识别 →
 * 多张图识别文字累积 → 一键生成思维导图。支持「公式题模式」保留数学结构。
 * OCR 失败可手动编辑文字后继续。
 */

import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { promptAction } from '@kit.ArkUI';
import { MindMapStore } from '../services/MindMapStore';
import { AIConfig } from '../services/AIConfig';
import { AIServiceFactory } from '../services/AIServiceFactory';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { Logger } from '../utils/Logger';

@Entry
@Component
export struct PhotoQuizPage {
  @State imgUris: string[] = [];
  @State recognized: string = '';
  @State editing: boolean = false;
  @State busy: boolean = false;
  @State toast: string = '';
  /** Wave 11：公式题模式（保留数学/公式结构，生成时按数学学科提示） */
  @State formulaMode: boolean = false;
  private store: MindMapStore = MindMapStore.getInstance();

  build() {
    NavDestination() {
      Column({ space: 14 }) {
        Row({ space: 8 }) {
          Button('返回')
            .height(32)
            .fontSize(14)
            .backgroundColor('#1677ff')
            .onClick(() => {
              DeepLinkRouter.pop();
            })
          Text('拍照识题')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
            .layoutWeight(1)
          // Wave 11：公式题模式开关
          Row({ space: 6 }) {
            Text(this.formulaMode ? '公式题' : '普通题')
              .fontSize(12)
              .fontColor(this.formulaMode ? '#d48806' : '#8a94a6')
            Toggle({ type: ToggleType.Switch, isOn: this.formulaMode })
              .width(42)
              .height(24)
              .onChange((v: boolean) => {
                this.formulaMode = v;
              })
          }
        }
        .padding(12)
        .width('100%')

        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 8 }) {
              Text('把一道或多道题的截图/照片选进来，端侧识别文字后一键生成导图（可连续多张）。')
                .fontSize(13)
                .fontColor('#4a5468')
                .width('100%')
              Button(this.imgUris.length > 0 ? '继续添加图片' : '从相册选择题目(可多选)')
                .width('100%')
                .height(44)
                .fontSize(14)
                .backgroundColor('#1677ff')
                .enabled(!this.busy)
                .onClick(() => {
                  this.pickAndRecognize();
                })
            }
            .padding(14)
            .backgroundColor('#ffffff')
            .borderRadius(12)
            .width('100%')

            if (this.imgUris.length > 0) {
              Text(`已选 ${this.imgUris.length} 张图片`)
                .fontSize(12)
                .fontColor('#8a94a6')
                .width('100%')
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.imgUris, (uri: string) => {
                    Image(uri)
                      .width(120)
                      .height(120)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(10)
                  }, (uri: string) => uri)
                }
                .width('100%')
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }

            if (this.recognized.length > 0 || this.editing) {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text('识别结果（可手动修正）')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#1a2333')
                    .layoutWeight(1)
                  if (!this.editing) {
                    Button('编辑')
                      .height(26)
                      .fontSize(12)
                      .backgroundColor('#f0f3f8')
                      .fontColor('#4a5468')
                      .onClick(() => {
                        this.editing = true;
                      })
                  }
                }
                .width('100%')
                if (this.editing) {
                  TextArea({ text: this.recognized, placeholder: '请填写或修正题目文字' })
                    .height(140)
                    .fontSize(14)
                    .onChange((v: string) => {
                      this.recognized = v;
                    })
                  Button('完成')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#1677ff')
                    .onClick(() => {
                      this.editing = false;
                    })
                } else {
                  Text(this.recognized)
                    .fontSize(14)
                    .fontColor('#1a2333')
                    .width('100%')
                }
              }
              .padding(14)
              .backgroundColor('#ffffff')
              .borderRadius(12)
              .width('100%')
            }

            if (this.busy) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color('#1677ff')
                Text('识别 / 生成中…')
                  .fontSize(13)
                  .fontColor('#4a5468')
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }

            if (this.recognized.trim().length > 0) {
              Button('生成思维导图')
                .width('100%')
                .height(48)
                .fontSize(15)
                .fontColor('#ffffff')
                .backgroundColor('#13c2c2')
                .enabled(!this.busy)
                .onClick(() => {
                  this.generate();
                })
            }

            if (this.toast.length > 0) {
              Text(this.toast)
                .fontSize(12)
                .fontColor('#fa8c16')
                .width('100%')
            }
          }
          .padding(16)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }

  /** 多选 → 逐张端侧 OCR，识别文字累积 */
  private async pickAndRecognize(): Promise<void> {
    if (this.busy) {
      return;
    }
    let picker: photoAccessHelper.PhotoViewPicker;
    try {
      picker = new photoAccessHelper.PhotoViewPicker();
    } catch (err) {
      this.toast = '无法打开相册选择器';
      return;
    }
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 4;
    this.busy = true;
    this.toast = '';
    let anyText = false;
    try {
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      const uris: Array<string> = result.photoUris;
      if (!uris || uris.length === 0) {
        this.busy = false;
        return;
      }
      let acc = this.recognized.trim().length > 0 ? this.recognized.trim() + '\n\n' : '';
      for (let i = 0; i < uris.length; i++) {
        const uri = uris[i];
        if (this.imgUris.indexOf(uri) < 0) {
          this.imgUris.push(uri);
        }
        const text = await this.recognize(uri);
        if (text.length > 0) {
          anyText = true;
          acc += (acc.length > 0 ? '\n' : '') + text;
        }
      }
      this.recognized = acc;
      if (!anyText) {
        this.editing = true;
        this.toast = '未识别到文字，可手动输入题目';
      }
    } catch (err) {
      Logger.error('PhotoQuizPage', `pick/recognize failed: ${JSON.stringify(err)}`);
      this.toast = '识别失败，可手动输入题目';
      this.editing = true;
    }
    this.busy = false;
  }

  /** 端侧文本识别：uri → PixelMap → CoreVisionKit.recognizeText */
  private async recognize(uri: string): Promise<string> {
    let src: image.ImageSource | undefined = undefined;
    try {
      src = image.createImageSource(uri);
      const pixelMap = await src.createPixelMap();
      const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
      const config: textRecognition.TextRecognitionConfiguration = {};
      const res = await textRecognition.recognizeText(visionInfo, config);
      pixelMap.release();
      const value: string = res.value;
      return value ? value.trim() : '';
    } catch (err) {
      Logger.error('PhotoQuizPage', `recognizeText failed: ${JSON.stringify(err)}`);
      return '';
    } finally {
      if (src) {
        src.release();
      }
    }
  }

  /** 用识别文字生成思维导图（公式题模式按数学学科提示） */
  private async generate(): Promise<void> {
    const query = this.recognized.trim();
    if (query.length === 0) {
      promptAction.showToast({ message: '请先提供题目文字' });
      return;
    }
    this.busy = true;
    Logger.aiRequest('PhotoQuizPage', 'request', 'photo generateMindMap');
    try {
      const config = AIConfig.load();
      const svc = AIServiceFactory.create(config);
      const res = await svc.generateMindMap(
        { query: query, subject: this.formulaMode ? 'math' : '', book: '' },
        () => { });
      if (res.ok) {
        const imported = this.store.importAsNew(res.data.map.toJson());
        if (imported.ok) {
          this.busy = false;
          DeepLinkRouter.push('MindMapPage');
          return;
        }
        this.toast = '生成结果无效，请重试';
      } else {
        this.toast = '生成失败，请重试';
      }
    } catch (err) {
      Logger.aiRequest('PhotoQuizPage', 'failed', JSON.stringify(err));
      this.toast = '生成失败，请重试';
    }
    this.busy = false;
  }
}
