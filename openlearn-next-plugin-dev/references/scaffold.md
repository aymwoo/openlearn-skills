[缓存自 OpenLearnV2 官方文档 v0.3.16 多页汇编，见文末来源列表]

# OpenLearn Plugin 脚手架与开发速查（v0.3.16 汇编版）

> 说明：官方文档自 0.1.x 重构后，旧的 `/scaffold.html` 页面已 404。`sdk/scaffold-cli.html` 现在只保留 init / build 两条命令，本文件由 SDK / Test Kit / 示例 / 数据库 API / Manifest 规范等多页**汇编**而成。
> 版本口径（重要）：`@openlearn/plugin-sdk` 的版本**随平台 release 同步，发布流程统一重写，官方明确要求勿在文档中写死**。因此下文引用到的具体 SDK 版本号仅代表「该特性引入时的文档口径」，请以实际安装版本为准。

---

## 快速开始

```bash
# 1. 脚手架创建（交互式；文档同时给出 --name 形式）
npx @openlearn/plugin-sdk init
npx @openlearn/plugin-sdk init --name my-plugin

# 2. 安装依赖
cd my-plugin && npm install        # 文档测试章节示例用 pnpm add -D

# 3. 构建 ZIP 分发包
npx @openlearn/plugin-sdk build
# 产物：my-plugin.zip，上传至插件中心即可安装
```

- 官方 CLI 页面（`sdk/scaffold-cli.html`）**只有**上面两条命令，不再列出 `--template / --description / --author` 等参数。这些参数是否仍受支持，**文档未明确**（旧缓存里记载的参数请视为待验证）。
- 支持三种模板：`server-only`、`full-stack`、`frontend-only`（见下）。
- 构建脚本：脚手架模板的 `package.json` 内为 `"build": "openlearn-plugin-sdk build"`，即 npm 脚本名也是 `openlearn-plugin-sdk`（CLI 二进制）。两者等价。

### 三种模板

| 模板类型 | 运行环境 | 生成的核心文件 |
| --- | --- | --- |
| `server-only` | Node.js Worker Thread | `package.json`、`tsconfig.json`、`src/index.ts` |
| `full-stack` | Worker Thread + 前端微前端 | `package.json`、`tsconfig.json`、`src/index.ts`、`src/frontend.tsx` |
| `frontend-only` | 前端 React 渲染层 | `package.json`、`tsconfig.json`、`src/index.ts`、`src/frontend.tsx` |

> 前端组件按 React 19 语义编写（宿主实际运行 React 19.2.7，见下文「package.json 与 tsconfig 要点」）。

---

## 生成的项目结构

```
my-plugin/
├── manifest.json        # 插件清单，宿主机通过 Zod Schema 强制运行时校验
├── package.json         # 依赖 @openlearn/plugin-sdk；build 脚本指向 openlearn-plugin-sdk
├── tsconfig.json
├── src/
│   ├── index.ts         # 服务端入口：export default { manifest, activate, deactivate? }
│   └── frontend.tsx     # 前端入口（full-stack / frontend-only）
└── dist/                # 构建产物
    ├── index.js
    ├── frontend.js      # 前端插件存在时
    └── my-plugin.zip
```

- 手动打包的等价结构（旧式）：`index.js`（入口）+ `package.json` + 可选 `README.md`，然后 `zip -r my-plugin.zip my-plugin/`。
- `manifest.json` **必须存在于插件根目录**；ZIP 产物应包含 `manifest.json` + `index.js` +（可选）`frontend.js`。

---

## 入口文件结构

### 最小插件（服务端）

```typescript
import type { PluginContext } from '@openlearn/plugin-sdk';

export default {
  manifest: {
    id: '@example/my-plugin',        // 全局唯一，推荐 @scope/name 或 ext-name
    name: '示例插件',
    version: '1.0.0',
    main: 'index.js',                // 入口相对路径（完整示例中为 dist/index.js）
    engines: { openlearn: '>=0.2.5' },
    requires: [
      '@openlearn/core:ICommandBusService@^1.0.0',
      '@openlearn/core:IActionRegistryService@^1.0.0',
      '@openlearn/core:IEventBusService@^1.0.0',
    ],
    capabilitiesProposed: ['lesson:read'],
  },
  activate: async (ctx: PluginContext) => {
    ctx.log.info('Plugin activated');
  },
  deactivate: async () => { /* 可选，资源由 ResourceTracker 兜底清理 */ },
};
```

### 前端入口（frontend.tsx）

