/**
 * 精品导图市场（v2.0 一起学 · 分享与市场；Wave 3 增加 UGC 发布）。
 * 社区精选：浏览内置精品导图一键导入；我的发布：把本机导图发布出来，可再次导入或删除。
 */
import { promptAction } from '@kit.ArkUI';
import { getMarketMindMap, listMarket, MarketItem, MarketUserItem } from '../model/MarketTemplates';
import { MindMapStore } from '../services/MindMapStore';
import { MarketService } from '../services/MarketService';
import { AccountService } from '../services/AccountService';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { ModelFailure } from '../model/Constants';

@Component
export struct MarketPage {
  @State items: MarketItem[] = [];
  @State mine: MarketUserItem[] = [];
  @State publishing: boolean = false;

  aboutToAppear(): void {
    this.items = listMarket();
    this.refreshMine();
  }

  private async refreshMine(): Promise<void> {
    await MarketService.getInstance().init();
    this.mine = MarketService.getInstance().listUser();
  }

  /** 把当前导图发布到「我的发布」 */
  private async doPublish(): Promise<void> {
    const snap = MindMapStore.getInstance().currentSnapshot();
    if (!snap) {
      promptAction.showToast({ message: '当前没有可发布的导图' });
      return;
    }
    const acc = AccountService.getInstance().getCurrent();
    const author = acc && acc.name.length > 0 ? acc.name : '我';
    this.publishing = true;
    await MarketService.getInstance().publish(snap.title, author, snap.subject, `${snap.nodes.length} 个节点 · 本机发布`, snap.toJson());
    this.publishing = false;
    await this.refreshMine();
    promptAction.showToast({ message: '已发布到「我的发布」' });
  }

  private importJson(json: string, title: string): void {
    const res = MindMapStore.getInstance().importAsNew(json);
    if (res.ok) {
      promptAction.showToast({ message: `已导入：${title}` });
      DeepLinkRouter.push('MindMapPage');
    } else {
      const fail: ModelFailure = res as ModelFailure;
      promptAction.showToast({ message: `导入失败：${fail.message}` });
    }
  }

  private importBuiltin(item: MarketItem): void {
    const map = getMarketMindMap(item.id);
    if (!map) {
      promptAction.showToast({ message: '导入失败' });
      return;
    }
    this.importJson(map.toJson(), item.title);
  }

  private async importUser(item: MarketUserItem): Promise<void> {
    const payload = MarketService.getInstance().getPayload(item.id);
    if (payload.length === 0) {
      promptAction.showToast({ message: '内容已失效' });
      return;
    }
    await MarketService.getInstance().bumpDownloads(item.id);
    this.importJson(payload, item.title);
    await this.refreshMine();
  }

  private async removeMine(id: string): Promise<void> {
    const ok = await MarketService.getInstance().remove(id);
    promptAction.showToast({ message: ok ? '已下架' : '下架失败' });
    await this.refreshMine();
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text('精品导图市场')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
            .layoutWeight(1)
          Button(this.publishing ? '发布中…' : '发布当前导图')
            .height(32)
            .fontSize(12)
            .backgroundColor('#52c41a')
            .enabled(!this.publishing)
            .onClick(() => {
              this.doPublish();
            })
        }
        .width('100%')

        // 我的发布（UGC）
        Text(`我的发布（${this.mine.length}）`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a2333')
          .alignSelf(ItemAlign.Start)
        if (this.mine.length === 0) {
          Text('还没有发布过导图，点右上角发布当前导图')
            .fontSize(13)
            .fontColor('#8a94a6')
            .width('100%')
        } else {
          Column({ space: 8 }) {
            ForEach(this.mine, (it: MarketUserItem) => {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(it.title)
                    .fontSize(15)
                    .fontColor('#1a2333')
                    .fontWeight(FontWeight.Medium)
                  Text(`${it.subject} · ${it.author} · ${it.downloads} 次下载`)
                    .fontSize(12)
                    .fontColor('#8a94a6')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Button('导入')
                  .height(32)
                  .fontSize(13)
                  .backgroundColor('#1677ff')
                  .onClick(() => {
                    this.importUser(it);
                  })
                Button('下架')
                  .height(32)
                  .fontSize(13)
                  .backgroundColor('#f5222d')
                  .onClick(() => {
                    this.removeMine(it.id);
                  })
              }
              .padding(12)
              .borderRadius(10)
              .backgroundColor('#f6ffed')
              .width('100%')
            }, (it: MarketUserItem) => it.id)
          }
          .width('100%')
        }

        Divider()
          .color('#eef2f7')
          .width('100%')

        // 社区精选
        Text('社区精选')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1a2333')
          .alignSelf(ItemAlign.Start)
        if (this.items.length === 0) {
          Text('暂无精品导图')
            .fontSize(13)
            .fontColor('#8a94a6')
        } else {
          List() {
            ForEach(this.items, (it: MarketItem) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(it.title)
                      .fontSize(15)
                      .fontColor('#1a2333')
                      .fontWeight(FontWeight.Medium)
                    Text(`${it.subject} · ${it.author} · ${it.downloads} 次下载`)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                    Text(it.summary)
                      .fontSize(12)
                      .fontColor('#8a94a6')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  Button('导入')
                    .height(32)
                    .fontSize(13)
                    .backgroundColor('#1677ff')
                    .onClick(() => {
                      this.importBuiltin(it);
                    })
                }
                .padding(12)
              }
            }, (it: MarketItem) => it.id)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .padding(16)
      .width('100%')
      .height('100%')
    }
    .title('精品市场')
    .width('100%')
    .height('100%')
  }
}
