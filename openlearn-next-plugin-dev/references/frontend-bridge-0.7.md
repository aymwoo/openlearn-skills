# 前端插件：沙箱桥接模型（v0.7.7 真源，SDK 3.7.4）

> 整理自官方文档 `plugin/frontend-sandbox-capability-boundary.html`（`doc-version: sdk=3.7.4`）与
> `reference/plugin-host-shared-deps.html` 的 v0.7.0 勘误；源码见 `src/plugin-host/plugin-host.ts`
> （`mountSandboxFrame` / `activateRemotePlugin`）与 `src/plugin-host/sandbox-frame.ts`。
> 平台仓库本地路径：`~/Develop/openlearnv2/docs/plugin/frontend-sandbox-capability-boundary.md`。
>
> **这一章推翻了 0.3.x 时代「插件前端 = React 组件」的整套心智模型。**

---

## 1. 一句话结论

**远程（第三方 / ZIP）前端插件目前是一个「隐藏的、无 UI 的逻辑执行体」。**
它的可见价值来自 manifest 的**声明式贡献**（由宿主渲染），而不是插件自己的前端代码。

---

## 2. 执行环境

| 维度 | 事实 |
|------|------|
| 宿主页面 | `frontend.js` 源码由父页面 fetch 后经 postMessage 送入 iframe |
| iframe 源 | `/plugin-sandbox/frame`，`sandbox="allow-scripts"`（**无** `allow-same-origin`）→ opaque origin |
| `window` realm | 与父页面隔离 —— iframe 内 `window.HostSharedDeps` 为 `undefined` |
| 可见性 | `display: none` —— 隐藏，插件**不能渲染任何用户可见内容** |
| DOM | 无权读取或改写宿主 DOM |
| 网络 | iframe CSP 禁止 `connect`；插件不能自己发请求，只能经 RPC 桥由宿主代发 |
| 加载 | 父页面送源码 → iframe 内 `new Blob([source])` → `import(url)` |

---

## 3. 能力边界

### 3.1 能做

| 能力 | 说明 |
|------|------|
| `ctx.services.frontendApi` | `get` / `post` / `del`，经父页面代发，受方法策略与能力声明约束 |
| `ctx.services.storageService` | 按 `manifest.id` 命名空间隔离的键值存储 |
| `ctx.invokeCommand` | 经 `POST /api/plugins/:id/sandbox-command` 派发，actor 由服务端绑定 |
| `ctx.ui.showToast` | 宿主代发 toast —— **iframe 内没有 DOM，这是唯一的弹提示通道** |
| `ctx.ui.registerExtensionPoint` | **仅数据型**（见 3.3） |
| `ctx.context.get()` | 当前 `lessonId` / `classId` |

### 3.2 不能做

| 不能做 | 原因 |
|--------|------|
| 提供**自定义 React 组件** | `registerExtensionPoint(slot, { component })` 的 `component` 是函数，postMessage 无法结构化克隆 → `DataCloneError`，激活直接失败 |
| 渲染任何**可见 UI** | 沙箱 iframe 是 `display:none` 隐藏执行体，无宿主 DOM 权限 |
| 使用 `window.HostSharedDeps` | realm 隔离，iframe 内为 `undefined` |
| 让 `import React from 'react'` 生效 | 宿主转译成 `window.HostSharedDeps.React` 后求值为 `undefined` → `Cannot read properties of undefined (reading 'React')` |

> **v0.7.0 勘误（官方原话）**：用官方 CLI 构建的远程前端插件，只要用到 React/JSX 就**必然激活失败**。
> 原因：CLI 的 `cli.mjs` 把 `external: ['react','react-dom','recharts','lucide-react']` **硬编码**了，
> 而这些包在 iframe 内根本不存在。
> 官方已把「不再教用户把 remote 插件的 react 设为 external」列为已落地修复项（事项 B），
> 但 **SDK CLI 的 externals 预置仍待立项可配置**（事项 E）—— 所以今天写远程前端插件，**唯一安全解就是不用 React**。

