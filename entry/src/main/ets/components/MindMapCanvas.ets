/**
 * MindMapCanvas —— 基于 ArkUI Canvas 自绘的思维导图画布。
 * 支持三种布局渲染、摄像机（缩放/平移/聚焦）、节点选中、折叠切换、深链「进入」入口。
 * 采用 Camera 裁剪仅绘制可视区域节点（大图性能）。
 * 右下角提供 WPS 风格缩放控制条：缩小 / 百分比(点击复位100%) / 放大 / 适配全图。
 */

import { image } from '@kit.ImageKit';
import { THEME_COLORS } from '../model/Constants';
import { MindMap } from '../model/MindMap';
import { LayoutEngine, LayoutResult, TreeNodeLayout } from '../engine/LayoutEngine';
import { Camera2D, MindNodeView, ScreenBox } from './MindNodeView';
import { MindMapStore } from '../services/MindMapStore';

export class MindMapCanvasController {
  capture: () => image.PixelMap | undefined = () => undefined;
  resetView: () => void = () => {
  };
}

const MIN_SCALE = 0.3;
const MAX_SCALE = 3.0;
const ZOOM_STEP = 1.2;
const DOUBLE_TAP_MS = 320;
const PAN_THRESHOLD = 10;

interface GestureState {
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  moved: boolean;
  lastTapAt: number;
  pinchStartDist: number;
  pinchStartScale: number;
}

@Component
export struct MindMapCanvas {
  @Prop mapId: string = '';
  @Prop enterText: string = '进入';
  @State zoomPct: number = 100;
  onSelectNode?: (id: string) => void;
  onEnterNode?: (id: string) => void;
  onMapChanged?: (map: MindMap | undefined) => void;
  controller: MindMapCanvasController = new MindMapCanvasController();

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private store: MindMapStore = MindMapStore.getInstance();
  private currentMap: MindMap | undefined = undefined;
  private layoutResult: LayoutResult = { positions: new Map<string, TreeNodeLayout>(), width: 0, height: 0 };
  private camera: Camera2D = { scale: 1, offsetX: 0, offsetY: 0 };
  private selectedId: string = '';
  private unsubscribe: (() => void) | undefined = undefined;
  private fitFirst: boolean = true;
  private lastFitMapId: string = '';
  private lastFitLayout: string = '';
  private viewW: number = 0;
  private viewH: number = 0;
  private gestureState: GestureState = {
    startX: 0, startY: 0, lastX: 0, lastY: 0,
    moved: false, lastTapAt: 0, pinchStartDist: 0, pinchStartScale: 1
  };

  aboutToAppear(): void {
    this.unsubscribe = this.store.subscribe((snapshot) => {
      this.currentMap = snapshot;
      this.recompute();
    });
    const snap = this.store.currentSnapshot();
    this.currentMap = snap;
    this.recompute();
    if (this.fitFirst && this.currentMap !== undefined) {
      this.fitFirst = false;
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private recompute(): void {
    if (!this.currentMap) {
      this.context.clearRect(0, 0, this.viewW, this.viewH);
      this.lastFitMapId = '';
      this.lastFitLayout = '';
      return;
    }
    this.layoutResult = LayoutEngine.compute(this.currentMap);
    // 导图被替换（重新生成）或布局切换时重新 fit 视口；普通编辑保留用户当前缩放/平移
    const needFit = this.viewW > 0 && this.viewH > 0 &&
      (this.currentMap.id !== this.lastFitMapId || this.currentMap.layout !== this.lastFitLayout);
    if (needFit) {
      this.fitAll(true);
      this.lastFitMapId = this.currentMap.id;
      this.lastFitLayout = this.currentMap.layout;
    } else {
      this.draw();
    }
  }

  private fitAll(force: boolean): void {
    if (this.viewW <= 0 || this.viewH <= 0) {
      this.fitFirst = false;
      return;
    }
    const lw = Math.max(1, this.layoutResult.width);
    const lh = Math.max(1, this.layoutResult.height);
    const scale = Math.min((this.viewW - 24) / lw, (this.viewH - 24) / lh);
    this.camera.scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, scale));
    this.camera.offsetX = (this.viewW - lw * this.camera.scale) / 2;
    this.camera.offsetY = (this.viewH - lh * this.camera.scale) / 2;
    this.draw();
  }

