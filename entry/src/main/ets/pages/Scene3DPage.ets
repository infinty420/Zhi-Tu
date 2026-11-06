/**
 * Scene3DPage —— 3D 学科知识馆（Wave 8 / 原生 ArkGraphics3D + 学习数据可视化）。
 *
 * 功能闭环（非纯演示）：
 * 1) 3D 学科星系：9 门学科标志物（书卷/八面体/积木/单摆/分子/DNA/金字塔/地球/天平）
 *    环绕中心知识晶体，总览模式缓慢自转。
 * 2) 点选学科 → 相机平滑飞行聚焦该展台 + 节点放大高亮 + 展示该学科真实学习数据
 *    （导图数量 / 最近更新 / 最近一张导图）。
 * 3) 「查看学科导图」→ 携带学科参数跳转我的导图（列表按学科过滤），回到学习闭环。
 * 4) FPS HUD：目标帧率跟随设备 vsync 自适应；页面隐藏即停帧驱动。
 * 5) 深色底 + 同色骨架 + TEXTURE 合成：全程无白屏/闪屏；切换聚焦纯相机动画零重载。
 */

import { DeepLinkRouter } from '../services/DeepLinkRouter';
import { Scene3DView } from '../components/Scene3DView';
import { Galaxy2DView } from '../components/Galaxy2DView';
import { MindMapStore, MindMapSummary } from '../services/MindMapStore';
import { SUBJECTS, SubjectItem } from '../model/Constants';
import { display } from '@kit.ArkUI';

/** 3D 星系模型（生成脚本 tools/gen_subjects_model.js，节点名 subj_<code>） */
const MODEL_PATH = 'models/zhitu_subjects.glb';
/** 学科展台环形布局参数（与生成脚本一致） */
const SUBJECT_COUNT = 9;
const RING_YAW = (i: number): number => i * 2 * Math.PI / SUBJECT_COUNT;

/** 学科统计行（数据源：MindMapStore.list() 按 subject 聚合） */
class SubjectRow {
  code: string = '';
  label: string = '';
  count: number = 0;
  latestAt: number = 0;
  latestTitle: string = '';
  latestId: string = '';

  constructor(code: string, label: string) {
    this.code = code;
    this.label = label;
  }
}

@Entry
@Component
export struct Scene3DPage {
  /** 当前聚焦学科下标；-1 = 总览（自转） */
  @State subjectIdx: number = -1;
  /**
   * 渲染模式三态：
   * '2d'      —— Canvas 2D 伪 3D 学科星系（默认；模拟器/无 GPU 环境保底，任何设备可见）
   * 'auto3d'  —— Component3D 自动托管（框架相机/光照/手势；需真机 GPU，模拟器空白属官方限制）
   * 'custom3d'—— 自定义场景（轨道相机/聚焦飞行/节点高亮；需真机 GPU）
   */
  @State renderMode: string = '2d';
  /** 页面可见且未被系统压后台时为 true（驱动帧回调） */
  @State viewActive: boolean = false;
  /** 自动旋转（总览态生效） */
  @State autoRotate: boolean = true;
  /** 重置视角信号 */
  @State resetTick: number = 0;
  /** 学科统计 */
  @State rows: SubjectRow[] = [];
  /** FPS 统计 */
  @State fps: number = 0;
  @State minFps: number = 0;
  @State drops: number = 0;
  @State intervalMs: number = 0;
  @State fpsSeen: boolean = false;
  /** 目标帧率：跟随设备刷新率（120Hz 屏 120；60Hz/模拟器按其实际 vsync） */
  @State targetHz: number = 120;

  private store: MindMapStore = MindMapStore.getInstance();

  aboutToAppear(): void {
    try {
      const rate: number = display.getDefaultDisplaySync().refreshRate;
      if (rate >= 30) {
        this.targetHz = Math.min(rate, 120);
      }
    } catch (err) {
      // 取不到刷新率则保持默认 120
    }
    this.loadStats();
  }

