/**
 * PhysicsSimEngine —— 2D 物理仿真引擎（自绘，不依赖第三方物理引擎）。
 * 固定时间步（60Hz 逻辑步进）× 定时器渲染回调解耦；参数越界 clamp；
 * 预置模型库：自由落体、平抛、单摆、牛顿摆、串/并联电路、光的折射、浮力。
 */
import { Logger } from '../utils/Logger';

export type PhysicsModelId =
  'freefall' | 'projectile' | 'pendulum' | 'newton_cradle' |
  'circuit_series' | 'circuit_parallel' | 'refraction' | 'buoyancy';

export interface ParamDef {
  key: string;
  label: string;
  min: number;
  max: number;
  step: number;
  value: number;
}

export interface PhysicsModelDef {
  id: PhysicsModelId;
  label: string;
  params: ParamDef[];
}

export interface Quantity {
  label: string;
  value: string;
  formula: string;
}

export interface FrameState {
  modelId: PhysicsModelId;
  t: number;
  quantities: Quantity[];
  running: boolean;
}

export class VisualState {
  modelId: PhysicsModelId = 'freefall';
  t: number = 0;
  x: number = 0;
  y: number = 0;
  angle: number = 0;
  extra: string = '';
}

const DT = 1 / 60;
const G = 9.8;

export class PhysicsSimEngine {
  private modelId: PhysicsModelId = 'freefall';
  private params: Map<string, number> = new Map<string, number>();
  private time: number = 0;
  private running: boolean = false;
  private timer: number | undefined = undefined;
  private frameListeners: ((state: FrameState, visual: VisualState) => void)[] = [];

  static readonly MODELS: PhysicsModelDef[] = [
    {
      id: 'freefall',
      label: '自由落体',
      params: [
        { key: 'h', label: '释放高度(m)', min: 1, max: 100, step: 1, value: 20 },
        { key: 'v0', label: '初速度(m/s)', min: 0, max: 20, step: 0.5, value: 0 },
        { key: 'g', label: '重力加速度(m/s²)', min: 1, max: 20, step: 0.1, value: 9.8 }
      ]
    },
    {
      id: 'projectile',
      label: '平抛运动',
      params: [
        { key: 'v0', label: '初速度(m/s)', min: 1, max: 30, step: 0.5, value: 10 },
        { key: 'angle', label: '抛射角(°)', min: 0, max: 85, step: 1, value: 30 },
        { key: 'h', label: '初始高度(m)', min: 0, max: 50, step: 1, value: 0 },
        { key: 'g', label: '重力加速度(m/s²)', min: 1, max: 20, step: 0.1, value: 9.8 }
      ]
    },
    {
      id: 'pendulum',
      label: '单摆',
      params: [
        { key: 'L', label: '摆长(m)', min: 0.2, max: 4, step: 0.1, value: 1 },
        { key: 'theta0', label: '振幅(°)', min: 1, max: 45, step: 1, value: 15 }
      ]
    },
    {
      id: 'newton_cradle',
      label: '牛顿摆',
      params: [
        { key: 'count', label: '小球数量', min: 3, max: 7, step: 1, value: 5 }
      ]
    },
    {
      id: 'circuit_series',
      label: '串联电路',
      params: [
        { key: 'U', label: '电源电压(V)', min: 1, max: 24, step: 0.5, value: 12 },
        { key: 'R1', label: '电阻R1(Ω)', min: 1, max: 100, step: 1, value: 10 },
        { key: 'R2', label: '电阻R2(Ω)', min: 1, max: 100, step: 1, value: 20 }
      ]
    },
    {
      id: 'circuit_parallel',
      label: '并联电路',
      params: [
        { key: 'U', label: '电源电压(V)', min: 1, max: 24, step: 0.5, value: 12 },
        { key: 'R1', label: '电阻R1(Ω)', min: 1, max: 100, step: 1, value: 10 },
        { key: 'R2', label: '电阻R2(Ω)', min: 1, max: 100, step: 1, value: 20 }
      ]
    },
    {
      id: 'refraction',
      label: '光的折射',
      params: [
        { key: 'n1', label: '介质1折射率', min: 1, max: 3, step: 0.05, value: 1 },
        { key: 'n2', label: '介质2折射率', min: 1, max: 3, step: 0.05, value: 1.5 },
        { key: 'theta1', label: '入射角(°)', min: 0, max: 89, step: 1, value: 45 }
      ]
    },
    {
      id: 'buoyancy',
      label: '浮力',
      params: [
        { key: 'rho', label: '液体密度(kg/m³)', min: 100, max: 1500, step: 10, value: 1000 },
        { key: 'V', label: '排开体积(m³)', min: 0.001, max: 0.02, step: 0.001, value: 0.005 },
        { key: 'm', label: '物体质量(kg)', min: 0.1, max: 20, step: 0.1, value: 3 }
      ]
    }
  ];

