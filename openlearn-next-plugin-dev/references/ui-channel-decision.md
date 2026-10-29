# UI 通道决策：执行模式 / 槽位 / 白板挂件

> 适用平台 v0.7.7 / SDK 3.7.4（2026-10-28 核对）。
> 本文件解决一类高频事故：**教师点了按钮，学生端什么也看不到**。根因往往不在某一行代码，
> 而是「UI 意图」与「执行模式 + 槽位 + 数据写入」三者没对齐，且平台不会报错，只会静默不渲染。
>
> 事实来源：`packages/core/plugin-host/execution-policy.ts`、`src/plugin-host/plugin-host.ts`、
> `src/features/whiteboard/InteractiveWhiteboard.tsx`、`packages/core/esm-loader/manifest-schema.ts`、
> `docs/tutorials/plugin-development-tutorial.md` §2.2 / §2.7、`packages/plugin-sdk/cli.mjs`（裸说明符守卫）。

---

## 0. 三条铁律（先记住，再谈方案）

1. **第三方 ZIP 插件默认且强制 `process`**：没有自定义 React UI、没有 DOM、iframe 是 `display:none` 的隐藏执行体。
2. **`manifest.id` 前缀不构成任何信任**。`@openlearn/`、`@ext/`、`lianyun-*` 都一样。
   进程内身份只有两个来源：文件真实位于 `packages/plugins`，或管理员把它写进 `OPENLEARN_TRUSTED_INLINE_PLUGINS`。
3. **manifest 自述的 `executionMode` 不参与判定**。实际模式由服务端 `resolvePluginExecutionMode()` 计算后写进
   `plugins.execution_mode` 列，前端只看这一列。因此插件无法「自己声明成 inline」拿到 UI。
4. **process 不等于没有自定义 UI**。v0.7.6 起有「双轨制 UI」：manifest 里给槽位条目写
   `view: "storage/xxx.html"`，宿主用**不透明源 iframe** 渲染你的 HTML 页面，并注入 `OpenLearnPluginBridge`
   （toast / resize / invokeCommand / api / storage）。自定义界面走这条，不需要白名单。

```ts
// 判定逻辑（execution-policy.ts）
if (isInsideBuiltinPluginsDir(sourcePath)) → 信任
else if (isInTrustedInlineAllowlist(manifestId)) → 信任   // 支持 `*` 与 `前缀*`
else if (requested === 'process') → process（不改写）
else → process + coerced=true（静默降档）
```

---

## 1. 先判定：这个插件到底能不能有自定义 UI

```
需求里出现「按钮/面板/看板/浮层/拖拽卡片」？
├─ 否 → server-only，声明式贡献即可，结束
└─ 是 → 谁看？
   ├─ 教师（管理页/白板卡片/工具架） → 声明式贡献 + 服务端命令（process 可行）
   └─ 学生（全屏页/浮层/白板挂件） → 需要「宿主渲染的 UI」
      ├─ 只需列表/按钮/文本/跳转 → manifest 声明式槽位（process 可行）
      └─ 需要自定义界面
         ├─ 能用 HTML/CSS/原生 JS 写（不需要宿主 React 组件） → **沙箱 HTML 视图（view）**，process 可行，无需白名单（见 §4.5）
         └─ 必须是 React 组件 / 要进白板画布卡片 → 必须 inline
            ├─ 能改宿主 .env 并重启、且接受该插件同进程运行？ → 走白名单（见 §3）
            └─ 不能 → 放弃，改成：view 页面 + 命令 + 轮询
```

**必须写进设计契约**（`plugin.contract.json`，见 §6），不要只留在对话里——它会被 L0/L2 测试强制校验。

| 你能拿到的 UI 能力 | process / worker | inline（白名单或内置） |
|---|---|---|
| manifest 声明式槽位（宿主渲染） | ✅ | ✅ |
| 远程前端桥接（数据/命令/轮询/toast） | ✅ | ✅ |
| `registerExtensionPoint({ component })` | ❌ 函数无法跨 `postMessage`（`DataCloneError` / 静默丢） | ✅ |
| `import React` 或 `window.HostSharedDeps` | ❌ 沙箱内不存在 | ⚠️ 仅 `HostSharedDeps`，且**不能写 `import`**（见 §4） |
| **沙箱 HTML 视图（`view`）** | ✅（自定义 HTML/CSS/JS，iframe 内） | ✅ |
| 白板自定义挂件（`type:'plugin'` 卡片） | ✅（配置 view 经 PluginSandboxIframeView 渲染） | ✅（component 或 view 均可） |

