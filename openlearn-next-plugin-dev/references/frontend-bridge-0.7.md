# 前端插件：沙箱桥接模型（v0.7.4 真源）

> 整理自官方文档 `plugin/frontend-sandbox-capability-boundary.html`（`doc-version: sdk=3.7.1`）与
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

---

## 5. 可见 UI 该怎么给（决策树）

```
插件需要自定义 React UI？
├─ 是，且是「内建插件」（manifest.id 以 @openlearn/ 开头、被列入 OPENLEARN_TRUSTED_INLINE_PLUGINS）
│   └─ 可以用 inline 执行 + 命令式 registerExtensionPoint({ component })（宿主父 realm 内执行）
└─ 否（第三方 / 社区插件）
    └─ 走「声明式」路线：
       ① manifest.contributes / manifest.classroomTools —— 宿主渲染，插件提供数据
       ② 后端 commandBus + actionRegistry —— 宿主代发，插件提供行为
       ③ ctx.ui.showToast —— 宿主代发提示
```

> 官方产品方向（v0.7.0 定稿）：远程插件的可见 UI 走**声明式 slot DSL** —— manifest 描述 UI 结构与数据 schema，
> 宿主用自己的 React 渲染；插件只提供数据与命令，不提供组件。
> 插件作者体验更好（不需要理解 React 实例 / Context / Portal），也与沙箱安全目标天然兼容。

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
| 桥接能力清单 | `server/utils/plugin-sandbox-frame.ts` | 只有 9 个 op：`api.get/post/del`、`storage.get/set/delete`、`ui.register`、`ui.toast`、`command.invoke`、`context.get` |
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

## 9. 上游不一致提醒（2026-10-27 实测）

| 位置 | 脚手架模板 | SDK 版本 |
|------|-----------|---------|
| npm 发布版 `@openlearn/plugin-sdk@3.7.1` | **桥接**（无 React）✅ 与本文一致 | 3.7.1 |
| 平台仓库 `origin/main`（平台 0.7.4） | **仍是旧的 React 模板** ⚠️ | 源码 3.7.0 |

- 插件作者应用 **npm 发布版**：`npx @openlearn/plugin-sdk init` 拿到的就是桥接模板。
- 平台仓库 `main` 分支的模板可能**滞后于已发布版本**；不要以它为准来判断「官方怎么写」。
- 平台仓库其他分支（如 `docs/*`）可能领先于 `main`，其中往往包含最新的一次性勘误与文档拆分。

---

## 来源

- 官方文档：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/frontend-sandbox-capability-boundary.html
- 共享依赖：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-host-shared-deps.html
- 槽位 Props：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-ui-extension-slots.html
