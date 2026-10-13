/**
 * GeoMapPage —— 地理地图 / 区位专项子界面（NavDestination，深链 geo）。
 * 解析节点要点为「地点: 说明」并绘制区位标注；支持回填节点备注。
 */
import { promptAction } from '@kit.ArkUI';
import { GeoMapEngine, GeoMarker, parseGeoMarkers } from '../engine/GeoMapEngine';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { MindMapStore } from '../services/MindMapStore';

@Entry
@Component
export struct GeoMapPage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private viewW: number = 0;
  private viewH: number = 0;
  @State nodeId: string = '';
  @State nodeTitle: string = '地理区位';
  @State markers: GeoMarker[] = [];

  aboutToAppear(): void {
    const link = DeepLinkRouter.currentLink();
    this.nodeId = link.nodeId;
    this.nodeTitle = link.payload && link.payload.length > 0 ? link.payload : '地理区位';
    const map = MindMapStore.getInstance().currentSnapshot();
    const detail = map && this.nodeId ? (map.findNode(this.nodeId)?.detail || '') : '';
    this.markers = parseGeoMarkers(detail);
    setTimeout(() => {
      this.draw();
    }, 50);
  }

  private draw(): void {
    GeoMapEngine.draw(this.context, this.viewW, this.viewH, this.markers);
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
              const text = `标注了 ${this.markers.length} 个区位` +
                (this.markers.length > 0 ? `，例如：${this.markers[0].name}` : '');
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