```typescript
let ctx: any = null;

// 组件必须用普通 function 声明（不要用箭头函数，esbuild 打包后闭包可能出问题）
function MyPanel() {
  const [data, setData] = React.useState([]);
  React.useEffect(() => { ctx.invokeCommand('myplugin.list').then(setData); }, []);
  return React.createElement('div', null, data.map((x: any) =>
    React.createElement('div', { key: x.id }, x.name)));
}

async function activate(hostCtx: any) {
  ctx = hostCtx;   // 通过模块级变量拿 ctx（扩展点组件 props 由宿主控制，拿不到 invokeCommand）
  hostCtx.ui.registerExtensionPoint('teacher.tab', {
    id: 'my-tab', label: '我的面板', icon: 'Layout',
    component: MyPanel,          // 普通函数引用，不是 () => <MyPanel/>
    position: 10,
  });
}
function deactivate() {}
export default { activate, deactivate };   // default export 是对象，不是组件本身
```

### Manifest 字段全表（当前规范）

**必需字段**：`id`（唯一，`@scope/name` 或 `ext-name`）、`name`、`version`（SemVer）、`main`（入口相对路径，如 `index.js` / `dist/index.js`）。

**依赖与服务声明**：

| 字段 | 说明 |
| --- | --- |
| `engines.openlearn` | 宿主版本范围。**推荐写向前兼容区间如 `">=0.2.5"`**；零主版本 `^0.2.9` 等价 `>=0.2.9 <0.3.0`，宿主升到 0.3.x 会被判不兼容而拒载 |
| `requires` | 强依赖的服务 Token，格式 `@scope/domain:IServiceName@SemVerRange`；不满足则抛 `SemverMismatchError` 并终止激活 |
| `optional` | 可选依赖，格式同 `requires`；不满足时宿主不阻塞，但把 `ctx.services[xxx]` 置为 `null`（插件需自行判空） |
| `pluginDependencies` | 依赖的其他插件 ID 列表（如 `["@openlearn/plugin-vfs"]`），被依赖插件须先处于 `ACTIVE` |
| `provides` | 本插件向 DI 注册的服务 Token 名列表，供其他插件 `ctx.resolve(token)` 消费 |

**权限**：`capabilitiesProposed`（字符串数组）。常见值：`vfs:read` / `vfs:write`、`storage:read` / `storage:write`、`ai:chat` / `ai:completion`、`process:execute`、`lesson:read|write|delete`、`whiteboard:read|write`、`file:write`、`assignment:write`、`management:read|write`。支持通配符（`lesson:*`）。格式规范为 `{resource}:{action}`。

**UI 贡献点**：`contributes`（声明式，供管理后台预览/枚举；实际渲染仍需在 `activate` 中命令式注册）。

- `teacher.tab`：教师端导航页。`{ id, label, icon（Lucide 图标名）, position }`，组件收到 `{ renderType: 'panel' }`
- `classroom.tool`：课堂工具。`{ id, name, commandType }`
- `teacher.dashboard.widget`：白板内可拖拽卡片，组件收到 `{ elementId, lessonId }`
- `student.view`：学生端全屏视图，组件收到 `{ studentId }`
- `student.lesson.tool`：学生课中互动小工具
- `student.fullscreen`（0.2.x）、`teacher.panel`（0.2.x）、`global.setting`（0.2.x）、`nav.user_menu`（v5.2）
- `anchor:*`（v0.2.6+）：锚点槽位，命名 `anchor:{页面或区域}:{锚点 id}`，如 `anchor:whiteboard-toolbar:rollcall`。条目为 `{ id, label, icon, placement: 'before'|'after'（默认 after） }`

> 前端实际渲染由 `ctx.ui.registerExtensionPoint(slot, { id, component, ... })` 完成，且宿主须在锚点前后渲染 `<ExtensionPointRenderer slot="..." placement="before|after" />`。完整锚点目录见官方 `plugin/anchor-slots.html`。

**`classroomTools`**（前端课堂工具声明，与 `contributes.classroom.tool` 并存于不同文档口径）：

```json
{
  "classroomTools": [{
    "id": "poll-tool",
    "name": "📊 投票",
    "icon": "BarChart3",
    "commandType": "poll.create",
    "payload": { "type": "single_choice" }
  }]
}
```

- `icon` 使用 `lucide-react` 图标名。
- **`classroomTools[].commandType` 必须在服务端 `activate()` 中注册对应 Handler**，否则报 `No handler registered for command: xxx`；即使无实际逻辑也要注册空 handler。
- `teacher.dashboard.widget` 的 `id` 必须与 `classroomTools[].payload.data.teacherWidgetId`（JSON 字符串）一致。

**`configuration`**：声明可配参数，平台自动生成配置界面，插件经 `ctx.config.get(key)` 读取。

