/**
 * Galaxy2DView —— 学科知识馆 2D 星系降级视图（Wave 8 附）。
 *
 * 背景：ArkGraphics 3D 官方明确不支持模拟器（需真机 GPU 的 OpenGL ES 3.2/Vulkan），
 * 开发期/无 GPU 环境下 3D 区域空白属预期。本组件用 Canvas 2D 绘制"伪 3D"学科星系，
 * 保证功能与交互在任何环境可见可用：
 * 1) 9 学科徽章沿椭圆轨道环绕中心知识晶体，深度排序 + 近大远小 + 远暗近亮；
 * 2) DisplaySync 帧驱动自转（帧率随设备 vsync 自适应），拖动可手动旋转；
 * 3) 聚焦学科：轨道对齐插值（该学科转到正前方）+ 徽章放大呼吸光环 + 其余变暗；
 * 4) FPS 统计与 Scene3DView 同口径（滑动窗口 + 500ms 节流上报）；
 * 5) 渲染纯 Canvas 位块绘制，不触发 UI 状态刷新，60Hz 模拟器轻松满帧。
 */

import { displaySync } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { Logger } from '../utils/Logger';

const TAG = 'Galaxy2DView';

/** FPS 滑动窗口大小（帧） */
const FPS_WINDOW = 120;
/** FPS 统计上报节流（毫秒） */
const FPS_REPORT_MS = 500;
/** 掉帧判定系数：单帧间隔超过 1.3 倍目标帧间隔视为一次掉帧 */
const DROP_FACTOR = 1.3;
/** dt 钳制上限（毫秒），防切后台跳变 */
const DT_CLAMP_MS = 100;

/** 学科星系配色（下标对齐 Constants.SUBJECTS 顺序） */
export const SUBJECT_COLORS: string[] = [
  '#ff8a65', // 语文
  '#64b5f6', // 数学
  '#4dd0e1', // 英语
  '#ffd54f', // 物理
  '#aed581', // 化学
  '#f06292', // 生物
  '#d7a86e', // 历史
  '#7986cb', // 地理
  '#ba68c8'  // 政治
];
/** 学科徽章单字（下标对齐 SUBJECTS 顺序） */
const SUBJECT_GLYPHS: string[] = ['语', '数', '英', '物', '化', '生', '史', '地', '政'];
/** 学科数量 */
const SUBJECT_COUNT = 9;

/** 背景星点（确定性伪随机，避免每帧闪烁） */
class StarDot {
  x: number = 0;
  y: number = 0;
  r: number = 0;
  a: number = 0;

  constructor(x: number, y: number, r: number, a: number) {
    this.x = x;
    this.y = y;
    this.r = r;
    this.a = a;
  }
}

@Component
export struct Galaxy2DView {
  /** 是否激活渲染：false 时停止帧回调（页面隐藏） */
  @Prop @Watch('onActiveChanged') active: boolean = false;
  /** 自动旋转开关（总览态生效） */
  @Prop @Watch('onAutoRotateChanged') autoRotate: boolean = true;
  /** 重置视角信号：父组件递增触发 */
  @Prop @Watch('onResetTick') resetTick: number = 0;
  /** 聚焦学科下标；-1 = 总览（自转） */
  @Prop @Watch('onFocusChanged') focusIdx: number = -1;
  /** FPS 上报回调：(平均帧率, 窗口最低帧率, 掉帧次数, 平均帧间隔ms) */
  onFps: ((fps: number, minFps: number, drops: number, intervalMs: number) => void) | undefined = undefined;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  /** 画布尺寸（onAreaChange 更新） */
  private cw: number = 0;
  private ch: number = 0;

  /** 全局轨道角（弧度）：自转/拖动/聚焦对齐都改它 */
  private angle: number = 0;
  /** 聚焦对齐目标角（null = 无对齐任务） */
  private alignTarget: number | null = null;
  /** 聚焦呼吸相位（光环动画） */
  private breath: number = 0;

  private sync: displaySync.DisplaySync | undefined = undefined;
  private syncRunning: boolean = false;