  static findModel(id: PhysicsModelId): PhysicsModelDef | undefined {
    for (let i = 0; i < PhysicsSimEngine.MODELS.length; i++) {
      if (PhysicsSimEngine.MODELS[i].id === id) {
        return PhysicsSimEngine.MODELS[i];
      }
    }
    return undefined;
  }

  /** 由节点文本匹配模型，无匹配返回 undefined */
  static matchModel(caption: string): PhysicsModelId | undefined {
    const c = caption ? caption : '';
    if (c.includes('自由落体') || c.includes('freefall')) {
      return 'freefall';
    }
    if (c.includes('平抛') || c.includes('projectile')) {
      return 'projectile';
    }
    if (c.includes('单摆') || c.includes('pendulum') || c.includes('摆')) {
      return 'pendulum';
    }
    if (c.includes('牛顿摆') || c.includes('cradle')) {
      return 'newton_cradle';
    }
    if (c.includes('串联') || c.includes('series')) {
      return 'circuit_series';
    }
    if (c.includes('并联') || c.includes('parallel')) {
      return 'circuit_parallel';
    }
    if (c.includes('折射') || c.includes('反射') || c.includes('refraction')) {
      return 'refraction';
    }
    if (c.includes('浮力') || c.includes('buoyancy')) {
      return 'buoyancy';
    }
    return undefined;
  }

  loadModel(id: PhysicsModelId): void {
    this.modelId = id;
    this.params.clear();
    const def = PhysicsSimEngine.findModel(id);
    if (def) {
      for (let i = 0; i < def.params.length; i++) {
        this.params.set(def.params[i].key, def.params[i].value);
      }
    }
    this.time = 0;
    this.running = false;
    this.stopInternal();
  }

  getModelId(): PhysicsModelId {
    return this.modelId;
  }

  getParam(key: string): number {
    const v = this.params.get(key);
    return v !== undefined ? v : 0;
  }

  setParam(key: string, value: number): void {
    const def = PhysicsSimEngine.findModel(this.modelId);
    let min = -10000;
    let max = 10000;
    if (def) {
      for (let i = 0; i < def.params.length; i++) {
        if (def.params[i].key === key) {
          min = def.params[i].min;
          max = def.params[i].max;
          break;
        }
      }
    }
    const clamped = Math.max(min, Math.min(max, value));
    this.params.set(key, clamped);
  }

  getParamDefs(): ParamDef[] {
    const def = PhysicsSimEngine.findModel(this.modelId);
    return def ? def.params : [];
  }

  play(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.startInternal();
  }

  pause(): void {
    this.running = false;
    this.stopInternal();
  }

  isRunning(): boolean {
    return this.running;
  }

  reset(): void {
    this.time = 0;
    this.notifyFrame(false);
  }

  getTime(): number {
    return this.time;
  }

  /**
   * 本模型的运动结束时间（自由落体 / 平抛落地时刻），其余模型永不结束。
   * 到点后时间夹停并自动暂停，避免"已落地还在继续算"。
   */
  private endTime(): number {
    const id = this.modelId;
    if (id === 'freefall') {
      const g = Math.max(0.01, this.getParam('g'));
      const v0 = this.getParam('v0');
      const h = Math.max(0.01, this.getParam('h'));
      const tf = (Math.sqrt(v0 * v0 + 2 * g * h) - v0) / g;
      return tf > 0 ? tf : 0.05;
    }
    if (id === 'projectile') {
      const g = Math.max(0.01, this.getParam('g'));
      const v0 = this.getParam('v0');
      const ang = this.getParam('angle') * Math.PI / 180;
      const h0 = Math.max(0, this.getParam('h'));
      const vy0 = v0 * Math.sin(ang);
      const tf = (vy0 + Math.sqrt(vy0 * vy0 + 2 * g * h0)) / g;
      return tf > 0.05 ? tf : 0.05;
    }
    return Number.POSITIVE_INFINITY;
  }

  onFrame(listener: (state: FrameState, visual: VisualState) => void): () => void {
    this.frameListeners.push(listener);
    const self = this;
    return () => {
      const idx = self.frameListeners.indexOf(listener);
      if (idx >= 0) {
        self.frameListeners.splice(idx, 1);
      }
    };
  }

