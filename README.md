# 智图（ZhiTu）

> 输入一个知识点，长出一张会思考的图。

面向中学阶段的「知识点 → 思维导图」互动学习 App。用户输入知识点或「学科 + 参考书目」，App 自动生成结构化思维导图；可对节点自由编辑，并通过内置 AI Agent 用自然语言改结构、改样式、补内容；对 math / physics / english 类型节点可一键深链到数学绘图、物理模型、英语例句专项子界面。

- **目标平台**：HarmonyOS NEXT（API 12+，Stage 模型，ArkTS + ArkUI 声明式）
- **包名**：`com.zhitu.app`
- **学科范围**：语文、数学、英语、物理、化学、生物、历史、地理、政治（可扩展）
- **节点深链类型**：`math` / `physics` / `english`（其余走 `general`）

---

## 一、工程结构

```
ZhiTu/
├─ AppScope/app.json5                      # bundleName=com.zhitu.app
├─ entry/src/main/
│  ├─ ets/
│  │  ├─ pages/                            # 页面层
│  │  │  ├─ Index.ets                      # Navigation 根容器（NavPathStack + pageMap）
│  │  │  ├─ HomePage.ets                   # 首页：自由输入 / 学科+书目
│  │  │  ├─ MindMapPage.ets               # 导图主界面：画布+工具栏+Agent面板
│  │  │  ├─ MyMapsPage.ets                # 我的导图：列表/导出/导入/删除
│  │  │  ├─ MathPlotPage.ets              # 数学绘图子界面（NavDestination）
│  │  │  ├─ PhysicsSimPage.ets            # 物理模型子界面（NavDestination）
│  │  │  └─ EnglishExamplesPage.ets       # 英语例句子界面（NavDestination）
│  │  ├─ components/                       # 组件层
│  │  │  ├─ MindMapCanvas.ets             # 导图画布（Canvas 自绘 + 缩放平移 + 拖拽）
│  │  │  ├─ MindNodeView.ets              # 节点卡片（形状/颜色/深链入口）
│  │  │  └─ AgentPanel.ets                # AI Agent 对话抽屉（流式气泡）
│  │  ├─ services/                         # 领域服务层
│  │  │  ├─ AIService.ets                 # AI 抽象接口 + AIResult<T> 联合类型
│  │  │  ├─ AIConfig.ets                  # AI 配置加载
│  │  │  ├─ AIServiceFactory.ets          # 工厂：Mock / OpenAICompat 切换 + 降级
│  │  │  ├─ MockAIService.ets             # 内置样例（二次函数/光的折射/例句）
│  │  │  ├─ OpenAICompatAIService.ets     # OpenAI 兼容 HTTP + SSE 流式
│  │  │  ├─ AIResponseValidator.ets       # 导图 JSON / patch 引用校验
│  │  │  ├─ MindMapStore.ets              # 全局可观察仓库（@Observed + AppStorage）
│  │  │  ├─ StorageService.ets            # Preferences + RDB 持久化
│  │  │  ├─ ExportService.ets             # 导出图片 / JSON
│  │  │  ├─ PatchApplier.ets              # Agent patch 增量应用（保留用户编辑）
│  │  │  └─ DeepLinkRouter.ets            # 深链路由（按 nodeType 路由 NavDestination）
│  │  ├─ engine/                          # 引擎层
│  │  │  ├─ LayoutEngine.ets              # tree-h / tree-v / radial 布局算法
│  │  │  ├─ FuncParser.ets                # y=f(x) 表达式解析
│  │  │  ├─ MathPlotEngine.ets            # 坐标系 + 函数采样 + 几何 + 关键点
│  │  │  └─ PhysicsSimEngine.ets          # 60Hz 仿真 + 7 类预置模型库
│  │  ├─ model/                           # 领域模型层
│  │  │  ├─ Constants.ets                 # NodeType/Layout/NodeShape 枚举 + 学科表
│  │  │  ├─ MindNode.ets                  # 节点领域对象 + NodeStyle
│  │  │  ├─ MindMap.ets                   # 导图文档 + 结构校验
│  │  │  ├─ DeepLink.ets                  # 深链参数
│  │  │  └─ TreeOps.ets                   # 树遍历/环检测/级联收集
│  │  └─ utils/                           # 工具基座
│  │     ├─ Logger.ets                    # hilog 统一封装
│  │     ├─ GenUid.ets                    # 唯一 id 生成
│  │     ├─ Config.ets                    # 配置文件加载
│  │     └─ AppContext.ets                # UIAbilityContext 全局持有
│  ├─ resources/
│  │  ├─ base/element/{string,color,float}.json   # 文案/主题色板/字号圆角规格
│  │  ├─ base/profile/main_pages.json     # 页面注册（NavDestination 模式仅需 Index）
│  │  └─ rawfile/ai_config.json           # AI 配置（endpoint/apiKey/model/mode）
│  └─ module.json5
```

