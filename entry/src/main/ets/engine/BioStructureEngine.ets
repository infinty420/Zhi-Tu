/**
 * 生物结构层级引擎（v1.2 学科引擎）。
 * 将「缩进 / 层级: 名称」文本解析为层级结构，并在 Canvas 上绘制结构树。
 */

/** 结构树节点 */
export interface BioNode {
  name: string;
  depth: number;
  children: BioNode[];
}

/** 布局后的平面节点 */
interface FlatNode {
  node: BioNode;
  x: number;
  y: number;
}

/** 解析层级结构：以行首空格数代表深度，或「层级: 名称」 */
export function parseBioTree(detail: string): BioNode[] {
  const roots: BioNode[] = [];
  if (!detail || detail.length === 0) {
    return roots;
  }
  const lines = detail.split('\n');
  const stack: BioNode[] = [];
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    if (raw.trim().length === 0) {
      continue;
    }
    const indent = raw.length - raw.trimStart().length;
    const depth = Math.floor(indent / 2);
    let name = raw.trim();
    const idx = name.indexOf(':');
    const idxC = name.indexOf('：');
    const cut = idx >= 0 ? idx : idxC;
    if (cut > 0) {
      name = name.substring(cut + 1).trim();
    }
    const node: BioNode = { name: name, depth: depth, children: [] };
    while (stack.length > 0 && stack[stack.length - 1].depth >= depth) {
      stack.pop();
    }
    if (stack.length === 0) {
      roots.push(node);
    } else {
      stack[stack.length - 1].children.push(node);
    }
    stack.push(node);
  }
  return roots;
}

/** 绘制结构树（纵向层级） */
export class BioStructureEngine {
  /**
   * ctx.font 的字号单位是物理 px，而几何绘制单位是 vp：
   * 直接写 '13px' 在 3 倍屏上只有约 4vp，文字会缩到 1/3 近乎不可见。
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

  static draw(ctx: CanvasRenderingContext2D, viewW: number, viewH: number, roots: BioNode[]): void {
    ctx.clearRect(0, 0, viewW, viewH);
    if (roots.length === 0) {
      ctx.fillStyle = '#8a94a6';
      ctx.font = BioStructureEngine.fontOf(14);
      ctx.textAlign = 'center';
      ctx.fillText('暂无结构内容，请用缩进表示层级', viewW / 2, viewH / 2);
      return;
    }
    const palette = ['#52c41a', '#13c2c2', '#1677ff', '#722ed1', '#fa8c16'];
    const flat: FlatNode[] = [];
    const rowH = 30;
    let row = 0;
    const layout = (nodes: BioNode[], depth: number): void => {
      for (let i = 0; i < nodes.length; i++) {
        const x = 30 + depth * 26;
        const y = 30 + row * rowH;
        flat.push({ node: nodes[i], x: x, y: y });
        row++;
        layout(nodes[i].children, depth + 1);
      }
    };
    layout(roots, 0);
    // 连线
    ctx.strokeStyle = '#b8c8dd';
    ctx.lineWidth = 1.4;
    for (let i = 0; i < flat.length; i++) {
      const f = flat[i];
      for (let c = 0; c < f.node.children.length; c++) {
        // 找子节点在 flat 中的位置
        const childName = f.node.children[c].name;
        for (let k = 0; k < flat.length; k++) {
          if (flat[k].node.name === childName && flat[k].node.depth === f.node.depth + 1) {
            ctx.beginPath();
            ctx.moveTo(f.x + 8, f.y);
            ctx.lineTo(flat[k].x - 4, flat[k].y);
            ctx.stroke();
            break;
          }
        }
      }
    }
    // 节点
    for (let i = 0; i < flat.length; i++) {
      const f = flat[i];
      ctx.fillStyle = palette[f.node.depth % palette.length];
      ctx.beginPath();
      ctx.arc(f.x, f.y, 6, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#1a2333';
      ctx.font = BioStructureEngine.fontOf(13);
      ctx.textAlign = 'left';
      ctx.fillText(f.node.name, f.x + 12, f.y + 4);
    }
  }
}
