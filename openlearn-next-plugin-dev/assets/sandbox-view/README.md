# sandbox-view 模板：process 模式下的自定义界面（推荐）

用 manifest 的 `view` 字段把 HTML 页面挂到宿主槽位上，宿主用**不透明源沙箱 iframe** 渲染，并注入
`OpenLearnPluginBridge`。**不需要 inline、不需要白名单**，也不是 React。

适用：教师管理页、学生看板、课堂浮层页面等「页面级」自定义 UI。
不适用：白板画布内的 `type:'plugin'` 卡片（那需要 React 组件 → `inline-react` 模板）。

## 1. 链路

```
manifest.contributes['student.view'] = [{ id, label, view: 'storage/student.html' }]
        ↓ 宿主注册声明式贡献（registerManifestContributions 保留 view）
ExtensionPointRenderer 检测到 ext.view
        ↓
PluginSandboxIframeView → iframe src=/plugins/<插件>/storage/student.html
        ↓ sandbox="allow-scripts allow-forms allow-downloads"（无 allow-same-origin）
页面 <script src="/plugin-sandbox/view-bridge.js">
        ↓ window.OpenLearnPluginBridge
bridge.onInit(ctx) / invokeCommand(type, payload) / api.get|post|del / storage.* / ui.toast|resize
```

## 2. 关键约束

| 约束 | 说明 |
|------|------|
| `view` 必须是相对路径 | 禁 `..`、绝对路径、`://`；宿主 `sanitizeViewPath` 会拒绝并显示「非法的插件视图路径」 |
| 槽位 | `teacher.tab` / `teacher.panel` / `teacher.dashboard.widget` / `student.view` / `student.lesson.tool` |
| 打包 | CLI **不打** `storage/**` → 用 `npm run pack`（本模板已带 `scripts/pack.mjs`） |
| 通信 | 无推送，统一 `invokeCommand` + 轮询；不要直接 `fetch('/api/...')`（不透明源 + Cookie 不可靠） |
| React | 页面里可以自带任何前端库（含打包进 bundle 的 React），但**不是**宿主 React，也拿不到宿主组件树 |
| 高度 | 页面要调 `bridge.ui.resize(document.body.scrollHeight)`，否则容器高度可能为 0 |

## 3. 目录

| 文件 | 作用 |
|------|------|
| `plugin.contract.json` | `executionMode: process` + `uiChannel: sandbox-view` + `viewFiles`（L0 依此校验） |
| `src/index.ts` | 后端命令：`add_note` / `list_notes`（页面通过桥接调用） |
| `storage/teacher.html` | 教师页（`teacher.tab`），带输入 + 列表 + 轮询 |
| `storage/student.html` | 学生页（`student.view`），同上 |
| `scripts/pack.mjs` | 把 `storage/**` 补进 ZIP |

## 4. 开发与验证

```bash
npm i
npm run pack                 # build + 补 storage/**
node test-harness/static-check.mjs .        # L0：view 路径 / 文件 / 桥接脚本 / 槽位 / 打包提示
npx vitest run --config test-harness/vitest.config.ts   # L1/L2：命令三件套 + 执行冒烟
```

L3 真实宿主：

1. 上传 ZIP → 安装 → 激活（process 模式即可）
2. 教师端出现 Tab → 打开后页面加载（Network 里 `storage/teacher.html` 200、`view-bridge.js` 200）
3. 学生端对应槽位出现页面 → 教师写一条 → 学生 3 秒内轮询到
4. 切换课节 → `onContextUpdate` 触发，列表跟着切换
5. 停用再激活 → 不重复渲染、无 `HANDLER_ALREADY_EXISTS`

## 5. 排错

| 现象 | 先查 |
|------|------|
| 面板空白 / 「正在加载…」 | `storage/**` 是否进了 ZIP；`view` 路径是否相对且无 `..` |
| 页面报 `OpenLearnPluginBridge is undefined` | 是否漏了 `<script src="/plugin-sandbox/view-bridge.js">` |
| 命令调用 403 / 失败 | `commandType` 是否注册了 handler + ActionDescriptor；权限是否已声明并批准 |
| 高度塌陷 | 是否调用 `bridge.ui.resize(...)` |
| 学生端看不到 | `student.view` 是否声明了 `view`；宿主学生端是否启用了该插件（仪表盘/课堂视图） |