分层依赖方向（禁止反向）：`pages → components → services → engine → model / utils`。

---

## 二、AI 密钥配置

AI 配置文件位于 `entry/src/main/resources/rawfile/ai_config.json`：

```json
{
  "endpoint": "https://api.openai.com/v1/chat/completions",
  "apiKey": "",
  "model": "gpt-4o-mini",
  "mode": "mock"
}
```

| 字段 | 说明 |
|------|------|
| `endpoint` | OpenAI 兼容 / 华为云兼容的 `chat/completions` 风格接口地址 |
| `apiKey` | 模型服务密钥。**留空时自动进入 Mock 模式**，主链路仍可跑通（使用内置样例数据） |
| `model` | 模型名，需支持中文理解与 JSON 结构化输出 |
| `mode` | `"mock"` 使用 MockAIService；`"openai"` 使用 OpenAICompatAIService。未配置密钥时强制降级为 `mock` |

**安全约束**：密钥仅经此配置文件注入，禁止硬编码到源码或提交到版本库。AI 请求的发起/成功/失败/重试关键节点经 `utils/Logger.ets` 统一埋点。

### 切换到真实模型

1. 将 `apiKey` 填入有效密钥；
2. 将 `mode` 改为 `"openai"`；
3. 按需调整 `endpoint`（华为云兼容接口同样适用）；
4. 重新编译运行。

### 离线 / 无密钥运行

保持 `mode: "mock"` 或 `apiKey` 为空即可。`MockAIService` 内置「二次函数」「光的折射」两套完整导图样例（含 math/physics/english 类型节点）、示例 patch 与分级例句，可端到端体验「输入→出图→编辑→对话改图→深链→回填」全链路。

---

## 三、运行与编译

### 环境要求

- DevEco Studio（最新版，自带 HarmonyOS NEXT SDK，API 12+）
- HarmonyOS 模拟器或真机

### 步骤

1. DevEco Studio 打开本工程根目录 `ZhiTu/`；
2. 等待 Sync 完成（自动拉取 `@ohos/hvigor-ohos-plugin` 等依赖）；
3. 连接真机或启动模拟器；
4. 点击 **Run**（或 `Build → Build Hap(s)/APP`）编译安装；
5. 应用启动后进入首页，输入「二次函数」点击「生成思维导图」即可体验主链路。

> 命令行构建：`hvigorw assembleHap --mode module -p product=default`（需配置 `DEVECO_SDK_HOME` 环境变量，且 DevEco Studio 未占用 `.hvigor` 缓存）。

---

## 四、专项子界面说明

通过导图节点的「进入」按钮触发深链，按节点类型路由：

