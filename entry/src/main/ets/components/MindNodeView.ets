/**
 * MindNodeView —— 节点自绘与命中测试工具（为 MindMapCanvas 提供节点级绘制能力）。
 * 支持 rect/round/ellipse 形状、主题色、选中/悬浮高亮、深链「进入」入口按钮、折叠角标。
 * 注意：ctx.font 必须使用标准 CSS 格式（'normal normal 13px sans-serif'），
 * 使用 '13vp' 等非标准写法会导致字体解析失败、fillText 静默不渲染。
 *
 * 文字策略（修复「字过小 / 放大后文字消失」）：
 *   - 字号随节点屏幕高度成比例（放大时同步变大），下限 16px 保证清晰可读；
 *   - 文字在节点内居中绘制，盒子部分移出屏幕左侧时不再整段被裁掉；
 *   - 不再用 camera.scale 阈值卡掉文字，所有布局类型一致出字。
 */
import { MasteryLevel, NodeShape, NodeType } from '../model/Constants';
import { MindNode } from '../model/MindNode';
import { MindMap } from '../model/MindMap';
import { LayoutEngine, TreeNodeLayout } from '../engine/LayoutEngine';

export interface Camera2D {
  scale: number;
  offsetX: number;
  offsetY: number;
}

const NODE_PAD_X = 10;
const ENTER_W = 44;
const ENTER_H = 26;
const ENTER_MARGIN = 6;
const COLLAPSE_SIZE = 18;
const COLLAPSE_MARGIN = 4;

export interface ScreenBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface NodeMeasure {
  w: number;
  h: number;
}

export class MindNodeView {
  /** 以标准 CSS 格式设置画布字体（sizeVp 为视口单位字号，随相机缩放取整；下限保证可读） */
  static applyFont(ctx: CanvasRenderingContext2D, sizeVp: number, scale: number): void {
    const px = Math.max(12, Math.round(sizeVp * scale));
    ctx.font = 'normal normal ' + px + 'px sans-serif';
  }

  /** 文本宽度单位估算（与 LayoutEngine.textUnits 一致）：CJK 全角=1，拉丁/数字≈0.55 */
  static textUnits(text: string): number {
    let units = 0;
    for (let i = 0; i < text.length; i++) {
      units += text.charCodeAt(i) > 0x2e7f ? 1.0 : 0.55;
    }
    return Math.max(1, units);
  }

  static measure(node: MindNode): NodeMeasure {
    return LayoutEngine.measureNode(node);
  }

  static toScreen(layout: TreeNodeLayout, camera: Camera2D): ScreenBox {
    return {
      x: layout.x * camera.scale + camera.offsetX,
      y: layout.y * camera.scale + camera.offsetY,
      w: layout.w * camera.scale,
      h: layout.h * camera.scale
    };
  }

  static isVisible(box: ScreenBox, viewW: number, viewH: number): boolean {
    return box.x + box.w > -40 && box.x < viewW + 40 && box.y + box.h > -40 && box.y < viewH + 40;
  }

  /** 节点主体绘制 */
  static drawNode(ctx: CanvasRenderingContext2D, node: MindNode, layout: TreeNodeLayout,
    camera: Camera2D, color: string, selected: boolean): void {
    const box = MindNodeView.toScreen(layout, camera);
    const r = 6 * camera.scale;
    ctx.save();
    // 阴影
    ctx.shadowColor = 'rgba(26,35,51,0.12)';
    ctx.shadowBlur = 4 * camera.scale;
    ctx.shadowOffsetY = 1 * camera.scale;
    ctx.fillStyle = color;
    MindNodeView.pathShape(ctx, box.x, box.y, box.w, box.h, node.style.shape, r);
    ctx.fill();
    ctx.restore();

    // 选中描边
    if (selected) {
      ctx.save();
      ctx.strokeStyle = '#ffd666';
      ctx.lineWidth = 2.5 * camera.scale;
      MindNodeView.pathShape(ctx, box.x - 2 * camera.scale, box.y - 2 * camera.scale,
        box.w + 4 * camera.scale, box.h + 4 * camera.scale, node.style.shape, r + 1);
      ctx.stroke();
      ctx.restore();
    }

    // 文本：字号随节点屏幕高度成比例（放大时同步变大），下限 16px；文字在节点内居中，
    // 避免盒子部分移出屏幕左侧时左对齐文字整段被裁掉
    if (box.h >= 8) {
      ctx.save();
      ctx.fillStyle = '#ffffff';
      const fontPx = Math.max(16, Math.min(Math.floor(box.h * 3 / 4), 120));
      ctx.font = 'normal normal ' + fontPx + 'px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const padX = Math.max(6, NODE_PAD_X * camera.scale);
      const interior = Math.max(fontPx, box.w - padX * 2);
      const maxUnits = interior / fontPx;
      let text = node.text;
      if (MindNodeView.textUnits(text) > maxUnits) {
        let t = text;
        while (t.length > 1 && MindNodeView.textUnits(t) + 1.0 > maxUnits) {
          t = t.substring(0, t.length - 1);
        }
        text = t + '…';
      }
      ctx.fillText(text, box.x + box.w / 2, box.y + box.h / 2);
      ctx.restore();
    }
  }