---

## 2. 「学生端能看到」的 6 条完整链路（缺一条就什么都看不到）

| # | 环节 | 常见漏项与高频大坑 |
|---|------|------------------|
| 1 | **manifest 声明容器槽位** | 只声明了 `teacher.tab`，学生侧根本没有任何渲染位；白板挂件需成对配置 `teacher.dashboard.widget` 与 `student.view` |
| 2 | **服务端把数据写进共享存储** | handler 只 `return { opened: true }`，没写白板元素/DB/事件 → 学生端无数据可渲染。<br>⚠️ **禁忌**：子进程严禁直写 SQL 读写 `whiteboard_elements`（会被 `sql-guard` 拦截）；必须通过 `whiteboard.draw` 命令落库 |
| 3 | **写入用对命令** | 白板挂件必须 `whiteboard.draw` + `type:'plugin'` + `data` 为 **JSON 字符串**（携带 `teacherWidgetId`、`studentWidgetId`、`title`、宽高与坐标） |
| 4 | **选的通道与模式匹配** | 自定义 React 必须 inline；process 模式支持声明式槽位与 **`view` 沙箱页面**（`storage/xxx.html`） |
| 5 | **前端组件按 id 对齐** | 白板挂件按 `teacherWidgetId` / `studentWidgetId` 精确匹配扩展点 `id`，差一个字符就是「正在加载…」 |
| 6 | **权限已授予** | `whiteboard:write` 未在 `capabilitiesProposed` 声明或管理员未批准 → 命令被拒（403） |

### 2.1 课堂互动工具（`manifest.classroomTools`）的标准投射模式

当教师在白板工具栏点击 🧩「互动工具」下的条目时，宿主前端会将配置的 payload 发送至 `/api/commands`：

- **模式 A：声明式白板投射（强烈推荐，零权限风险）**
  直接在 manifest 中将 `commandType` 声明为 `whiteboard.draw`。宿主前端代发该内核命令，由平台内核（`builtin.ts`）直接写入白板元素并广播 `whiteboard.element_drawn`：
  ```json
  "classroomTools": [
    {
      "id": "tool_sticky_notes",
      "name": "课堂便签",
      "icon": "StickyNote",
      "commandType": "whiteboard.draw",
      "payload": {
        "lessonId": "$lessonId",
        "type": "plugin",
        "data": "{\"pluginId\":\"@openlearn-ext/my-tool\",\"teacherWidgetId\":\"my_tool_widget\",\"studentWidgetId\":\"my_tool_widget\",\"title\":\"课堂工具\",\"width\":640,\"height\":480,\"x\":120,\"y\":80,\"page\":0}"
      }
    }
  ]
  ```
- **模式 B：插件后端级联派发**
  若下发前必须由插件后端执行校验或前置准备，在 manifest 申请并获批 `whiteboard:write` 能力，在 handler 中调用：
  ```ts
  await ctx.services.commandBus.execute({
    id: crypto.randomUUID(),
    type: 'whiteboard.draw',
    payload: { lessonId, type: 'plugin', data: JSON.stringify({...}) }
  });
  ```
  ❌ **严禁**：在插件 handler 内执行 `rawDb.prepare("INSERT INTO whiteboard_elements ...")`，此举会被 `sql-guard` 零信任门禁拦截，导致前端提示「执行成功」但画布空无一物。

### 2.2 课堂浮层（`student.classroom.overlay`）规范

- **避免挤占主白板**：宿主对该槽位采用 `floating` 模式渲染（fixed 定位）。若插件采用 `view`，页面不得写撑满整屏的块级面板（否则在旧版宿主中会作为横向 Flex item 把白板挤没）。
- **高度联动**：浮层页面必须在展开/折叠时主动调用 `window.OpenLearnPluginBridge.ui.resize(height)`，让容器随内容伸缩，避免遮挡白板交互。
- **上下文与限流防范**：
  - 页面加载时统一做防御性降级：`const classId = ctx.classId || 'default';`，避免单课调试未排班时崩溃；
  - 状态同步务必加防抖（≥500ms）与去重，轮询建议 ≥3000ms，避免耗尽写限流池触发 HTTP 429 导致全班锁屏指令失败。

