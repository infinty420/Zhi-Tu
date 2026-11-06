/**
 * Scene3DView —— 原生 ArkGraphics3D（Ark3）3D 渲染视图组件（Wave 8 / 3D 能力落地）。
 *
 * 技术要点（面向 120fps + 稳定性设计）：
 * 1) 原生管线：Scene.load 加载 .glb → SceneResourceFactory 创建相机/平行光 →
 *    Component3D(ModelType.TEXTURE) GPU 合成进 ArkUI 渲染树（非 SURFACE 独立层，
 *    页面转场/切换不会出现独立图层闪黑闪白，天然防闪屏）。
 * 2) 帧驱动：displaySync(期望 120Hz, 60~120 自适应)逐帧推进轨道相机；
 *    相机/光照属性直写 3D 场景，不触发 ArkUI 状态刷新，UI 树零重绘。
 * 3) 可见性节能：active=false（页面隐藏/非当前模型）即停帧回调，防过热防耗电。
 * 4) 交互：拖动轨道旋转（偏航/俯仰钳制）、双指缩放（距离钳制），直接写相机变换。
 * 5) 帧统计：滑动窗口帧间隔 → 平均帧率/最低瞬时帧率/掉帧次数，500ms 节流上报，
 *    上报频率与 UI 刷新解耦，避免统计本身引入性能抖动。
 * 6) 防白屏：加载期骨架占位（同色深底）、就绪后 200ms 淡入；失败可重试，全程无白屏态。
 */

import { Scene, Camera, LightType, SceneNodeParameters, DirectionalLight, Node,
  SceneResourceFactory, Vec3, Vec4 } from '@kit.ArkGraphics3D';
import { displaySync } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { Logger } from '../utils/Logger';

const TAG = 'Scene3DView';

/** FPS 滑动窗口大小（帧） */
const FPS_WINDOW = 120;
/** FPS 统计上报节流（毫秒） */
const FPS_REPORT_MS = 500;
/** 掉帧判定系数：单帧间隔超过 1.3 倍目标帧间隔视为一次掉帧（随设备 vsync 自适应） */
const DROP_FACTOR = 1.3;
/** dt 钳制上限（毫秒），防切后台回来瞬间大 dt 造成旋转跳变 */
const DT_CLAMP_MS = 100;

@Component
export struct Scene3DView {
  /** rawfile 相对路径，如 'models/zhitu_subjects.glb' */
  modelPath: string = '';
  /**
   * 自动场景模式（true = Component3D 直接加载 glb，框架托管相机/光照/手势，
   * 官方保证渲染路径，兼容性最佳；false = 自定义场景模式，轨道相机/聚焦飞行/
   * 节点高亮由本组件驱动）。运行时切换会重建 3D 组件。
   */
  @Prop @Watch('onModeChanged') autoMode: boolean = true;
  /** 是否激活渲染：false 时停止帧回调（页面隐藏或非当前展示模型） */
  @Prop @Watch('onActiveChanged') active: boolean = false;
  /** 自动旋转开关 */
  @Prop @Watch('onAutoRotateChanged') autoRotate: boolean = true;
  /** 重置视角信号：父组件递增触发 */
  @Prop @Watch('onResetTick') resetTick: number = 0;
  /** 聚焦节点名（glTF 场景内节点名，如 'subj_math'）；空串 = 总览模式 */
  @Prop @Watch('onFocusChanged') focusNode: string = '';
  /** 聚焦时相机轨道角（弧度）：学科展台在场景中的方位角，飞行目标 */
  @Prop focusYaw: number = 0;
  /** 总览相机距离（依场景尺度配置，如知识馆环形布局取 7.5） */
  @Prop overviewDist: number = 5.4;
  /** 总览相机俯仰角 */
  @Prop overviewPitch: number = 0.42;
  /** FPS 上报回调：(平均帧率, 窗口最低帧率, 掉帧次数, 平均帧间隔ms) */
  onFps: ((fps: number, minFps: number, drops: number, intervalMs: number) => void) | undefined = undefined;

  /** loading | ready | error */
  @State phase: string = 'loading';
  @State errMsg: string = '';

  private scene: Scene | undefined = undefined;
  private camera: Camera | undefined = undefined;
  /** ArkUI 全局类型（Component3D 参数），不入 kit import */
  private sceneOpt: SceneOptions | undefined = undefined;
  private sync: displaySync.DisplaySync | undefined = undefined;
  private syncRunning: boolean = false;

