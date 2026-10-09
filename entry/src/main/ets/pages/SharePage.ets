/**
 * 分享页（v2.0 一起学 · 分享）。为当前导图生成分享二维码（zhitu:// Mock 链接），
 * 可复制链接；支持「分享到精品市场」（标记 shared=true 上传到云端）。
 */
import { promptAction } from '@kit.ArkUI';
import { MindMapStore } from '../services/MindMapStore';
import { CloudService } from '../services/CloudService';
import { AccountService } from '../services/AccountService';

@Component
export struct SharePage {
  @State title: string = '';
  @State link: string = '';
  @State sharing: boolean = false;

  aboutToAppear(): void {
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (snap) {
      this.title = snap.title;
      const encId = encodeURIComponent(snap.id);
      const encTitle = encodeURIComponent(snap.title);
      this.link = `zhitu://map/share?id=${encId}&title=${encTitle}`;
    }
  }

  private async doShareToMarket(): Promise<void> {
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (!snap) {
      promptAction.showToast({ message: '当前没有可导出的导图' });
      return;
    }
    const acc = AccountService.getInstance().getCurrent();
    if (!acc) {
      promptAction.showToast({ message: '请先在「云端」登录' });
      return;
    }
    this.sharing = true;
    await CloudService.getInstance().upload(snap, acc.name, true);
    this.sharing = false;
    promptAction.showToast({ message: '已分享到精品市场（Mock）' });
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {
          if (this.title.length === 0) {
            Text('当前没有可导出的导图，先去首页生成一张吧')
              .fontSize(14)
              .fontColor('#8a94a6')
              .width('100%')
              .textAlign(TextAlign.Center)
          } else {
            Text(`分享《${this.title}》`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1a2333')
              .width('100%')
              .textAlign(TextAlign.Center)
            QRCode(this.link)
              .width(200)
              .height(200)
              .margin(8)
            Text(this.link)
              .fontSize(12)
              .fontColor('#8a94a6')
              .width('100%')
              .textAlign(TextAlign.Center)
              .copyOption(CopyOptions.InApp)
            Text('长按上方链接即可复制')
              .fontSize(12)
              .fontColor('#8a94a6')
              .width('100%')
              .textAlign(TextAlign.Center)
            Button(this.sharing ? '分享中…' : '分享到精品市场')
              .width('100%')
              .height(40)
              .backgroundColor('#13c2c2')
              .enabled(!this.sharing)
              .onClick(() => {
                this.doShareToMarket();
              })
          }
        }
        .padding(16)
        .width('100%')
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .title('分享')
    .width('100%')
    .height('100%')
  }
}