  /** 帧统计 */
  private lastNs: number = -1;
  private deltas: number[] = [];
  private statAccNs: number = 0;

  /** 背景星点（按画布尺寸生成一次） */
  private stars: StarDot[] = [];

  /** 手势锚点 */
  private panLastX: number = 0;

  aboutToAppear(): void {
    this.ensureSync();
  }

  aboutToDisappear(): void {
    this.stopSync();
    if (this.sync) {
      this.sync.off('frame');
      this.sync = undefined;
    }
    this.deltas = [];
  }

  // ---------------- 帧驱动 ----------------

  private ensureSync(): void {
    if (this.sync) {
      return;
    }
    this.sync = displaySync.create();
    const range: ExpectedFrameRateRange = { expected: this.targetHz(), min: 30, max: 120 };
    this.sync.setExpectedFrameRateRange(range);
    this.sync.on('frame', (info: displaySync.IntervalInfo) => {
      this.onFrame(info.timestamp);
    });
  }

  private targetHz(): number {
    try {
      const rate: number = display.getDefaultDisplaySync().refreshRate;
      if (rate >= 30) {
        return Math.min(rate, 120);
      }
    } catch (err) {
      Logger.warn(TAG, `refreshRate: ${err}`);
    }
    return 60;
  }

  private startSync(): void {
    if (!this.sync || this.syncRunning) {
      return;
    }
    this.lastNs = -1;
    this.statAccNs = 0;
    this.sync.start();
    this.syncRunning = true;
  }

  private stopSync(): void {
    if (!this.sync || !this.syncRunning) {
      return;
    }
    this.sync.stop();
    this.syncRunning = false;
  }

  private onFrame(tsNs: number): void {
    if (this.lastNs < 0) {
      this.lastNs = tsNs;
      return;
    }
    let dtMs = (tsNs - this.lastNs) / 1e6;
    this.lastNs = tsNs;
    if (dtMs <= 0) {
      return;
    }
    if (dtMs > DT_CLAMP_MS) {
      dtMs = DT_CLAMP_MS;
    }
    this.deltas.push(dtMs);
    if (this.deltas.length > FPS_WINDOW) {
      this.deltas.shift();
    }
    this.statAccNs += dtMs * 1e6;

    // 聚焦对齐优先（指数逼近，帧率无关）
    if (this.alignTarget !== null) {
      const k = Math.min(1, dtMs / 240);
      this.angle += (this.alignTarget - this.angle) * k;
      if (Math.abs(this.alignTarget - this.angle) < 0.004) {
        this.angle = this.alignTarget;
        this.alignTarget = null;
      }
    } else if (this.autoRotate && this.focusIdx < 0) {
      // 总览自转：时间驱动恒定角速度（与帧率解耦）
      this.angle += 0.35 * (dtMs / 1000);
    }
    this.breath += dtMs / 1000;

    this.draw();

    if (this.statAccNs >= FPS_REPORT_MS * 1e6) {
      this.statAccNs = 0;
      this.reportFps();
    }
  }

  private reportFps(): void {
    if (!this.onFps || this.deltas.length < 8) {
      return;
    }
    const dropMs = 1000 * DROP_FACTOR / this.targetHz();
    let sum = 0;
    let maxD = 0;
    let drops = 0;
    for (let i = 0; i < this.deltas.length; i++) {
      const d = this.deltas[i];
      sum += d;
      if (d > maxD) {
        maxD = d;
      }
      if (d > dropMs) {
        drops++;
      }
    }
    const avg = sum / this.deltas.length;
    const fps = 1000 / avg;
    const minFps = maxD > 0 ? 1000 / maxD : 0;
    this.onFps(Math.round(fps), Math.round(minFps), drops, Math.round(avg * 100) / 100);
  }

  // ---------------- 状态联动 ----------------

  onActiveChanged(): void {
    if (this.active) {
      this.startSync();
    } else {
      this.stopSync();
    }
  }

  onAutoRotateChanged(): void {
    // 帧回调内直接读取 this.autoRotate
  }

  onResetTick(): void {
    this.alignTarget = 0;
  }