| 节点类型 | 子界面 | 能力 |
|---------|--------|------|
| `math` | 数学绘图（`MathPlotPage`） | 笛卡尔坐标系、y=f(x) 函数绘制（一次/二次/反比例/指数/对数/三角）、点线圆几何、关键点（交点/顶点/零点）自动标注、模板下拉（抛物线/正弦曲线等） |
| `physics` | 物理模型（`PhysicsSimPage`） | 7+ 类预置模型（自由落体/平抛/单摆/牛顿摆/串并联电路/折射反射/浮力）、参数滑块、暂停/继续/重置、物理量与公式实时展示 |
| `english` | 英语例句（`EnglishExamplesPage`） | 3–5 条难度分级例句（中考/高考）、英文+中文+划词解析、系统 TTS 朗读、收藏回填 |
| `general` | 仅展开详情编辑 | — |

子界面产出的结果（收藏例句、关键结论等）可「回填」到对应节点的 detail（追加写入，不覆盖用户已有内容），形成「导图 → 深学 → 回填」闭环。

---

## 五、主链路使用示例

1. **输入**：首页输入「二次函数」→ 点击「生成思维导图」；
2. **出图**：AI（Mock 或真实模型）返回结构化 JSON → 校验通过 → 渲染为 tree-h 树状导图；
3. **编辑**：双击节点重命名、选中节点新增子节点、拖拽调整父子关系、改类型/颜色/形状、编辑要点详情（实时持久化）；
4. **对话改图**：唤起 Agent 面板，输入「数学节点用圆角矩形」→ Agent 返回 patch → 增量应用，保留用户已编辑部分；
5. **深链**：点击 math 类型节点的「进入」→ 跳转数学绘图界面 → 输入表达式绘制抛物线 → 「回填节点」将结论追加到节点详情；
6. **重启**：关闭再打开应用，导图与编辑结果完整保留（本地 Preferences + RDB 持久化）。

---

## 六、数据模型

```ts
interface MindNode {
  id: string
  text: string                 // ≤100 字符
  parentId: string | null
  type: 'general' | 'math' | 'physics' | 'english'
  detail: string               // 要点 / 备注
  style: { color: string; shape: 'rect' | 'round' | 'ellipse' }
  collapsed?: boolean
}

interface MindMap {
  id: string
  title: string                // ≤50 字符
  subject?: string
  book?: string
  nodes: MindNode[]
  layout: 'tree-h' | 'tree-v' | 'radial'
  theme: string
  updatedAt: number
}
```

AI 输出契约严格遵守 spec 第七节：导图 JSON（title/layout/theme/nodes）与 Agent patch（`add`/`remove`/`rename`/`move`/`restyle`/`layout`/`updateDetail`）。所有 AI 输出经 `AIResponseValidator` 校验（字段完整、根唯一、无环、枚举合法、引用存在）后才允许应用。

---

## 七、导出与导入

- **导出图片**：导图主界面工具栏 → 导出图片（基于 Canvas snapshot 保存到应用沙箱）；
- **导出 JSON**：导出符合数据模型的 JSON 文件，可重新导入还原；
- **导入 JSON**：我的导图页 → 导入 → 经校验通过后建图（格式不合法提示「导入文件格式不正确」）；
- **损坏数据**：RDB 解析失败的导图在列表标记「数据异常」，禁止进入编辑但可删除。

---

## 八、DFX 指标

| 维度 | 指标 |
|------|------|
| 性能 | 百节点首屏 ≤2s；节点编辑反馈 ≤100ms；AI 首字返回 ≤5s；单导图支持 ≥200 节点 |
| 可靠性 | 编辑实时持久化，重启不丢失；AI 失败保留上次成功结果 + 重试 + Mock 降级；离线主链路可跑通 |
| 安全 | 密钥仅经配置文件注入，禁止硬编码；本地数据不上传 |
| 可维护 | 六层分层 + AIService 统一抽象，可替换模型不影响业务层 |

---

## 九、规格文档

需求规格、技术设计、编码任务分解归档于 `.codeartsdoer/specs/knowledge_mindmap/`：

- `spec.md` —— 需求规格（8 大能力模块 + DFX 约束 + 数据约束 + AI 契约）
- `design.md` —— 技术设计（六层架构 / 4 接口族 / 关键实现设计）
- `tasks.md` —— 编码任务分解（13 组 / 50 子任务 / 98 项）