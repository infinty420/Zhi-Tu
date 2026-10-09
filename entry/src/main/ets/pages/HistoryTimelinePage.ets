/**
 * HistoryTimelinePage —— 历史时间轴专项子界面（NavDestination，深链 history）。
 * 解析节点要点为「年份: 事件」并绘制时间轴；支持回填节点备注。
 */
import { promptAction } from '@kit.ArkUI';
import { HistoryTimelineEngine, parseTimeline, TimelineEvent } from '../engine/HistoryTimelineEngine';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { MindMapStore } from '../services/MindMapStore';

@Entry
@Component
export struct HistoryTimelinePage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private viewW: number = 0;
  private viewH: number = 0;
  @State nodeId: string = '';
  @State nodeTitle: string = '历史时间轴';
  @State events: TimelineEvent[] = [];

  aboutToAppear(): void {
    const link = DeepLinkRouter.currentLink();
    this.nodeId = link.nodeId;
    this.nodeTitle = link.payload && link.payload.length > 0 ? link.payload : '历史时间轴';
    const map = MindMapStore.getInstance().currentSnapshot();
    const detail = map && this.nodeId ? (map.findNode(this.nodeId)?.detail || '') : '';
    this.events = parseTimeline(detail);
    setTimeout(() => {
      this.draw();
    }, 50);
  }

  private draw(): void {
    HistoryTimelineEngine.draw(this.context, this.viewW, this.viewH, this.events);
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
          Text(this.nodeTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Button('回填节点')
            .height(32)
            .fontSize(13)
            .backgroundColor('#722ed1')
            .onClick(() => {
              const text = `时间轴共 ${this.events.length} 个事件` +
                (this.events.length > 0 ? `，例如：${this.events[0].text}` : '');
              DeepLinkRouter.backfill(this.nodeId, text);
              promptAction.showToast({ message: '已回填到节点备注' });
            })
        }
        .padding(12)
        .width('100%')

        Canvas(this.context)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#ffffff')
          .onReady(() => {
            this.viewW = this.context.width;
            this.viewH = this.context.height;
            this.draw();
          })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }
}