### 学生端可用的容器槽位（常用）

| 槽位 | 渲染位置 | props | 说明 |
|------|---------|-------|------|
| `student.view` | 白板内学生视角的 `type:'plugin'` 卡片 | `{ elementId, lessonId }` | **白板挂件学生侧渲染位** |
| `teacher.dashboard.widget` | 白板内教师视角的同一卡片 | `{ elementId, lessonId }` | 教师侧渲染位（与上者成对） |
| `student.fullscreen` | 学生全屏视图（考试/答题模式） | 视宿主而定 | 全屏交互 |
| `student.classroom.overlay` | 学生端课堂**浮层**（弹幕/水印/抢答悬浮球） | `{ studentId, lessonId }` | 不是白板卡片，别混用 |
| `student.lesson.tool` | 学生课中工具栏 | — | 轻量入口 |
| `student.quick_actions.item / action / fab` | 学生快捷指令 | — | 悬浮球/菜单 |

> 槽位是**封闭集合**（数量见 `slot-registry.json` 的 `count`，勿凭记忆报数）。完整清单与分组见
> `assets/test-harness/slot-registry.json`（由 `src/plugin-host/types.ts` 的 `ExtensionSlot` 联合类型生成）。
> 槽位名写错宿主不会报错，只会永远不渲染；L0 的 `SLOT_UNKNOWN` 会拦住。

---

## 3. 白名单（inline）怎么开、容易踩什么

```bash
# 宿主 .env（示例：允许本系列插件进程内运行）
OPENLEARN_TRUSTED_INLINE_PLUGINS=@ext/attendance-record,@ext/class-manager,@openlearn-ext/*,lianyun-course
```

1. **改完必须重启服务**（环境变量在启动时读取）。
2. **重新安装或切换隔离档位**：安装向导对受信 id 才显示 inline/worker 选项；已安装插件改 `.env` 后
   需要重新触发一次安装/更新（或按管理端档位重新选择），否则 DB 里的 `execution_mode` 仍是 `process`。
3. **验证实际模式**：`GET /api/plugins` 返回的 `executionMode` 必须是 `inline`；被改写时响应带 `executionModeCoerced: true`。
4. **通配符代价**：`前缀*` 会让整批插件同进程运行；`*` 等于全部信任，启动时会有显著告警。
   只在开发机或完全可控的校内环境使用。
5. **安全后果**：inline 插件与宿主同进程同上下文，能读到宿主内存与环境变量。不要用它跑不可信代码。

---

## 4. inline ZIP 插件的 React 到底怎么写

SDK CLI 3.7.2+ 有**裸说明符守卫**：`dist/frontend.js` 里任何 `from 'react'` / `require('react')` / 动态 `import('react')`
都会让构建失败。守卫的理由是「远程插件跑在 iframe」，对 inline 插件同样会拦——**它是构建期一刀切**。

因此 inline ZIP 插件（前端在宿主页面里执行）唯一可行的写法是**用宿主注入的全局对象，不写任何 import**：

```ts
// src/frontend.tsx —— 没有任何 import（import type 也会被擦除，可留）
type AnyProps = Record<string, unknown>;
const HostDeps = () => (globalThis as any).HostSharedDeps as
  | { React?: any; ReactDOM?: any; jsxRuntime?: any }
  | undefined;

let React: any;
const h = (type: any, props: any = null, ...children: any[]) => React.createElement(type, props, ...children);

function TeacherWidget(props: AnyProps) {
  const [count, setCount] = React.useState(0);   // hooks 用的是宿主那份 React，没问题
  return h('button', { onClick: () => setCount(count + 1) }, `点了 ${count} 次`);
}

export default {
  async activate(ctx: any) {
    React = HostDeps()?.React;
    if (!React) throw new Error('HostSharedDeps.React 不可用：插件没有以 inline 模式运行');
    ctx.ui.registerExtensionPoint('teacher.dashboard.widget', { id: 'my-widget', component: TeacherWidget });
    ctx.ui.registerExtensionPoint('student.view', { id: 'my-widget-student', component: StudentWidget });
  },
  async deactivate(ctx: any) {
    ctx.ui.unregisterExtensionPoint('teacher.dashboard.widget', 'my-widget');
    ctx.ui.unregisterExtensionPoint('student.view', 'my-widget-student');
  },
};
```

