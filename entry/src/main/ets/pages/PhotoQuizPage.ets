/**
 * PhotoQuizPage —— 拍照识题（Wave 8，端侧 OCR，无云依赖）。
 * 流程：相册选图 → ImageSource 解码为 PixelMap → CoreVisionKit 端侧文本识别 →
 * 展示识别文字 → 一键生成思维导图。OCR 失败可手动编辑文字后继续。
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
  @State imgUri: string = '';
  @State recognized: string = '';
  @State editing: boolean = false;
  @State busy: boolean = false;
  @State toast: string = '';
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
        }
        .padding(12)
        .width('100%')

        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 8 }) {
              Text('把一道题的截图/照片选进来，端侧识别文字后一键生成导图。')
                .fontSize(13)
                .fontColor('#4a5468')
                .width('100%')
              Button(this.imgUri.length > 0 ? '重新选择图片' : '从相册选择题目')
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

            if (this.imgUri.length > 0) {
              Image(this.imgUri)
                .width('100%')
                .height(180)
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
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
                    .height(120)
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

  /** 选图 → 端侧 OCR */
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
    options.maxSelectNumber = 1;
    this.busy = true;
    this.toast = '';
    try {
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      const uris: Array<string> = result.photoUris;
      if (!uris || uris.length === 0) {
        this.busy = false;
        return;
      }
      this.imgUri = uris[0];
      const text = await this.recognize(uris[0]);
      this.recognized = text;
      if (text.length === 0) {
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

  /** 用识别文字生成思维导图（复用现有 AI 生成链路） */
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
        { query: query, subject: '', book: '' },
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