### 3.3 数据型扩展点：远程插件唯一的可见入口通道

```ts
await ctx.ui.registerExtensionPoint('command_palette.item', {
  id: 'my-create',
  label: '我的插件：新建',
  icon: 'Puzzle',
  slotProps: {            // ← 只有数据，没有 component
    title: '新建记录',
    description: '写入一条记录',
    category: 'Plugin',
    commandType: 'my-plugin.create',   // 必须写全限定名
    payload: { lessonId: '$lessonId' },
  },
});
```

宿主用自己的 React 渲染这个条目；插件只提供数据与命令。

常见数据型槽位：`command_palette.item`（Ctrl+K 命令面板）、`quick_insert.item`、`ai.prompt.template`、
`ai.skill.provider`、以及声明式 `classroom.tool`。

---

## 4. 前端文件的唯一硬契约

```ts
export default { activate, deactivate };   // 宿主逐字检查 typeof plugin.activate === 'function'
```

不满足 → 抛 `missing activate function` → 插件进入错误态（可见入口全部带红色告警）。

- `activate(ctx)` / `deactivate()` 均为异步，可无参。
- 宿主在停用/卸载时会摘掉本插件运行期注册的扩展点并销毁 iframe，**无需手工反注册**。

### 4.1 存在性契约（`frontend.js` 缺了会怎样 —— v0.7.7 + #350 起已放宽）

`frontend.js` 只影响**隐藏前端逻辑**，不再阻断声明式贡献：

| 事实 | 位置 |
|------|------|
| `hasFrontend` 为假 → 直接置 `ACTIVE` 并 return，**不请求** `frontend.js` | `src/plugin-host/plugin-host.ts`（`activateRemotePlugin`） |
| `registerManifestContributions()` 在 `fetch` **之前**执行 | 同上（顺序断言见 `integration-facts.json` 的 `frontend-register-before-fetch`） |
| 有文件但 404 → 状态 `ERROR`，但贡献被 `preserveManifestContributions` 保留 | 同上 `catch` 分支 |
| 旧门禁 `if (!plugin.has_frontend) continue;` 已从 `useClassroomSlice.ts` 移除 | `grep -c` 应为 0 |
| CLI 只在存在 `src/frontend.tsx` 时产出 `dist/frontend.js` | `packages/plugin-sdk/cli.mjs` |

**现在什么情况才必须有 `frontend.js`**：插件要注册**自己的命令**（`invokeCommand` 打到自家 command）、
定时任务、或订阅宿主 store。纯 `view` / 纯声明式插件可以没有。

> **⚠ 已失效的旧结论**：本节曾写「没有 `frontend.js` → 所有 `contributes` 一个都不注册，
> 表现为安装成功、状态 active、入口全不出现、日志无 404」。该因果在 #350 之后**不再成立**。
> 现在「入口全消失」应先查 DB manifest 里的 `view` 是否被 strip（见 §5.5），而不是先怀疑 `frontend.js`。

若确实需要隐藏前端，最小占位入口（不要写任何 `import`）：

```ts
// src/frontend.tsx
export default { async activate() {}, async deactivate() {} };
```

打包自检：`unzip -l dist/*.zip | grep -q frontend.js`（需要时）。

### 4.2 槽位布局契约（`student.classroom.overlay` 会挤掉白板）

槽位按**容器语义**分四类（官方定义：平台 `docs/reference/plugin-ui-extension-slots.md` §1.1.1
的 `layoutVariant`）。第三方 `view` 用错类会**破坏宿主布局**，而不只是样式难看：