  /** 聚合每学科的导图数量与最近更新 */
  private async loadStats(): Promise<void> {
    await this.store.ensureInit();
    const list: MindMapSummary[] = this.store.list();
    const map: Map<string, SubjectRow> = new Map<string, SubjectRow>();
    for (const s of SUBJECTS) {
      map.set(s.code, new SubjectRow(s.code, s.label));
    }
    for (const m of list) {
      const row: SubjectRow | undefined = map.get(m.subject);
      if (row) {
        row.count += 1;
        if (m.updatedAt > row.latestAt) {
          row.latestAt = m.updatedAt;
          row.latestTitle = m.title;
          row.latestId = m.id;
        }
      }
    }
    this.rows = Array.from(map.values());
  }

  private currentCode(): string {
    return this.subjectIdx >= 0 && this.subjectIdx < SUBJECT_COUNT ? SUBJECTS[this.subjectIdx].code : '';
  }

  private currentRow(): SubjectRow | undefined {
    const code = this.currentCode();
    for (const r of this.rows) {
      if (r.code === code) {
        return r;
      }
    }
    return undefined;
  }

  /** 当前学科导图数（无聚焦/无数据时 0） */
  private currentCount(): number {
    const r: SubjectRow | undefined = this.currentRow();
    return r ? r.count : 0;
  }

  /** 当前学科最近导图标题 */
  private currentTitle(): string {
    const r: SubjectRow | undefined = this.currentRow();
    return r ? r.latestTitle : '';
  }

  /** 当前学科最近更新时间 */
  private currentAt(): number {
    const r: SubjectRow | undefined = this.currentRow();
    return r ? r.latestAt : 0;
  }