  /** 轨道相机参数（绕原点） */
  private yaw: number = 0.7;
  private pitch: number = 0.42;
  private dist: number = 5.4;

  /** 相机飞行状态：向目标 yaw/dist/pitch 插值 */
  private flying: boolean = false;
  private flyTargetYaw: number = 0;
  private flyTargetDist: number = 5.4;
  private flyTargetPitch: number = 0.42;
  /** 当前高亮节点（scale 放大），取消聚焦时还原 */
  private highlighted: Node | undefined = undefined;

  /** 帧统计 */
  private lastNs: number = -1;
  private deltas: number[] = [];
  private statAccNs: number = 0;

  /** 手势锚点 */
  private panLastX: number = 0;
  private panLastY: number = 0;
  private pinchBaseDist: number = 5.4;

  aboutToAppear(): void {
    // 总览初始视角（依场景尺度由页面配置）
    this.dist = this.overviewDist;
    this.pitch = this.overviewPitch;
    this.flyTargetDist = this.overviewDist;
    this.flyTargetPitch = this.overviewPitch;
    this.pinchBaseDist = this.overviewDist;
    this.ensureSync();
    if (!this.autoMode) {
      // 自定义场景模式才走 Scene.load 管线；自动模式由 Component3D 框架托管
      this.initScene();
    } else {
      this.phase = 'ready';
    }
  }

  aboutToDisappear(): void {
    this.stopSync();
    if (this.sync) {
      this.sync.off('frame');
      this.sync = undefined;
    }
    this.clearHighlight();
    this.scene = undefined;
    this.camera = undefined;
    this.sceneOpt = undefined;
    this.deltas = [];
  }

  // ---------------- 场景初始化 ----------------

  private initScene(): void {
    this.phase = 'loading';
    this.errMsg = '';
    Scene.load($rawfile(this.modelPath))
      .then(async (sc: Scene) => {
        this.scene = sc;
        const rf: SceneResourceFactory = sc.getResourceFactory();
        // 轨道相机
        const camParam: SceneNodeParameters = { name: 'orbitCam' };
        const cam: Camera = await rf.createCamera(camParam);
        cam.enabled = true;
        cam.fov = 50 * Math.PI / 180;
        // 清屏色与页面底色一致：相机输出激活后不再出现引擎默认灰白层
        cam.clearColor = { r: 0.05, g: 0.08, b: 0.15, a: 1.0 };
        this.camera = cam;
        // 双平行光：暖主光（强）+ 冷补光（弱），避免暗面全黑与点光源的性能开销
        await this.setupLight(rf, 'mainLight', 4.5, 6.0, 3.5, 1.0, 0.97, 0.92, 4.0);
        await this.setupLight(rf, 'fillLight', -5.0, 2.5, -4.0, 0.55, 0.68, 0.95, 1.8);
        this.updateCamera();
        // 诊断埋点：root 非空即模型节点已进入场景树（空场景可从此行日志定位）
        Logger.info(TAG, `scene ready: ${this.modelPath}, root=${sc.root ? 'ok' : 'null'}`);
        this.sceneOpt = { scene: sc, modelType: ModelType.TEXTURE } as SceneOptions;
        this.phase = 'ready';
        // 补应用聚焦（prop 可能先于场景就绪变化）
        if (this.focusNode.length > 0) {
          this.onFocusChanged();
        }
        if (this.active) {
          this.startSync();
        }
      })
      .catch((err: string) => {
        Logger.error(TAG, `scene load failed: ${err}`);
        this.phase = 'error';
        this.errMsg = err && err.length > 0 ? err : '模型加载失败';
      });
  }

  private async setupLight(rf: SceneResourceFactory, name: string, ex: number, ey: number, ez: number,
    r: number, g: number, b: number, intensity: number): Promise<void> {
    const param: SceneNodeParameters = { name: name };
    // DirectionalLight 才暴露 intensity；Light 基类不含该属性（默认不保证非 0，
    // 缺省时 PBR 无环境贴图下模型全黑不可见）
    const light: DirectionalLight = await rf.createLight(param, LightType.DIRECTIONAL) as DirectionalLight;
    light.color = { r: r, g: g, b: b, a: 1.0 };
    light.intensity = intensity;
    light.position = { x: ex, y: ey, z: ez };
    // 平行光方向 = 节点 -Z 指向原点（glTF 语义）
    light.rotation = this.lookAtQuat(ex, ey, ez, 0, 0, 0);
    light.enabled = true;
  }