```json
{
  "configuration": {
    "properties": {
      "autoGradeEnabled": { "type": "boolean", "default": true, "description": "..." },
      "maxScore": { "type": "number", "default": 100, "minimum": 1, "maximum": 150 }
    }
  }
}
```

- `ConfigProperty` 支持 `type`：`string | number | boolean | integer`，可选 `default` / `description` / `enum` / `minimum` / `maximum`。
- 系统内置特殊键 `showInDashboard`（boolean，默认 true）：用户可在插件卡片切换，用于隐藏 `teacher.dashboard.widget` 小部件，框架层实现，插件无需处理。

**`api.routes`**（v0.3.11 新增）：静态声明 RESTful 路由与前置安全规则，网关据此做 RBAC 拦截。

```json
{
  "api": { "routes": [
    { "method": "GET", "path": "/public-status", "auth": false },
    { "method": "POST", "path": "/submissions/:id/grade", "auth": true,
      "roles": ["teacher", "administrator"],
      "rateLimit": { "max": 60, "windowMs": 60000 } }
  ] }
}
```

| 属性 | 必填 | 默认 | 说明 |
| --- | --- | --- | --- |
| `method` | 是 | — | `GET`/`POST`/`PUT`/`DELETE`/`PATCH`/`ALL` |
| `path` | 是 | — | 相对子路径，支持命名参数与通配符 `*` |
| `auth` | 否 | `true` | `false` 为公开端点 |
| `roles` | 否 | `[]` | 角色白名单；为空则仅需认证，管理员始终最高权限 |
| `rateLimit.max` | 否 | `120` | 单 IP 时间窗口内最大请求数 |
| `rateLimit.windowMs` | 否 | `60000` | 滑动窗口毫秒 |

**`deploy`**：`staticRoute`（挂载到 Express 的 URL 前缀，如 `/plugins/my-plugin/static`）+ `staticDir`（插件目录下静态文件相对路径，如 `"public"` / `"dist/frontend"`）。

**`updateSource`**（v0.3.10+）：`{ "type": "github-release" | "gitee-release", "repo": "owner/repo" }`。未声明时平台回退扫描本地 `v2_plugins/*/manifest.json` 做 SemVer 比对。

---

## package.json 与 tsconfig 要点

### 版本（必须来自抓取内容，勿臆造）

- **`@openlearn/plugin-sdk`：版本随平台 release 同步，官方明确「勿在文档中写死」。** 文档中出现过的口径：`3.5.2`（verifiable-examples 页与教程 §2.8）、`3.6.0`（`ctx.http` / 平台 v0.3.11 引入）、`3.6.1`（数据库 API 页、共享依赖页，适用平台 v0.3.15+）。旧缓存写的 `^3.2.0` 属过时信息。
- **`@openlearn/plugin-test-kit`：文档口径为 `3.3.1`**（verifiable-examples 页与教程 §2.8 均写明）；SDK 与 test-kit 版本号各自独立演进。
- **React**：宿主实际运行 `react` / `react-dom` / `react-dom/client` / `react/jsx-runtime` 均为 **19.2.7**（`package.json` 声明范围 `^19.0.1`）。`recharts` 3.8.1（声明 `^3.8.1`）、`lucide-react` 0.546.0（声明 `^0.546.0`）。
- 但**脚手架模板本身**声明的 `peerDependencies` 仍是 `{ "react": ">=17", "react-dom": ">=17" }`（`full-stack` 与 `frontend-only` 模板）。文档明确说明这只是「插件消费宿主 React」的清单信号，**不参与 externals 计算**（externals 由 CLI 硬编码注入）。

### 构建脚本

```json
{
  "scripts": { "build": "openlearn-plugin-sdk build" },
  "peerDependencies": { "react": ">=17", "react-dom": ">=17" }
}
```

### tsconfig / JSX 配置

- `tsconfig.json` 需支持 JSX。文档新旧口径并存，按目标平台版本选择：
  - 官方「发布前自检清单」与前端章节的**推荐值为 `"jsx": "react"`（经典模式）**，并明确要求产物中不要出现 `import ... from "react/jsx-runtime"`。
  - **自平台 v0.3.15+ 起**，宿主已内置 `react/jsx-runtime` 映射，`"jsx": "react-jsx"`（自动模式）与 `"jsx": "react"` 均可原生支持；v0.3.16 进一步重构前端转译器以全面放行 `react-jsx` 输出。因此面向 v0.3.15+ 时两者皆可，面向更老平台请用 `"react"`。
- 旧缓存记载的 `moduleResolution: "bundler"`：新版文档**未明确**，保留待验证。
- 前端构建配置（esbuild）示例：

