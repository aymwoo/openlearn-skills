[缓存自 OpenLearnV2 官方文档 v0.3.16 多页汇编，见文末来源列表]

# OpenLearnV2 核心架构速查

> 插件开发者提炼版；关键 API 保留精确签名，「文档未明确」= 新文档未覆盖。

## 1. 设计理念

**微内核 + 插件化微前端**，插件驱动 **CQRS/EDA**。三原则：① **绝对组合根**——服务与依赖全在 `server.ts` 显式解析；② **Worker 沙箱隔离**——插件跑独立 Node.js Worker Thread；③ **点对点事件与指令**——写走 `CommandBus`、变更通知走 `EventBus`。延伸：内核只转发不做业务；一切皆插件；Command → Event → Audit 全链路审计；安全纵深防御。启动 = Composition Root + 5 阶段 Bootstrap Pipeline。

## 2. 分层架构（Platform Kernel 四层模型）

`packages/core/kernel/index.ts` 导出 `class Kernel` / `const kernel` / `kernelContainer`，按依赖顺序四层初始化：

| 层 | 组件 |
|----|------|
| L0 基础设施 | `EventBus`、`CapabilityGuard`、`ServiceRegistry`、`StorageService(db)`、`AIService(db)` |
| L1 AI 与能力 | `AIRuntimeKernel`、`AICapabilityKernel`、`CapabilityRuntimeKernel`、`CapabilityGovernanceKernel`、`ServiceRegistryKernel` |
| L2 总线与领域引擎 | `CommandBus`、`ActionRegistry`、`ProcessManager`、`LessonRuntime`、`ClassroomRuntimeKernel`、`PresenceEngineKernel`、`CollaborationEngineKernel`、`AnalyticsEngineKernel` |
| L3 宿主与 Worker | `PluginHost`、`WorkerManager`、`HotReloadController` |

`Kernel` 以 `public readonly` 暴露全部子系统 + `ready: Promise<void>`。Ready 三段：Layer0~3 实例化 + DI Token 绑定 → 加载 7 个内置插件（§11）→ resolve 后启动 HTTP/WebSockets。

## 3. 核心子系统

- **Kernel**：全局单例、四层初始化、`ready` 门闩；**CommandBus**：1-to-1 `register(type, handler)` / `dispatch(cmd)`；**EventBus**：1-to-N `subscribe(type, fn)`→unsubscribe / `publish(event)`；**ActionRegistry**：AI 工具注册；**CapabilityGuard**：RBAC 能力关卡（主线程侧二次校验）
- **PluginHost**（`core/plugin-host/`）：生命周期 / 沙箱调度 / DI 代理 / 贡献点注册 / 能力管控；配套 `context-builder`（`buildContext`）、`resource-tracker`（`disposeAll(pluginId)` 清理 `Disposable`）、`middleware`、`contribution-registry`、`unified-extension-registry`、`http-router`
- **PluginApiGateway**：插件 REST 统一入口与六道防线
- **ServiceRegistry**（`core/di/`，Token DI）；**ServiceRegistryKernel**（`core/service-registry/`，服务描述符 / 依赖校验）；**WorkerManager**（`core/worker-runtime/`）；**NodeEsmLoader**（`core/esm-loader/`）

## 4. 插件生命周期状态机

`PluginState`（`core/plugin-host/types.ts`）**7 状态**：`INSTALLED`('installed'，稳定) → `ACTIVATING`(瞬态) → `ACTIVE`(稳定) / `ERROR`(稳定)；`ACTIVE` → `DEACTIVATING`(瞬态) → `INACTIVE`(稳定，资源已清但记录保留)；`UNINSTALLED`('uninstalled'，终态，记录 / 自建表 / 目录全销毁)。`INACTIVE`、`ERROR` 可再 `ACTIVATING`。

合法转换矩阵（`plugin-host/index.ts:62`，非法转换抛 `IllegalStateTransitionError`）：`INSTALLED:[ACTIVATING,UNINSTALLED]`、`ACTIVATING:[ACTIVE,ERROR]`、`ACTIVE:[DEACTIVATING]`、`DEACTIVATING:[INACTIVE]`、`INACTIVE:[ACTIVATING,UNINSTALLED]`、`ERROR:[ACTIVATING,UNINSTALLED]`、`UNINSTALLED:[]`。`ACTIVE → INACTIVE` **不直连**（必经 `DEACTIVATING`）；`ERROR → ACTIVATING` 为重试路径。