  private draw(): void {
    const ctx = this.context;
    const map = this.currentMap;
    this.syncZoom();
    ctx.clearRect(0, 0, this.viewW, this.viewH);
    if (!map || this.viewW <= 0) {
      return;
    }
    const palette = THEME_COLORS.get(map.theme) || THEME_COLORS.get('ocean') || ['#1677ff'];
    // 1. 连线
    const positions = this.layoutResult.positions;
    positions.forEach((layout, id) => {
      const node = map.findNode(id);
      if (!node || node.parentId === null) {
        return;
      }
      const parentLayout = positions.get(node.parentId);
      if (!parentLayout) {
        return;
      }
      const box = MindNodeView.toScreen(layout, this.camera);
      const pbox = MindNodeView.toScreen(parentLayout, this.camera);
      if (!MindNodeView.isVisible(box, this.viewW, this.viewH) && !MindNodeView.isVisible(pbox, this.viewW, this.viewH)) {
        return;
      }
      ctx.save();
      ctx.strokeStyle = '#b8c8dd';
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      const x1 = pbox.x + pbox.w;
      const y1 = pbox.y + pbox.h / 2;
      const x2 = box.x;
      const y2 = box.y + box.h / 2;
      const mid = (x1 + x2) / 2;
      ctx.moveTo(x1, y1);
      ctx.bezierCurveTo(mid, y1, mid, y2, x2, y2);
      ctx.stroke();
      ctx.restore();
    });
    // 2. 节点（仅可视区域）
    positions.forEach((layout, id) => {
      const node = map.findNode(id);
      if (!node) {
        return;
      }
      const box = MindNodeView.toScreen(layout, this.camera);
      if (!MindNodeView.isVisible(box, this.viewW, this.viewH)) {
        return;
      }
      const color = MindNodeView.nodeColor(node, id, layout, this.currentMap, palette);
      const selected = id === this.selectedId;
      MindNodeView.drawNode(ctx, node, layout, this.camera, color, selected);
    });
    // 3. 深链进入按钮 与 折叠角标
    positions.forEach((layout, id) => {
      const node = map.findNode(id);
      if (!node) {
        return;
      }
      const box = MindNodeView.toScreen(layout, this.camera);
      if (!MindNodeView.isVisible(box, this.viewW, this.viewH)) {
        return;
      }
      MindNodeView.drawEnterButton(ctx, node, layout, this.camera);
      MindNodeView.drawCollapseBadge(ctx, node, layout, this.camera);
      MindNodeView.drawMasteryBadge(ctx, node, layout, this.camera);
      MindNodeView.drawRichBadge(ctx, node, layout, this.camera);
    });
  }

  private syncZoom(): void {
    const pct = Math.round(this.camera.scale * 100);
    if (pct !== this.zoomPct) {
      this.zoomPct = pct;
    }
  }