  private retry(): void {
    this.scene = undefined;
    this.camera = undefined;
    this.sceneOpt = undefined;
    this.highlighted = undefined;
    this.flying = false;
    this.lastNs = -1;
    this.deltas = [];
    this.initScene();
  }

  // ---------------- 相机与数学 ----------------

  private clamp(v: number, lo: number, hi: number): number {
    return v < lo ? lo : (v > hi ? hi : v);
  }

  /** 更新轨道相机：位置 + 朝向（朝原点） */
  private updateCamera(): void {
    const cam = this.camera;
    if (!cam) {
      return;
    }
    const cp = Math.cos(this.pitch);
    const ex = this.dist * cp * Math.sin(this.yaw);
    const ey = this.dist * Math.sin(this.pitch);
    const ez = this.dist * cp * Math.cos(this.yaw);
    cam.position = { x: ex, y: ey, z: ez };
    cam.rotation = this.lookAtQuat(ex, ey, ez, 0, 0, 0);
  }

  /**
   * 计算 eye→target 的朝向四元数（相机/平行光通用）。
   * 相机约定：看向 -Z。构造正交基 right/up/backward，矩阵→四元数。
   */
  private lookAtQuat(ex: number, ey: number, ez: number, tx: number, ty: number, tz: number): Vec4 {
    let fx = tx - ex;
    let fy = ty - ey;
    let fz = tz - ez;
    const fl = Math.sqrt(fx * fx + fy * fy + fz * fz);
    if (fl > 0.000001) {
      fx /= fl;
      fy /= fl;
      fz /= fl;
    }
    // right = forward × worldUp(0,1,0)
    let rx = -fz;
    let ry = 0;
    let rz = fx;
    const rl = Math.sqrt(rx * rx + rz * rz);
    if (rl > 0.000001) {
      rx /= rl;
      rz /= rl;
    }
    // up = right × forward
    const ux = ry * fz - rz * fy;
    const uy = rz * fx - rx * fz;
    const uz = rx * fy - ry * fx;
    // 行主序旋转矩阵 M = [right; up; -forward]
    const m00 = rx;
    const m01 = ry;
    const m02 = rz;
    const m10 = ux;
    const m11 = uy;
    const m12 = uz;
    const m20 = -fx;
    const m21 = -fy;
    const m22 = -fz;
    const trace = m00 + m11 + m22;
    if (trace > 0) {
      const s = Math.sqrt(trace + 1.0) * 2;
      return { x: (m21 - m12) / s, y: (m02 - m20) / s, z: (m10 - m01) / s, w: s / 4 };
    } else if (m00 > m11 && m00 > m22) {
      const s = Math.sqrt(1.0 + m00 - m11 - m22) * 2;
      return { x: s / 4, y: (m01 + m10) / s, z: (m02 + m20) / s, w: (m21 - m12) / s };
    } else if (m11 > m22) {
      const s = Math.sqrt(1.0 + m11 - m00 - m22) * 2;
      return { x: (m01 + m10) / s, y: s / 4, z: (m12 + m21) / s, w: (m02 - m20) / s };
    } else {
      const s = Math.sqrt(1.0 + m22 - m00 - m11) * 2;
      return { x: (m02 + m20) / s, y: (m12 + m21) / s, z: s / 4, w: (m10 - m01) / s };
    }
  }

  private resetView(): void {
    this.flying = false;
    this.yaw = 0.7;
    this.pitch = this.overviewPitch;
    this.dist = this.overviewDist;
    this.updateCamera();
  }

  // ---------------- 帧驱动（DisplaySync 120Hz） ----------------

  private ensureSync(): void {
    if (this.sync) {
      return;
    }
    this.sync = displaySync.create();
    // 目标帧率跟随设备 vsync：120Hz 屏期望 120；60Hz/模拟器屏期望其实际刷新率，
    // 避免期望值超出 vsync 上限造成 DisplaySync 回调频率异常与全帧掉帧误报。
    const range: ExpectedFrameRateRange = { expected: this.targetHz(), min: 30, max: 120 };
    this.sync.setExpectedFrameRateRange(range);
    this.sync.on('frame', (info: displaySync.IntervalInfo) => {
      this.onFrame(info.timestamp);
    });
  }

  /** 目标帧率：设备刷新率（30~120 钳制），取不到时退回 60 */
  private targetHz(): number {
    try {
      const rate: number = display.getDefaultDisplaySync().refreshRate;
      if (rate >= 30) {
        return Math.min(rate, 120);
      }
    } catch (err) {
      Logger.warn(TAG, `refreshRate: ${err}`);
    }
    return 60;
  }