  private startInternal(): void {
    const self = this;
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
    const step = (): void => {
      if (!self.running) {
        return;
      }
      self.time += DT;
      const end = self.endTime();
      if (self.time >= end) {
        // 落地：时间夹停到精确落地时刻并自动暂停
        self.time = end;
        self.running = false;
        self.notifyFrame(true);
        self.stopInternal();
        return;
      }
      self.notifyFrame(true);
      if (self.running) {
        self.timer = setTimeout(step, 16);
      }
    };
    this.timer = setTimeout(step, 16);
  }

  private stopInternal(): void {
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  destroy(): void {
    this.running = false;
    this.frameListeners = [];
    this.stopInternal();
  }

  private notifyFrame(advance: boolean): void {
    const state = this.computeFrame();
    const visual = this.computeVisual();
    const listeners = this.frameListeners.slice();
    for (let i = 0; i < listeners.length; i++) {
      try {
        listeners[i](state, visual);
      } catch (err) {
        Logger.error('PhysicsSimEngine', `frame listener error: ${JSON.stringify(err)}`);
      }
    }
  }

  private computeFrame(): FrameState {
    const t = this.time;
    const quantities: Quantity[] = [];
    const id = this.modelId;
    if (id === 'freefall') {
      const g = this.getParam('g');
      const v0 = this.getParam('v0');
      const h = this.getParam('h');
      const v = v0 + g * t;
      const s = v0 * t + 0.5 * g * t * t;
      const landed = s >= h;
      const impactV = Math.sqrt(v0 * v0 + 2 * g * h);
      quantities.push({ label: '时间', value: `${t.toFixed(2)} s`, formula: 't' });
      quantities.push({ label: '速度', value: `${(landed ? impactV : v).toFixed(2)} m/s`, formula: 'v=v₀+gt' });
      quantities.push({ label: '下落距离', value: `${(landed ? h : s).toFixed(2)} m`, formula: 's=v₀t+½gt²' });
      quantities.push({ label: '状态', value: landed ? '已落地' : '下落中', formula: `h=${h.toFixed(0)}m` });
    } else if (id === 'projectile') {
      const v0 = this.getParam('v0');
      const angle = this.getParam('angle') * Math.PI / 180;
      const g = this.getParam('g');
      const h0 = this.getParam('h');
      const x = v0 * Math.cos(angle) * t;
      const y = h0 + v0 * Math.sin(angle) * t - 0.5 * g * t * t;
      const landed = y <= 0 && t > 0;
      quantities.push({ label: '时间', value: `${t.toFixed(2)} s`, formula: 't' });
      quantities.push({ label: '水平位移', value: `${x.toFixed(2)} m`, formula: 'x=v₀cosθ·t' });
      quantities.push({ label: '高度', value: `${(landed ? 0 : y).toFixed(2)} m`, formula: 'y=h+v₀sinθ·t-½gt²' });
      quantities.push({ label: '状态', value: landed ? '已落地' : '飞行中', formula: `h₀=${h0.toFixed(0)}m` });
    } else if (id === 'pendulum') {
      const L = this.getParam('L');
      const theta0 = this.getParam('theta0') * Math.PI / 180;
      const omega = Math.sqrt(G / L);
      const theta = theta0 * Math.cos(omega * t);
      const period = 2 * Math.PI * Math.sqrt(L / G);
      quantities.push({ label: '时间', value: `${t.toFixed(2)} s`, formula: 't' });
      quantities.push({ label: '摆角', value: `${(theta * 180 / Math.PI).toFixed(2)}°`, formula: 'θ=θ₀cos(ωt)' });
      quantities.push({ label: '周期', value: `${period.toFixed(2)} s`, formula: 'T=2π√(L/g)' });
    } else if (id === 'newton_cradle') {
      const count = this.getParam('count');
      quantities.push({ label: '小球数', value: `${count}`, formula: '动量守恒' });
      quantities.push({ label: '碰撞示意', value: '周期摆动', formula: 'm₁v₁=m₁v₁′+m₂v₂′' });
    } else if (id === 'circuit_series') {
      const U = this.getParam('U');
      const R1 = this.getParam('R1');
      const R2 = this.getParam('R2');
      const I = U / (R1 + R2);
      quantities.push({ label: '电流', value: `${I.toFixed(3)} A`, formula: 'I=U/(R₁+R₂)' });
      quantities.push({ label: 'R1电压', value: `${(I * R1).toFixed(2)} V`, formula: 'U₁=IR₁' });
      quantities.push({ label: 'R2电压', value: `${(I * R2).toFixed(2)} V`, formula: 'U₂=IR₂' });
    } else if (id === 'circuit_parallel') {
      const U = this.getParam('U');
      const R1 = this.getParam('R1');
      const R2 = this.getParam('R2');
      const I1 = U / R1;
      const I2 = U / R2;
      quantities.push({ label: '支路电流I1', value: `${I1.toFixed(3)} A`, formula: 'I₁=U/R₁' });
      quantities.push({ label: '支路电流I2', value: `${I2.toFixed(3)} A`, formula: 'I₂=U/R₂' });
      quantities.push({ label: '总电流', value: `${(I1 + I2).toFixed(3)} A`, formula: 'I=I₁+I₂' });
    } else if (id === 'refraction') {
      const n1 = this.getParam('n1');
      const n2 = this.getParam('n2');
      const theta1 = this.getParam('theta1');
      const sin2 = n1 * Math.sin(theta1 * Math.PI / 180) / n2;
      const theta2 = Math.asin(Math.max(-1, Math.min(1, sin2))) * 180 / Math.PI;
      quantities.push({ label: '入射角', value: `${theta1.toFixed(1)}°`, formula: 'θ₁' });
      quantities.push({ label: '折射角', value: `${theta2.toFixed(1)}°`, formula: 'n₁sinθ₁=n₂sinθ₂' });
      quantities.push({ label: '状态', value: Math.abs(sin2) >= 1 ? '发生全反射' : '正常折射', formula: sin2 >= 1 ? 'sinC=n₂/n₁' : '' });
    } else if (id === 'buoyancy') {
      const rho = this.getParam('rho');
      const V = this.getParam('V');
      const m = this.getParam('m');
      const F = rho * G * V;
      const W = m * G;
      const net = F - W;
      quantities.push({ label: '浮力', value: `${F.toFixed(2)} N`, formula: 'F=ρgV' });
      quantities.push({ label: '重力', value: `${W.toFixed(2)} N`, formula: 'G=mg' });
      quantities.push({ label: '合力', value: `${net.toFixed(2)} N`, formula: net > 0 ? '上浮' : (net < 0 ? '下沉' : '悬浮') });
    }
    return { modelId: id, t: t, quantities: quantities, running: this.running };
  }

  private computeVisual(): VisualState {
    const visual = new VisualState();
    visual.modelId = this.modelId;
    visual.t = this.time;
    const id = this.modelId;
    if (id === 'freefall') {
      const g = this.getParam('g');
      const v0 = this.getParam('v0');
      const h = this.getParam('h');
      visual.y = Math.min(h, v0 * this.time + 0.5 * g * this.time * this.time);
    } else if (id === 'projectile') {
      const v0 = this.getParam('v0');
      const angle = this.getParam('angle') * Math.PI / 180;
      const g = this.getParam('g');
      const h0 = this.getParam('h');
      visual.x = v0 * Math.cos(angle) * this.time;
      visual.y = Math.max(0, h0 + v0 * Math.sin(angle) * this.time - 0.5 * g * this.time * this.time);
    } else if (id === 'pendulum') {
      const L = this.getParam('L');
      const theta0 = this.getParam('theta0') * Math.PI / 180;
      const omega = Math.sqrt(G / L);
      visual.angle = theta0 * Math.cos(omega * this.time);
      visual.x = Math.sin(visual.angle) * L;
      visual.y = Math.cos(visual.angle) * L;
    } else if (id === 'newton_cradle') {
      visual.extra = '牛顿摆碰撞示意';
      const count = Math.max(3, Math.round(this.getParam('count')));
      visual.x = count;
    } else if (id === 'refraction') {
      const n1 = this.getParam('n1');
      const n2 = this.getParam('n2');
      const theta1 = this.getParam('theta1');
      const sin2 = n1 * Math.sin(theta1 * Math.PI / 180) / n2;
      let theta2 = Math.asin(Math.max(-1, Math.min(1, sin2))) * 180 / Math.PI;
      if (!Number.isFinite(theta2)) {
        theta2 = 90;
      }
      visual.angle = theta2;
      visual.extra = Math.abs(sin2) >= 1 ? 'total_reflection' : 'normal';
    } else if (id === 'buoyancy') {
      const rho = this.getParam('rho');
      const V = this.getParam('V');
      const m = this.getParam('m');
      const F = rho * G * V;
      const W = m * G;
      visual.y = Math.max(-0.5, Math.min(0.5, (F - W) / (m * 10)));
    } else {
      visual.extra = '静态电路';
    }
    return visual;
  }
}