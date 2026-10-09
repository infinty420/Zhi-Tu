/**
 * MathPlotPage —— 数学绘图专项子界面（NavDestination，深链 math）。
 * 表达式绘制、坐标系网格、几何对象（点/线/圆/三角形）、关键点标注、模板匹配、缩放平移、结果回填。
 */
import { promptAction } from '@kit.ArkUI';
import { ModelFailure } from '../model/Constants';
import { FuncParser, FnOfX } from '../engine/FuncParser';
import { GeoPoint, KeyPoint, MathCamera2D, MathPlotEngine } from '../engine/MathPlotEngine';
import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { Logger } from '../utils/Logger';

interface CircleGeo {
  center: GeoPoint;
  radius: number;
}

@Component
export struct MathPlotPage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private viewW: number = 0;
  private viewH: number = 0;
  /**
   * ctx.font 的字号单位是物理 px，而几何绘制单位是 vp，需按 vp2px 换算，
   * 否则 3 倍屏上文字只有 1/3 大小。
   */
  private fontOf(sizeVp: number): string {
    let px = Math.round(sizeVp * 3);
    try {
      px = Math.round(vp2px(sizeVp));
    } catch (err) {
      px = Math.round(sizeVp * 3);
    }
    const real = px < 12 ? 12 : px;
    return 'normal normal ' + real.toString() + 'px sans-serif';
  }


  @State expr: string = 'x^2';
  @State templateIndex: number = 0;
  @State errorText: string = '';
  @State keyPoints: KeyPoint[] = [];
  @State geoMode: string = 'point';
  @State circleRadius: number = 1;
  @State points: GeoPoint[] = [];
  @State linePairs: GeoPoint[][] = [];
  @State circles: CircleGeo[] = [];
  @State infoText: string = '';
  @State nodeId: string = '';
  @State nodeTitle: string = '数学绘图';

  private camera: MathCamera2D = { scale: 40, offsetX: 0, offsetY: 0 };
  private fn: FnOfX | undefined = undefined;
  private gestureStartX: number = 0;
  private gestureStartY: number = 0;
  private gestureMoved: boolean = false;
  private pinchStartDist: number = 0;
  private pinchStartScale: number = 40;

  private templateList: string[] = ['抛物线 y=x^2', '正弦曲线 y=sin(x)', '反比例 y=1/x', '指数 y=exp(x)', '对数 y=log(x)'];
  private templateExprs: string[] = ['x^2', 'sin(x)', '1/x', 'exp(x)', 'log(x)'];

  private templateOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < this.templateList.length; i++) {
      const opt: SelectOption = { value: this.templateList[i] };
      options.push(opt);
    }
    return options;
  }

  aboutToAppear(): void {
    const link = DeepLinkRouter.currentLink();
    this.nodeId = link.nodeId;
    this.nodeTitle = link.payload && link.payload.length > 0 ? link.payload : '数学绘图';
    const match = MathPlotEngine.matchTemplate(link.payload);
    if (match) {
      for (let i = 0; i < this.templateExprs.length; i++) {
        if (this.templateExprs[i] === match.expr) {
          this.templateIndex = i;
          this.expr = match.expr;
          break;
        }
      }
      if (!this.templateExprs.includes(match.expr)) {
        this.expr = match.expr;
      }
    }
    setTimeout(() => {
      this.plotCurrent();
    }, 50);
  }

  private plotCurrent(): void {
    const parsed = FuncParser.parseFuncY(this.expr);
    if (!parsed.ok) {
      const failure: ModelFailure = parsed as ModelFailure;
      this.errorText = failure.message;
      this.fn = undefined;
      this.keyPoints = [];
      this.draw();
      return;
    }
    this.errorText = '';
    this.fn = parsed.data;
    try {
      const xMin = -8;
      const xMax = 8;
      this.keyPoints = MathPlotEngine.locateKeyPoints(this.fn, xMin, xMax);
    } catch (err) {
      this.keyPoints = [];
    }
    this.draw();
  }

  private draw(): void {
    const ctx = this.context;
    if (this.viewW <= 0) {
      return;
    }
    ctx.clearRect(0, 0, this.viewW, this.viewH);
    MathPlotEngine.drawCoordinate(ctx, this.viewW, this.viewH, this.camera);
    if (this.fn) {
      MathPlotEngine.drawFunction(ctx, this.fn, this.viewW, this.viewH, this.camera, '#1677ff');
    }
    // 关键点
    ctx.fillStyle = '#f5222d';
    ctx.font = this.fontOf(11);
    for (let i = 0; i < this.keyPoints.length; i++) {
      const kp = this.keyPoints[i];
      const sx = MathPlotEngine.worldToScreenX(kp.x, this.camera);
      const sy = MathPlotEngine.worldToScreenY(kp.y, this.camera);
      ctx.beginPath();
      ctx.arc(sx, sy, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#f5222d';
      ctx.fillText(`${kp.label}(${kp.x.toFixed(1)},${kp.y.toFixed(1)})`, sx + 8, sy - 8);
      ctx.fillStyle = '#f5222d';
    }
    // 点
    ctx.fillStyle = '#722ed1';
    for (let i = 0; i < this.points.length; i++) {
      const sx = MathPlotEngine.worldToScreenX(this.points[i].x, this.camera);
      const sy = MathPlotEngine.worldToScreenY(this.points[i].y, this.camera);
      ctx.beginPath();
      ctx.arc(sx, sy, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.font = this.fontOf(11);
      ctx.fillText(`P${i + 1}(${this.points[i].x.toFixed(1)},${this.points[i].y.toFixed(1)})`, sx + 6, sy - 6);
    }
    // 线
    ctx.strokeStyle = '#00b96b';
    ctx.lineWidth = 2;
    for (let i = 0; i < this.linePairs.length; i++) {
      const a = this.linePairs[i][0];
      const b = this.linePairs[i][1];
      ctx.beginPath();
      ctx.moveTo(MathPlotEngine.worldToScreenX(a.x, this.camera), MathPlotEngine.worldToScreenY(a.y, this.camera));
      ctx.lineTo(MathPlotEngine.worldToScreenX(b.x, this.camera), MathPlotEngine.worldToScreenY(b.y, this.camera));
      ctx.stroke();
    }
    // 圆
    ctx.strokeStyle = '#fa8c16';
    ctx.lineWidth = 2;
    for (let i = 0; i < this.circles.length; i++) {
      const c = this.circles[i];
      const sx = MathPlotEngine.worldToScreenX(c.center.x, this.camera);
      const sy = MathPlotEngine.worldToScreenY(c.center.y, this.camera);
      const r = c.radius * this.camera.scale;
      ctx.beginPath();
      ctx.arc(sx, sy, r, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fillStyle = '#fa8c16';
      ctx.font = this.fontOf(11);
      ctx.fillText(`圆(${c.center.x.toFixed(1)},${c.center.y.toFixed(1)}) r=${c.radius.toFixed(1)}`, sx + 8, sy - 8);
      ctx.fillStyle = '#fa8c16';
    }
    // 三角形（前 3 个点）与度量
    if (this.points.length >= 3) {
      const a = this.points[0];
      const b = this.points[1];
      const c = this.points[2];
      ctx.strokeStyle = '#eb2f96';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(MathPlotEngine.worldToScreenX(a.x, this.camera), MathPlotEngine.worldToScreenY(a.y, this.camera));
      ctx.lineTo(MathPlotEngine.worldToScreenX(b.x, this.camera), MathPlotEngine.worldToScreenY(b.y, this.camera));
      ctx.lineTo(MathPlotEngine.worldToScreenX(c.x, this.camera), MathPlotEngine.worldToScreenY(c.y, this.camera));
      ctx.closePath();
      ctx.stroke();
      const ab = MathPlotEngine.segmentLength(a, b);
      const bc = MathPlotEngine.segmentLength(b, c);
      const ca = MathPlotEngine.segmentLength(c, a);
      const angleB = MathPlotEngine.angleAtB(a, b, c);
      ctx.fillStyle = '#eb2f96';
      ctx.font = this.fontOf(11);
      const midX = MathPlotEngine.worldToScreenX((a.x + b.x + c.x) / 3, this.camera);
      const midY = MathPlotEngine.worldToScreenY((a.y + b.y + c.y) / 3, this.camera);
      ctx.fillText(`AB=${ab.toFixed(1)} BC=${bc.toFixed(1)} CA=${ca.toFixed(1)} ∠B=${angleB.toFixed(0)}°`, midX - 70, midY);
      ctx.fillStyle = '#eb2f96';
    }
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
          Text('数学绘图')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a2333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Button($r('app.string.math_draw'))
            .height(32)
            .fontSize(14)
            .backgroundColor('#00b96b')
            .onClick(() => {
              this.plotCurrent();
            })
          Button('回填节点')
            .height(32)
            .fontSize(13)
            .backgroundColor('#722ed1')
            .onClick(() => {
              const content = this.buildBackfillText();
              DeepLinkRouter.backfill(this.nodeId, content);
              promptAction.showToast({ message: '已回填到节点备注' });
            })
        }
        .padding(12)
        .width('100%')

        // 表达式区
        Row({ space: 8 }) {
          TextInput({ placeholder: '表达式，如 y=x^2', text: this.expr })
            .layoutWeight(1)
            .height(40)
            .onChange((value: string) => {
              this.expr = value;
            })
            .onSubmit(() => {
              this.plotCurrent();
            })
          Select(this.templateOptions())
            .selected(this.templateIndex)
            .value(this.templateList[this.templateIndex])
            .font({ size: 13 })
            .onSelect((index: number) => {
              this.templateIndex = index;
              this.expr = this.templateExprs[index];
              this.plotCurrent();
            })
        }
        .padding({ left: 12, right: 12 })
        .width('100%')

        if (this.errorText.length > 0) {
          Text(`${$r('app.string.math_error_position')}：${this.errorText}`)
            .fontSize(12)
            .fontColor('#f5222d')
            .padding(6)
            .width('100%')
        }

        // 画布
        Canvas(this.context)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#ffffff')
          .onReady(() => {
            this.viewW = this.context.width;
            this.viewH = this.context.height;
            this.camera.offsetX = this.viewW / 2;
            this.camera.offsetY = this.viewH / 2;
            this.draw();
          })
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })

        // 底部工具栏
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            this.toolChip('添加点', this.geoMode === 'point', () => {
              this.geoMode = 'point';
            })
            this.toolChip('连线', this.geoMode === 'line', () => {
              this.geoMode = 'line';
              this.connectLine();
            })
            this.toolChip('画圆', this.geoMode === 'circle', () => {
              this.geoMode = 'circle';
            })
            this.toolChip('标注关键点', this.keyPoints.length > 0, () => {
              this.plotCurrent();
            })
            Button('清空')
              .height(30)
              .fontSize(13)
              .backgroundColor('#8a94a6')
              .onClick(() => {
                this.points = [];
                this.linePairs = [];
                this.circles = [];
                this.draw();
              })
          }
          if (this.geoMode === 'circle') {
            Row({ space: 8 }) {
              Text(`半径 ${this.circleRadius.toFixed(1)}`)
                .fontSize(13)
                .fontColor('#8a94a6')
              Slider({ value: this.circleRadius, min: 0.5, max: 5, step: 0.5 })
                .layoutWeight(1)
                .onChange((value: number) => {
                  this.circleRadius = value;
                })
            }
          }
          if (this.infoText.length > 0) {
            Text(this.infoText)
              .fontSize(12)
              .fontColor('#8a94a6')
              .textAlign(TextAlign.Center)
              .width('100%')
          }
        }
        .padding(10)
        .backgroundColor('#ffffff')
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor('#F7F9FC')
  }

  @Builder
  toolChip(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(active ? '#ffffff' : '#1a2333')
      .backgroundColor(active ? '#722ed1' : '#f3f8ff')
      .borderRadius(14)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(onTap)
  }

  private connectLine(): void {
    if (this.points.length >= 2) {
      const a = this.points[this.points.length - 2];
      const b = this.points[this.points.length - 1];
      this.linePairs.push([{ x: a.x, y: a.y }, { x: b.x, y: b.y }]);
    } else {
      promptAction.showToast({ message: '请先在画布上点击添加至少 2 个点' });
    }
  }

  private handleTouch(event: TouchEvent): void {
    const touches = event.touches;
    if (event.type === TouchType.Down) {
      if (touches.length >= 1) {
        this.gestureStartX = touches[0].x;
        this.gestureStartY = touches[0].y;
        this.gestureMoved = false;
      }
      if (touches.length >= 2) {
        this.pinchStartDist = this.distance(touches[0].x, touches[0].y, touches[1].x, touches[1].y);
        this.pinchStartScale = this.camera.scale;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (touches.length >= 2) {
        const dist = this.distance(touches[0].x, touches[0].y, touches[1].x, touches[1].y);
        if (this.pinchStartDist > 0) {
          this.camera.scale = Math.max(5, Math.min(300, this.pinchStartScale * dist / this.pinchStartDist));
          this.gestureMoved = true;
        }
      } else if (touches.length === 1) {
        const t = touches[0];
        const dx = t.x - this.gestureStartX;
        const dy = t.y - this.gestureStartY;
        if (Math.abs(dx) + Math.abs(dy) > 10) {
          this.gestureMoved = true;
        }
        if (this.gestureMoved) {
          this.camera.offsetX += t.x - (touches[0].x - dx);
          this.camera.offsetY += t.y - (touches[0].y - dy);
          this.camera.offsetX = this.camera.offsetX;
          this.camera.offsetY = this.camera.offsetY;
        }
        this.gestureStartX = t.x;
        this.gestureStartY = t.y;
      }
      this.draw();
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.gestureMoved || touches.length > 0) {
        return;
      }
      const changed = event.changedTouches;
      if (changed.length < 1) {
        return;
      }
      this.onTap(changed[0].x, changed[0].y);
    }
  }

  private distance(x1: number, y1: number, x2: number, y2: number): number {
    return Math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  }

  private onTap(sx: number, sy: number): void {
    const wx = MathPlotEngine.screenToWorldX(sx, this.camera);
    const wy = MathPlotEngine.screenToWorldY(sy, this.camera);
    if (this.geoMode === 'circle') {
      const c: CircleGeo = { center: { x: wx, y: wy }, radius: this.circleRadius };
      this.circles.push(c);
      this.infoText = `添加圆：圆心(${wx.toFixed(1)}, ${wy.toFixed(1)}) 半径 ${this.circleRadius.toFixed(1)}`;
      this.draw();
      return;
    }
    // 点模式：添加点
    this.points.push({ x: wx, y: wy });
    if (this.geoMode === 'line' && this.points.length >= 2) {
      const a = this.points[this.points.length - 2];
      const b = this.points[this.points.length - 1];
      this.linePairs.push([{ x: a.x, y: a.y }, { x: b.x, y: b.y }]);
      this.infoText = `添加点：(${wx.toFixed(1)}, ${wy.toFixed(1)})，并与上一点连线`;
    } else {
      this.infoText = `添加点 P${this.points.length}：(${wx.toFixed(1)}, ${wy.toFixed(1)})`;
      if (this.points.length >= 3) {
        this.infoText += '（已构成三角形，显示边长与角度）';
      }
    }
    this.draw();
  }

  private buildBackfillText(): string {
    let text = `表达式 ${this.expr}`;
    if (this.keyPoints.length > 0) {
      const parts: string[] = [];
      for (let i = 0; i < this.keyPoints.length; i++) {
        parts.push(`${this.keyPoints[i].label}(${this.keyPoints[i].x.toFixed(2)},${this.keyPoints[i].y.toFixed(2)})`);
      }
      text += `；关键点：${parts.join('，')}`;
    }
    if (this.points.length >= 3) {
      text += '；绘制了三边三角形（含边长/角度标注）';
    }
    return text;
  }
}