  private startSync(): void {
    if (!this.sync || this.syncRunning || this.phase !== 'ready') {
      return;
    }
    this.lastNs = -1;
    this.statAccNs = 0;
    this.sync.start();
    this.syncRunning = true;
  }

  private stopSync(): void {
    if (!this.sync || !this.syncRunning) {
      return;
    }
    this.sync.stop();
    this.syncRunning = false;
  }

  private onFrame(tsNs: number): void {
    if (this.lastNs < 0) {
      this.lastNs = tsNs;
      return;
    }
    let dtMs = (tsNs - this.lastNs) / 1e6;
    this.lastNs = tsNs;
    if (dtMs <= 0) {
      return;
    }
    if (dtMs > DT_CLAMP_MS) {
      dtMs = DT_CLAMP_MS;
    }
    this.deltas.push(dtMs);
    if (this.deltas.length > FPS_WINDOW) {
      this.deltas.shift();
    }
    this.statAccNs += dtMs * 1e6;
    if (this.flying) {
      // 相机飞行插值优先（学科聚焦/回总览）
      this.stepFlight(dtMs);
    } else if (this.autoRotate && this.focusNode.length === 0) {
      // 自动旋转：时间驱动恒定角速度（与帧率解耦）；聚焦学科时停转保持构图
      this.yaw += 0.55 * (dtMs / 1000);
      this.updateCamera();
    }
    if (this.statAccNs >= FPS_REPORT_MS * 1e6) {
      this.statAccNs = 0;
      this.reportFps();
    }
  }

  private reportFps(): void {
    if (!this.onFps || this.deltas.length < 8) {
      return;
    }
    const dropMs = 1000 * DROP_FACTOR / this.targetHz();
    let sum = 0;
    let maxD = 0;
    let drops = 0;
    for (let i = 0; i < this.deltas.length; i++) {
      const d = this.deltas[i];
      sum += d;
      if (d > maxD) {
        maxD = d;
      }
      if (d > dropMs) {
        drops++;
      }
    }
    const avg = sum / this.deltas.length;
    const fps = 1000 / avg;
    const minFps = maxD > 0 ? 1000 / maxD : 0;
    this.onFps(Math.round(fps), Math.round(minFps), drops, Math.round(avg * 100) / 100);
  }

  // ---------------- 状态联动 ----------------

  onActiveChanged(): void {
    if (this.active) {
      this.startSync();
    } else {
      this.stopSync();
    }
  }

  onAutoRotateChanged(): void {
    // 帧回调内直接读取 this.autoRotate，无需处理
  }

  onResetTick(): void {
    this.resetView();
  }

  /** 渲染模式切换：自动 ⇄ 自定义（重建 3D 组件） */
  onModeChanged(): void {
    this.clearHighlight();
    this.flying = false;
    this.scene = undefined;
    this.camera = undefined;
    this.sceneOpt = undefined;
    if (this.autoMode) {
      this.phase = 'ready';
      // 自动模式：释放资源即切换（Component3D 框架自行加载）
    } else {
      this.initScene();
    }
  }

  /** 聚焦节点变化：高亮目标节点 + 相机飞向其方位；空串 = 回总览 */
  onFocusChanged(): void {
    if (!this.scene || this.phase !== 'ready') {
      return;
    }
    this.clearHighlight();
    if (this.focusNode.length === 0) {
      // 总览：回退到总览视角并恢复自转
      this.flyTo(this.yaw, this.overviewDist, this.overviewPitch);
      return;
    }
    const node: Node | null = this.scene.root ? this.scene.root.getNodeByPath(this.focusNode) : null;
    if (!node) {
      Logger.warn(TAG, `focus node not found: ${this.focusNode}`);
      this.flyTo(this.yaw, this.overviewDist, this.overviewPitch);
      return;
    }
    node.scale = { x: 1.35, y: 1.35, z: 1.35 } as Vec3;
    this.highlighted = node;
    // 飞向学科方位：yaw 取最短路径，dist 拉近、pitch 压低平视展台
    this.flyTo(this.focusYaw, 6.8, 0.22);
  }

  private clearHighlight(): void {
    if (this.highlighted) {
      this.highlighted.scale = { x: 1.0, y: 1.0, z: 1.0 } as Vec3;
      this.highlighted = undefined;
    }
  }

