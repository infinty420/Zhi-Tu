/**
 * 化学方程式与实验装置引擎（v1.2 学科引擎）。
 * 解析化学方程式（支持系数 / 下标 / 括号），校验配平；绘制反应式与简易实验装置（烧杯+试管）。
 */

/** 单元素原子计数表 */
export type AtomCount = Map<string, number>;

/** 化学方程式配平结果 */
export interface EquationResult {
  left: AtomCount;
  right: AtomCount;
  ok: boolean;
}

/** 统计一个化学式（含系数与括号）的原子数 */
export function countAtoms(formula: string): AtomCount {
  const result: AtomCount = new Map<string, number>();
  const text = formula.trim();
  if (text.length === 0) {
    return result;
  }
  // 提取前置系数
  let coeff = 1;
  const numMatch = text.match(/^(\d+)\s*/);
  let body = text;
  if (numMatch) {
    coeff = Number(numMatch[1]);
    body = text.substring(numMatch[0].length);
  }
  ChemEquationEngine.accumulate(body, 1, result);
  result.forEach((value, key) => {
    result.set(key, value * coeff);
  });
  return result;
}

export class ChemEquationEngine {
  /**
   * ctx.font 的字号单位是物理 px，而几何绘制单位是 vp：
   * 直接写 '16px' 在 3 倍屏上只有约 4vp，文字会缩到 1/3 近乎不可见。
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

  /** 解析整个方程式 "2H2 + O2 = 2H2O" 为左右两侧原子总数 */
  static parseEquation(eq: string): EquationResult {
    const left: AtomCount = new Map<string, number>();
    const right: AtomCount = new Map<string, number>();
    const sides = eq.split('=');
    if (sides.length < 2) {
      return { left: left, right: right, ok: false };
    }
    ChemEquationEngine.addSide(sides[0], left);
    ChemEquationEngine.addSide(sides[1], right);
    return { left: left, right: right, ok: ChemEquationEngine.balanced(left, right) };
  }

  /** 方程式是否配平 */
  static balanced(left: AtomCount, right: AtomCount): boolean {
    const keys: string[] = [];
    left.forEach((_v, k) => {
      if (keys.indexOf(k) < 0) {
        keys.push(k);
      }
    });
    right.forEach((_v, k) => {
      if (keys.indexOf(k) < 0) {
        keys.push(k);
      }
    });
    for (let i = 0; i < keys.length; i++) {
      const l = left.get(keys[i]) || 0;
      const r = right.get(keys[i]) || 0;
      if (l !== r) {
        return false;
      }
    }
    return true;
  }

  private static addSide(section: string, acc: AtomCount): void {
    const parts = section.split('+');
    for (let i = 0; i < parts.length; i++) {
      const f = parts[i].trim();
      if (f.length === 0) {
        continue;
      }
      const c = countAtoms(f);
      c.forEach((value, key) => {
        acc.set(key, (acc.get(key) || 0) + value);
      });
    }
  }

  /** 递归累加化学式（body 不含前置系数）；mult 为括号外乘子 */
  static accumulate(body: string, mult: number, acc: AtomCount): void {
    let i = 0;
    while (i < body.length) {
      const ch = body[i];
      if (ch >= 'A' && ch <= 'Z') {
        let elem = ch;
        let j = i + 1;
        while (j < body.length && body[j] >= 'a' && body[j] <= 'z') {
          elem += body[j];
          j++;
        }
        let numStr = '';
        while (j < body.length && body[j] >= '0' && body[j] <= '9') {
          numStr += body[j];
          j++;
        }
        const num = numStr.length > 0 ? Number(numStr) : 1;
        acc.set(elem, (acc.get(elem) || 0) + num * mult);
        i = j;
      } else if (ch === '(') {
        let depth = 1;
        let k = i + 1;
        while (k < body.length && depth > 0) {
          if (body[k] === '(') {
            depth++;
          } else if (body[k] === ')') {
            depth--;
          }
          k++;
        }
        const inner = body.substring(i + 1, k - 1);
        let numStr = '';
        let p = k;
        while (p < body.length && body[p] >= '0' && body[p] <= '9') {
          numStr += body[p];
          p++;
        }
        const innerMult = numStr.length > 0 ? Number(numStr) : 1;
        ChemEquationEngine.accumulate(inner, mult * innerMult, acc);
        i = p;
      } else {
        i++;
      }
    }
  }

  /** 绘制反应式 + 简易实验装置 */
  static draw(ctx: CanvasRenderingContext2D, viewW: number, viewH: number, eq: string, balancedOk: boolean): void {
    ctx.clearRect(0, 0, viewW, viewH);
    // 反应式文本
    ctx.fillStyle = balancedOk ? '#13c2c2' : '#f5222d';
    ctx.font = ChemEquationEngine.fontOf(16);
    ctx.textAlign = 'center';
    const shown = eq.length > 40 ? eq.substring(0, 39) + '…' : eq;
    ctx.fillText(shown, viewW / 2, 40);
    ctx.fillStyle = balancedOk ? '#52c41a' : '#f5222d';
    ctx.font = ChemEquationEngine.fontOf(13);
    ctx.fillText(balancedOk ? '✓ 已配平' : '✗ 未配平，请检查系数', viewW / 2, 64);
    // 简易实验装置：烧杯 + 试管
    const cx = viewW / 2;
    const baseY = viewH - 40;
    ctx.strokeStyle = '#1677ff';
    ctx.lineWidth = 2;
    // 烧杯
    ctx.beginPath();
    ctx.moveTo(cx - 50, baseY - 70);
    ctx.lineTo(cx - 40, baseY);
    ctx.lineTo(cx + 40, baseY);
    ctx.lineTo(cx + 50, baseY - 70);
    ctx.stroke();
    ctx.fillStyle = 'rgba(22,119,255,0.12)';
    ctx.fillRect(cx - 44, baseY - 50, 88, 48);
    // 试管
    ctx.strokeStyle = '#722ed1';
    ctx.beginPath();
    ctx.moveTo(cx + 90, baseY - 90);
    ctx.lineTo(cx + 100, baseY - 30);
    ctx.arc(cx + 100, baseY - 26, 5, Math.PI / 2, -Math.PI / 2, false);
    ctx.lineTo(cx + 110, baseY - 90);
    ctx.stroke();
  }
}