- **激活** `activatePlugin`：转 `ACTIVATING` → `checkPluginDependencies`（`pluginDependencies` 须 `ACTIVE`）+ `checkCrossPluginServices`（`requires` 的服务须由某已激活插件 `provides` 声明）→ `buildContext`（optional 不满足置 `null`）→ 申请 `capabilitiesProposed` → `beforeActivate` → `activate(ctx)`（`Promise.race` 包超时与错误）→ `ACTIVE`；失败 / 超时转 `ERROR`，强制 `disposeAll` 并撤销能力
- **停用** `deactivatePlugin`：须 `ACTIVE` → `DEACTIVATING` → `beforeDeactivate` → 可选 `deactivate()` → **finally 强制清理**（`disposeAll(pluginId)` + `revokeAll(actorId)` + 注销热重载监听）→ `INACTIVE`

超时：Inline `ACTIVATION_TIMEOUT_MS = 5000ms`、`DEACTIVATION_TIMEOUT_MS = 5000ms`；Worker `OPENLEARN_WORKER_ACTIVATE_TIMEOUT_MS = 60000ms`，可用 `ctx.reportProgress(stage?, message?)` 续期，Worker 异常退出 **5ms 快速失败**。

中间件（洋葱模型，`pluginHost.registerMiddleware(phase, fn)`，`async (ctx, next) => { ...; await next(); }`）：`beforeActivate` / `afterActivate` / `beforeDeactivate` / `afterDeactivate` / `beforeCommand` / `afterCommand`。

## 5. 内核服务 Token 与获取方式

DI 由 `packages/core/di/` 与 `@openlearn/plugin-sdk` 提供。`Token<T>` 带契约名 + 版本：`new Token<IFoo>('IFoo', '1.0.0')`；容器 `ServiceRegistry`：`register<T>(token: Token<T> | string, instance: T): void` / `resolve<T>(token): T` / `has<T>(token): boolean`。

`packages/core/di/interfaces.ts` 核心 Token（13 个标准项，接口为去掉末尾 `Token` 的同类名）：`ICommandBusServiceToken`、`IEventBusServiceToken`、`IActionRegistryServiceToken`、`ICapabilityServiceToken`、`IProcessServiceToken`、`IStorageServiceToken`、`IAIServiceToken`、`ILessonEngineServiceToken`、`IClassroomRuntimeServiceToken`、`IPresenceEngineServiceToken`、`ITeachingCollaborationServiceToken`、`ILearningAnalyticsServiceToken`、`IAICapabilityServiceToken`；3 个特例：`IPluginHostToken`→`PluginHost`、`IPlatformServiceRegistryToken`→`ServiceRegistryKernel`、`IDatabaseToken`→`better-sqlite3.Database`。

注：`IDatabaseToken` 未列入 DI 一览表，但 DB API 页用 `ctx.resolve(IDatabaseToken)`；新文档**未给出** Token 字符串标识符（旧版 `@openlearn/core:xxx` 未再出现），统一 `new Token(name, version)`。插件内必须 `await ctx.resolve(IStorageServiceToken)`（**返回 `Promise<T>`**，与容器同步 `resolve` 不同），亦可 `await ctx.provide(token, instance)`。

## 6. PluginContext 与 Worker Thread 隔离

`PluginContext`（`plugin-host/types.ts` / `context-builder.ts`）：`services`（7 代理 `commandBus` / `eventBus` / `actionRegistry` / `capability` / `processManager` / `storage` / `ai`）、`pluginId`、`manifest`、`resolve<T>(token): Promise<T>`、`provide<T>(token, instance): Promise<void>`、`db: PluginDatabaseAPI`、`log: IPluginLogger`（**日志对象 `ctx.log`，类型 `IPluginLogger`**）、`contributions: ContributionAccessor`（`ctx.contributions.list()`）、`config: IConfigService`、`require(moduleName: string): any`。

`buildContext`：① handler / 订阅自动包装并登记 `ResourceTracker`；② 敏感能力调用透传 `plugin:${manifest.id}` actor ID 做权限过滤；③ `skipTokens` 把不满足 optional SemVer 的依赖在 `services` 中置 `null`。