```javascript
import esbuild from 'esbuild';
esbuild.build({
  entryPoints: ['src/frontend.tsx'],
  bundle: true,
  outfile: 'dist/frontend.js',
  external: ['react', 'react-dom', 'react-dom/client', 'react/jsx-runtime', 'recharts', 'lucide-react'],
  format: 'esm',
  platform: 'browser',
  jsxFactory: 'React.createElement',
  jsxFragment: 'React.Fragment',
});
```

---

## 数据库 API 与 migration 规范

插件有**两条**数据库路径，务必分清（丰富方法集 `query/select/insert/update/delete/transaction/exec` **不在**插件 API 上，而在原始 `better-sqlite3` 实例上）。

### 路径 A — `ctx.db`：`PluginDatabaseAPI`（命名空间隔离，推荐）

```typescript
interface PluginDatabaseAPI {
  ensureTable(tableName: string, schema: string): Promise<void>;
  table(tableName: string): string;                  // 同步，返回 plugin_{pluginId}_{tableName}
  dropAllTables(): Promise<void>;
  migrate(targetVersion: number, upgradeFn: (db: any) => Promise<void> | void): Promise<void>;
}
```

- `ensureTable` 的 `schema` 是**列定义片段**（不是完整 `CREATE TABLE`），表名自动加前缀，内部执行 `CREATE TABLE IF NOT EXISTS`。
- `table('polls')` 返回如 `plugin_@openlearn/plugin-poll_polls`（前缀用 `manifest.id`，**不是**内核 UUID；Worker 模式下 `table()` 返回 UUID 前缀，切换模式会导致表名变化）。
- `dropAllTables()` 删除 `plugin_{pluginId}_%` 全部表，**卸载时由 PluginHost 自动调用**（插件无需在 `deactivate` 手动调用）。
- SQL 方言：SQLite（better-sqlite3 `^12.11.1`），**无查询构造器**，需手写原生 SQL。
- 无 `transaction` / `beginTransaction` 方法。

### 路径 B — `ctx.resolve(IDatabaseToken)`：平台共享数据库

- 返回整个平台共享的 SQLite 连接，**无命名空间隔离**，可读写 `vfs_nodes`、`students`、`users` 等平台基础表；是唯一能直接对平台表做 `SELECT/INSERT/UPDATE/DELETE` 的路径。
- 类型：Inline 模式为 `better-sqlite3.Database`（同步 `prepare()` / `exec()`）；Worker 模式为异步 RPC Proxy（方法返回 Promise）。
- 事务**仅**在路径 B 的 Inline 进程原始实例上可用，且是 better-sqlite3 的**回调式** API：

```typescript
const db = await ctx.resolve(IDatabaseToken);
const tx = db.transaction(() => {
  db.prepare('DELETE FROM students WHERE id = ?').run(id);
  db.prepare('DELETE FROM grades WHERE student_id = ?').run(id);
});
tx();  // 调用返回函数才真正执行
```

- Worker 隔离模式**不支持** `db.transaction(fn)`（IPC 无法同步传闭包 + 线程独占锁），多步一致性需在单个 `exec` 中含多条 SQL 或在主侧命令中封装。
- 兼容方法表：`prepare().run/get/all`（全版本）、`exec()`（better-sqlite3 ≥9.0.0；Worker 模式自 v0.3.9 起支持异步转发）、`pragma()`（≥4.0.0）、`transaction()`（全版本，Worker 不行）。

### KV 存储（非 SQL）

`ctx.services.storage`（`IStorageService` 的 `get` / `set` / `delete`）后端为 `plugin_storage` 表，按 `plugin_id` 自动命名空间隔离，适合简单键值，无需建表。

### migration 规范

`migrate(targetVersion, upgradeFn)` 是**正式的幂等版本迁移 API**：在 `plugin_migrations` 表（`plugin_id` 主键）记录版本，读取当前版本（默认 0），`current < target` 时执行 `upgradeFn(db)` 再写入 `target`。

标准范式（每次升级新增一个更高版本号的 `migrate` 调用，旧版本自动跳过）：

```typescript
export async function activate(ctx: PluginContext) {
  // v1：建表
  await ctx.db.migrate(1, async (sqliteDb) => {
    sqliteDb.exec(`CREATE TABLE IF NOT EXISTS my_table (id TEXT PRIMARY KEY, data TEXT)`);
  });
  // v2：加列
  await ctx.db.migrate(2, async (sqliteDb) => {
    sqliteDb.exec(`ALTER TABLE my_table ADD COLUMN extra TEXT DEFAULT ''`);
  });
  // v3：加索引
  await ctx.db.migrate(3, async (sqliteDb) => {
    sqliteDb.exec(`CREATE INDEX IF NOT EXISTS idx_my_table_extra ON my_table(extra)`);
  });
}
```