| `layoutVariant` | 槽位（示例） | 插件视图该怎么写 |
|------|------|----------|
| `Panel` 页面级 | `teacher.tab` / `teacher.panel` / `admin.tab` | 铺满容器（`w-full h-full` + `flex flex-col min-h-0`） |
| `WhiteboardWidget` 白板卡片 | `teacher.dashboard.widget` / `student.view` / `whiteboard.canvas.widget` | 尺寸由卡片图元与拖拽决定，**不要写死铺满**，要适配缩放 |
| `FloatingOverlay` 视口浮层 | `student.classroom.overlay` / `stage.display.overlay` / `student.quick_actions.fab` | **必须 `position: fixed`**，严禁 `w-full`/`h-full`/`flex-1` |
| `ActionItem` 行内 | `classroom.topbar.action` / `header.action` / `course.card.badge` | 紧凑内联（`h-8 px-2 flex items-center`） |

> `student.view` 不是页面级：它在学生工作台作为 widget 渲染（`StudentPluginWidgets`），
> 同时是白板卡片的学生侧槽位（`InteractiveWhiteboard` 按角色在 `teacher.dashboard.widget` /
> `student.view` 之间二选一）。给它写满屏页面会出问题。

**踩坑实录（平台 0.7.7 早期构建）**：`App.tsx` 根容器是 `flex h-screen`（横向 flex），
`<ClassroomOverlays />` 与主内容区（`flex-1` 的白板）是**同级 flex item**。
`PluginSandboxIframeView` 当时只提供页面级容器（`relative w-full h-full`），于是浮层视图成为
flex item 并占满整行宽 → `flex-1` 的主内容被压成 0 宽。

现象：**给 `student.classroom.overlay` 加 `view` 后，课堂白板整块消失**（插件面板正常显示，
所以很容易误判成「白板插件坏了」）。

- 平台侧已修（v0.7.7 / commit `6e00ca3`，官方文档已把这条写成 `FloatingOverlay` 铁律）：
  `PluginSandboxIframeView` 支持 `variant: 'panel' | 'floating'`，渲染器按 `FLOATING_VIEW_SLOTS`
  判定；`floating` 用 `fixed` 定位。
- 插件侧仍需自己守规矩：`bridge.ui.resize()` 只传 `height`，宿主也只写 `minHeight`，
  **改不了宽度与定位** —— 视图自己写死 `w-full` 仍会出问题。
- 若目标平台是更早的构建（无 `variant`），改用 `student.lesson.tool`（课堂工具按钮）而非浮层槽位。
- 自查信号：白板/主内容区突然消失，而插件自己的面板显示正常 → 先怀疑槽位布局，不要查白板。

---

## 5. 可见 UI 该怎么给（决策树）

```
插件需要自定义 React UI？
├─ 是，且「文件在 packages/plugins 内置目录 或 id 在 OPENLEARN_TRUSTED_INLINE_PLUGINS」
│   （**id 前缀不构成信任**，manifest 自述 executionMode 也不作数）
│   └─ 可以用 inline 执行 + 命令式 registerExtensionPoint({ component })（宿主父 realm 内执行）
└─ 否（第三方 / 社区插件）
    └─ 走「声明式」路线：
       ⓪ contributes["teacher.tab"|"teacher.panel"|...].view = "storage/xxx.html"
          —— 自带 HTML 页面，宿主用严格沙箱 iframe 挂载（v0.7.6+，见 §5.5）
       ① manifest.contributes / manifest.classroomTools —— 宿主渲染，插件提供数据
       ② 后端 commandBus + actionRegistry —— 宿主代发，插件提供行为
       ③ ctx.ui.showToast —— 宿主代发提示
```

> 官方产品方向（v0.7.0 定稿）：远程插件的可见 UI 走**声明式 slot DSL** —— manifest 描述 UI 结构与数据 schema，
> 宿主用自己的 React 渲染；插件只提供数据与命令，不提供组件。
> **v0.7.6 起补上了 `view`（可视沙箱 HTML）**，第三方插件终于能做真正自定义的界面（网格、图表、表单），
> 而不再受限于宿主渲染的固定插槽形态。实测细节与三个必踩的坑见 §5.5。

