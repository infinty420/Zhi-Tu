/**
 * BioPage —— 生物结构层级专项子界面（NavDestination，深链 bio）。
 * 解析节点要点为缩进层级结构并绘制结构树；支持回填节点备注。
 */
import { promptAction } from '@kit.ArkUI';
import { BioNode, BioStructureEngine, parseBioTree } from '../engine/BioStructureEngine';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { MindMapStore } from '../services/MindMapStore';

@Entry
@Component
export struct BioPage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private viewW: number = 0;
  private viewH: number = 0;
  @State nodeId: string = '';
  @State nodeTitle: string = '生物结构';
  @State roots: BioNode[] = [];

  aboutToAppear(): void {
    const link = DeepLinkRouter.currentLink();
    this.nodeId = link.nodeId;
    this.nodeTitle = link.payload && link.payload.length > 0 ? link.payload : '生物结构';
    const map = MindMapStore.getInstance().currentSnapshot();
    const detail = map && this.nodeId ? (map.findNode(this.nodeId)?.detail || '') : '';
    this.roots = parseBioTree(detail);
    setTimeout(() => {
      this.draw();
    }, 50);
  }

  private draw(): void {
    BioStructureEngine.draw(this.context, this.viewW, this.viewH, this.roots);
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
              const text = `结构层级共 ${this.roots.length} 个顶层节点`;
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
