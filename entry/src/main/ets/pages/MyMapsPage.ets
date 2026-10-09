/**
 * MyMapsPage —— 我的导图管理（NavDestination）。
 * 导图列表（标题/学科/最近更新时间）、打开编辑、删除确认、导出/导入 JSON、损坏数据标记。
 */
import { promptAction } from '@kit.ArkUI';
import { ModelFailure } from '../model/Constants';
import { MindMapStore, MindMapSummary } from '../services/MindMapStore';
import { ExportService } from '../services/ExportService';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { Logger } from '../utils/Logger';

@Component
export struct MyMapsPage {
  @State summaries: MindMapSummary[] = [];
  @State showImport: boolean = false;
  @State importText: string = '';
  private store: MindMapStore = MindMapStore.getInstance();

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    await this.store.ensureInit();
    this.summaries = this.store.list();
  }

  private async openMap(id: string): Promise<void> {
    const ok = await this.store.openMapById(id);
    if (!ok) {
      promptAction.showToast({ message: '数据异常，无法打开该导图，可删除后重新生成' });
      return;
    }
    DeepLinkRouter.push('MindMapPage');
  }

  private confirmDelete(summary: MindMapSummary): void {
    AlertDialog.show({
      message: `确认删除导图「${summary.title}」？删除后不可恢复。`,
      primaryButton: {
        value: '删除',
        fontColor: '#f5222d',
        action: () => {
          this.store.deleteMap(summary.id);
          this.refresh();
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        }
      }
    });
  }

  private doImport(): void {
    const text = this.importText.trim();
    if (text.length === 0) {
      promptAction.showToast({ message: '导入内容为空' });
      return;
    }
    const parsed = ExportService.importMap(text);
    if (!parsed.ok) {
      promptAction.showToast({ message: '导入文件格式不正确' });
      return;
    }
    const r = this.store.importMap(parsed.data.toJson());
    if (r.ok) {
      this.showImport = false;
      this.importText = '';
      this.refresh();
      promptAction.showToast({ message: '导入成功' });
      DeepLinkRouter.push('MindMapPage');
    } else {
      const failure: ModelFailure = r as ModelFailure;
      promptAction.showToast({ message: failure.message });
    }
  }

  private subjectColor(index: number): string {
    const colors: string[] = ['#1677ff', '#00b96b', '#fa8c16', '#722ed1', '#eb2f96', '#13c2c2', '#2f54eb', '#faad14', '#52c41a'];
    return colors[index % colors.length];
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
          Text('我的导图')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
          Blank()
          Button('导入JSON')
            .height(32)
            .fontSize(14)
            .backgroundColor('#00b96b')
            .onClick(() => {
              this.showImport = true;
            })
        }
        .padding(12)
        .width('100%')

        if (this.summaries.length === 0) {
          Column() {
            Blank()
            Text('暂无导图，去首页生成一张吧')
              .fontSize(15)
              .fontColor('#8a94a6')
            Blank()
          }
          .layoutWeight(1)
        } else {
          List({ space: 10 }) {
            ForEach(this.summaries, (item: MindMapSummary, index: number) => {
              ListItem() {
                Row({ space: 10 }) {
                  Text(item.subject && item.subject.length > 0 ? this.subjectLabel(item.subject) : '导图')
                    .fontSize(14)
                    .fontColor('#ffffff')
                    .backgroundColor(this.subjectColor(index))
                    .borderRadius(8)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  Column({ space: 4 }) {
                    Row({ space: 6 }) {
                      Text(item.title)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#1a2333')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (item.damaged) {
                        Text('数据异常')
                          .fontSize(12)
                          .fontColor('#f5222d')
                          .backgroundColor('#fff1f0')
                          .borderRadius(8)
                          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                      }
                    }
                    Text(this.formatTime(item.updatedAt))
                      .fontSize(12)
                      .fontColor('#8a94a6')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (!item.damaged) {
                    Button('打开')
                      .height(30)
                      .fontSize(13)
                      .backgroundColor('#1677ff')
                      .onClick(() => {
                        this.openMap(item.id);
                      })
                  }
                  Button('删除')
                    .height(30)
                    .fontSize(13)
                    .backgroundColor('#f5222d')
                    .onClick(() => {
                      this.confirmDelete(item);
                    })
                }
                .padding(12)
                .backgroundColor('#ffffff')
                .borderRadius(12)
              }
            }, (item: MindMapSummary) => item.id)
          }
          .layoutWeight(1)
          .padding(12)
        }
      }
      .width('100%')
      .height('100%')

      if (this.showImport) {
        Column({ space: 12 }) {
          Text('导入导图 JSON')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
          TextArea({ placeholder: '粘贴符合规范的导图 JSON 内容', text: this.importText })
            .height(160)
            .onChange((value: string) => {
              this.importText = value;
            })
          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .backgroundColor('#8a94a6')
              .onClick(() => {
                this.showImport = false;
              })
            Button('导入')
              .layoutWeight(1)
              .backgroundColor('#1677ff')
              .onClick(() => {
                this.doImport();
              })
          }
        }
        .padding(16)
        .width('86%')
        .backgroundColor('#ffffff')
        .borderRadius(16)
        .position({ x: '7%', y: '30%' })
      }
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }

  private subjectLabel(code: string): string {
    const map: Map<string, string> = new Map<string, string>([
      ['chinese', '语文'], ['math', '数学'], ['english', '英语'], ['physics', '物理'],
      ['chemistry', '化学'], ['biology', '生物'], ['history', '历史'], ['geography', '地理'], ['politics', '政治']
    ]);
    const label = map.get(code);
    return label ? label : code;
  }

  private formatTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
}