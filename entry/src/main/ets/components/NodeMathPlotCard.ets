/**
 * NodeMathPlotCard —— 节点详情页内的轻量函数图像预览卡。
 * 复用 engine 层 FuncParser 解析 y=f(x) 表达式，用 ArkUI Canvas 画坐标轴与曲线，
 * 不引入任何图表/可视化新依赖。仅作「富内容公式」的可视化预览。
 *
 * 表达式约定：仅含变量 x 时可直绘；含参数 a/b/c/d 时以演示值（a=1,b=-2,c=-3,d=1）代入，
 * 得到一个有代表性的样例曲线（精确绘图请走 MathPlotPage 专项子屏）。
 */
import { FuncParser } from '../engine/FuncParser';

@Component
export struct NodeMathPlotCard {
  @Prop expr: string = '';
  private readonly W: number = 340;
  private readonly H: number = 160;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Column({ space: 4 }) {
      if (this.expr.length > 0) {
        Canvas(this.context)
          .width(this.W)
          .height(this.H)
          .backgroundColor('#fafbff')
          .borderRadius(8)
          .onReady(() => {
            this.draw();
          })
        Text(`预览：${this.plotExpr()}`)
          .fontSize(11)
          .fontColor('#b0b9c9')
          .width('100%')
      } else {
        Text('该公式暂无可绘制的函数表达式')
          .fontSize(12)
          .fontColor('#b0b9c9')
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /** 把常见参数 a/b/c/d/h/k/m/n/r 替换为演示数值，得到可直接解析的 y=f(x) 表达式 */
  private plotExpr(): string {
    let s = this.expr;
    s = s.replace(/\ba\b/g, '1');
    s = s.replace(/\bb\b/g, '-2');
    s = s.replace(/\bc\b/g, '-3');
    s = s.replace(/\bd\b/g, '1');
    s = s.replace(/\bh\b/g, '0');
    s = s.replace(/\bk\b/g, '0');
    s = s.replace(/\bm\b/g, '0');
    s = s.replace(/\bn\b/g, '0');
    s = s.replace(/\br\b/g, '0');
    return s;
  }

  private draw(): void {
    const ctx = this.context;
    const w = this.W;
    const h = this.H;
    ctx.clearRect(0, 0, w, h);
    const fnRes = FuncParser.parseFuncY(this.plotExpr());
    if (!fnRes.ok) {
      ctx.fillStyle = '#b0b9c9';
      ctx.fillText('暂不支持绘制该表达式', 12, h / 2);
      return;
    }
    const fn = fnRes.data;
    const N = 240;
    const xs: number[] = [];
    const ys: number[] = [];
    let yMin = Infinity;
    let yMax = -Infinity;
    for (let i = 0; i <= N; i++) {
      const x = -10 + (20 * i) / N;
      let y = 0;
      try {
        y = fn(x);
      } catch (e) {
        y = NaN;
      }
      if (!isFinite(y)) {
        xs.push(NaN);
        ys.push(NaN);
        continue;
      }
      xs.push(x);
      ys.push(y);
      if (y < yMin) {
        yMin = y;
      }
      if (y > yMax) {
        yMax = y;
      }
    }
    if (yMin === Infinity) {
      ctx.fillStyle = '#b0b9c9';
      ctx.fillText('无有效取值点', 12, h / 2);
      return;
    }
    const pad = (yMax - yMin) * 0.1;
    const lo = yMin - pad;
    const hi = yMax + pad;
    const span = hi - lo;
    const toX = (x: number): number => ((x + 10) / 20) * w;
    const toY = (y: number): number => h - ((y - lo) / span) * h;

    // 坐标轴（包含 0 时绘制）
    ctx.strokeStyle = '#d0d7e2';
    ctx.lineWidth = 1;
    ctx.beginPath();
    const zeroY = toY(0);
    if (zeroY >= 0 && zeroY <= h) {
      ctx.moveTo(0, zeroY);
      ctx.lineTo(w, zeroY);
    }
    const zeroX = toX(0);
    if (zeroX >= 0 && zeroX <= w) {
      ctx.moveTo(zeroX, 0);
      ctx.lineTo(zeroX, h);
    }
    ctx.stroke();

    // 函数曲线
    ctx.strokeStyle = '#1677ff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    let started = false;
    for (let i = 0; i < xs.length; i++) {
      if (isNaN(xs[i]) || isNaN(ys[i])) {
        started = false;
        continue;
      }
      const px = toX(xs[i]);
      const py = toY(ys[i]);
      if (!started) {
        ctx.moveTo(px, py);
        started = true;
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.stroke();
  }
}