  /** 启动相机飞行（最短角路径） */
  private flyTo(targetYaw: number, targetDist: number, targetPitch: number): void {
    this.flyTargetYaw = this.nearestAngle(targetYaw);
    this.flyTargetDist = targetDist;
    this.flyTargetPitch = this.clamp(targetPitch, -1.35, 1.35);
    this.flying = true;
  }

  /** 目标角换算到与当前 yaw 差值 ≤ π 的等价角（避免绕远路） */
  private nearestAngle(target: number): number {
    let d = (target - this.yaw) % (2 * Math.PI);
    if (d > Math.PI) {
      d -= 2 * Math.PI;
    } else if (d < -Math.PI) {
      d += 2 * Math.PI;
    }
    return this.yaw + d;
  }

  /** 帧内飞行插值：指数逼近（帧率无关），到位即停 */
  private stepFlight(dtMs: number): void {
    if (!this.flying) {
      return;
    }
    const k = Math.min(1, dtMs / 260);
    this.yaw += (this.flyTargetYaw - this.yaw) * k;
    this.dist += (this.flyTargetDist - this.dist) * k;
    this.pitch += (this.flyTargetPitch - this.pitch) * k;
    this.updateCamera();
    const done = Math.abs(this.flyTargetYaw - this.yaw) < 0.004
      && Math.abs(this.flyTargetDist - this.dist) < 0.02
      && Math.abs(this.flyTargetPitch - this.pitch) < 0.004;
    if (done) {
      this.flying = false;
    }
  }

  // ---------------- UI ----------------

  @Builder
  loadingCard() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color('#5b8cff')
      Text('3D 模型加载中…')
        .fontSize(13)
        .fontColor('#8a94a6')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#0d1526')
  }

  @Builder
  errorCard() {
    Column({ space: 12 }) {
      Text('⚠')
        .fontSize(28)
        .fontColor('#ff9f43')
      Text('3D 场景加载失败')
        .fontSize(14)
        .fontColor('#e8ecf5')
        .fontWeight(FontWeight.Medium)
      if (this.errMsg.length > 0) {
        Text(this.errMsg)
          .fontSize(11)
          .fontColor('#8a94a6')
          .maxLines(2)
          .textAlign(TextAlign.Center)
      }
      Button('重试')
        .height(32)
        .fontSize(13)
        .backgroundColor('#2a3a5c')
        .fontColor('#dce5f5')
        .onClick(() => {
          this.retry();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#0d1526')
  }

  build() {
    Stack() {
      if (this.autoMode) {
        // 自动场景模式：Component3D 直接加载 glb，框架托管相机/光照/手势
        // （官方保证渲染路径，兼容性最佳；默认 SURFACE 硬件合成）
        // 关键：renderWidth/renderHeight 指定渲染分辨率（官方示例必设项），
        // 与 width/height 布局尺寸是两回事，缺省时渲染目标无效 → 区域空白不绘制。
        Component3D({ scene: $rawfile(this.modelPath), modelType: ModelType.SURFACE } as SceneOptions)
          .renderWidth('100%')
          .renderHeight('100%')
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      } else if (this.phase === 'ready' && this.sceneOpt) {
        // 自定义场景模式：轨道相机 + 聚焦飞行 + 节点高亮（本组件手势驱动）
        Component3D(this.sceneOpt)
          .renderWidth('100%')
          .renderHeight('100%')
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PanGesture({ fingers: 1, distance: 2 })
                .onActionStart((e: GestureEvent) => {
                  this.panLastX = e.offsetX;
                  this.panLastY = e.offsetY;
                  this.flying = false; // 用户接管相机，中断自动飞行
                })
                .onActionUpdate((e: GestureEvent) => {
                  const dx = e.offsetX - this.panLastX;
                  const dy = e.offsetY - this.panLastY;
                  this.panLastX = e.offsetX;
                  this.panLastY = e.offsetY;
                  this.yaw -= dx * 0.008;
                  this.pitch = this.clamp(this.pitch + dy * 0.006, -1.35, 1.35);
                  this.updateCamera();
                }),
              PinchGesture({ fingers: 2 })
                .onActionStart((e: GestureEvent) => {
                  this.pinchBaseDist = this.dist;
                })
                .onActionUpdate((e: GestureEvent) => {
                  const sc = e.scale > 0.05 ? e.scale : 1;
                  this.dist = this.clamp(this.pinchBaseDist / sc, 3.0, 10.0);
                  this.updateCamera();
                })
            )
          )
      } else if (this.phase === 'error') {
        this.errorCard()
      } else {
        this.loadingCard()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0d1526')
  }
}