  /** 深链「进入」按钮（所有节点均绘制，便于测试跳转链路；GENERAL 跳转通用节点详情页） */
  static drawEnterButton(ctx: CanvasRenderingContext2D, node: MindNode, layout: TreeNodeLayout,
    camera: Camera2D): ScreenBox | undefined {
    const box = MindNodeView.toScreen(layout, camera);
    const ew = ENTER_W * camera.scale;
    const eh = ENTER_H * camera.scale;
    const x = box.x + box.w + ENTER_MARGIN * camera.scale;
    const y = box.y + (box.h - eh) / 2;
    ctx.save();
    ctx.fillStyle = '#1677ff';
    ctx.globalAlpha = 0.16;
    MindNodeView.roundRectPath(ctx, x, y, ew, eh, 6 * camera.scale);
    ctx.fill();
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#1677ff';
    MindNodeView.applyFont(ctx, 14, camera.scale);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('进入', x + ew / 2, y + eh / 2);
    ctx.restore();
    return { x: x, y: y, w: ew, h: eh };
  }

  /** 折叠角标（有子节点且未折叠时显示「−」，折叠时显示「+」） */
  static drawCollapseBadge(ctx: CanvasRenderingContext2D, node: MindNode, layout: TreeNodeLayout,
    camera: Camera2D): ScreenBox | undefined {
    const box = MindNodeView.toScreen(layout, camera);
    const s = COLLAPSE_SIZE * camera.scale;
    const x = box.x - s - COLLAPSE_MARGIN * camera.scale;
    const y = box.y + (box.h - s) / 2;
    ctx.save();
    ctx.fillStyle = node.collapsed ? '#faad14' : '#b8c8dd';
    ctx.beginPath();
    ctx.arc(x + s / 2, y + s / 2, s / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ffffff';
    MindNodeView.applyFont(ctx, 14, camera.scale);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(node.collapsed ? '+' : '−', x + s / 2, y + s / 2 + 1 * camera.scale);
    ctx.restore();
    return { x: x, y: y, w: s, h: s };
  }

  /** 掌握度角标（会=绿✓ / 模糊=橙? / 不会=红✗），未标记不绘制 */
  static drawMasteryBadge(ctx: CanvasRenderingContext2D, node: MindNode, layout: TreeNodeLayout,
    camera: Camera2D): void {
    if (node.mastery === MasteryLevel.UNSET) {
      return;
    }
    const box = MindNodeView.toScreen(layout, camera);
    const s = 15 * camera.scale;
    const x = box.x + box.w - s / 2;
    const y = box.y - s / 2;
    let fill = '#52c41a';
    let mark = '✓';
    if (node.mastery === MasteryLevel.FUZZY) {
      fill = '#faad14';
      mark = '?';
    } else if (node.mastery === MasteryLevel.UNKNOWN) {
      fill = '#f5222d';
      mark = '✗';
    }
    ctx.save();
    ctx.fillStyle = fill;
    ctx.beginPath();
    ctx.arc(x, y, s / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ffffff';
    MindNodeView.applyFont(ctx, 11, camera.scale);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(mark, x, y + 0.5 * camera.scale);
    ctx.restore();
  }

  /** 富内容角标：节点含图片/公式/链接/标签时，在左下角绘制小标记（v1.2） */
  static drawRichBadge(ctx: CanvasRenderingContext2D, node: MindNode, layout: TreeNodeLayout,
    camera: Camera2D): void {
    const count = (node.rich ? (node.rich.images.length + node.rich.links.length + (node.rich.formula.length > 0 ? 1 : 0) + node.rich.tags.length) : 0);
    if (count <= 0) {
      return;
    }
    const box = MindNodeView.toScreen(layout, camera);
    const s = 13 * camera.scale;
    const x = box.x + 2 * camera.scale;
    const y = box.y + box.h - s / 2;
    ctx.save();
    ctx.fillStyle = '#722ed1';
    ctx.beginPath();
    ctx.arc(x, y, s / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ffffff';
    MindNodeView.applyFont(ctx, 9, camera.scale);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(`${count}`, x, y + 0.5 * camera.scale);
    ctx.restore();
  }

  /** 命中测试：节点主体 */
  static hitNode(box: ScreenBox, x: number, y: number): boolean {
    return x >= box.x - 4 && x <= box.x + box.w + 4 && y >= box.y - 4 && y <= box.y + box.h + 4;
  }

  /** 命中测试：进入按钮 */
  static hitEnter(btn: ScreenBox | undefined, x: number, y: number): boolean {
    if (!btn) {
      return false;
    }
    return x >= btn.x && x <= btn.x + btn.w && y >= btn.y && y <= btn.y + btn.h;
  }

  /** 命中测试：折叠角标 */
  static hitCollapse(badge: ScreenBox | undefined, x: number, y: number): boolean {
    if (!badge) {
      return false;
    }
    return x >= badge.x && x <= badge.x + badge.w && y >= badge.y && y <= badge.y + badge.h;
  }

  /** 纯计算进入按钮区域（不绘制） */
  static computeEnterButtonBox(layout: TreeNodeLayout, camera: Camera2D): ScreenBox | undefined {
    const box = MindNodeView.toScreen(layout, camera);
    const ew = ENTER_W * camera.scale;
    const eh = ENTER_H * camera.scale;
    return { x: box.x + box.w + ENTER_MARGIN * camera.scale, y: box.y + (box.h - eh) / 2, w: ew, h: eh };
  }

  /** 纯计算折叠角标区域（不绘制） */
  static computeCollapseBox(layout: TreeNodeLayout, camera: Camera2D): ScreenBox {
    const box = MindNodeView.toScreen(layout, camera);
    const s = COLLAPSE_SIZE * camera.scale;
    return { x: box.x - s - COLLAPSE_MARGIN * camera.scale, y: box.y + (box.h - s) / 2, w: s, h: s };
  }

  /** 节点颜色：用户自定义优先，否则按主题色板+深度映射 */
  static nodeColor(node: MindNode, id: string, layout: TreeNodeLayout | undefined, map: MindMap | undefined,
    palette: string[]): string {
    if (node.userEdited && node.style.color && node.style.color !== '#1677ff') {
      return node.style.color;
    }
    if (!map) {
      return node.style.color && node.style.color.length > 0 ? node.style.color : palette[0];
    }
    let depth = 0;
    let current: MindNode | undefined = map.findNode(id);
    let guard = 0;
    while (current && current.parentId && guard < 100) {
      depth++;
      current = map.findNode(current.parentId);
      guard++;
    }
    const idx = Math.min(depth, palette.length - 1);
    return palette[idx];
  }

  private static pathShape(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number,
    shape: NodeShape, r: number): void {
    if (shape === NodeShape.RECT) {
      ctx.beginPath();
      ctx.rect(x, y, w, h);
    } else if (shape === NodeShape.ELLIPSE) {
      ctx.beginPath();
      ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
    } else {
      MindNodeView.roundRectPath(ctx, x, y, w, h, r);
    }
  }

  private static roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    const rr = r > w / 2 ? w / 2 : r;
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.lineTo(x + w - rr, y);
    ctx.arcTo(x + w, y, x + w, y + rr, rr);
    ctx.lineTo(x + w, y + h - rr);
    ctx.arcTo(x + w, y + h, x + w - rr, y + h, rr);
    ctx.lineTo(x + rr, y + h);
    ctx.arcTo(x, y + h, x, y + h - rr, rr);
    ctx.lineTo(x, y + rr);
    ctx.arcTo(x, y, x + rr, y, rr);
    ctx.closePath();
  }
}
