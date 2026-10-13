/**
 * 历史时间轴引擎（v1.2 学科引擎）。
 * 将「年份: 事件」文本解析为时间轴事件，并在 Canvas 上绘制可交互时间轴。
 */

/** 单条时间轴事件 */
export interface TimelineEvent {
  year: string;
  text: string;
}

/** 从节点 detail 解析时间轴事件：支持「公元前221年: 秦统一」或「221: xxx」或「-221 xxx」 */
export function parseTimeline(detail: string): TimelineEvent[] {
  const events: TimelineEvent[] = [];
  if (!detail || detail.length === 0) {
    return events;
  }
  const lines = detail.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0) {
      continue;
    }
    const colon = line.indexOf(':');
    const sep = line.indexOf('：');
    const idx = colon >= 0 ? colon : sep;
    if (idx > 0) {
      const year = line.substring(0, idx).replace(/[^0-9\-]/g, '').trim();
      const text = line.substring(idx + 1).trim();
      if (year.length > 0 && text.length > 0) {
        events.push({ year: line.substring(0, idx).trim(), text: text });
        continue;
      }
    }
    events.push({ year: '', text: line });
  }
  return events;
}

/** 绘制时间轴（水平主轴 + 交替上下标注） */
export class HistoryTimelineEngine {
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

  static draw(ctx: CanvasRenderingContext2D, viewW: number, viewH: number, events: TimelineEvent[]): void {
    ctx.clearRect(0, 0, viewW, viewH);
    if (events.length === 0) {
      ctx.fillStyle = '#8a94a6';
      ctx.font = HistoryTimelineEngine.fontOf(14);
      ctx.textAlign = 'center';
      ctx.fillText('暂无时间轴内容，请在节点要点里按「年份: 事件」逐行填写', viewW / 2, viewH / 2);
      return;
    }
    const axisY = viewH / 2;
    ctx.strokeStyle = '#1677ff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(40, axisY);
    ctx.lineTo(viewW - 40, axisY);
    ctx.stroke();
    const left = 60;
    const right = viewW - 60;
    const step = events.length > 1 ? (right - left) / (events.length - 1) : 0;
    ctx.textAlign = 'center';
    for (let i = 0; i < events.length; i++) {
      const x = events.length > 1 ? left + step * i : viewW / 2;
      ctx.fillStyle = '#1677ff';
      ctx.beginPath();
      ctx.arc(x, axisY, 5, 0, Math.PI * 2);
      ctx.fill();
      const above = i % 2 === 0;
      ctx.fillStyle = '#1a2333';
      ctx.font = HistoryTimelineEngine.fontOf(12);
      if (events[i].year.length > 0) {
        ctx.fillText(events[i].year, x, above ? axisY - 18 : axisY + 34);
      }
      ctx.fillStyle = '#5a6473';
      ctx.font = HistoryTimelineEngine.fontOf(13);
      const label = events[i].text.length > 16 ? events[i].text.substring(0, 15) + '…' : events[i].text;
      ctx.fillText(label, x, above ? axisY - 36 : axisY + 52);
    }
  }
}