  /** 以视图中心为锚点缩放（保持中心内容不漂移） */
  private zoomBy(factor: number): void {
    if (this.viewW <= 0 || this.viewH <= 0) {
      return;
    }
    const newScale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.camera.scale * factor));
    if (Math.abs(newScale - this.camera.scale) < 0.0001) {
      this.syncZoom();
      return;
    }
    const cx = (this.viewW / 2 - this.camera.offsetX) / this.camera.scale;
    const cy = (this.viewH / 2 - this.camera.offsetY) / this.camera.scale;
    this.camera.scale = newScale;
    this.camera.offsetX = this.viewW / 2 - cx * newScale;
    this.camera.offsetY = this.viewH / 2 - cy * newScale;
    this.draw();
  }

  /** 复位到 100%，保持当前视图中心 */
  private resetZoom(): void {
    if (this.viewW <= 0 || this.viewH <= 0) {
      return;
    }
    const cx = (this.viewW / 2 - this.camera.offsetX) / this.camera.scale;
    const cy = (this.viewH / 2 - this.camera.offsetY) / this.camera.scale;
    this.camera.scale = 1;
    this.camera.offsetX = this.viewW / 2 - cx;
    this.camera.offsetY = this.viewH / 2 - cy;
    this.draw();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .backgroundColor('#F7F9FC')
        .onReady(() => {
          this.viewW = this.context.width;
          this.viewH = this.context.height;
          const canvas = this.context;
          this.controller.capture = (): image.PixelMap | undefined => {
            try {
              if (canvas.width <= 0 || canvas.height <= 0) {
                return undefined;
              }
              return canvas.getPixelMap(0, 0, canvas.width, canvas.height);
            } catch (err) {
              return undefined;
            }
          };
          this.controller.resetView = (): void => {
            this.fitAll(true);
          };
          if (this.currentMap === undefined) {
            this.currentMap = this.store.currentSnapshot();
          }
          if (this.currentMap !== undefined) {
            this.layoutResult = LayoutEngine.compute(this.currentMap);
            this.fitAll(false);
            this.lastFitMapId = this.currentMap.id;
            this.lastFitLayout = this.currentMap.layout;
          } else {
            this.context.clearRect(0, 0, this.viewW, this.viewH);
          }
        })
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })

      // WPS 风格缩放控制条（右下角悬浮）
      Row({ space: 10 }) {
        Text('−')
          .fontSize(18)
          .fontColor(this.zoomPct <= MIN_SCALE * 100 ? '#c3ccda' : '#334155')
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(14)
          .backgroundColor('#f1f5fb')
          .onClick(() => {
            this.zoomBy(1 / ZOOM_STEP);
          })
        Text(`${this.zoomPct}%`)
          .fontSize(12)
          .fontColor('#334155')
          .fontWeight(FontWeight.Medium)
          .width(46)
          .height(28)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.resetZoom();
          })
        Text('+')
          .fontSize(16)
          .fontColor(this.zoomPct >= MAX_SCALE * 100 ? '#c3ccda' : '#334155')
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(14)
          .backgroundColor('#f1f5fb')
          .onClick(() => {
            this.zoomBy(ZOOM_STEP);
          })
        Divider()
          .vertical(true)
          .height(16)
          .color('#dbe2ec')
        Text('适配')
          .fontSize(12)
          .fontColor('#1677ff')
          .height(28)
          .padding({ left: 4, right: 4 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.fitAll(true);
          })
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
      .border({ width: 1, color: '#e3e9f2' })
      .shadow({ radius: 10, color: 'rgba(15,35,70,0.12)', offsetY: 2 })
      .margin(12)
    }
    .width('100%')
    .height('100%')
  }

  private handleTouch(event: TouchEvent): void {
    const ctx = this.context;
    const touches = event.touches;
    if (event.type === TouchType.Down) {
      if (touches.length >= 1) {
        const t = touches[0];
        this.gestureState.startX = t.x;
        this.gestureState.startY = t.y;
        this.gestureState.lastX = t.x;
        this.gestureState.lastY = t.y;
        this.gestureState.moved = false;
      }
      if (touches.length >= 2) {
        this.gestureState.pinchStartDist = this.distance(touches[0].x, touches[0].y, touches[1].x, touches[1].y);
        this.gestureState.pinchStartScale = this.camera.scale;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (touches.length >= 2) {
        const dist = this.distance(touches[0].x, touches[0].y, touches[1].x, touches[1].y);
        if (this.gestureState.pinchStartDist > 0) {
          const ratio = dist / this.gestureState.pinchStartDist;
          this.camera.scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.gestureState.pinchStartScale * ratio));
          this.gestureState.moved = true;
        }
      } else if (touches.length === 1) {
        const t = touches[0];
        const dx = t.x - this.gestureState.lastX;
        const dy = t.y - this.gestureState.lastY;
        const totalDx = t.x - this.gestureState.startX;
        const totalDy = t.y - this.gestureState.startY;
        if (!this.gestureState.moved && Math.abs(totalDx) + Math.abs(totalDy) > PAN_THRESHOLD) {
          this.gestureState.moved = true;
        }
        if (this.gestureState.moved) {
          this.camera.offsetX += dx;
          this.camera.offsetY += dy;
        }
        this.gestureState.lastX = t.x;
        this.gestureState.lastY = t.y;
      }
      this.draw();
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.gestureState.moved) {
        return;
      }
      const changed = event.changedTouches;
      if (changed.length < 1) {
        return;
      }
      const t = changed[0];
      const now = Date.now();
      if (now - this.gestureState.lastTapAt < DOUBLE_TAP_MS) {
        this.gestureState.lastTapAt = 0;
        this.handleDoubleTap(t.x, t.y);
      } else {
        this.gestureState.lastTapAt = now;
        this.handleTap(t.x, t.y);
      }
    }
  }

  private distance(x1: number, y1: number, x2: number, y2: number): number {
    return Math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  }

  private handleTap(sx: number, sy: number): void {
    const map = this.currentMap;
    if (!map) {
      return;
    }
    // 命中顺序：进入按钮 → 折叠角标 → 节点主体 → 空白
    let id: string = '';
    this.layoutResult.positions.forEach((layout, nodeId) => {
      const node = map.findNode(nodeId);
      if (!node) {
        return;
      }
      const enterBox = MindNodeView.computeEnterButtonBox(layout, this.camera);
      if (id.length === 0 && MindNodeView.hitEnter(enterBox, sx, sy)) {
        id = nodeId;
      }
    });
    if (id.length > 0) {
      this.selectedId = id;
      if (this.onEnterNode) {
        this.onEnterNode(id);
      }
      return;
    }
    id = '';
    this.layoutResult.positions.forEach((layout, nodeId) => {
      const node = map.findNode(nodeId);
      if (!node) {
        return;
      }
      const box = MindNodeView.computeCollapseBox(layout, this.camera);
      if (MindNodeView.hitCollapse(box, sx, sy)) {
        id = nodeId;
      }
    });
    if (id.length > 0) {
      const node = map.findNode(id);
      if (node) {
        this.store.setCollapsed(id, !node.collapsed);
      }
      return;
    }
    id = '';
    this.layoutResult.positions.forEach((layout, nodeId) => {
      const box = MindNodeView.toScreen(layout, this.camera);
      if (MindNodeView.hitNode(box, sx, sy)) {
        id = nodeId;
      }
    });
    this.selectedId = id;
    if (this.onSelectNode) {
      this.onSelectNode(id);
    }
  }

  private handleDoubleTap(sx: number, sy: number): void {
    const map = this.currentMap;
    if (!map) {
      return;
    }
    let id: string = '';
    this.layoutResult.positions.forEach((layout, nodeId) => {
      const box = MindNodeView.toScreen(layout, this.camera);
      if (MindNodeView.hitNode(box, sx, sy)) {
        id = nodeId;
      }
    });
    if (id.length === 0 || this.viewW <= 0) {
      return;
    }
    this.selectedId = id;
    const layout = this.layoutResult.positions.get(id);
    if (!layout) {
      return;
    }
    // 聚焦：放大并居中
    this.camera.scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, this.camera.scale * 1.5));
    const cx = layout.x + layout.w / 2;
    const cy = layout.y + layout.h / 2;
    this.camera.offsetX = this.viewW / 2 - cx * this.camera.scale;
    this.camera.offsetY = this.viewH / 2 - cy * this.camera.scale;
    this.draw();
    if (this.onSelectNode) {
      this.onSelectNode(id);
    }
  }

  /** 外部控制：切换布局后重新 fit（页面可调用） */
  resetView(): void {
    this.fitFirst = false;
    this.fitAll(true);
  }
}
