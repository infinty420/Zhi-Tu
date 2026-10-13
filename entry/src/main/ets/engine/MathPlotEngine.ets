/**
 * MathPlotEngine —— 数学绘图自绘引擎。
 * 笛卡尔坐标系（网格/坐标轴/刻度自适应缩放平移）、函数采样绘制、关键点定位、模板匹配、几何度量。
 */

import { FnOfX } from './FuncParser';

export interface MathCamera2D {
  scale: number;
  offsetX: number;
  offsetY: number;
}

export interface KeyPoint {
  label: string;
  x: number;
  y: number;
  type: string;
}

export interface TemplateMatch {
  id: string;
  expr: string;
}

export interface GeoPoint {
  x: number;
  y: number;
}

const GRID_AXIS_COLOR = '#cfd8e3';
const GRID_LINE_COLOR = '#eef2f7';
const GRID_LABEL_COLOR = '#8a94a6';

export class MathPlotEngine {
  /**
   * ctx.font 的字号单位是物理 px，而几何绘制单位是 vp：
   * 直接写 '10px' 在 3 倍屏上只有约 4vp，文字会缩到 1/3 近乎不可见。
   * 统一按 vp 意图换算成 px。
   */
  static fontOf(sizeVp: number): string {
    let px = Math.round(sizeVp * 3);
    try {
      px = Math.round(vp2px(sizeVp));
    } catch (err) {
      px = Math.round(sizeVp * 3);
    }
    const real = px < 12 ? 12 : px;
    return 'normal normal ' + real.toString() + 'px sans-serif';
  }

  static screenToWorldX(sx: number, camera: MathCamera2D): number {
    return (sx - camera.offsetX) / camera.scale;
  }

  static screenToWorldY(sy: number, camera: MathCamera2D): number {
    return -(sy - camera.offsetY) / camera.scale;
  }

  static worldToScreenX(wx: number, camera: MathCamera2D): number {
    return camera.offsetX + wx * camera.scale;
  }

  static worldToScreenY(wy: number, camera: MathCamera2D): number {
    return camera.offsetY - wy * camera.scale;
  }