- **没有 down-migration / 回滚**，只有卸载时的 `dropAllTables()`。
- **Worker 兼容写法**：Worker 模式下 `upgradeFn` 拿到的是受限代理（可用 `prepare().run/get/all` + `exec()`，**无 `transaction`**）。因此官方建议迁移脚本**统一用 `prepare().run()`** 而非 `sqliteDb.exec()`，以保证 Inline / Worker 双模式兼容。
- Worker 迁移白名单（v0.3.16）：`plugin_migrations` 已加入 DDL 白名单；异步 SQL 由 `pendingPromises` 队列在迁移后统一 `Promise.all` 等待，避免未 `await` 导致版本号提前落库。第三方 Worker 建表/改表必须使用自身前缀 `plugin_{pluginId}_`，`users`、`client_sessions` 等核心表 DDL 被黑名单禁止。
- `migrations/` 目录 + `server/utils/migrate.ts` 的 `runMigrations` 是**核心平台** schema 迁移系统，**不是**插件迁移系统，插件请只用 `ctx.db.migrate`。

### 其他与数据相关的上下文

- `ctx.config`：读 `manifest.configuration` 声明的参数（`get` / `getAll` / `set` / `onChange`）。Worker 模式不可用。
- `ctx.require(moduleName)`：引用宿主共享模块白名单，仅允许 `recharts`、`react-markdown`、`jspdf`、`jspdf-autotable`、`xlsx`、`lucide-react`、`uuid`；越权抛 `Module ... is not in the plugin shared modules whitelist.`。
- `ctx.http`（v0.3.11+）：`get/post/put/delete/patch/all/stream`。`stream` 为 v0.3.12 新增 SSE 端点。所有端点经网关统一挂载至 `/api/plugins/:pluginId/*`，请求体硬限制 ≤1MB。
- `ctx.reportProgress(stage?, message?)`（v0.3.15+）：耗时长初始化期间的心跳续期，防止激活超时误判。

---

## 构建与打包

```bash
npx @openlearn/plugin-sdk build            # 构建 + 生成 ZIP
npx @openlearn/plugin-sdk build --watch    # 旧缓存记载的 watch 模式（新文档未提及，待验证）
```

构建要点：

- **打包工具是 esbuild**，插件构建**不使用 Vite / Rollup**；插件无独立打包器配置文件，构建完全由 SDK CLI 驱动（源码 `packages/plugin-sdk/cli.mjs`）。
- **externals 由 CLI 自动注入**，插件作者无需声明：前端 externals 硬编码为 `['react','react-dom','recharts','lucide-react']`；服务端 bundle 另加 `@openlearn/plugin-sdk`。
- **服务端产物严禁把 `@openlearn/plugin-sdk` 打进 ZIP**（应保持 external）。
- 宿主侧二次扫描：上传 ZIP 后平台用 esbuild 插件 **`openlearn-token-enforcer`** 对入口 `index.js` 重新扫描，**只允许两类导入**——相对路径导入（`./utils`）与 `@openlearn/*` Token 服务；其余裸 specifier（含 Node 内置模块）一律拒绝。
- 前端共享依赖（HostSharedDeps，v0.3.16 从 4 个扩充到 6 个）：`react`、`react-dom`、`react-dom/client`、`react/jsx-runtime`、`recharts`、`lucide-react`。运行时通过 `window.HostSharedDeps` 注入，并由 `transformBareModuleImports` 转译裸模块导入（支持复合导入、别名、命名空间、多行/注释）。宿主**不**共享 `react-konva`、`konva`、`socket.io-client`、`motion`、`react-markdown` 等，需自行 bundle。
- 注意：`window.HostSharedDeps` **没有** `socketService` / `uiService` 键，前端通信/UI 服务须走 `hostCtx.services` 或 `hostCtx.ui`。

### 产物自检命令

```bash
# 检查 dist/index.js 中是否有白名单外的裸导入（有输出 = 有问题，无输出 = 通过）
grep -E '^import .+ from "[^@\./]' dist/index.js

# 解压 ZIP 后确认 frontend.js 不含 react/jsx-runtime 裸导入
grep -E 'react/jsx-runtime' dist/frontend.js
```

### 发布前自检清单（摘要）