要点：

- **不要** `import React from 'react'`；也不要用 JSX（`jsx: react-jsx` 会生成 `react/jsx-runtime` 导入）。
  用 `React.createElement` 或上面的 `h()` 辅助函数即可；确需 JSX 就配 `"jsx": "react"` 并确保 `React` 是全局取到的那份。
- 组件的 hooks 依赖**宿主那份 React**；自己 bundle 一份 React 会导致 `Invalid hook call`。
- **中文字号 ≥ 13px**：`fontSize: 11` / `text-xs`（=12px）在教室投影和白板上不可读。
  正文与标签至少 13px；纯图标 / 装饰可在同行注明 `font-size-ok`。L0 `FONT_TOO_SMALL` 会拦。
- `HostSharedDeps` 只有 inline 才有；process 下它是 `undefined`，激活时应显式抛错而不是静默降级。

---

---

## 4.5 沙箱 HTML 视图（`view`）：process 拿到自定义 UI 的正解

这是 v0.7.6 引入的「双轨制 UI」，也是**大多数第三方插件真正该走的路**：
manifest 里声明 `view: "storage/xxx.html"`，宿主用 `sandbox="allow-scripts allow-forms allow-downloads"`
（**不透明源、无 allow-same-origin**）的 iframe 加载 `/plugins/<插件>/<view>`，并注入桥接脚本。
**不需要 inline、不需要白名单**，也不受「不能写 React」限制——因为页面里就是普通 HTML/CSS/JS。

### 4.5.1 支持 `view` 的槽位

`teacher.tab` · `teacher.panel` · `teacher.dashboard.widget` · `student.view` · `student.lesson.tool`

> 这些槽位由 `manifest-schema.ts` 显式声明 `view` 字段。
> `student.classroom.overlay` 等走 `frontendSlotEntrySchema`（passthrough），`view` 会透传并由
> `ExtensionPointRenderer` 渲染，**能用但不承诺长期契约**（L0 会给 `VIEW_SLOT_UNSUPPORTED` 警告）；正式产品优先用上表。

### 4.5.2 前置：`src/frontend.tsx` 还要不要？（v0.7.7 + #350 起按需）

`view` 页面由宿主 iframe 承载，本身不需要前端逻辑，**也不再依赖前端入口**：

- `registerManifestContributions()` 已前移到 `fetch(frontend.js)` **之前**；
  `hasFrontend=false` 的插件直接置 `ACTIVE` 且**不发请求**；
- `useClassroomSlice` 中原 `if (!plugin.has_frontend) continue;` 已移除；
- 只有要用「插件自身命令 / 定时任务 / store 订阅」时才需要 `src/frontend.tsx`；
  CLI 只有看到它才产出 `dist/frontend.js`。

所以最小入口：

```ts
// src/frontend.tsx —— 空桥接即可，不要写任何 import
export default {
  async activate() {},
  async deactivate() {},
};
```

缺它的表现（**v0.7.7 + #350 起**）：入口**照常显示**，只是插件的隐藏前端逻辑不存在
（自定义命令找不到、定时任务不跑）。L0 的 `FRONTEND_ENTRY_MISSING` 只报提醒，不再拦。
**旧结论「所有 contributes 都不出现且日志无 404」已失效** —— 那种现象现在是安装期 schema strip，
见 `references/troubleshooting.md` 的 4c 与 `platform-change-watchlist.md` §7.2。

### 4.5.3 manifest 写法

```jsonc
{
  "contributes": {
    "teacher.tab": [{ "id": "notes-admin", "label": "便签板", "icon": "StickyNote", "view": "storage/teacher.html" }],
    "student.view": [{ "id": "notes-student", "label": "便签板", "icon": "StickyNote", "view": "storage/student.html" }]
  }
}
```