  static drawCoordinate(ctx: CanvasRenderingContext2D, viewW: number, viewH: number, camera: MathCamera2D): void {
    // 防止缩放为 0/负数/非有限值导致网格步长计算死循环
    if (!camera || !Number.isFinite(camera.scale) || camera.scale <= 1e-6) {
      camera = { scale: 1e-3, offsetX: camera ? camera.offsetX : viewW / 2, offsetY: camera ? camera.offsetY : viewH / 2 };
    }
    ctx.save();
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, viewW, viewH);
    // 自适应网格步长（保证 >=36px）
    let step = 1;
    while (step * camera.scale < 36) {
      if (step === 1) {
        step = 5;
      } else if (step === 5) {
        step = 10;
      } else if (step === 10) {
        step = 50;
      } else if (step === 50) {
        step = 100;
      } else {
        step *= 10;
      }
    }
    // 竖线
    const xMin = MathPlotEngine.screenToWorldX(0, camera);
    const xMax = MathPlotEngine.screenToWorldX(viewW, camera);
    ctx.strokeStyle = GRID_LINE_COLOR;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let wx = Math.ceil(xMin / step) * step; wx <= xMax; wx += step) {
      const sx = MathPlotEngine.worldToScreenX(wx, camera);
      ctx.moveTo(sx, 0);
      ctx.lineTo(sx, viewH);
    }
    ctx.stroke();
    // 横线
    const yMin = MathPlotEngine.screenToWorldY(viewH, camera);
    const yMax = MathPlotEngine.screenToWorldY(0, camera);
    ctx.beginPath();
    for (let wy = Math.ceil(yMin / step) * step; wy <= yMax; wy += step) {
      const sy = MathPlotEngine.worldToScreenY(wy, camera);
      ctx.moveTo(0, sy);
      ctx.lineTo(viewW, sy);
    }
    ctx.stroke();
    // 坐标轴
    ctx.strokeStyle = GRID_AXIS_COLOR;
    ctx.lineWidth = 1.6;
    ctx.beginPath();
    const sy0 = MathPlotEngine.worldToScreenY(0, camera);
    if (sy0 >= 0 && sy0 <= viewH) {
      ctx.moveTo(0, sy0);
      ctx.lineTo(viewW, sy0);
    }
    const sx0 = MathPlotEngine.worldToScreenX(0, camera);
    if (sx0 >= 0 && sx0 <= viewW) {
      ctx.moveTo(sx0, 0);
      ctx.lineTo(sx0, viewH);
    }
    ctx.stroke();
    // 刻度标签（仅绘制可视范围内的整数刻度，范围过大时跳过硬分 Label 防爆栈）
    ctx.fillStyle = GRID_LABEL_COLOR;
    ctx.font = MathPlotEngine.fontOf(10);
    ctx.save();
    const xTickCount = Number.isFinite(xMin) && Number.isFinite(xMax) ? Math.floor(xMax) - Math.ceil(xMin) + 1 : 0;
    if (xTickCount > 0 && xTickCount <= 4000) {
      for (let wx = Math.ceil(xMin); wx <= xMax; wx++) {
        const sx = MathPlotEngine.worldToScreenX(wx, camera);
        ctx.fillText(`${wx}`, sx + 3, sy0 > 0 ? sy0 + 12 : 12);
      }
    }
    const yTickCount = Number.isFinite(yMin) && Number.isFinite(yMax) ? Math.floor(yMax) - Math.ceil(yMin) + 1 : 0;
    if (yTickCount > 0 && yTickCount <= 4000) {
      for (let wy = Math.ceil(yMin); wy <= yMax; wy++) {
        const sy = MathPlotEngine.worldToScreenY(wy, camera);
        ctx.fillText(`${wy}`, sx0 > 0 ? sx0 + 4 : 4, sy - 3);
      }
    }
    ctx.restore();
    ctx.restore();
  }

  /** 函数采样绘制（自适应固定 320 采样点防锯齿） */
  static drawFunction(ctx: CanvasRenderingContext2D, fn: FnOfX, viewW: number, viewH: number,
    camera: MathCamera2D, color: string): void {
    const xMin = MathPlotEngine.screenToWorldX(0, camera);
    const xMax = MathPlotEngine.screenToWorldX(viewW, camera);
    ctx.save();
    ctx.strokeStyle = color;
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    let started = false;
    let prevWy: number | undefined = undefined;
    const samples = 320;
    const dw = (xMax - xMin) / samples;
    for (let i = 0; i <= samples; i++) {
      const wx = xMin + i * dw;
      const wy = fn(wx);
      if (Number.isFinite(wy) && Math.abs(wy) < 1e6) {
        const sx = MathPlotEngine.worldToScreenX(wx, camera);
        const sy = MathPlotEngine.worldToScreenY(wy, camera);
        if (sy < -5000 || sy > viewH + 5000) {
          started = false;
          prevWy = undefined;
          continue;
        }
        if (!started) {
          ctx.moveTo(sx, sy);
          started = true;
        } else {
          // 间断点（如 1/x、tan(x)）处断开路径，避免画穿整屏的虚假连线
          if (prevWy !== undefined && prevWy * wy < 0 && (Math.abs(prevWy) > 1000 || Math.abs(wy) > 1000)) {
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(sx, sy);
          } else {
            ctx.lineTo(sx, sy);
          }
        }
        prevWy = wy;
      } else {
        started = false;
        prevWy = undefined;
      }
    }
    ctx.stroke();
    ctx.restore();
  }

  /** 标注关键点（零点 + 数值极值点近似） */
  static locateKeyPoints(fn: FnOfX, xMin: number, xMax: number): KeyPoint[] {
    const points: KeyPoint[] = [];
    const samples = 400;
    let prevX = xMin;
    let prevY = fn(xMin);
    for (let i = 1; i <= samples; i++) {
      const wx = xMin + (xMax - xMin) * i / samples;
      const wy = fn(wx);
      if (Number.isFinite(prevY) && Number.isFinite(wy) && prevY * wy < 0) {
        let lo = prevX;
        let hi = wx;
        let baseY = prevY;
        for (let j = 0; j < 24; j++) {
          const mid = (lo + hi) / 2;
          const midY = fn(mid);
          if (baseY * midY <= 0) {
            hi = mid;
          } else {
            lo = mid;
            baseY = midY;
          }
        }
        const zx = (lo + hi) / 2;
        points.push({ label: '零点', x: zx, y: 0, type: 'zero' });
      }
      prevX = wx;
      prevY = wy;
    }
    // 数值极值（导数符号变化点 → 顶点近似）
    let prevSlope = 0.000001;
    let hasPrev = false;
    for (let i = 1; i <= samples; i++) {
      const x0 = xMin + (xMax - xMin) * (i - 1) / samples;
      const x1 = xMin + (xMax - xMin) * i / samples;
      const y0 = fn(x0);
      const y1 = fn(x1);
      if (!Number.isFinite(y0) || !Number.isFinite(y1)) {
        hasPrev = false;
        continue;
      }
      const slope = (y1 - y0) / (x1 - x0);
      if (hasPrev && Number.isFinite(slope) && Number.isFinite(prevSlope)) {
        if (prevSlope * slope < 0) {
          const vx = (x0 + x1) / 2;
          const vy = fn(vx);
          if (Number.isFinite(vy)) {
            points.push({ label: '顶点', x: vx, y: vy, type: 'vertex' });
          }
        }
      }
      prevSlope = slope;
      hasPrev = true;
    }
    return points;
  }

  /** 模板匹配：由节点文本匹配常用函数模板 */
  static matchTemplate(caption: string): TemplateMatch | undefined {
    const c = caption ? caption : '';
    if (c.includes('抛物线') || c.includes('二次') || c.includes('parabola') || c.includes('quadratic')) {
      return { id: 'parabola', expr: 'x^2' };
    }
    if (c.includes('正弦') || c.includes('sin') || c.includes('sine')) {
      return { id: 'sine', expr: 'sin(x)' };
    }
    if (c.includes('反比例') || c.includes('reciprocal')) {
      return { id: 'reciprocal', expr: '1/x' };
    }
    if (c.includes('指数') || c.includes('exp') || c.includes('exponential')) {
      return { id: 'exponential', expr: 'exp(x)' };
    }
    if (c.includes('对数') || c.includes('log')) {
      return { id: 'logarithmic', expr: 'log(x)' };
    }
    return undefined;
  }

  static segmentLength(p1: GeoPoint, p2: GeoPoint): number {
    return Math.sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
  }

  /** 三角形 ∠B 角度（a,b,c 相对坐标，返回角度制） */
  static angleAtB(a: GeoPoint, b: GeoPoint, c: GeoPoint): number {
    const abx = a.x - b.x;
    const aby = a.y - b.y;
    const cbx = c.x - b.x;
    const cby = c.y - b.y;
    const dot = abx * cbx + aby * cby;
    const len = Math.sqrt(abx * abx + aby * aby) * Math.sqrt(cbx * cbx + cby * cby);
    if (len === 0) {
      return 0;
    }
    let cos = dot / len;
    if (cos > 1) {
      cos = 1;
    }
    if (cos < -1) {
      cos = -1;
    }
    return Math.acos(cos) * 180 / Math.PI;
  }
}