---

## 5.5 声明式可视沙箱视图（`view`）—— 第三方自定义 UI 的唯一可行通道

**版本门槛**：平台 v0.7.6+（`sdk 3.7.x`）。低于此版本没有该字段，声明了也只会被静默忽略。

> ⚠️ **两个必踩前提**
> 1. **`src/frontend.tsx` 从 v0.7.7 + #350 起不再是必需**：贡献注册已前移到 fetch 之前，
>    无前端产物的纯 `view` 插件会直接置 `ACTIVE`。只有要用**插件自身命令**时才需要它
>    （空导出 `{ activate, deactivate }` 即可）。历史坑与现状见 §4.1。
> 2. **安装时 schema 决定落库**：`view` 在 v0.7.7 才补进 `teacher.tab`/`teacher.panel` 的 schema。
>    在旧版本安装过的插件，DB 里的 manifest 已被 strip；升级平台不会回填，必须重装。
>    详见 `references/platform-change-watchlist.md` §7.1 / §7.2。

### 链路

```
manifest.json
  contributes["teacher.tab"][0] = { id, label, icon, view: "storage/dashboard.html" }
        ↓ 宿主 registerManifestContributions 注册（view 进 entry 与 slotProps）
PluginSandboxIframeView  <iframe src="/plugins/{pluginId}/storage/dashboard.html"
                                 sandbox="allow-scripts allow-forms allow-downloads">   ← 无 allow-same-origin
        ↓ HTML 里 <script src="/plugin-sandbox/view-bridge.js"> 注入 window.OpenLearnPluginBridge
bridge.api.get/post  →  宿主父页面同源 fetch  →  /api/plugins/{id}/*  →  插件 ctx.http 处理器
```

宿主渲染优先级：`React 真实组件 ≻ DOM render 函数 ≻ 声明式 view ≻ 占位空态`。
所以第三方插件给 `view` 时，宿主那一侧一定能走到 iframe 分支。

### 三个必踩的坑（都实测过）

| 坑 | 现象 | 处理 |
|---|---|---|
| **zod 把 `view` 剥掉** | 面板空白、日志无报错。`contributes["teacher.tab"]` / `["teacher.panel"]` / `["student.view"]` 的条目 schema 没有 `.passthrough()`，zod 默认 strip 未声明键 | 平台 ≥ 0.7.7 已修（补了 `view` 字段 + 回归用例）。**在自己的平台上先 `manifestSchema.parse()` 断言一次**：`parse({...}).contributes["teacher.tab"][0].view` 必须还在 |
| **view 路径必须在 `storage/` 下** | 404，面板空。安装侧只解压 ZIP 里 `storage/**` 的条目（`install.ts → extractZipEntries`），其它位置即使入包也不会落盘 | 页面放 `storage/dashboard.html`，`view` 写 `"storage/dashboard.html"`。`student.classroom.overlay` 等 `frontendSlotEntrySchema` 槽位同样是 `.passthrough()`，规则一致 |
| **官方 CLI `pack` 不打静态文件** | zip 里只有 `index.js` / `manifest.json` / `frontend.js` | 自写打包脚本（`jszip`）：`index.js` + `manifest.json` + 递归 `storage/**`；并在打包期断言「每个 `view` 都以 `storage/` 开头且文件真实存在」（平台对缺失的 view 只会 404，作者拿不到任何报错） |

### 桥接 API 面（`window.OpenLearnPluginBridge`）