- `id` 全局唯一；`engines.openlearn` 用向前兼容区间（推荐 `">=0.2.5"`）。
- `requires` 中 Token 版本前缀正确；`classroomTools` 每个 `commandType` 都有 `registerHandler`；导出 HTTP 端点已写入 `api.routes`。
- 已把 `@openlearn/plugin-sdk` 标记为 external，**严禁打入 ZIP**。
- 每个 `actionRegistry.register` 都有对应 `commandBus.registerHandler`；`ctx.db.ensureTable` 建的每张表有注释；跨插件调用已在 `capabilitiesProposed` 声明权限；`activate()` 中易错操作包了 `try/catch`。
- Worker 目标模式额外检查：`IDatabaseToken.exec()` 需 `await`；未用 `db.transaction(fn)`；未直接访问 `ctx.config`（改用 `ctx.manifest.configuration.properties` 默认值）；`ctx.provide()` 有 `typeof` 守卫；`eventBus` 用 `subscribe()/unsubscribe()` 而非 `on()/off()`；Worker 内部 `commandBus.execute()` 的 `type` **手动拼接了 `ctx.manifest.id` 前缀**。
- 前端：`jsx` 配置与目标平台匹配；`react/react-dom/recharts/lucide-react` 标记 external；不直接 import React 子路径（面向 <0.3.15 时）。

---

## 安装与调试

### 安装

1. 以管理员身份登录 → 侧边栏「插件中心」（或「系统设置」→「插件中心」）。
2. 上传 ZIP 插件包，或使用「一键极速安装（Express Install ⚡）」向导。
3. 安装流程自动执行：解压 ZIP → 提取 `index.js` 为入口 → 解析 manifest → **esbuild `openlearn-token-enforcer` 二次扫描** → 验证依赖（SemVer 兼容性）→ 检查权限请求并按颜色编码提示风险（玫瑰色/高危、琥珀色/中风险、翡翠绿/安全）→ 存入数据库 → 可选立即激活。
4. 在「已安装」列表启用/停用插件；安装时可审查并授予/拒绝 `capabilitiesProposed` 声明的能力。

### 调试

- **结构化日志**：统一用 `ctx.log.debug/info/warn/error(message, meta?)`，自动注入 `pluginId` 与高精度时间戳，替代 `console.log`。
- **进程/插件状态**：`curl http://localhost:9000/api/plugins`；后台进程在「系统设置 → 进程管理」查看。
- **事件审计**：所有事件写入 SQLite `events` 表，如 `SELECT * FROM events WHERE type LIKE 'poll.%' ORDER BY timestamp DESC;`。
- **热重载**：`NODE_ENV=development` 时 `HotReloadController` 用 chokidar 监听 `plugins/`，变更（debounce 300ms）后自动停用旧版 → 清中间件 → 激活新版，无需重启。
- **生命周期中间件**（洋葱模型）：`beforeActivate`、`afterActivate`、`beforeDeactivate`、`afterDeactivate`、`beforeCommand`、`afterCommand`。
- **生命周期状态机**：`INSTALLED → ACTIVATING → ACTIVE → DEACTIVATING → INACTIVE`，失败进入 `ERROR`（可重试），最终 `UNINSTALLED`。`ACTIVATING` 为瞬态（Inline 10 秒 / Worker 10 秒激活超时）。Worker 激活期新增 `activating` 状态与 5ms fail-fast（v0.3.16）。
- 用户侧排查：插件安装后不显示 → 确认状态为「已启用」、权限已授予、刷新页面、查服务端日志（dev 模式看终端，PM2 用 `pm2 logs`）。
- 平台侧启动/运维 CLI（与插件 CLI 不同，属 `openlearn-next` 包）：`npx openlearn-next doctor [--fix]`、`backup`、`restore`、`reset-admin`、`plugins`、`clean --npx`。默认账户 `admin/admin`、`teacher/teacher`，端口 9000。

---

## 测试

### 版本与安装

- 包名：`@openlearn/plugin-test-kit`，**文档口径版本为 `3.3.1`**。测试运行器文档示例同时给出 npm 与 pnpm：

```bash
npm install --save-dev @openlearn/plugin-test-kit vitest
# 或
pnpm add -D @openlearn/plugin-test-kit vitest
```

> 注意：test-kit 版本号与 `@openlearn/plugin-sdk` 版本号**独立**，不要混用（SDK 文档口径为 3.5.2 / 3.6.0 / 3.6.1，test-kit 为 3.3.1）。

### `createMockContext(options)` 能力

零真实平台依赖的隔离 Mock 上下文，可用于 Vitest 或 Jest（文档示例以 Vitest 为主）。

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `ctx.pluginId` | `string` | 默认 `'test-plugin'`，可由参数指定 |
| `ctx.manifest` | `Manifest` | 模拟 manifest |
| `ctx.services` | `Record<string, any>` | 内核 7 大服务 Mock 桩（`commandBus` / `eventBus` / `storage` / `ai` 等） |
| `ctx.db` | `PluginDatabaseAPI` | 内存 SQLite / 模拟库，支持 `ensureTable` / `table` / `migrate` |
| `ctx.log` | `IPluginLogger` | 内存日志捕获，可断言输出 |
| `ctx.http` | `PluginHttpRouter` | v0.3.11 新增，无需启动 HTTP 服务即可离线测试接口 |
| `ctx.resolve` / `ctx.provide` | `Function` | DI 解析与自定义服务注入 |