规则（`sanitizeViewPath` 会校验，违规直接显示「非法的插件视图路径」）：

- 必须是**相对路径**，禁止 `://`、`//` 开头、`..`、`javascript:` / `data:` / `blob:`；
- **必须以 `storage/` 开头**：安装器（`install.ts`）只解压 `storage/**`；
  官方教程里 `"views/index.html"` 的示例对本仓库的 ZIP 插件是**错的**（装上去 404 → 空白面板）；
- 实际 URL 是 `/plugins/<插件安装 id>/<storage/...>`，文件放在插件包的 `storage/` 下；
- `.html` 响应带 `PLUGIN_VIEW_CSP`（允许内联脚本/样式与 https 资源，`frame-ancestors 'self'`）。

### 4.5.4 页面写法（桥接 API）

```html
<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8" /><title>便签板</title>
<style>body{font:13px/1.5 system-ui;margin:0;padding:12px}</style></head>
<body>
  <div id="app">加载中…</div>
  <script src="/plugin-sandbox/view-bridge.js"></script>
  <script>
    const app = document.getElementById('app');
    let ctx = null, lessonId = null;

    OpenLearnPluginBridge.onInit((c) => {
      ctx = c; lessonId = c.lessonId;          // { pluginId, slot, lessonId, classId, lang, theme }
      document.documentElement.lang = c.lang || 'zh-CN';
      render();
    });
    OpenLearnPluginBridge.onContextUpdate((c) => { ctx = { ...ctx, ...c }; lessonId = c.lessonId; render(); });

    async function render() {
      if (!lessonId) { app.textContent = '请先进入课堂'; return; }
      const { notes = [] } = await OpenLearnPluginBridge.invokeCommand('list_notes', { lessonId });
      app.innerHTML = notes.map((n) => `<div class="note">${escapeHtml(n.text)}<small>${escapeHtml(n.author)}</small></div>`).join('')
        || '<p>还没有便签</p>';
    }

    function escapeHtml(s) {
      return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    // 高度自适应（宿主据此调整容器）
    new ResizeObserver(() => OpenLearnPluginBridge.ui.resize(document.body.scrollHeight)).observe(document.body);
  </script>
</body>
</html>
```

桥接 API（`window.OpenLearnPluginBridge`）：

> 字号约束：中文正文 / 标签 ≥ **13px**（含 `font-size`、`font` 简写、行内 style 与 JS 动态设置）。
> 11/12px 在投影和白板上不可读；纯图标可加同行注释 `font-size-ok`。L0 `FONT_TOO_SMALL` 会拦。

| API | 作用 |
|-----|------|
| `onInit(cb)` / `onContextUpdate(cb)` / `getContext()` | 拿 `{ pluginId, slot, lessonId, classId, lang, theme }`，课堂切换时同步 |
| `invokeCommand(type, payload)` | 调**本插件**已注册的命令（自动加命名空间前缀） |
| `api.get/post/del(path, body)` | 走宿主代发到 `/api/plugins/<id>/<path>`（推荐，鉴权与审批一致） |
| `storage.get/set/delete(key)` | 宿主 localStorage 命名空间（`ol_pv_<pluginId>_*`） |
| `ui.toast/showToast(msg, type)` / `ui.resize(h)` | 提示与高度自适应 |

### 4.5.5 打包（必须自己补）

官方 CLI 的 `pack` **只打 `manifest.json` / `index.js` / `frontend.js`**，`storage/**` 不会进 ZIP。
不补的话：本地能预览、装到宿主后 404 → 面板空白/加载失败。最小打包脚本（放 `scripts/pack.mjs`）：