| 成员 | 说明 |
|---|---|
| `onInit(cb)` / `onContextUpdate(cb)` / `getContext()` | 上下文 `{ pluginId, slot, lessonId, classId, studentId, studentName, lang, theme }` —— `studentId` / `studentName` 只有学生侧槽位有值 |
| `api.get(path)` / `api.post(path, body)` / `api.del(path)` | 由宿主父页面代发，带 session cookie；相对路径拼成 `/api/plugins/{pluginId}/{path}` |
| `invokeCommand(type, payload)` | 走宿主的 `/sandbox-command`（见下方身份陷阱） |
| `ui.toast(msg, type)` / `ui.resize(height)` | iframe 自撑高度必须调 `resize`，否则被裁切 |
| `storage.get/set/delete` | 宿主 localStorage 命名空间化（`ol_pv_{pluginId}_*`）；iframe 自身无 `allow-same-origin`，直接访问 localStorage 会抛错 |

> ⚠️ **`lessonId` / `classId` 有两条来源，别一概而论**
> `PluginSandboxIframeView` 取的是 `propLessonId !== undefined ? propLessonId : storeLessonId`
> —— **显式 slotProps 优先**，缺省才退回教师侧 store（`selectedLesson` / `liveClassSelectedClassId`）。
> - 页面级槽位（`teacher.tab` / `student.view` …）走通用循环，注入的正是那两个教师侧选择态；
> - `student.classroom.overlay` 由 `StudentInteractiveOverlay` 显式传
>   `slotProps={{ studentId, studentName, lessonId, classId }}`，**就是学生当前课堂**，可以直接信。
>
> ❌ **不要再用 `classroom_sessions` 兜底**：它在 SQL 黑名单里
> （`docs/agent/contracts/forbidden-tables.json`），process 模式的 DB 垫片同样过
> `assertDatabaseAccessAllowed`，直查必被拒；而 `catch` 一吃掉就只剩「还没进入课堂」这种
> 无从排查的表现。平台也没有「查当前进行中课堂」的命令，缺参数时**明确拒绝**（409 / `active:false`），
> 不要猜一个课堂出来。
>
> 学生身份：`req.actor.userId` 在 `server/middleware/auth.ts` 里兜底成 `session.studentId`
> （通常即 `students.id`），但**不保证**——学生用学号登录时它就是学号。
> 稳妥做法是按名册先比 `id`、再比 `student_number`（并优先用注入的 `studentId`）。

> ⚠️ **返回形态不对称（最容易写错的一处）**
> - `api.get/post/del` → **网关裸响应体**。网关是 `res.status(status).send(response.body)`，
>   桥接层 `reply(true, json)` 原样交回，不拆 `{success, result}`。
>   所以 `const r = await api.get('state'); r.status` 是对的，`r.result.xxx` **恒为 undefined**。
> - `invokeCommand` → `/sandbox-command` 信封里的 `json.result`，**已拆一层**。
>   同一个页面混用两种调用时，一定按各自形态取值。
> - L0 `VIEW_API_RESULT_UNWRAP` 会抓 `api.*` 后接 `.result` 的写法。

> ⚠️ **方法策略不对称（决定要不要申请能力）**
> - view 页面的 `api.*` 由宿主**父页面**同源 fetch 代发，**不经过** `checkMethodPolicy`：
>   第三方 process 插件无需 `api:write` / `api:admin` 就能写（教师端编辑页可以放心做）。
> - 隐藏前端（`frontend.tsx` 的 `ctx.services.frontendApi`）**会**过 `checkMethodPolicy`：
>   普通写需 `api:write`；高危路径 / 不可逆 / 实体删除需 `api:admin`。需要写数据时，
>   把入口放到 view 页面，而不是塞进隐藏前端。
> - 两者都受同一套 `manifest.api.routes`（方法 + roles + 限流）约束。

CSP 对 `.html` 是宽松的（`script-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https:`），
单文件内联 `<style>` / `<script>` 与 `Blob` 下载均可用。

### ⚠️ 身份陷阱：`invokeCommand` 拿不到登录用户

宿主 `/api/plugins/:id/sandbox-command` 构造命令时用的是 `pluginActorIdFor(manifestId, pluginId)`
—— **插件自己的 actor**。命令处理器里 `command.actorId` 恒为插件，`userId` / `role` 都没有。