### 基础用法

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { createMockContext } from '@openlearn/plugin-test-kit';
import myPlugin from '../src/index.js';

describe('My Plugin Unit Tests', () => {
  it('should activate cleanly', async () => {
    const ctx = createMockContext({ pluginId: 'ext-demo' });
    await myPlugin.activate(ctx);
    expect(ctx.pluginId).toBe('ext-demo');
  });
});
```

### 测试 Command / Event

```typescript
// 命令：注册后可断言执行结果
const ctx = createMockContext({ pluginId: 'ext-poll' });
ctx.services.commandBus.registerHandler('poll.create', async (cmd: any) =>
  ({ pollId: 'poll-101', title: cmd.payload.title }));
const result = await ctx.services.commandBus.execute({
  type: 'poll.create', payload: { title: '今天理解了吗？' } });
expect(result).toEqual({ pollId: 'poll-101', title: '今天理解了吗？' });

// 事件：用 vi.fn() 订阅并断言调用次数
import { vi } from 'vitest';
const eventHandler = vi.fn();
ctx.services.eventBus.subscribe('poll.created', eventHandler);
```

### 测试 RESTful API 路由（v0.3.11+）

`createMockContext` 默认内置真实 `PluginHttpRouter` 实例，用 `ctx.http.handle()` 派发模拟请求并断言状态码 / body / 参数提取：

```typescript
const ctx = createMockContext({ pluginId: 'ext-feedback' });
await feedbackPlugin.activate(ctx);