  onFocusChanged(): void {
    if (this.focusIdx < 0 || this.focusIdx >= SUBJECT_COUNT) {
      // 回总览：恢复自转
      this.alignTarget = null;
      return;
    }
    // 学科 i 的轨道角 = i * 2π/9 + angle；对齐到正面（角 = π/2，屏幕下方偏前），
    // 求 angle 使 i*2π/9 + angle ≡ π/2 (mod 2π)
    const base = this.focusIdx * 2 * Math.PI / SUBJECT_COUNT;
    let target = Math.PI / 2 - base;
    // 就近取整圈，避免绕远
    const twoPi = 2 * Math.PI;
    while (target - this.angle > Math.PI) {
      target -= twoPi;
    }
    while (target - this.angle < -Math.PI) {
      target += twoPi;
    }
    this.alignTarget = target;
  }

  // ---------------- 绘制 ----------------

  private ensureStars(): void {
    if (this.stars.length > 0 || this.cw <= 0 || this.ch <= 0) {
      return;
    }
    // 确定性 LCG 伪随机：每次进入页面星点布局稳定
    let seed = 20261102;
    const rand = (): number => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    };
    const dots: StarDot[] = [];
    for (let i = 0; i < 46; i++) {
      const d = new StarDot(rand(), rand(), 0.6 + rand() * 1.4, 0.15 + rand() * 0.5);
      dots.push(d);
    }
    this.stars = dots;
  }

  private draw(): void {
    if (this.cw <= 0 || this.ch <= 0) {
      return;
    }
    const ctx = this.ctx;
    const cx = this.cw / 2;
    const cy = this.ch * 0.44;
    // 轨道半径：横向占画布 38%，纵向压缩模拟俯视
    const rx = Math.min(this.cw, this.ch * 1.15) * 0.36;
    const ry = rx * 0.34;

    // 背景
    ctx.clearRect(0, 0, this.cw, this.ch);
    this.ensureStars();
    ctx.save();
    for (const s of this.stars) {
      ctx.globalAlpha = s.a;
      ctx.fillStyle = '#dce8ff';
      ctx.beginPath();
      ctx.arc(s.x * this.cw, s.y * this.ch, s.r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    // 轨道椭圆（虚线）
    ctx.save();
    ctx.strokeStyle = 'rgba(91,140,255,0.22)';
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 6]);
    ctx.beginPath();
    ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();

    // 学科节点按深度排序（sin>0 在前，最后画覆盖在上）
    const order: number[] = [];
    for (let i = 0; i < SUBJECT_COUNT; i++) {
      order.push(i);
    }
    order.sort((a: number, b: number): number => this.nodeZ(b) - this.nodeZ(a));

    // 后排节点（z < 0）
    for (const i of order) {
      if (this.nodeZ(i) < 0) {
        this.drawNode(cx, cy, rx, ry, i);
      }
    }
    // 中心知识晶体
    this.drawCrystal(cx, cy);
    // 前排节点（z >= 0）
    for (const i of order) {
      if (this.nodeZ(i) >= 0) {
        this.drawNode(cx, cy, rx, ry, i);
      }
    }
  }

  /** 学科 i 的深度值：sin(轨道角)，>0 在前（近） */
  private nodeZ(i: number): number {
    return Math.sin(this.focusAngle(i));
  }

  /** 学科 i 的当前轨道角（含全局自转角） */
  private focusAngle(i: number): number {
    return i * 2 * Math.PI / SUBJECT_COUNT + this.angle;
  }

  private drawNode(cx: number, cy: number, rx: number, ry: number, i: number): void {
    const ctx = this.ctx;
    const a = this.focusAngle(i);
    const x = cx + rx * Math.cos(a);
    const y = cy + ry * Math.sin(a);
    const z = Math.sin(a);
    // 近大远小 + 远暗近亮
    const scale = 1 + 0.4 * z;
    const alpha = 0.5 + 0.5 * (z + 1) / 2;
    const focused = this.focusIdx === i;
    const dimmed = this.focusIdx >= 0 && !focused;
    const color = SUBJECT_COLORS[i];
    const r = 15 * scale * (focused ? 1.35 : 1);

    ctx.save();
    ctx.globalAlpha = dimmed ? alpha * 0.45 : alpha;

    // 连向中心的引力线（聚焦学科加亮）
    ctx.strokeStyle = focused ? 'rgba(124,177,255,0.75)' : 'rgba(91,140,255,0.18)';
    ctx.lineWidth = focused ? 1.6 : 1;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(cx, cy);
    ctx.stroke();

    // 聚焦呼吸光环
    if (focused) {
      const pulse = 0.5 + 0.5 * Math.sin(this.breath * 3.2);
      ctx.strokeStyle = 'rgba(124,177,255,' + (0.35 + 0.45 * pulse).toFixed(2) + ')';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(x, y, r + 7 + 3 * pulse, 0, Math.PI * 2);
      ctx.stroke();
    }

    // 徽章：深底盘 + 学科色描边 + 渐变填充
    const grad = ctx.createRadialGradient(x - r * 0.3, y - r * 0.3, r * 0.2, x, y, r);
    grad.addColorStop(0, '#2a3a5c');
    grad.addColorStop(1, '#101a30');
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = color;
    ctx.lineWidth = focused ? 2.5 : 1.6;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.stroke();

    // 学科单字
    ctx.fillStyle = color;
    ctx.font = (focused ? 'bold ' : '') + Math.round(r * 0.95) + 'vp sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(SUBJECT_GLYPHS[i], x, y + 1);
    ctx.restore();
  }

  private drawCrystal(cx: number, cy: number): void {
    const ctx = this.ctx;
    const pulse = 0.5 + 0.5 * Math.sin(this.breath * 2.1);
    const rr = 26 + 3 * pulse;
    ctx.save();
    // 光晕
    const halo = ctx.createRadialGradient(cx, cy, rr * 0.4, cx, cy, rr * 2.6);
    halo.addColorStop(0, 'rgba(91,140,255,0.30)');
    halo.addColorStop(1, 'rgba(91,140,255,0)');
    ctx.fillStyle = halo;
    ctx.beginPath();
    ctx.arc(cx, cy, rr * 2.6, 0, Math.PI * 2);
    ctx.fill();
    // 菱形晶体（上下拉伸）
    ctx.beginPath();
    ctx.moveTo(cx, cy - rr);
    ctx.lineTo(cx + rr * 0.62, cy);
    ctx.lineTo(cx, cy + rr);
    ctx.lineTo(cx - rr * 0.62, cy);
    ctx.closePath();
    const body = ctx.createLinearGradient(cx - rr, cy - rr, cx + rr, cy + rr);
    body.addColorStop(0, '#7cb1ff');
    body.addColorStop(0.5, '#3d6fe0');
    body.addColorStop(1, '#9fd0ff');
    ctx.fillStyle = body;
    ctx.fill();
    ctx.strokeStyle = 'rgba(220,236,255,0.85)';
    ctx.lineWidth = 1.4;
    ctx.stroke();
    // 内高光棱线
    ctx.strokeStyle = 'rgba(255,255,255,0.5)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(cx, cy - rr);
    ctx.lineTo(cx, cy + rr);
    ctx.stroke();
    ctx.restore();
  }

  // ---------------- UI ----------------

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onAreaChange((_old: Area, newArea: Area) => {
          const w = Number(newArea.width);
          const h = Number(newArea.height);
          if (w > 0 && h > 0) {
            this.cw = w;
            this.ch = h;
            this.stars = [];
            this.draw();
          }
        })
        .gesture(
          PanGesture({ fingers: 1, distance: 3 })
            .onActionStart((e: GestureEvent) => {
              this.panLastX = e.offsetX;
              this.alignTarget = null; // 用户接管旋转，中断对齐
            })
            .onActionUpdate((e: GestureEvent) => {
              const dx = e.offsetX - this.panLastX;
              this.panLastX = e.offsetX;
              this.angle += dx * 0.008;
              this.draw();
            })
        )
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0d1526')
  }
}