因此：
- **身份敏感的业务**（学生上报、教师审批、个人数据）必须走 `bridge.api.get/post` → `ctx.http` 路由，
  那里 `req.actor = { actorId, userId, username, role, permissions }` 才是真实登录身份；
- `invokeCommand` 只适合**无身份动作**（拉字典、触发无状态计算），或作为排障探针。

### ⚠️ 限流陷阱：机房 / 校园网同出口 IP

网关限流键是 `clientIp:pluginId:method:path`。机房 40 台机器共用一个 NAT 出口，
5 秒轮询 = 12 次/分钟/人 × 40 = **480 次/分钟**，直接打爆默认的 120/分钟。

```json
"api": { "routes": [
  { "method": "GET", "path": "/board", "roles": ["teacher", "administrator"],
    "rateLimit": { "windowMs": 60000, "max": 1200 } }
] }
```

`roles` 由网关强制（`administrator` 恒放行），未声明的路由只要登录即可访问。
声明 `api.routes` 时**路由 path 必须与 `ctx.http` 注册的 path 一致**，否则规则匹配不上、退回默认限流。

### 自检清单（`view` 路线）

- [ ] `manifestSchema.parse()` 后 `contributes[*][0].view` 仍然存在
- [ ] `view` 全部以 `storage/` 开头，且对应文件在 zip 里
- [ ] HTML 引用了 `/plugin-sandbox/view-bridge.js`
- [ ] 页面在桥接未就绪时有等待/超时提示（脚本是外部资源，可能被网络策略挡住）
- [ ] 页面调 `ui.resize()` 上报高度
- [ ] 身份敏感请求走 `api.*` 而非 `invokeCommand`
- [ ] `manifest.api.routes` 为该端点声明了够用的 `rateLimit`
- [ ] 内联脚本做过语法检查（无构建步骤，语法错 = 空白面板）

---

## 6. HostSharedDeps 白名单（仅对 inline / 宿主父 realm 有效）

| 场景 | 口径 |
|------|------|
| 宿主共享（**仅 inline / 宿主父 realm 有效**） | `react` `react-dom` `react-dom/client` `react/jsx-runtime` `recharts` `lucide-react` |
| **远程（process 沙箱）插件前端** | `window.HostSharedDeps` 为 `undefined` —— **不得依赖 React**，官方 CLI 构建的远程前端插件用 React/JSX 必然激活失败 |
| 必须自行打包（**仅 inline 插件有意义**） | `socket.io-client` `zustand` `motion` `react-konva`/`konva` `react-markdown` `exceljs`（**不是 xlsx**）`jspdf` `jspdf-autotable` `uuid` |
| `ctx.require()` 白名单（v0.7.x） | `recharts` `react-markdown` `jspdf` `jspdf-autotable` `exceljs`（需自行安装到 package.json）`lucide-react` `uuid` |

> ⚠️ 远程插件前端 **连 socket 都用不了**（iframe CSP `connect-src 'none'`），
> 所以 `socket.io-client` 这一行只对 **inline 内建插件**成立；远程插件的同步方式见 §7。

---

## 7. 实时同步的真实通道（重要）

**远程（process 沙箱）插件的 iframe 内没有任何网络能力，且没有事件推送通道。**

| 证据 | 位置 | 事实 |
|------|------|------|
| iframe 的 CSP | `server.ts`（`/plugin-sandbox/frame` 路由） | `default-src 'none'; script-src 'unsafe-inline' blob:; **connect-src 'none'**; style-src 'none'; img-src 'none'` |
| 桥接能力清单 | `server/utils/plugin-sandbox-frame.ts` | **10 个 op**：`api.get/post/del`、`storage.get/set/delete`、`ui.register`、`ui.toast`、`command.invoke`、`context.get`（真值源：平台 `docs/agent/contracts/bridge-ops.json` 的 `frame_ops`。**view 通道是另一套 8 个**，没有 `ui.register` 与 `context.get`） |
| 宿主→iframe 消息 | `src/plugin-host/plugin-host.ts` | 只有 `load` / `reply` / `deactivate` 三种 —— **无事件推送** |