**两种运行模式**：Inline 内联（主进程内存，内核级插件用，闭包直调内核 API）；Worker 沙箱（`worker_threads.Worker`，第三方未信任 / 高 CPU 插件用）。Worker **三层隔离**：物理（独立 V8 线程，无 `window` / `document`）、通信（`WorkerTransport` + `MessageChannel`）、权限（主线程侧 `CapabilityGuard` 复查）。`ctx.require` 共享模块白名单（`plugin-host/types.ts:73`）：`recharts`、`react-markdown`、`jspdf`、`jspdf-autotable`、`xlsx`、`lucide-react`、`uuid`。

## 7. 前端插件系统与 HostSharedDeps

`window.HostSharedDeps`（`src/main.tsx`）**事实白名单**：`react`、`react-dom`、`react-dom/client`、`react/jsx-runtime`、`recharts`、`lucide-react`（对象键 `React` / `ReactDOM` / `ReactDOMClient` / `Recharts` / `LucideReact` / `jsxRuntime`）；版本：React 19.2.7、`recharts` 3.8.1、`lucide-react` 0.546.0。

需自行打包（不共享）：`react-konva` / `konva` / `socket.io-client` / `motion` / `react-markdown` / `xlsx` / `jspdf` / `zustand` 等。

**口径纠正**：旧文档的 `window.HostSharedDeps.socketService` / `uiService` **不存在**；通信与 UI 服务须走 `hostCtx.services` / `hostCtx.ui`。（前端 `FrontendServiceRegistry` 的 5 个 Token、`FRONTEND_API_TOKEN` 在新文档中不再出现，视为文档未明确。）

**构建**：esbuild（**不用** Vite/Rollup），由 SDK CLI `openlearn-plugin-sdk build` 驱动；externals 由 CLI 自动注入，前端数组 `['react','react-dom','recharts','lucide-react']` 硬编码，服务端 bundle 另加 `@openlearn/plugin-sdk`。漏 external 会产生第二个 React → "Invalid hook call"。

> 旧说法「JSX 必须用经典模式 `"react"`」已被取代：新文档明确兼容 `react/jsx-runtime`。

## 8. 扩展槽位

双层：① `ContributionRegistry`（静态声明式，未激活即解析 `manifest.contributes`，供后台渲染图标菜单）；② `UnifiedExtensionRegistry`（统一索引 UI 组件 / Activity 提供者 / AI Actions / 命令 / Capability；启动时 `syncContributionRegistry()` 提升为统一分类）。

| 槽位（挂载位置） | 字段 |
|------|------|
| `classroom.tool`（课堂工具箱） | `id`,`name`,`icon`,`commandType`,`payload` |
| `teacher.tab`（教师端主导航） | `id`,`label`,`icon`,`position` |
| `teacher.dashboard.widget`（教师端仪表盘） | `id`,`label`,`icon`,`position` |
| `student.view`（学生端主导航） | `id`,`label`,`icon`,`route` |
| `student.lesson.tool`（学生端课中工具） | `id`,`label`,`icon` |
| `anchor:*`（原生按钮前后，**v0.2.6+**） | `id`,`label`,`icon`,`placement` |

> 旧版 `teacher.panel`、`student.fullscreen`、`global.setting` **未出现在新版槽位分类表**（文档未明确现状，可能已移除或迁出该页）。

锚点命名 `anchor:{页面或区域}:{锚点 id}`；锚点 id 为宿主公布的受治理契约。白板工具栏 `whiteboard-toolbar` 已公布 7 个：`:presentation`、`:code-sandbox`、`:math-graph`、`:courseware`、`:rollcall`、`:ai-tutor`、`:grid`。实际渲染走命令式 `ctx.ui.registerExtensionPoint(slot, { id, label, placement: 'before'|'after'（缺省 'after'）, position（缺省 100 升序，仅同侧跨插件排序）, component })`。API：`pluginHost.getContributionRegistry()`、`contributions.summary(pluginId)`、`contributions.getTeacherTabs()`；`IUnifiedExtensionRegistry`：`registerExtension` / `hasExtension` / `getExtension` / `listExtensions` / `listCategories`。

## 9. 安全与权限模型