```js
import { execSync } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import JSZip from 'jszip';

execSync('npx @openlearn/plugin-sdk build', { stdio: 'inherit' });
const zipPath = readdirSync('.').find((f) => f.endsWith('.zip'));
const zip = await JSZip.loadAsync(readFileSync(zipPath));

const walk = (dir, base = '') =>
  readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p, `${base}${name}/`) : [`${base}${name}`];
  });

for (const rel of walk('storage')) zip.file(rel, readFileSync(join('storage', rel)));
writeFileSync(zipPath, await zip.generateAsync({ type: 'nodebuffer' }));
console.log(`repacked ${zipPath} with storage/**`);
```

> `jszip` 已是 `@openlearn/plugin-sdk` 的依赖，可直接 `npm i -D jszip` 显式声明。

### 4.5.6 边界与安全

- iframe **没有** `allow-same-origin`：拿不到宿主 DOM / localStorage / Cookie，只能通过桥接；
- **不要**在页面里直接 `fetch('/api/...')`：不透明源下 Cookie 不可靠，统一走 `api.*` / `invokeCommand`；
- 页面不能渲染到白板画布卡片里（那需要 `component`，见 §5）；view 是**页面/面板**级 UI；
- 天然 CSP 允许内联脚本与 https 资源，但宿主无法审计你的 JS —— 只加载自己打包的代码。

## 5. 白板挂件端到端契约（教师下发 → 学生看到）

### 5.1 数据形状（`whiteboard_elements`）

```jsonc
// whiteboard.draw 的 payload
{
  "lessonId": "lesson-123",
  "type": "plugin",
  "data": "{\"teacherWidgetId\":\"my-widget\",\"studentWidgetId\":\"my-widget-student\",\"width\":520,\"height\":420}"
}
```

- `data` 必须是 **JSON 字符串**（宿主解析后补 `page` / `segmentId` 再落库）。
- 学生视角读 `studentWidgetId`，教师视角读 `teacherWidgetId`（`InteractiveWhiteboard.tsx`）。
- 渲染器按「槽位 + 扩展点 id」精确匹配；id 缺失/不匹配时页面显示「组件 [xxx] 正在加载或未启用…」。

### 5.2 三件套 + 一次派发

```ts
// 1) manifest：教师工具架按钮
classroomTools: [{ id: 'open-board', name: '便签板', commandType: '{{commandPrefix}}.open_board' }]

// 2) ActionDescriptor（capabilityRequired 必须是 whiteboard:write）
await actionRegistry.register({
  id: '{{commandPrefix}}-open-board',
  commandType: '{{commandPrefix}}.open_board',
  description: '把便签板挂件插入当前白板（教师与学生都将看到）',
  capabilityRequired: 'whiteboard:write',
  inputSchema: { type: 'OBJECT', properties: { lessonId: { type: 'STRING' } }, required: ['lessonId'] },
});

// 3) handler：必须真的写白板，而不是只 return
await commandBus.registerHandler('{{commandPrefix}}.open_board', {
  async execute(command) {
    const { lessonId } = command.payload as { lessonId: string };
    const res = await commandBus.execute({
      id: crypto.randomUUID(),
      type: 'whiteboard.draw',
      payload: {
        lessonId,
        type: 'plugin',
        data: JSON.stringify({ teacherWidgetId: 'my-widget', studentWidgetId: 'my-widget-student', width: 520, height: 420 }),
      },
      actorId: `plugin:${manifest.id}`,
      timestamp: Date.now(),
    });
    return res; // { elementId }
  },
});
```

### 5.3 前端注册（必须 inline）

```ts
ctx.ui.registerExtensionPoint('teacher.dashboard.widget', { id: 'my-widget', component: TeacherWidget });
ctx.ui.registerExtensionPoint('student.view', { id: 'my-widget-student', component: StudentWidget });
```

`classroomTools.payload` 里可写 `$lessonId` / `$classId`，宿主点击时替换成当前课堂上下文
——这是按钮拿到 `lessonId` 的唯一通道。

---

## 6. 设计契约文件 `plugin.contract.json`

放在插件项目根目录；由 skill 在需求阶段生成，L0/L2 用它做强制校验：

```jsonc
// A. 白板挂件 + 自定义 React（需要白名单）
{
  "executionMode": "inline",
  "uiChannel": "inline-react",
  "studentVisible": true,
  "whiteboardWidget": true,
  "slots": ["teacher.dashboard.widget", "student.view"],
  "trustedInlineAllowlistEntry": "@openlearn-ext/*"
}

// B. 沙箱 HTML 页面（process 即可，推荐大多数插件）
{
  "executionMode": "process",
  "uiChannel": "sandbox-view",
  "studentVisible": true,
  "whiteboardWidget": false,
  "slots": ["teacher.tab", "student.view"],
  "viewFiles": ["storage/teacher.html", "storage/student.html"]
}
```

| 字段 | 取值 | 用途 |
|------|------|------|
| `executionMode` | `process` / `inline` | 与前端是否使用 component 必须自洽 |
| `uiChannel` | `declarative`（宿主渲染）/ `polling`（仅数据）/ `sandbox-view`（HTML 页面）/ `inline-react`（自定义组件） | 防止「说好只要数据、结果写了 React」 |
| `viewFiles` | `sandbox-view` 时必填，列出 `storage/*.html` | L0 校验文件存在、引了桥接脚本、能被打进 ZIP |
| `studentVisible` | `true` 时必须有学生侧槽位或白板挂件 | 防「只做了教师端」 |
| `whiteboardWidget` | `true` 时必须派发 `whiteboard.draw` 且注册成对 widget id | 防「只 return 内存对象」 |
| `slots` | 槽位名数组，必须 ∈ 真实注册表 | 防编造槽位 |
| `trustedInlineAllowlistEntry` | inline 且非内置时必填 | 防「以为 id 前缀能换信任」 |

---

## 7. 失败模式对照（本次事故四连）

| 现象 | 真实根因 | 正确做法 | 谁抓得住 |
|------|---------|---------|---------|
| 后端只 `return { opened: true }`，学生端无元素 | 没调 `whiteboard.draw` | handler 里派发内核命令，写 `type:'plugin'` 元素 | L2 `whiteboardWidget` 断言（检查 `commandBus.executeCalls`） |
| 只声明 `teacher.tab` | 学生端没有渲染容器 | 加 `student.view` + 成对 widget id；浮层用 `student.classroom.overlay` | L0 `STUDENT_ENTRY_MISSING` / `SLOT_UNKNOWN` |
| `frontend.tsx` 只有命令面板数据项 | 没有可渲染组件 | inline + `registerExtensionPoint({component})` | L0 `UI_MODE_MISMATCH` / `CONTRACT` |
| 被强制 `process`，React 不挂载 | 不在白名单，且 `@openlearn-ext/` 前缀不算信任 | 写 `.env` 白名单 + 重启 + 重装/切档位 + 验证 `executionMode` | L0 `INLINE_TRUST_MISSING` / `INLINE_NOT_WHITELISTED`；L3 冒烟 |
| 面板/学生页空白，或提示「非法的插件视图路径」 | ① 该用 `view` 却写了 component；② view 路径含 `..`/绝对路径；③ `storage/**` 没打进 ZIP | 改 `view` 相对路径 + 桥接脚本 + 自写打包脚本 | L0 `VIEW_PATH_UNSAFE` / `VIEW_FILE_MISSING` / `VIEW_BRIDGE_MISSING` / `VIEW_NOT_PACKED` |
| **所有贡献都不出现，日志也没有 404** | DB 里 `view` 已被安装期 schema strip（#350 后不再由缺 frontend.js 引起） | 先跑 `post-install-check.sh` 确认 strip，再**重新安装** | 人工：`SELECT manifest FROM plugins` |
| 入口都在，但插件自身命令不存在 / 定时任务没跑 | 没有 `dist/frontend.js`，隐藏前端逻辑没加载 | 需要时加空 `src/frontend.tsx`（纯 view 插件不必） | L0 `FRONTEND_ENTRY_MISSING`（提醒级） |
| DB 里 `teacher.tab` 丢了 `view`，但 overlay 还留着 | 安装时平台 schema < v0.7.7，zod strip 后落库；升级不回填 | 升到 ≥0.7.7 后**重新安装**插件 | 人工：`SELECT manifest FROM plugins` |

---

## 8. 自查命令

```bash
# 当前插件是否在宿主白名单里（读本机 .env，也可换成远端配置）
grep -n "OPENLEARN_TRUSTED_INLINE_PLUGINS" ~/Develop/openlearnv2/.env

# 确认服务端实际求值的模式（不是 manifest 自述）
curl -s -b cookie.txt http://localhost:3000/api/plugins | jq '.[] | select(.id=="@openlearn-ext/stickynotes") | {id, executionMode, executionModeCoerced}'

# 槽位是否存在
node -e "const r=require('./test-harness/slot-registry.json');console.log(r.slots.includes('student.view'))"
```
