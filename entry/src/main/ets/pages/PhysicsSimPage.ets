/**
 * PhysicsSimPage —— 物理模型专项子界面（NavDestination，深链 physics）。
 * 预置模型库选择、参数滑块实时仿真、播放控制、物理量数值与公式面板、结果回填。
 */
import { promptAction } from '@kit.ArkUI';

import { FrameState, PhysicsModelDef, PhysicsModelId, PhysicsSimEngine, Quantity, VisualState } from '../engine/PhysicsSimEngine';
import { DeepLinkRouter } from '../services/DeepLinkRouter';

@Component
export struct PhysicsSimPage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private viewW: number = 0;
  private viewH: number = 0;
  // 场景缩放系数：全部几何常量以 320vp 设计基准书写，再乘以该系数，
  // 避免大屏 / 高屏下元素相对画布过小、挤在一角。
  private unit: number = 1;
  private engine: PhysicsSimEngine = new PhysicsSimEngine();

  @State modelLabels: string[] = [];
  @State selectedIndex: number = 0;
  @State playing: boolean = false;
  @State quantities: Quantity[] = [];
  @State modelId: PhysicsModelId = 'freefall';
  @State nodeId: string = '';
  @State nodeTitle: string = '物理模型';
  @State paramKeys: string[] = [];
  @State paramValues: number[] = [];
  @State paramMins: number[] = [];
  @State paramMaxs: number[] = [];
  @State paramSteps: number[] = [];

  private unsubscribe: (() => void) | undefined = undefined;

  private modelOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < this.modelLabels.length; i++) {
      const opt: SelectOption = { value: this.modelLabels[i] };
      options.push(opt);
    }
    return options;
  }

  aboutToAppear(): void {
    this.engine.destroy();
    const labels: string[] = [];
    const defs = PhysicsSimEngine.MODELS;
    for (let i = 0; i < defs.length; i++) {
      labels.push(defs[i].label);
    }
    this.modelLabels = labels;
    const link = DeepLinkRouter.currentLink();
    this.nodeId = link.nodeId;
    this.nodeTitle = link.payload && link.payload.length > 0 ? link.payload : '物理模型';
    const matched = PhysicsSimEngine.matchModel(link.payload);
    this.loadModelInternal(matched ? matched : 'freefall', matched !== undefined);
    this.engine.onFrame((state: FrameState, visual: VisualState) => {
      this.quantities = state.quantities.map((q) => q);
      this.modelId = state.modelId;
      this.playing = state.running;
      this.drawSim(visual);
    });
  }

  aboutToDisappear(): void {
    this.engine.pause();
  }

  private loadModelInternal(id: PhysicsModelId, matched: boolean): void {
    const def = PhysicsSimEngine.findModel(id);
    if (!def) {
      promptAction.showToast({ message: '模型加载失败，请重新选择' });
      return;
    }
    this.engine.loadModel(id);
    this.modelId = id;
    let index = 0;
    for (let i = 0; i < PhysicsSimEngine.MODELS.length; i++) {
      if (PhysicsSimEngine.MODELS[i].id === id) {
        index = i;
        break;
      }
    }
    this.selectedIndex = index;
    this.syncParams(def);
    this.engine.pause();
  }

  private onSelectModel(index: number): void {
    if (index >= 0 && index < PhysicsSimEngine.MODELS.length) {
      this.loadModelInternal(PhysicsSimEngine.MODELS[index].id, false);
    }
  }

  private syncParams(def: PhysicsModelDef): void {
    const keys: string[] = [];
    const values: number[] = [];
    const mins: number[] = [];
    const maxs: number[] = [];
    const steps: number[] = [];
    for (let i = 0; i < def.params.length; i++) {
      const p = def.params[i];
      keys.push(p.key);
      values.push(p.value);
      mins.push(p.min);
      maxs.push(p.max);
      steps.push(p.step);
    }
    this.paramKeys = keys;
    this.paramValues = values;
    this.paramMins = mins;
    this.paramMaxs = maxs;
    this.paramSteps = steps;
  }

  private setParamAt(index: number, value: number): void {
    if (index < 0 || index >= this.paramKeys.length) {
      return;
    }
    const key = this.paramKeys[index];
    if (value < this.paramMins[index]) {
      value = this.paramMins[index];
      promptAction.showToast({ message: '参数超出有效范围' });
    }
    if (value > this.paramMaxs[index]) {
      value = this.paramMaxs[index];
      promptAction.showToast({ message: '参数超出有效范围' });
    }
    this.paramValues[index] = value;
    // 重新赋值触发 @State 数组响应式更新（按索引赋值不会刷新 UI）
    this.paramValues = this.paramValues.slice();
    this.engine.setParam(key, value);
    setTimeout(() => {
      this.drawSim(null);
    }, 10);
  }

  private drawSim(visual: VisualState | null): void {
    if (this.viewW <= 0) {
      return;
    }
    this.updateMetrics();
    const ctx = this.context;
    const w = this.viewW;
    const h = this.viewH;
    let v: VisualState = visual ? visual : new VisualState();
    v.modelId = this.modelId;
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, w, h);
    const id = v.modelId;
    if (id === 'freefall') {
      this.drawFreefall(ctx, w, h, v);
    } else if (id === 'projectile') {
      this.drawProjectile(ctx, w, h, v);
    } else if (id === 'pendulum') {
      this.drawPendulum(ctx, w, h, v);
    } else if (id === 'newton_cradle') {
      this.drawCradle(ctx, w, h, v);
    } else if (id === 'circuit_series' || id === 'circuit_parallel') {
      this.drawCircuit(ctx, w, h, id);
    } else if (id === 'refraction') {
      this.drawRefraction(ctx, w, h, v);
    } else if (id === 'buoyancy') {
      this.drawBuoyancy(ctx, w, h, v);
    }
  }

  /**
   * 依据画布实际尺寸计算缩放系数。几何常量以 320vp 为设计基准，
   * 大屏不再出现「元素很小、堆在一角」的观感。
   */
  private updateMetrics(): void {
    const w = this.viewW;
    const h = this.viewH;
    if (w <= 0 || h <= 0) {
      return;
    }
    const u = Math.min(w, h) / 320;
    this.unit = u < 0.8 ? 0.8 : (u > 2 ? 2 : u);
  }

  /**
   * ctx.font 的字号单位是物理 px，而几何绘制单位是 vp：
   * 直接写 '12px' 在 3 倍屏上只有约 4vp，文字会缩到 1/3 近乎不可见。
   * 统一按 vp 意图换算成 px（vp2px），再随画布缩放，保证可读。
   */
  private applyFont(ctx: CanvasRenderingContext2D, sizeVp: number): void {
    const target = Math.max(12, Math.min(26, sizeVp * this.unit));
    let px = Math.round(target * 3);
    try {
      px = Math.round(vp2px(target));
    } catch (err) {
      px = Math.round(target * 3);
    }
    if (px < 12) {
      px = 12;
    }
    ctx.font = 'normal normal ' + px.toString() + 'px sans-serif';
  }

  private label(ctx: CanvasRenderingContext2D, text: string, x: number, y: number): void {
    ctx.fillStyle = '#1a2333';
    this.applyFont(ctx, 13);
    ctx.fillText(text, x, y);
  }

  private ball(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, color: string): void {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#1a233344';
    ctx.lineWidth = Math.max(1, this.unit);
    ctx.stroke();
  }

  /** 地面：实线 + 斜线阴影，让"地面"可读 */
  private drawGround(ctx: CanvasRenderingContext2D, w: number, groundY: number, u: number): void {
    ctx.strokeStyle = '#8a94a6';
    ctx.lineWidth = Math.max(1.5, 2 * u);
    ctx.beginPath();
    ctx.moveTo(8 * u, groundY);
    ctx.lineTo(w - 8 * u, groundY);
    ctx.stroke();
    ctx.strokeStyle = '#c9d2e0';
    ctx.lineWidth = Math.max(1, u);
    const step = Math.max(8, 14 * u);
    for (let x = 8 * u + step; x < w - 8 * u; x += step) {
      ctx.beginPath();
      ctx.moveTo(x, groundY);
      ctx.lineTo(x - 7 * u, groundY + 9 * u);
      ctx.stroke();
    }
  }

  private drawFreefall(ctx: CanvasRenderingContext2D, w: number, h: number, v: VisualState): void {
    const u = this.unit;
    const pad = 18 * u;
    const r = Math.max(12, 17 * u);
    const groundY = h - pad - 16 * u;
    const topY = pad + 26 * u;
    const cx = w / 2;
    // 下落导轨
    ctx.strokeStyle = '#d0d7e2';
    ctx.lineWidth = Math.max(1, u);
    ctx.setLineDash([6 * u, 6 * u]);
    ctx.beginPath();
    ctx.moveTo(cx, topY);
    ctx.lineTo(cx, groundY);
    ctx.stroke();
    ctx.setLineDash([]);
    this.drawGround(ctx, w, groundY, u);
    // visual.y 是"下落位移"，位移越大越接近地面（此前写反成向上运动）
    const sMax = Math.max(1, this.engine.getParam('h'));
    const frac = Math.max(0, Math.min(1, v.y / sMax));
    const travel = Math.max(0, groundY - topY - 2 * r);
    const cy = topY + r + frac * travel;
    this.ball(ctx, cx, cy, r, '#1677ff');
    const t = this.engine.getTime();
    const g = this.engine.getParam('g');
    const v0 = this.engine.getParam('v0');
    this.label(ctx, `t=${t.toFixed(2)}s   h=${sMax.toFixed(0)}m   s=${v.y.toFixed(2)}m   v=${(v0 + g * t).toFixed(2)}m/s`, pad, pad + 4 * u);
  }

  private drawProjectile(ctx: CanvasRenderingContext2D, w: number, h: number, v: VisualState): void {
    const u = this.unit;
    const pad = 18 * u;
    const r = Math.max(10, 15 * u);
    const groundY = h - pad - 16 * u;
    const topY = pad + 26 * u;
    const originX = pad + 12 * u;
    const v0 = this.engine.getParam('v0');
    const ang = this.engine.getParam('angle') * Math.PI / 180;
    const g = this.engine.getParam('g');
    const h0 = this.engine.getParam('h');
    const vy0 = v0 * Math.sin(ang);
    // 含初始高度的飞行时间与射高：h₀+v₀sinθ·t-½gt²=0
    const flight = Math.max(0.2, (vy0 + Math.sqrt(vy0 * vy0 + 2 * g * h0)) / g);
    const range = Math.max(1, v0 * Math.cos(ang) * flight);
    const apex = Math.max(1, h0 + Math.pow(vy0, 2) / (2 * g));
    // 等比自适应：整条弹道刚好铺满画布可用区域
    const sx = (w - originX - pad) / range;
    const sy = (groundY - topY) / apex;
    let s = Math.min(sx, sy);
    if (!Number.isFinite(s) || s <= 0) {
      s = 1;
    }
    this.drawGround(ctx, w, groundY, u);
    ctx.strokeStyle = '#1677ff';
    ctx.lineWidth = Math.max(1.5, 2 * u);
    ctx.beginPath();
    let started = false;
    for (let i = 0; i <= 60; i++) {
      const tt = flight * i / 60;
      const px = v0 * Math.cos(ang) * tt;
      const py = h0 + vy0 * tt - 0.5 * g * tt * tt;
      const dx = originX + px * s;
      const dy = groundY - py * s;
      if (!Number.isFinite(dx) || !Number.isFinite(dy)) {
        continue;
      }
      if (!started) {
        ctx.moveTo(dx, dy);
        started = true;
      } else {
        ctx.lineTo(dx, dy);
      }
    }
    ctx.stroke();
    const t = this.engine.getTime();
    const cx = originX + v0 * Math.cos(ang) * t * s;
    const cy = groundY - (h0 + vy0 * t - 0.5 * g * t * t) * s;
    this.ball(ctx, Math.max(r, Math.min(w - r, cx)), Math.max(r, Math.min(h - r, cy)), r, '#00b96b');
    this.label(ctx, `t=${t.toFixed(2)}s   x=${v.x.toFixed(2)}m   y=${v.y.toFixed(2)}m`, pad, pad + 4 * u);
  }

  private drawPendulum(ctx: CanvasRenderingContext2D, w: number, h: number, v: VisualState): void {
    const u = this.unit;
    const pivotY = 26 * u;
    const cx = w / 2;
    const L = Math.min(w * 0.36, h * 0.56);
    const r = Math.max(12, 17 * u);
    const theta0 = this.engine.getParam('theta0') * Math.PI / 180;
    // 摆动轨迹
    ctx.strokeStyle = '#e6f4ff';
    ctx.lineWidth = Math.max(1, u);
    ctx.beginPath();
    ctx.arc(cx, pivotY, L, Math.PI / 2 - theta0, Math.PI / 2 + theta0);
    ctx.stroke();
    // 平衡位置
    ctx.strokeStyle = '#d0d7e2';
    ctx.lineWidth = Math.max(1, u);
    ctx.setLineDash([6 * u, 6 * u]);
    ctx.beginPath();
    ctx.moveTo(cx, pivotY);
    ctx.lineTo(cx, pivotY + L + r);
    ctx.stroke();
    ctx.setLineDash([]);
    const bx = cx + Math.sin(v.angle) * L;
    const by = pivotY + Math.cos(v.angle) * L;
    ctx.strokeStyle = '#8a94a6';
    ctx.lineWidth = Math.max(1.5, 2 * u);
    ctx.beginPath();
    ctx.moveTo(cx, pivotY);
    ctx.lineTo(bx, by);
    ctx.stroke();
    ctx.fillStyle = '#8a94a6';
    ctx.beginPath();
    ctx.arc(cx, pivotY, Math.max(4, 5 * u), 0, Math.PI * 2);
    ctx.fill();
    this.ball(ctx, bx, by, r, '#1677ff');
    const period = 2 * Math.PI * Math.sqrt(this.engine.getParam('L') / 9.8);
    this.label(ctx, `θ=${(v.angle * 180 / Math.PI).toFixed(1)}°   T=${period.toFixed(2)}s`, 16 * u, 20 * u);
  }

  private drawCradle(ctx: CanvasRenderingContext2D, w: number, h: number, v: VisualState): void {
    const u = this.unit;
    const count = Math.max(3, Math.min(7, Math.round(v.x)));
    const pad = 22 * u;
    const gap = Math.min((w - pad * 2) / count, 48 * u);
    const r = Math.max(9, Math.min(gap * 0.42, 18 * u));
    const topY = h * 0.16;
    const rope = Math.min(h * 0.42, 170 * u);
    const center = w / 2;
    const left = center - (count - 1) * gap / 2;
    // 支架
    ctx.strokeStyle = '#8a94a6';
    ctx.lineWidth = Math.max(1.5, 2 * u);
    ctx.beginPath();
    ctx.moveTo(left - pad * 0.6, topY);
    ctx.lineTo(left + (count - 1) * gap + pad * 0.6, topY);
    ctx.stroke();
    const cyc = ((this.engine.getTime() * 2) % 2);
    const kick = Math.cos(cyc * Math.PI / 2);
    for (let i = 0; i < count; i++) {
      const bx = left + i * gap;
      let offset = 0;
      if (i === 0) {
        offset = (1 - kick) * rope * 0.35;
      } else if (i === count - 1) {
        offset = (-1 - kick) * rope * 0.35;
      }
      ctx.strokeStyle = '#d0d7e2';
      ctx.lineWidth = Math.max(1, u);
      ctx.beginPath();
      ctx.moveTo(bx, topY);
      ctx.lineTo(bx + offset, topY + rope);
      ctx.stroke();
      this.ball(ctx, bx + offset, topY + rope + r, r, i === 0 || i === count - 1 ? '#eb2f96' : '#1677ff');
    }
  }

  private drawCircuit(ctx: CanvasRenderingContext2D, w: number, h: number, id: PhysicsModelId): void {
    const u = this.unit;
    const left = w * 0.16;
    const right = w * 0.84;
    const top = h * 0.24;
    const bottom = h * 0.74;
    const size = Math.max(10, 17 * u);
    ctx.strokeStyle = '#1a2333';
    ctx.lineWidth = Math.max(1.5, 2 * u);
    ctx.strokeRect(left, top, right - left, bottom - top);
    if (id === 'circuit_series') {
      this.drawResistor(ctx, (left + right) / 2, top + (bottom - top) * 0.28, true, size, '#1677ff');
      this.drawResistor(ctx, (left + right) / 2, bottom - (bottom - top) * 0.28, true, size, '#00b96b');
    } else {
      this.drawResistor(ctx, left + (right - left) * 0.24, (top + bottom) / 2, false, size, '#1677ff');
      this.drawResistor(ctx, right - (right - left) * 0.24, (top + bottom) / 2, false, size, '#00b96b');
    }
    this.label(ctx, id === 'circuit_series' ? '串联电路' : '并联电路', 16 * u, 20 * u);
  }

  private drawResistor(ctx: CanvasRenderingContext2D, x: number, y: number, vertical: boolean, size: number, color: string): void {
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(2, 3 * this.unit);
    ctx.beginPath();
    if (vertical) {
      ctx.moveTo(x, y - size);
      ctx.lineTo(x - size * 0.7, y - size * 0.3);
      ctx.lineTo(x + size * 0.7, y + size * 0.1);
      ctx.lineTo(x - size * 0.6, y + size * 0.6);
      ctx.lineTo(x, y + size);
    } else {
      ctx.moveTo(x - size, y);
      ctx.lineTo(x - size * 0.4, y - size * 0.5);
      ctx.lineTo(x + size * 0.3, y + size * 0.5);
      ctx.lineTo(x + size, y);
    }
    ctx.stroke();
  }

  private drawRefraction(ctx: CanvasRenderingContext2D, w: number, h: number, v: VisualState): void {
    const u = this.unit;
    const midY = h * 0.56;
    // 下方介质
    ctx.fillStyle = '#e6f4ff';
    ctx.fillRect(0, midY, w, h - midY);
    ctx.strokeStyle = '#8a94a6';
    ctx.lineWidth = Math.max(1.5, 2 * u);
    ctx.beginPath();
    ctx.moveTo(0, midY);
    ctx.lineTo(w, midY);
    ctx.stroke();
    const topX = w * 0.38;
    const len = Math.min(w, h) * 0.34;
    // 法线
    ctx.strokeStyle = '#c9d2e0';
    ctx.lineWidth = Math.max(1, u);
    ctx.setLineDash([6 * u, 6 * u]);
    ctx.beginPath();
    ctx.moveTo(topX, midY - len * 1.1);
    ctx.lineTo(topX, midY + len * 1.1);
    ctx.stroke();
    ctx.setLineDash([]);
    const theta1 = this.engine.getParam('theta1');
    const n2 = this.engine.getParam('n2');
    const ang1 = theta1 * Math.PI / 180;
    // 入射光
    ctx.strokeStyle = '#1677ff';
    ctx.lineWidth = Math.max(2, 2.5 * u);
    ctx.beginPath();
    ctx.moveTo(topX - Math.sin(ang1) * len, midY - Math.cos(ang1) * len);
    ctx.lineTo(topX, midY);
    ctx.stroke();
    if (v.extra === 'total_reflection') {
      // 全反射：只有反射光
      ctx.strokeStyle = '#eb2f96';
      ctx.lineWidth = Math.max(2, 2.5 * u);
      ctx.beginPath();
      ctx.moveTo(topX, midY);
      ctx.lineTo(topX + Math.sin(ang1) * len, midY - Math.cos(ang1) * len);
      ctx.stroke();
    } else {
      const ang2 = v.angle * Math.PI / 180;
      ctx.strokeStyle = '#00b96b';
      ctx.lineWidth = Math.max(2, 2.5 * u);
      ctx.beginPath();
      ctx.moveTo(topX, midY);
      ctx.lineTo(topX + Math.sin(ang2) * len, midY + Math.cos(ang2) * len);
      ctx.stroke();
    }
    const show = n2 > 1 ? v.angle.toFixed(0) : '?';
    this.label(ctx, `入射角${theta1.toFixed(0)}°　折射角${show}°`, 16 * u, 20 * u);
  }

  private drawBuoyancy(ctx: CanvasRenderingContext2D, w: number, h: number, v: VisualState): void {
    const u = this.unit;
    const bw = Math.min(w * 0.58, 340 * u);
    const left = (w - bw) / 2;
    const right = left + bw;
    const top = h * 0.18;
    const bottom = h * 0.76;
    const waterY = bottom - (bottom - top) * 0.38;
    ctx.fillStyle = '#e6f4ff';
    ctx.fillRect(left, waterY, right - left, bottom - waterY);
    ctx.strokeStyle = '#1a2333';
    ctx.lineWidth = Math.max(1.5, 2 * u);
    ctx.beginPath();
    ctx.moveTo(left, top);
    ctx.lineTo(left, bottom);
    ctx.lineTo(right, bottom);
    ctx.lineTo(right, top);
    ctx.stroke();
    const r = Math.max(12, 20 * u);
    const dy = v.y * (bottom - waterY) * 0.9;
    const cy = (waterY + bottom) / 2 - dy;
    this.ball(ctx, (left + right) / 2, Math.max(top + r, Math.min(bottom - r, cy)), r, '#fa8c16');
    const rho = this.engine.getParam('rho');
    const state = v.y > 0.02 ? '上浮' : (v.y < -0.02 ? '下沉' : '悬浮');
    this.label(ctx, `液体密度 ρ=${rho.toFixed(0)}kg/m³　${state}`, 16 * u, 20 * u);
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
              this.engine.pause();
              DeepLinkRouter.pop();
            })
          Text('物理模型')
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
              const content = this.buildBackfillText();
              DeepLinkRouter.backfill(this.nodeId, content);
              promptAction.showToast({ message: '已回填到节点备注' });
            })
        }
        .padding(12)
        .width('100%')

        Row({ space: 8 }) {
          Text('选择模型')
            .fontSize(14)
            .fontColor('#8a94a6')
          Select(this.modelOptions())
            .selected(this.selectedIndex)
            .value(this.modelLabels.length > 0 ? this.modelLabels[this.selectedIndex] : '')
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.onSelectModel(index);
            })
        }
        .padding({ left: 12, right: 12 })
        .width('100%')

        // 画布
        Canvas(this.context)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#ffffff')
          .onReady(() => {
            this.viewW = this.context.width;
            this.viewH = this.context.height;
            this.drawSim(null);
          })

        // 控制 + 参数
        Column({ space: 8 }) {
          Row({ space: 12 }) {
            Button('播放')
              .height(34)
              .fontSize(14)
              .layoutWeight(1)
              .backgroundColor('#1677ff')
              .enabled(!this.playing)
              .onClick(() => {
                this.engine.play();
                this.playing = true;
              })
            Button('暂停')
              .height(34)
              .fontSize(14)
              .layoutWeight(1)
              .backgroundColor('#fa8c16')
              .enabled(this.playing)
              .onClick(() => {
                this.engine.pause();
                this.playing = false;
              })
            Button('重置')
              .height(34)
              .fontSize(14)
              .layoutWeight(1)
              .backgroundColor('#00b96b')
              .onClick(() => {
                this.engine.reset();
              })
          }
          ForEach(this.paramKeys, (key: string, index: number) => {
            Row({ space: 8 }) {
              Text(this.paramLabel(key))
                .fontSize(13)
                .fontColor('#1a2333')
                .width(110)
              Slider({
                value: this.paramValues[index],
                min: this.paramMins[index],
                max: this.paramMaxs[index],
                step: this.paramSteps[index]
              })
                .layoutWeight(1)
                .onChange((value: number) => {
                  this.setParamAt(index, value);
                })
              Text(this.paramValues[index].toFixed(2))
                .fontSize(12)
                .fontColor('#8a94a6')
                .width(52)
            }
          }, (key: string, index: number) => `${key}_${index}`)

          // 物理量面板
          if (this.quantities.length > 0) {
            Scroll() {
              Column({ space: 4 }) {
                ForEach(this.quantities, (q: Quantity) => {
                  Row({ space: 8 }) {
                    Text(q.label)
                      .fontSize(13)
                      .fontColor('#8a94a6')
                      .width(80)
                    Text(q.value)
                      .fontSize(14)
                      .fontColor('#1677ff')
                      .fontWeight(FontWeight.Medium)
                      .width(110)
                    Text(q.formula)
                      .fontSize(12)
                      .fontColor('#00b96b')
                      .layoutWeight(1)
                  }
                  .width('100%')
                }, (q: Quantity) => q.label + q.value)
              }
              .padding(6)
            }
            .scrollable(ScrollDirection.Vertical)
            .height(86)
            .backgroundColor('#f7f9fc')
            .borderRadius(8)
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

  private paramLabel(key: string): string {
    const def = PhysicsSimEngine.findModel(this.modelId);
    if (!def) {
      return key;
    }
    for (let i = 0; i < def.params.length; i++) {
      if (def.params[i].key === key) {
        return def.params[i].label;
      }
    }
    return key;
  }

  private buildBackfillText(): string {
    let text = `模型：${this.modelLabels[this.selectedIndex]}`;
    if (this.paramKeys.length > 0) {
      const parts: string[] = [];
      for (let i = 0; i < this.paramKeys.length; i++) {
        parts.push(`${this.paramLabel(this.paramKeys[i])}=${this.paramValues[i].toFixed(2)}`);
      }
      text += `；参数：${parts.join('，')}`;
    }
    if (this.quantities.length > 0) {
      const qs: string[] = [];
      for (let i = 0; i < this.quantities.length; i++) {
        qs.push(`${this.quantities[i].label}=${this.quantities[i].value}`);
      }
      text += `；物理量：${qs.join('，')}`;
    }
    return text;
  }
}