三角色 `Admin` / `Teacher` / `Student`；登录发 HttpOnly JWT Cookie（`getCookieToken`）；`checkIsTeacherOrAdmin` 中间件拦截敏感 API。权限格式 `{resource}:{action}`（如 `lesson:read`、`whiteboard:*`），在 `manifest.capabilitiesProposed` 声明，安装时登记、运行时强制；管理员（`actorId` 含 `:administrator`/`:admin`）绕过审批与权限检查。权限矩阵（操作 / Admin / Teacher / Student / Plugin）：创建或修改课程 ✅✅❌依 Manifest；查看全班学习分析 ✅✅仅个人依 Manifest；访问 SQLite ✅❌❌❌（插件仅 Plugin DB）；修改系统密钥配置 ✅❌❌❌。

纵深防御：① 命名空间隔离（裸字符命令加 `{pluginId}.` 前缀 + UUID 防劫持）；② CapabilityGuard 运行时强制；③ Worker Thread 隔离；④ 高危 Action 审批闸门（写 `pending_commands` 表待教师批准）；⑤ DB 屏障——`ServiceHost` 拦截 Worker DB 操作，禁访问 `users` / `client_sessions` / `plugins` / `ai_providers` 等系统表；自建表 DDL 限白名单（`manifest.id` 与 `dbPluginId` 双前缀）。AI Key 以 **AES-256-GCM** 加密存储；iframe 课件用 CSP 白名单 + `sandbox`。

## 10. 数据存储与迁移

SQLite（`better-sqlite3 ^12.11.1`），两条路径。

**路径 A `ctx.db`（`PluginDatabaseAPI`，命名空间隔离，推荐）**，仅 4 方法：`ensureTable(tableName, schema): Promise<void>`（`schema` 为列定义片段，表名自动加前缀）、`table(tableName): string`（**同步**，返回 `plugin_{pluginId}_{tableName}`）、`dropAllTables(): Promise<void>`（删 `plugin_{pluginId}_%` 全部表，卸载时自动调用）、`migrate(targetVersion, upgradeFn: (db: any) => Promise<void> | void): Promise<void>`。SQLite 方言、**无查询构造器**，手写原生 SQL；`pluginId` = `manifest.id`；`query` / `select` / `insert` / `update` / `delete` / `transaction` 等**不在**插件 API 上。

**路径 B `ctx.resolve(IDatabaseToken)`（平台共享库，无隔离）**：返回 `better-sqlite3.Database`（Inline）或异步 RPC Proxy（Worker），可读写 `vfs_nodes` / `students` / `users` 等平台表，是唯一能执行平台级 DML 的路径，也是**唯一支持事务**的路径（回调式 `db.transaction(fn)`，调用返回函数即执行）。Worker 支持 `exec` 跨线程 RPC（经主侧 `assertDatabaseAccessAllowed` 守卫），**不支持** `db.transaction(fn)`。

**Migration（v5.1）**：`plugin_migrations` 以 `plugin_id` 主键记版本；`migrate(target, fn)` 读当前版本（默认 0），`current < target` 时执行 `upgradeFn(db)` 再写 `target`，**幂等**，每次升级只加一个更高 `targetVersion` 调用。**无回滚**，仅 `dropAllTables()`。**KV**：`ctx.services.storage`（`get`/`set`/`delete`），后端 `plugin_storage` 表。

## 11. 内置系统插件

`kernel.ready` 阶段自动加载（`packages/plugins/`）：`@openlearn/plugin-builtin`（关键，课堂核心）、`@openlearn/plugin-vfs`（关键，VFS）、`@openlearn/plugin-process`（关键，后台进程）、`@openlearn/plugin-management`（关键，LMS）、`@openlearn/plugin-ai-planner`、`@openlearn/plugin-ai-submit-injector`、`@openlearn/plugin-assignment-eval`（均非关键）。

## 来源

（前缀均为 `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/`）

- `architecture/system-overview.html`、`architecture/platform-kernel.html`、`architecture/command-event-bus.html`
- `architecture/dependency-injection.html`、`architecture/security-permissions.html`、`architecture/service-registry.html`
- `plugin/plugin-architecture.html`、`plugin/plugin-lifecycle.html`、`plugin/anchor-slots.html`、`plugin/extension-registry.html`
- `reference/plugin-host-shared-deps.html`、`reference/plugin-database-api.html`
