/**
 * LayoutEngine —— 三种布局纯函数算法。
 * 输入节点树 + layout + 默认节点度量，输出节点→坐标映射；不持有状态，布局切换无损重算。
 * 折叠语义：collapsed 节点的子树不参与布局计算。
 */
import { Layout } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { MindNode } from '../model/MindNode';

export interface NodeSize {
  w: number;
  h: number;
}

export interface TreeNodeLayout {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface LayoutResult {
  positions: Map<string, TreeNodeLayout>;
  width: number;
  height: number;
}

const NODE_W_MIN = 104;
const NODE_H = 44;
const TEXT_PAD = 14;
const CHAR_W = 33;
const GAP_X = 56;
const GAP_Y = 24;
const PADDING = 48;
const RADIAL_R0 = 90;
const RADIAL_DR = 110;

interface CountedNode {
  node: MindNode;
  children: CountedNode[];
  subtreeSpan: number;
}

export class LayoutEngine {
  static measureNode(node: MindNode): NodeSize {
    const units = LayoutEngine.textUnits(node.text);
    const w = Math.max(NODE_W_MIN, TEXT_PAD * 2 + units * CHAR_W);
    return { w: w, h: NODE_H };
  }

  /** 估算文本宽度单位（CJK 全角=1，拉丁/数字≈0.55），让节点宽度贴合计字号的实际文字宽 */
  static textUnits(text: string): number {
    let units = 0;
    for (let i = 0; i < text.length; i++) {
      units += text.charCodeAt(i) > 0x2e7f ? 1.0 : 0.55;
    }
    return Math.max(1, units);
  }

  static compute(map: MindMap): LayoutResult {
    const root = map.rootNode();
    const positions = new Map<string, TreeNodeLayout>();
    if (!root) {
      return { positions: positions, width: 0, height: 0 };
    }
    const counted = LayoutEngine.buildCounted(root, map);
    LayoutEngine.computeSpan(counted, map.layout);
    if (map.layout === Layout.TREE_V) {
      LayoutEngine.placeT(counted, 0, PADDING, PADDING, true, positions, map.layout);
    } else if (map.layout === Layout.TREE_H) {
      LayoutEngine.placeT(counted, 0, PADDING, PADDING, false, positions, map.layout);
    } else {
      LayoutEngine.placeRadial(counted, 0, -Math.PI / 2, Math.PI * 2, positions);
    }
    return LayoutEngine.bounds(positions);
  }

  /** 构建折叠感知的计数树 */
  private static buildCounted(root: MindNode, map: MindMap): CountedNode {
    const counted = LayoutEngine.countNode(root, map);
    return counted;
  }

  private static countNode(node: MindNode, map: MindMap): CountedNode {
    const counted: CountedNode = { node: node, children: [], subtreeSpan: 0 };
    if (!node.collapsed) {
      const children = node.childrenOf(map);
      for (let i = 0; i < children.length; i++) {
        counted.children.push(LayoutEngine.countNode(children[i], map));
      }
    }
    return counted;
  }

  private static computeSpan(cn: CountedNode, layout: Layout): void {
    const size = LayoutEngine.measureNode(cn.node);
    if (cn.children.length === 0) {
      cn.subtreeSpan = layout === Layout.TREE_V ? size.w : size.h;
      return;
    }
    let total = 0;
    for (let i = 0; i < cn.children.length; i++) {
      LayoutEngine.computeSpan(cn.children[i], layout);
      total += cn.children[i].subtreeSpan;
    }
    total += GAP_Y * (cn.children.length - 1);
    const own = layout === Layout.TREE_V ? size.w : size.h;
    cn.subtreeSpan = Math.max(own, total);
  }

  /** tree-h / tree-v 放置（horizontal=true 表示深度沿 y 轴 = tree-v） */
  private static placeT(cn: CountedNode, depth: number,
    cur: number, base: number, horizontal: boolean,
    positions: Map<string, TreeNodeLayout>, layout: Layout): void {
    const size = LayoutEngine.measureNode(cn.node);
    if (cn.children.length === 0) {
      if (horizontal) {
        positions.set(cn.node.id, { id: cn.node.id, x: base, y: cur, w: size.w, h: size.h });
      } else {
        positions.set(cn.node.id, { id: cn.node.id, x: cur, y: base, w: size.w, h: size.h });
      }
      return;
    }
    let total = 0;
    for (let i = 0; i < cn.children.length; i++) {
      total += cn.children[i].subtreeSpan;
    }
    const own = horizontal ? size.w : size.h;            // 兄弟轴尺寸（用于居中）
    const depthExtent = horizontal ? size.h : size.w;    // 深度轴尺寸（父节点沿深度方向的占位）
    const axisGap = horizontal ? GAP_X : GAP_Y;          // 兄弟/层级间距随方向变化
    total += axisGap * (cn.children.length - 1);
    if (horizontal) {
      const y = base + Math.max(0, (total - own) / 2);
      positions.set(cn.node.id, { id: cn.node.id, x: y, y: cur + 0, w: size.w, h: size.h });
    } else {
      const yBase = base + Math.max(0, (total - own) / 2);
      positions.set(cn.node.id, { id: cn.node.id, x: cur, y: yBase, w: size.w, h: size.h });
    }
    let childPos = base;
    for (let i = 0; i < cn.children.length; i++) {
      const child = cn.children[i];
      LayoutEngine.placeT(child, depth + 1, cur + depthExtent + axisGap, childPos, horizontal, positions, layout);
      childPos += child.subtreeSpan + axisGap;
    }
  }

  /** radial 放射状放置：根居中，按叶子权重分配角度扇区 */
  private static placeRadial(cn: CountedNode, depth: number,
    angleStart: number, angleSpan: number,
    positions: Map<string, TreeNodeLayout>): void {
    const size = LayoutEngine.measureNode(cn.node);
    const r = RADIAL_R0 + depth * RADIAL_DR;
    const angle = angleStart + angleSpan / 2;
    const cx = PADDING + r * Math.cos(angle) - size.w / 2;
    const cy = PADDING + r * Math.sin(angle) - size.h / 2;
    positions.set(cn.node.id, { id: cn.node.id, x: cx, y: cy, w: size.w, h: size.h });
    let childStart = angleStart;
    for (let i = 0; i < cn.children.length; i++) {
      const child = cn.children[i];
      const span = cn.subtreeSpan > 0 ? (child.subtreeSpan / cn.subtreeSpan) * angleSpan : angleSpan / cn.children.length;
      LayoutEngine.placeRadial(child, depth + 1, childStart, span, positions);
      childStart += span;
    }
  }

  private static bounds(positions: Map<string, TreeNodeLayout>): LayoutResult {
    let minX = Number.MAX_VALUE;
    let minY = Number.MAX_VALUE;
    let maxX = -Number.MAX_VALUE;
    let maxY = -Number.MAX_VALUE;
    let maxR = 0;
    positions.forEach((value, key) => {
      minX = Math.min(minX, value.x);
      minY = Math.min(minY, value.y);
      maxX = Math.max(maxX, value.x + value.w);
      maxY = Math.max(maxY, value.y + value.h);
      maxR = Math.max(maxR, value.x + value.w, value.y + value.h);
    });
    const empty = positions.size === 0;
    const width = empty ? 0 : (maxX - minX + PADDING * 2);
    const height = empty ? 0 : (maxY - minY + PADDING * 2);
    return { positions: positions, width: width, height: height };
  }
}