  /** 切换学科：-1 总览 / i 聚焦（Scene3DView 由 @Prop 联动飞行+高亮） */
  private selectSubject(idx: number): void {
    if (idx === this.subjectIdx) {
      return;
    }
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.subjectIdx = idx;
    });
  }

  /** 跳转该学科的导图列表（MyMapsPage 按学科过滤） */
  private openSubjectMaps(): void {
    const code = this.currentCode();
    if (code.length === 0) {
      DeepLinkRouter.push('MyMapsPage');
      return;
    }
    const param: Record<string, Object> = { 'subject': code };
    DeepLinkRouter.pushWithParam('MyMapsPage', param);
  }

  /** Scene3DView 帧统计上报（已由组件 500ms 节流） */
  private onFpsReport(fps: number, minFps: number, drops: number, intervalMs: number): void {
    this.fps = fps;
    this.minFps = minFps;
    this.drops = drops;
    this.intervalMs = intervalMs;
    this.fpsSeen = true;
  }

  /** FPS 优秀线：贴近设备目标帧率（60Hz 屏跑满 60 即优秀，不误判） */
  private fpsGoodLine(): number {
    return this.targetHz >= 120 ? 110 : Math.max(30, this.targetHz - 5);
  }

  private fpsColor(): string {
    if (this.fps >= this.fpsGoodLine()) {
      return '#52e0a1';
    }
    if (this.fps >= 60) {
      return '#ffc44d';
    }
    return '#ff6b6b';
  }

  private fpsGrade(): string {
    if (!this.fpsSeen) {
      return '采样中';
    }
    if (this.fps >= this.fpsGoodLine()) {
      return `优秀 ${this.targetHz}Hz`;
    }
    if (this.fps >= 60) {
      return '良好 60Hz+';
    }
    return '需优化';
  }

  /** 最近更新时间 → 'MM-DD HH:mm' */
  private fmtTime(ts: number): string {
    if (ts <= 0) {
      return '--';
    }
    const d: Date = new Date(ts);
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  @Builder
  subjectChip(idx: number) {
    Button(idx < 0 ? '总览' : SUBJECTS[idx].label)
      .height(30)
      .fontSize(12.5)
      .padding({ left: 13, right: 13 })
      .backgroundColor(this.subjectIdx === idx ? '#2a4a8f' : '#141d33')
      .fontColor(this.subjectIdx === idx ? '#ffffff' : '#8a94a6')
      .borderRadius(15)
      .onClick(() => {
        this.selectSubject(idx);
      })
  }

  @Builder
  fpsHud() {
    Column({ space: 3 }) {
      Row({ space: 5 }) {
        Text(this.fpsSeen ? `${this.fps}` : '--')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.fpsColor())
        Column({ space: 1 }) {
          Text('FPS')
            .fontSize(10)
            .fontColor('#8a94a6')
          Text(this.fpsGrade())
            .fontSize(9)
            .fontColor(this.fpsColor())
        }
        .alignItems(HorizontalAlign.Start)
      }
      .alignItems(VerticalAlign.Bottom)

      Text(`最低 ${this.minFps} · 掉帧 ${this.drops} 次 · 间隔 ${this.intervalMs}ms`)
        .fontSize(9)
        .fontColor('#8a94a6')
      Text(`DisplaySync 期望 ${this.targetHz}Hz · vsync 自适应`)
        .fontSize(8.5)
        .fontColor('#5f6a80')
    }
    .padding(9)
    .borderRadius(12)
    .backgroundColor('rgba(13,21,38,0.82)')
    .border({ width: 1, color: 'rgba(91,140,255,0.25)' })
    .alignItems(HorizontalAlign.End)
  }

  /** 学科数据卡（左下浮层，不拦截 3D 旋转手势） */
  @Builder
  statCard() {
    if (this.subjectIdx >= 0) {
      Column({ space: 7 }) {
        Row({ space: 8 }) {
          Text(SUBJECTS[this.subjectIdx].label)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#eef2fa')
          Text(`${this.currentCount()} 张导图`)
            .fontSize(11.5)
            .fontColor('#7fb2ff')
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('rgba(42,74,143,0.35)')
            .borderRadius(10)
        }
        .alignItems(VerticalAlign.Center)

        if (this.currentTitle().length > 0) {
          Column({ space: 2 }) {
            Text('最近导图')
              .fontSize(9.5)
              .fontColor('#5f6a80')
            Text(this.currentTitle())
              .fontSize(12)
              .fontColor('#c4cede')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          Text(`更新于 ${this.fmtTime(this.currentAt())}`)
            .fontSize(10)
            .fontColor('#8a94a6')
        } else {
          Text('还没有该学科的导图——去创建第一张吧')
            .fontSize(11)
            .fontColor('#8a94a6')
        }

        Button('查看学科导图')
          .height(30)
          .fontSize(12.5)
          .backgroundColor('#2a4a8f')
          .fontColor('#ffffff')
          .borderRadius(15)
          .onClick(() => {
            this.openSubjectMaps();
          })
      }
      .padding(12)
      .borderRadius(14)
      .backgroundColor('rgba(13,21,38,0.86)')
      .border({ width: 1, color: '#1e2a45' })
      .alignItems(HorizontalAlign.Start)
    } else {
      Column({ space: 3 }) {
        Text('点击下方学科，聚焦展台查看学习数据')
          .fontSize(11)
          .fontColor('#8a94a6')
      }
      .padding(10)
      .borderRadius(12)
      .backgroundColor('rgba(13,21,38,0.66)')
    }
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        // 顶栏
        Row({ space: 10 }) {
          Button('返回')
            .height(32)
            .fontSize(14)
            .backgroundColor('#1a2742')
            .fontColor('#dce5f5')
            .onClick(() => {
              DeepLinkRouter.pop();
            })
          Column({ space: 1 }) {
            Text('3D 学科知识馆')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor('#eef2fa')
            Text(this.renderMode === '2d' ? `学科星系 · 2D 降级视图 · 目标 ${this.targetHz}Hz` : `原生 ArkGraphics3D · 目标 ${this.targetHz}Hz`)
              .fontSize(10.5)
              .fontColor('#8a94a6')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 12, right: 12, top: 8 })
        .width('100%')

        // 星系舞台：2D 星系（任何环境可见）⇄ 3D 渲染（真机 GPU；模拟器空白属官方限制）
        Stack() {
          if (this.renderMode === '2d') {
            Galaxy2DView({
              active: this.viewActive,
              autoRotate: this.autoRotate,
              resetTick: this.resetTick,
              focusIdx: this.subjectIdx,
              onFps: (fps: number, minFps: number, drops: number, intervalMs: number): void => {
                this.onFpsReport(fps, minFps, drops, intervalMs);
              }
            })
              .width('100%')
              .height('100%')
          } else {
            Scene3DView({
              modelPath: MODEL_PATH,
              autoMode: this.renderMode === 'auto3d',
              active: this.viewActive,
              autoRotate: this.autoRotate,
              resetTick: this.resetTick,
              focusNode: this.currentCode().length > 0 && this.renderMode === 'custom3d' ? `subj_${this.currentCode()}` : '',
              focusYaw: this.subjectIdx >= 0 ? RING_YAW(this.subjectIdx) : 0,
              overviewDist: 7.6,
              overviewPitch: 0.52,
              onFps: (fps: number, minFps: number, drops: number, intervalMs: number): void => {
                this.onFpsReport(fps, minFps, drops, intervalMs);
              }
            })
              .width('100%')
              .height('100%')
          }

          // FPS HUD 悬浮层（右上角，不拦截手势）
          Column() {
            this.fpsHud()
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopEnd)
          .padding(10)
          .hitTestBehavior(HitTestMode.None)

          // 学科数据卡（左下浮层，不拦截 3D 旋转手势）
          Column() {
            Blank()
            Row() {
              this.statCard()
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .align(Alignment.BottomStart)
          .padding(12)
          .hitTestBehavior(HitTestMode.None)
        }
        .layoutWeight(1)
        .width('100%')
        .borderRadius(18)
        .clip(true)
        .border({ width: 1, color: '#1e2a45' })
        .backgroundColor('#0d1526')

        // 学科 chips（横向滚动）
        Scroll() {
          Row({ space: 8 }) {
            this.subjectChip(-1)
            ForEach(SUBJECTS, (s: SubjectItem, idx: number) => {
              this.subjectChip(idx)
            }, (s: SubjectItem) => s.code)
          }
          .padding({ left: 12, right: 12 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        // 控制区：渲染模式三选 + 自转
        Row({ space: 10 }) {
          Row({ space: 5 }) {
            Text('2D 星系')
              .fontSize(12)
              .fontColor(this.renderMode === '2d' ? '#ffffff' : '#8a94a6')
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .backgroundColor(this.renderMode === '2d' ? '#2a4a8f' : '#141d33')
              .borderRadius(12)
              .onClick(() => {
                this.renderMode = '2d';
              })
            Text('3D 托管')
              .fontSize(12)
              .fontColor(this.renderMode === 'auto3d' ? '#ffffff' : '#8a94a6')
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .backgroundColor(this.renderMode === 'auto3d' ? '#2a4a8f' : '#141d33')
              .borderRadius(12)
              .onClick(() => {
                this.renderMode = 'auto3d';
              })
            Text('3D 自定义')
              .fontSize(12)
              .fontColor(this.renderMode === 'custom3d' ? '#ffffff' : '#8a94a6')
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .backgroundColor(this.renderMode === 'custom3d' ? '#2a4a8f' : '#141d33')
              .borderRadius(12)
              .onClick(() => {
                this.renderMode = 'custom3d';
              })
          }

          Row({ space: 6 }) {
            Text('自转')
              .fontSize(12.5)
              .fontColor('#c4cede')
            Toggle({ type: ToggleType.Switch, isOn: this.autoRotate })
              .width(38)
              .height(22)
              .onChange((v: boolean) => {
                this.autoRotate = v;
              })
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14 })

        // 技术说明脚注
        Column({ space: 3 }) {
          Text(this.renderMode === '2d'
            ? '2D 星系：Canvas 伪 3D（深度排序/近大远小/自转/聚焦对齐），任何设备可见；官方限制 ArkGraphics3D 不支持模拟器'
            : this.renderMode === 'auto3d'
              ? '3D 托管：Component3D 直接加载 glb（框架相机/光照/手势）；需真机 GPU，模拟器空白属官方预期'
              : '3D 自定义：Scene.load + 轨道相机飞行聚焦 + 节点高亮；需真机 GPU，模拟器空白属官方预期')
            .fontSize(10)
            .fontColor('#5f6a80')
          Text(`帧率上限受设备 vsync 限制（当前设备 ${this.targetHz}Hz 屏）；3D 渲染与 120fps 实测请用真机`)
            .fontSize(10)
            .fontColor('#5f6a80')
        }
        .padding({ left: 14, right: 14, bottom: 10 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#0a0f1e')
    }
    .hideTitleBar(true)
    .backgroundColor('#0a0f1e')
    .onShown(() => {
      this.viewActive = true;
      // 返回本页时刷新学科统计（可能在导图页新建/删除了导图）
      this.loadStats();
    })
    .onHidden(() => {
      this.viewActive = false;
    })
  }
}
