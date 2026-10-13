/**
 * 地理地图 / 区位引擎（v1.2 学科引擎）。
 * 绘制简易经纬网格底图 + 区位标注点；支持从 detail 解析「地点: 说明」逐行标注。
 */

/** 单个区位标注 */
export interface GeoMarker {
  name: string;
  desc: string;
}

/** 解析区位标注：每行「地点: 说明」 */
export function parseGeoMarkers(detail: string): GeoMarker[] {
  const markers: GeoMarker[] = [];
  if (!detail || detail.length === 0) {
    return markers;
  }
  const lines = detail.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0) {
      continue;
    }
    const idx = line.indexOf(':') >= 0 ? line.indexOf(':') : line.indexOf('：');
    if (idx > 0) {
      markers.push({ name: line.substring(0, idx).trim(), desc: line.substring(idx + 1).trim() });
    } else {
      markers.push({ name: line, desc: '' });
    }
  }
  return markers;
}

/** 绘制简易地图（经纬网格 + 区位点） */
export class GeoMapEngine {
  /**
   * ctx.font 的字号单位是物理 px，而几何绘制单位是 vp：
   * 直接写 '14px' 在 3 倍屏上只有约 4vp，文字会缩到 1/3 近乎不可见。
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

  static draw(ctx: CanvasRenderingContext2D, viewW: number, viewH: number, markers: GeoMarker[]): void {
    ctx.clearRect(0, 0, viewW, viewH);
    // 底图
    ctx.fillStyle = '#eaf4ff';
    ctx.fillRect(0, 0, viewW, viewH);
    // 经纬网格
    ctx.strokeStyle = '#cfe3ff';
    ctx.lineWidth = 1;
    const grid = 40;
    for (let x = grid; x < viewW; x += grid) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, viewH);
      ctx.stroke();
    }
    for (let y = grid; y < viewH; y += grid) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(viewW, y);
      ctx.stroke();
    }
    if (markers.length === 0) {
      ctx.fillStyle = '#8a94a6';
      ctx.font = GeoMapEngine.fontOf(14);
      ctx.textAlign = 'center';
      ctx.fillText('暂无区位信息，请在节点要点里按「地点: 说明」逐行填写', viewW / 2, viewH / 2);
      return;
    }
    // 均匀布点
    const m = 40;
    const usableW = viewW - m * 2;
    const usableH = viewH - m * 2;
    const cols = Math.ceil(Math.sqrt(markers.length));
    const rows = Math.ceil(markers.length / cols);
    for (let i = 0; i < markers.length; i++) {
      const c = i % cols;
      const r = Math.floor(i / cols);
      const x = m + usableW * (cols > 1 ? c / (cols - 1) : 0.5);
      const y = m + usableH * (rows > 1 ? r / (rows - 1) : 0.5);
      ctx.fillStyle = '#fa541c';
      ctx.beginPath();
      ctx.arc(x, y, 6, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#1a2333';
      ctx.font = GeoMapEngine.fontOf(12);
      ctx.textAlign = 'center';
      ctx.fillText(markers[i].name, x, y - 12);
      if (markers[i].desc.length > 0) {
        const d = markers[i].desc.length > 12 ? markers[i].desc.substring(0, 11) + '…' : markers[i].desc;
        ctx.fillStyle = '#5a6473';
        ctx.font = GeoMapEngine.fontOf(11);
        ctx.fillText(d, x, y + 18);
      }
    }
  }
}
