/**
 * ChemPage —— 化学方程式与实验装置专项子界面（NavDestination，深链 chem）。
 * 解析化学方程式并校验配平；绘制反应式与简易实验装置；支持回填节点备注。
 */
import { promptAction } from '@kit.ArkUI';
import { ChemEquationEngine } from '../engine/ChemEquationEngine';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { MindMapStore } from '../services/MindMapStore';

@Entry
@Component
export struct ChemPage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private viewW: number = 0;
  private viewH: number = 0;
  @State nodeId: string = '';
  @State nodeTitle: string = '化学方程式';
  @State eq: string = '2H2 + O2 = 2H2O';
  @State balancedOk: boolean = true;
  @State errorText: string = '';

  aboutToAppear(): void {
    const link = DeepLinkRouter.currentLink();
    this.nodeId = link.nodeId;
    this.nodeTitle = link.payload && link.payload.length > 0 ? link.payload : '化学方程式';
    const map = MindMapStore.getInstance().currentSnapshot();
    const detail = map && this.nodeId ? (map.findNode(this.nodeId)?.detail || '') : '';
    if (detail && detail.indexOf('=') >= 0) {
      this.eq = detail;
    }
    this.check();
    setTimeout(() => {
      this.draw();
    }, 50);
  }

  private check(): void {
    if (this.eq.indexOf('=') < 0) {
      this.errorText = '请按 反应物=生成物 格式输入，如 2H2 + O2 = 2H2O';
      this.balancedOk = false;
      return;
    }
    const parsed = ChemEquationEngine.parseEquation(this.eq);
    this.balancedOk = parsed.ok;
    this.errorText = '';
    this.draw();
  }

  private draw(): void {
    ChemEquationEngine.draw(this.context, this.viewW, this.viewH, this.eq, this.balancedOk);
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
              const text = `方程式：${this.eq}（${this.balancedOk ? '已配平' : '未配平'}）`;
              DeepLinkRouter.backfill(this.nodeId, text);
              promptAction.showToast({ message: '已回填到节点备注' });
            })
        }
        .padding(12)
        .width('100%')

        TextInput({ placeholder: '化学方程式，如 2H2 + O2 = 2H2O', text: this.eq })
          .padding({ left: 12, right: 12 })
          .height(40)
          .onChange((value: string) => {
            this.eq = value;
          })
          .onSubmit(() => {
            this.check();
          })

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(12)
            .fontColor('#f5222d')
            .padding(6)
            .width('100%')
        }

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