**推论**：

- ❌ iframe 内 `fetch` 被 CSP 直接禁掉（`connect-src 'none'`）—— 连宿主自己的 API 都连不上；
- ❌ 自带 `socket.io-client` 也连不上（同样被 CSP 拦）；
- ❌ 宿主**不会**把 EventBus 事件主动推给 iframe；
- ✅ **唯一可行的同步方式是轮询**：`ctx.invokeCommand(type, payload)` 或 `ctx.services.frontendApi.get(path)`
  —— 两者都由宿主代发 HTTP，iframe 不发请求。

**因此，远程插件的「实时」是这样实现的**：

| 需求 | 做法 |
|------|------|
| 读取最新状态 | 定时 `ctx.invokeCommand(...)` 拉取（间隔与频率自行权衡） |
| 用户操作 | `ctx.invokeCommand(...)` 提交给后端，后端写库 / 发 EventBus 事件 |
| 给用户反馈 | `ctx.ui.showToast(...)`（宿主代发，唯一可用的弹提示通道） |
| 让别人看到 | 后端 `eventBus.publish(...)` —— 宿主侧消费者（其他插件 / 平台自身）能收到，但**推不回 iframe** |
| 可见界面 | 只能靠 manifest 声明式贡献（宿主渲染）与课堂事件流 |

> 若你的插件确实需要**双向实时**（例如课堂抢答），当前只有两条路：
> ① 把交互做成**宿主渲染**的声明式贡献 + 后端命令（用户点按钮 → 后端处理 → 宿主侧刷新）；
> ② 作为**内建插件**（`@openlearn/` 前缀且在 `OPENLEARN_TRUSTED_INLINE_PLUGINS` 白名单）跑在宿主 realm 里，
>    此时 socket 与 DOM 都可用（但那已不是「第三方插件」了）。

---

## 8. 写远程前端插件的自检清单

- [ ] `frontend.tsx` 里**没有** `import React` / `import ReactDOM` / 任何 JSX
- [ ] `frontend.tsx` 里**没有** `document.` / `window.` / `fetch(`（用 `ctx.services.frontendApi`）
- [ ] `default export { activate, deactivate }`，`activate` 是函数
- [ ] 可见入口来自 manifest 声明式贡献，不是自定义组件
- [ ] `ctx.invokeCommand` 的 commandType 写**全限定名**（`{{pluginId}}.xxx`）
- [ ] 可见提示走 `ctx.ui.showToast`

---

## 9. 上游一致性（2026-10-28 核对，此前的不一致已消除）

| 位置 | 脚手架模板 | SDK 版本 |
|------|-----------|---------|
| npm 发布版 `@openlearn/plugin-sdk@3.7.4`（latest） | **桥接**（无 React）✅ 与本文一致 | 3.7.4 |
| 平台仓库 `main`（平台 0.7.7 / HEAD 2026-10-28） | **桥接**（无 React）✅ 与 npm 逐字节一致 | 3.7.4 |

- 两处源码 `diff -rq` 无输出，说明仓库 `main` 已追平 npm 发布版；此前「仓库仍是 React 模板」的勘误已修复。
- **判定顺序不变**：再次出现分歧时，以 **npm 发布版**为准（`npx @openlearn/plugin-sdk init` 拿到的就是发布版模板）。
- 平台仓库其他分支（如 `docs/*`）可能领先于 `main`，其中往往包含最新的一次性勘误与文档拆分。
- 3.7.2 起 CLI 会在构建期拦截 `frontend.js` 的裸模块说明符（见 SKILL.md「破坏性变化」）。

---

## 来源

- 官方文档：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/frontend-sandbox-capability-boundary.html
- 共享依赖：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-host-shared-deps.html
- 槽位 Props：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-ui-extension-slots.html