const res = await ctx.http.handle({
  method: 'GET',
  path: '/students/stu_007/summary',
  params: {},
  query: { term: '2026-autumn' },
  headers: {},
  body: null,
  ip: '127.0.0.1',
  actor: { actorId: 'user:1', username: 'teacher_li', role: 'teacher' },
});
expect(res.status).toBe(200);
```

未注册路由返回 404；校验失败用例可断言 `status: 400`。

### 最佳实践

1. 每个用例用 `beforeEach` 重新 `createMockContext()`，防止状态交叉污染。
2. 实现了 `deactivate` 的插件，在 `afterEach` 或末尾 `await plugin.deactivate()` 验证资源释放。
3. 通过检查 `ctx.log` 记录，验证未泄露敏感信息、异常分支有正确 warn/error。

---

## 常见问题

### 打包失败：`Import of "<module>" is not allowed`

```
ERROR: [plugin: openlearn-token-enforcer] Import of "crypto" is not allowed.
Plugins may only use relative imports or @openlearn/* Token services.
```

`crypto` / `fs` / `path` / `lodash` 等裸导入全部被拒。解决方式：

```typescript
// ❌ import { randomUUID } from 'crypto';
const id = crypto.randomUUID();              // ✅ 全局 Web Crypto（Node 20+），无需 import
const id2 = `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;  // ✅ 非密码学 ID

// ❌ import { readFileSync } from 'fs';   ✅ 改用 VFS：commandBus.execute('vfs.read_file', ...)
// ❌ import path from 'path';             ✅ 用字符串操作 filePath.split('/').pop()
```

白名单内包用 `ctx.require()`（`uuid` / `xlsx` / `recharts` / `jspdf` / `lucide-react` 等），其余第三方包必须在构建阶段 bundle 内联，产物中不得残留裸 specifier。

### `Failed to resolve module specifier "react"` / `"react/jsx-runtime"`

- tsconfig `jsx` 为 `"react-jsx"` 且宿主 < v0.3.15 时会出现；解决办法是改为 `"jsx": "react"`。**自 v0.3.15+ 宿主已内置 `react/jsx-runtime` 映射**，v0.3.16 全面放行 `react-jsx` 输出，两种模式皆原生支持。
- 该问题曾导致插件菜单（`teacher.tab`）与仪表板部件（`teacher.dashboard.widget`）挂载失败。

### `React is not defined`

前端未把 `react` 声明为 `peerDependency` 或未标记 `external`。在构建配置中加 `external: ['react']`。

### `process is not defined`

前端构建 `platform` 未设为 `browser`。

### `Invalid hook call` / Context 断裂

原因是未 externalize `react` / `react-dom`，被打进了**第二个 React 实例**。使用标准 `openlearn-plugin-sdk build` 不会遗漏（externals 数组由 CLI 强制注入）；手写打包工具时必须手动把共享库列入 external。

### classroomTools 点击报 `No handler registered for command: xxx`

`classroomTools[].commandType` 未在服务端注册 Handler。即使只用于打开前端面板，也要注册空 handler。

### Dashboard 小部件不显示

`contributes.teacher.dashboard.widget` 的 `id` 必须与 `classroomTools[].payload.data.teacherWidgetId` 完全一致；另检查 `showInDashboard` 配置是否被用户关闭。

### `WorkerCapabilityError`（Worker 模式建表/迁移被拦）

第三方 Worker 插件建表必须用自身前缀 `plugin_{pluginId}_`；`plugin_migrations` 已白名单放行；核心表 DDL 被禁。参见「数据库 API」章节。

### Worker 内部命令调用失败

Worker 中 `commandBus.execute()` **不会**自动加 `manifest.id` 前缀（`registerHandler` 会），需手动拼接：``type: `${ctx.manifest.id}.myplugin.do_work` ``。

### 表名在 Inline / Worker 间变化

`ctx.db.table()` 在 Inline 返回 `manifest.id` 前缀，在 Worker 返回 UUID 前缀。同一次激活内一致，但切换 `execution_mode` 会导致表名变化（切换 `UPDATE plugins SET execution_mode = 'worker' WHERE id = ?` 时需注意）。

### 前端扩展点组件不渲染 / 报错

`registerExtensionPoint` 的 `component` 必须用**普通 function** 声明（箭头函数经 esbuild 打包可能丢失闭包）；API 能力必须通过模块级变量传递，不要依赖 props。

### 旧文档记载项（新文档未覆盖，需实测）

- `npx @openlearn/plugin-sdk init` 的 `--description` / `--author` / `--template` 参数。
- `build --watch` / `-w` 选项。
- `tsconfig.json` 的 `moduleResolution: "bundler"`。
- `vfs:read` / `vfs:write` 之外的细粒度权限与 `classroomTools` 与 `contributes.classroom.tool` 的取舍关系。

### 文档不一致提醒

`examples/verifiable-examples` 示例中使用 `ctx.logger.info(...)`，而 SDK / 数据库 / 测试套件等页面统一使用 `ctx.log.info(...)`。以 `ctx.log` 为准（类型定义与 Worker/Inline 差异表均只列出 `ctx.log`）。

---

## 来源

实际抓取并用于汇编的页面（均在 `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/` 下）：

1. `sdk/scaffold-cli.html` — Scaffold CLI 脚手架指南（内容极薄，仅 init / build 两条命令；readable 模式抓取失败，改用 raw 模式成功）
2. `sdk/plugin-sdk.html` — `@openlearn/plugin-sdk` API 参考手册（PluginContext、DI Token、ctx.http、ctx.reportProgress）
3. `sdk/plugin-test-kit.html` — 插件测试套件（createMockContext、ctx.http.handle、最佳实践）
4. `examples/verifiable-examples.html`（及 `_sources/examples/verifiable-examples.md.txt`）— 可编译验证示例全集（内容极薄，仅一个最小插件示例与 SDK 3.5.2 / test-kit 3.3.1 版本口径）
5. `examples/existing-plugins-guide.html` — 内置范例插件拆解指南（7 个生产级范例、manifest 解析、用作模板的步骤）
6. `reference/plugin-database-api.html` — 插件数据库 API 与 Migration 规范（适用范围标注 SDK 3.6.1 / 平台 v0.3.15+）
7. `getting-started/quickstart.html` — 快速入门（平台侧 5 分钟启动、默认账户）
8. `plugin/plugin-manifest-spec.html` — 插件 Manifest 规范（Zod 校验、完整字段、api.routes、updateSource）
9. `tutorials/plugin-development-tutorial.html` — 插件开发完全指南（项目结构、三件套、npm 脚本、ZIP 打包、token-enforcer、发布自检清单、前端 JSX 配置、Worker/Inline 差异）
10. `plugin/plugin-architecture.html` — 插件宿主架构与沙箱隔离机制（PluginApiGateway 六道防御、白名单、ResourceTracker）
11. `reference/plugin-host-shared-deps.html` — 宿主共享依赖白名单（精确版本、externals、esbuild 规范）
12. `troubleshooting/troubleshooting-faq.html` — 故障排查（内容极薄，仅 iframe postMessage 一条；readable 抓取成功但正文近乎空）
13. `release-notes/v0.3.16.html` — 发布日志 v0.3.16（前端转译器、Worker fail-fast、迁移白名单）
14. `getting-started/installation-guide.html` — 安装与使用指南（插件中心安装、平台 CLI、常见问题）
15. `index.html` — 文档首页（版本同步声明、模块导览）

未使用：旧 `scaffold.html`（已 404）。
