# 插件故障归因与 Bug 报告 SOP

[本文件为 skill 自建的诊断方法论，依据 OpenLearnV2 官方文档 **v0.7.7**（插件宿主 / 生命周期 / 安全权限 / 信任边界 / Release Notes）整理；文末列出依据来源]

> **版本基线**：平台 v0.7.7 / SDK 3.7.4（npm `latest`，2026-10-28 核对）。v0.7.0 起第三方插件被策略层强制改写为 `process` 子进程执行模式，
> 排障时**必须**先确认实际执行模式（见 §D6 与 §D4-W）。SDK 3.7.2 起 frontend 产物不得含裸模块说明符，CLI 构建期直接拦截。

当开发者报告"插件不工作 / 报错了"时，**不要立刻改代码，也不要立刻甩锅给平台**。先按本 SOP 做归因，得出明确结论后再决定动作。归因错误会导致：明明是系统缺陷却在插件里到处打补丁，或明明是插件违规却去给作者提无效 bug。

---

## 0. 归因结论只有 6 种

> 用户直接粘贴报错时，输出的结论必须落到下表之一，并附**缘由**（哪一处机制导致）与**证据**。

| 结论 | 含义 | 后续动作 |
|------|------|---------|
| **插件侧** | 插件自身代码/配置/manifest 违规 | 直接修插件（配合 SKILL.md 第四步预检清单）；**不提 Issue** |
| **系统侧** | 宿主 / 内核 / SDK / 官方文档缺陷 | ① 生成本地 bug 报告；② 去重后向 `aymwoo/OpenLearn-Next-V2` 提 Issue（见 SKILL.md 第六步 B） |
| **插件间冲突** | 两个插件命名空间/事件名/表名/槽位撞车 | 定位冲突双方，按命名空间规范改名；**不提 Issue** |
| **环境与配置** | 版本不匹配、未重新构建、缓存、权限未审批 | 给出修复步骤，不算缺陷；**不提 Issue** |
| **产品边界 / 设计行为** | 文档已写明的限制（remote 无 UI、熔断停用、`auth:false` 需审批） | 改插件写法或告知操作路径；**绝不提 Issue** |
| **待定** | 证据不足，无法归因 | 列出缺失证据，指导用户补充后再判定；**不提 Issue** |

---

## 1. 三条铁律

1. **堆栈归属**：错误堆栈的顶层帧决定责任方。`dist/index.js` / `dist/frontend.js` → 插件；`packages/core/...`、`src/plugin-host/...`、`node_modules/@openlearn/...` → 系统/SDK。
2. **对照实验**：用官方脚手架原始产物或最小复现插件做控制变量实验。**能在最小插件上复现的才是系统侧。**
3. **先核版本**：任何归因之前，先确认"系统版本 vs 插件 engines vs 所用 API 的最低版本"。大量"系统 bug"其实是插件用了未来版本的 API 或声明了不兼容的 engines。

---

## 1b. 现象 → 先读哪个平台源文件

归因不靠猜：下表把常见现象直接映射到**唯一该看的源码位置**。读完再下结论，比通读 `references/` 快得多。
路径均相对平台仓库根 `~/Develop/openlearnv2/`；对应的行为约定见 `references/integration-facts.json`（可用 `bash scripts/facts-check.sh` 校验锚点是否仍成立）。

| 现象 / 错误码 | 先读 | 找什么 |
|---|---|---|
| `COMMAND_NOT_REGISTERED`（403） | `src/plugin-host/plugin-host.ts` 命令派发 + `actionRegistry` | manifest 声明的 commandType 是否有同名 handler **且** ActionDescriptor |
| 面板空白 / 永远"加载中" / 入口消失 | `src/components/PluginTabPanel.tsx` → `src/plugin-host/extension-point-renderer.tsx` | `ext.view` 是否保留、`isReact/isDOM/hasView` 三分支、`return null` 条件 |
| `OpenLearnPluginBridge is undefined` | `server/utils/plugin-view-bridge.ts` + `server.ts` 静态路由 | `/plugin-sandbox/view-bridge.js` 是否 200、页面 script 标签顺序 |
| view 页面 404 / 装不上后文件不在 | `packages/core/plugin-host/install.ts` | 只解压 `storage/**`；`view` 路径是否相对且无 `..` |
| 路由 401 / 403 / 404 | `server/routes/plugin-api-gateway.ts` | `api.routes` 方法+路径逐字匹配、`compileRoutePattern`、roles 与 administrator 放行 |
| 路由 413 | 同上（`MAX_PAYLOAD_BYTES`） | 1MB 上限；大文件必须分片 |
| 路由请求"卡住"后 5xx | 同上（`dispatchHttpRequest(..., 5000)`） | 5 秒熔断；同步长任务必死 |
| 命令里拿不到 `userId` / `role` | `src/components/PluginSandboxIframeView.tsx`（`command.invoke`）+ `pluginActorIdFor` | `invokeCommand` 的 actor 是插件自身；身份敏感操作走 `api.*` |
| 隐藏前端 POST 报"需要 api:write" | `src/plugin-host/plugin-host.ts` + `packages/core/plugin-host/method-policy.ts` | `frontendApi` 写操作过策略；view 页面的 `api.*` 不过 |
| SQL 报"not permitted to perform DDL / table not allowed" | `packages/core/plugin-host/sql-guard.ts` | 表必须 `plugin_<uuid>_*`；禁 ATTACH/PRAGMA/VACUUM/TRIGGER/VIEW；核心表黑名单 |
| `ctx.db` 返回 Promise / `undefined` | `packages/core/plugin-host/*` 的数据库代理 | process 模式是异步代理：统一 `await` |
| 改了 manifest 但行为没变 | `packages/core/esm-loader/manifest-schema.ts` | zod 默认 strip 未声明字段；旧版本安装过的插件需重装 |
| 提示「工具下发成功」但白板无组件 | `src/components/LiveClassroomView.tsx`（`handleExecuteTool`）+ `packages/core/plugin-host/sql-guard.ts` | `classroomTools` 的 commandType 是否为 `whiteboard.draw`；handler 是否非法直写 `whiteboard_elements` 被安全拦截 |
| 学生端浮层出现后主白板消失 | `src/plugin-host/extension-point-renderer.tsx`（`FLOATING_VIEW_SLOTS`） | 浮层视图是否写了 `w-full h-full` 挤占了横向 Flex 主容器；是否缺少 `bridge.ui.resize()` |
| 提示「当前暂无活跃班级上下文」 | 插件前端 `storage/*.html` + 命令 handler | 未选班级时 `classId` 为 undefined，代码缺少 `classId || 'default'` 兜底降级 |
| 教师锁屏失效 / 接口报 HTTP 429 | `server.ts` 写限流配置 + Network 面板 | 是否有无防抖的 `view-state` 回写或高频短轮询（<3s）打满了宿主写限流池 |

> 表里没有的现象，再用报错文案/符号名在 `packages/core/`、`src/plugin-host/` 搜一次，别从文档反推。

---

## 2. 证据采集清单（先收集，后判断）

在给结论前，尽量收齐以下信息。缺哪项就在"待定"结论里点名要哪项。

- [ ] **系统完整版本号**：`npx openlearn-next@<ver> doctor` 输出，或管理后台「关于」。禁止用"最新版"代替具体版本号。
- [ ] **SDK 版本**：插件 `package.json` 中 `@openlearn/plugin-sdk` 的版本。
- [ ] **manifest 全文**：`id` / `version` / `engines.openlearn` / `requires` / `capabilitiesProposed` / `execution_mode` / `classroomTools`。
- [ ] **完整错误信息与堆栈**：不要截断，尤其保留顶层 3–5 帧的**文件路径**。
- [ ] **日志**：服务端带 `[Plugin:<id>]` 前缀的日志；浏览器 Console 与 Network 报错。
- [ ] **插件状态机**：当前处于 INSTALLED / ACTIVATING / ACTIVE / INACTIVE / ERROR 哪一个，持续多久。
- [ ] **复现步骤与稳定性**：每次必现 / 偶发 / 特定操作后必现。
- [ ] **执行模式**：inline 还是 worker（`execution_mode`）。同一问题是否只在其中一种模式出现。
- [ ] **运行环境**：浏览器版本、Node 版本、OS。
- [ ] **是否多插件环境**：停用其他插件后是否仍复现。

> 取证命令
> ```bash
> # 系统自检与版本
> npx openlearn-next@<ver> doctor
> # 产物裸导入体检（应无输出）
> grep -E '^import .+ from "[^@\./]' dist/index.js
> # JSX 运行时引用检查（0.3.15+/0.3.16+ 已放行 react/jsx-runtime，低版本会报错）
> grep -n 'react/jsx-runtime' dist/frontend.js
> ```

---

## 3. 归因决策树

按故障发生**阶段**逐层下钻。

### D1. 故障在哪个阶段？

| 阶段 | 典型表现 |
|------|---------|
| 安装 / 上传 | ZIP 解析失败、manifest 校验失败、`Import of "<module>" is not allowed` |
| 激活 | `activate()` 抛错、状态机 `ACTIVATING → ERROR`、`WorkerActivateError` / `WorkerTimeoutError` |
| 运行 | 命令执行 500、前端白屏/渲染报错、事件不推送、DB 报错、UI 布局错乱 |
| 停用 / 卸载 | 资源泄漏、`disposeAll` / `revokeAll` 失败 |

### D2. 安装 / 上传阶段

| 现象 | 归因 | 依据 |
|------|------|------|
| `Import of "<module>" is not allowed` | **插件侧** | 产物残留裸导入，违反 token-enforcer 白名单（禁用 `crypto`/`fs`/`path`/第三方裸包） |
| `✖ frontend 产物里有裸模块说明符`（**构建阶段**，3.7.2+） | **插件侧** | `frontend.js` 残留 `from 'x'` / `import 'x'` / `require('x')` / 动态 `import('x')`。沙箱 iframe 无 importmap、无 React，裸说明符无从解析；依赖须内联进 bundle，能力走 `ctx.services.*`。相对/绝对路径放行 |
| 值导入 SDK 符号得到 `undefined`（如 `PluginRuntimeComposition`） | **插件侧** | 3.7.2 起 7 个宿主内部类改为 **type-only** 导出，只能 `import type` |
| manifest 缺失 / 字段非法 / `id` 非 `@scope/name` | **插件侧** | 插件元数据不合规 |
| `engines.openlearn` 高于系统实际版本 | **插件侧** | 声明不兼容，属配置错误而非系统 bug |
| manifest 完全符合当前版本文档却被拒 | **系统侧** | 需引用文档 URL 作为"承诺与实际不符"的证据 |

### D3. 激活阶段

| 现象 | 归因 | 依据 |
|------|------|------|
| 堆栈顶层在 `dist/index.js` | **插件侧** | `activate()` 内未 `try/catch` 的异常逃逸 |
| `TOKEN_NOT_FOUND`，且 `requires` 漏声明 | **插件侧** | manifest 依赖声明缺失 |
| `TOKEN_NOT_FOUND`，`requires` 已声明，但该服务由另一插件经 `manifest.provides` 提供而对方未 ACTIVE | **插件侧 / 插件间依赖** | 跨插件服务依赖未满足（`checkCrossPluginServices`） |
| `TOKEN_NOT_FOUND`，`requires` 已正确声明且提供方已 ACTIVE | **系统侧** | 系统侧 DI 注册缺陷或 Token 名变更 |
| 激活 / 启用插件返回 500，日志 `[WorkerRuntime] Capability denied … no granted capability, only 'get' methods allowed` | **插件侧** | `capabilitiesProposed` 为空（或全部是捏造串），而 `activate()` 调了非 get RPC（`ctx.db.ensureTable` / `actionRegistry.register` / `publish`…）。`effectiveCapabilities` = 声明 ∩ 授予 = 空 ⇒ ServiceHost Barrier 2 拒一切非 get。先跑 L0 看 `CAP_EMPTY_ISOLATED` |
| 同上，但清单已声明**真实**能力 | **环境与配置** | 安装向导里没勾「确认授予清单申请的能力」⇒ 授予集合为空。重装/更新时补勾（无单独审批端点）；仅升级平台重启不会回填 |
| 同上，清单已声明、已确认勾选、且 `activate` 只有 get 调用与订阅 | **系统侧** | 需附 `plugin_capability_grants` 行、`GET /api/plugins` 的 `executionMode`、完整日志后走最小复现 |
| `HANDLER_ALREADY_EXISTS` | **插件侧** | 重复 `registerHandler` 或上次 `deactivate` 未注销 |
| `WorkerCapabilityError`，`requires` 已正确声明 | **系统侧** | 历史缺陷：Worker 下 `ctx.db.migrate` 访问 `plugin_migrations` 被误拦，0.3.16 已修 |
| `WorkerTimeoutError` / `WorkerTransportError` / `WorkerNotSupportedError`，插件为最小实现 | **系统侧** | Worker RPC / 传输层缺陷；`WorkerNotSupportedError` 若文档未标注限制，则为文档缺陷 |
| 状态机卡在 `ACTIVATING` 超过激活超时窗口且无日志（**Inline 5s / Worker 60s**，Worker 可 `ctx.reportProgress()` 滑动续期） | **系统侧** | 激活管道 / 看门狗缺陷 |
| `WorkerActivateError` 且插件代码无明显错误 | **看版本** | ≤0.3.15 存在"激活期 60 秒假超时"缺陷；0.3.16+ 为 5ms 快速失败，属系统侧 |
| 激活报 `checkPluginDependencies` / `checkCrossPluginServices` 失败 | **插件侧** | `manifest.pluginDependencies` 依赖的插件未 ACTIVE，或 `requires` 的服务无人 `provides` |

### D4. 运行阶段

| 现象 | 归因 | 依据 |
|------|------|------|
| `Failed to resolve module specifier "react"`（复合导入/别名） | **看版本** | ≤0.3.15 FrontendPluginHost 转译器缺陷（系统侧）；0.3.16+ 已修复，若仍现查插件 external 配置 |
| `Failed to resolve module specifier "react/jsx-runtime"` | **看版本** | 0.3.15+/0.3.16+ 已纳入宿主共享依赖白名单；更低版本为系统侧（见已知问题索引的版本口径提示） |
| `ReferenceError: React is not defined` | **插件侧** | 未显式 `import React` 或未把 react 标记 external |
| `process is not defined` | **插件侧** | esbuild `platform` 未设为 `browser` |
| `COMMAND_NOT_REGISTERED`（HTTP 403） | **插件侧** | 内核 default-deny：该 commandType 没有在 `actionRegistry` 登记 ActionDescriptor。**只 `registerHandler()` 不 `actionRegistry.register()` 就是这个错** |
| `COMMAND_CAPABILITY_DENIED`，未在 `capabilitiesProposed` 声明 | **插件侧** | 权限声明缺失 |
| `COMMAND_CAPABILITY_DENIED`，已声明且权限名真实存在，但管理员未批准 | **环境与配置** | v0.7.2 起按**已授予**能力集判定，未审批即不放行 |
| `COMMAND_CAPABILITY_DENIED`，已声明、已批准且权限名在矩阵中存在 | **系统侧** | CapabilityGuard 误判或权限矩阵与实现不同步 |
| `empty manifestCapabilities, only 'get' methods allowed`（旧版错误串） | **插件侧** | 同 D3「Capability denied … no granted capability」：声明为空 + activate 调非 get RPC；新版本错误串已改，归因不变 |
| 命令执行 500，堆栈在插件 handler 内 | **插件侧** | 业务逻辑异常 |
| 命令执行 500，堆栈在 CommandBus 管线（Schema/Guard/审计）内且入参合法 | **系统侧** | 管线缺陷 |
| 事件 `publish()` 成功但审计表无记录 / 前端无推送 | **系统侧** | EventBus / 审计 / Socket 缺陷 |
| DB 报命名空间拦截，但表名来自 `ctx.db.table()` | **系统侧** | 命名空间隔离实现缺陷 |
| 白板工具栏布局错乱 / 按钮被挤压 | **插件侧** | 未用 `createPortal(..., document.body)` |
| 仅多插件并存时出现 | **先查插件间冲突** | 命名空间 / 事件名 / 表名 / 槽位 id 撞车；若双方均遵守官方规范仍冲突 → 系统侧（隔离机制缺陷） |
| 仅 worker 模式出现、inline 正常 | **先查插件侧** | Worker 与 Inline 存在**已知且已文档化**的 API 差异（见 §3-W）。插件未适配 → 插件侧 |
| 同上，但插件已按文档适配 Worker 差异 | **系统侧** | Worker RPC 代理缺陷 |
| 抛 `WorkerNotSupportedError`，且该限制未在文档标注 | **系统侧（文档缺陷）** | API 文档未同步 |

#### D4-W. Worker 模式差异速查（判定插件侧 / 系统侧的边界）

下表来自官方 §8.1.1「Worker 与 Inline 模式 API 差异」。**插件违反下表属于插件侧；插件遵守下表仍失败，才可能是系统侧。**

| API | Inline | Worker | 归因提示 |
|-----|--------|--------|---------|
| `ctx.config` / `ctx.provide()` | 可用 | ❌ 不可用 | 插件未做 `typeof` 守卫 → 插件侧 |
| `ctx.services.eventBus` | `subscribe()` / `unsubscribe()` | `subscribe()` / `unsubscribe()`（同名同签名） | — |
| `ctx.services.commandBus.execute()` | 自动加 `manifest.id` 前缀 | **不自动加前缀** | 未手动拼完整 type → 插件侧 |
| `ctx.db.migrate(version, fn)` / `IDatabaseToken` | 同步 `better-sqlite3` | 异步 `prepare().run/get/all`（**无** `exec()`、**无** `transaction`） | 用同步写法或 `transaction` → 插件侧 |
| `ctx.db.table()` | 返回 `plugin_<安装行UUID>_` 前缀 | 同左（**两模式已统一**，切模式不再改变表名） | 切模式后表名变化 → 多半是别的插件/别的实例 |
| `ctx.http` | 完整 | 完整（RPC 跨进程，5000ms 熔断） | — |
| `ctx.pluginId` | 安装行 UUID | 同左（`ctx.manifest.id` 才是 manifest ID） | 用它拼持久化键会不一致 → 插件侧 |
| `child_process` / `worker_threads` / `eval` | 可用 | ❌ 全部禁止（Node permission model 不提供 `--allow-child-process` / `--allow-worker`，并禁止字符串代码生成） | 触碰被禁 API → 插件侧 |
| 出站网络 | 不受限 | 默认拒绝；仅管理员批准的域名由宿主代发（`plugin_network_grants`） | 直接 `fetch` 外网 → 插件侧 |

#### D4-UI. 教师端点了有反应，学生端看不到 / 自定义界面不出现

按「渲染链路」从数据到容器逐层排查，**每层都能单独导致空白，且宿主不会报错**。

**先按这个顺序收敛，别按表格从上往下一路读**（表格是「有哪些层」，不是「先查哪层」）：

```bash
# 第 1 步：一条命令同时查「入口门槛 / DB 落库 / 静态文件」
# 脚本在 skill 的 scripts/ 下；在插件项目里运行时用绝对路径
bash <skill>/scripts/post-install-check.sh <manifest.id> --zip <刚上传的.zip>
```

| 顺序 | 查什么 | 一条命令命中 | 为什么排这个位置 |
|------|--------|--------------|------------------|
| **① ** | `frontend.js` 是否在包里、`view` 是否被 strip、静态文件是否落盘 | `post-install-check.sh` | 这三件事**运行期全部静默**：无 500、无异常日志、只有「入口不出现」。先排除它们，能一次省掉后面所有层 |
| ② | 宿主日志有无 `404 /plugins/{id}/frontend.js` | `curl -I localhost:9000/plugins/{id}/frontend.js` | 与①同源，用于确认「装了但没激活成功」 |
| ③ | 通道与执行模式是否匹配（process 只能声明式或 `view`） | 对照 §下表第 5 层 / `static-check.mjs` | 结构对了还不显示，多半是通道选错 |
| ④ | 权限、审批、渲染器求值 | §下表第 7–8 层 | 到这一步才需要读平台源码 |

> **判别口诀**：若「**所有**声明式入口（页签 + 浮层 + 挂件）**同时**消失，且日志无报错」→ 几乎一定是
> ①的 `frontend.js` 缺失（宿主 `fetch` 抛错，`registerManifestContributions` 根本没执行）。
> 若只有**某一个槽位**不显示、其它正常 → 才轮到 `view` 被 strip（④⑤层）或该槽位的渲染分支。

| 检查点 | 典型现象 | 归因 | 证据/动作 |
|--------|---------|------|----------|
| 1. handler 是否真的写了共享状态 | 命令返回 `{opened:true}` 但白板无元素 | **插件侧** | 看 handler 是否派发 `whiteboard.draw` / 写 DB / 发事件；L2 契约用例可直接抓。<br>⚠️ **高危禁忌**：子进程严禁直写 SQL 操作 `whiteboard_elements`（`sql-guard` 拦截）；必须调 `commandBus.execute` 或在 `manifest.classroomTools` 直配 `whiteboard.draw` |
| 2. 写入命令用对没有 | 元素存在但类型不对 | **插件侧** | 白板挂件必须 `whiteboard.draw` + `type:'plugin'` + `data` 为 JSON 字符串（含 teacherWidgetId/studentWidgetId） |
| 3. widget id 是否成对且一致 | 「组件 [x] 正在加载或未启用…」 | **插件侧** | `data.teacherWidgetId` / `data.studentWidgetId` 与扩展点 `id` 逐字符比对 |
| 4. 是否声明了学生侧容器 | 学生端完全没有位置 | **插件侧** | 白板挂件要 `teacher.dashboard.widget` + `student.view`；页面级 UI 要 `view` |
| 4b. 有没有 `dist/frontend.js` | **所有入口都不出现，且日志无 404** | **插件侧（打包）** | 宿主按 `has_frontend` 跳过激活，贡献注册在 fetch 之后；补空 `src/frontend.tsx`。L0 `FRONTEND_ENTRY_MISSING` |
| 4c. DB 里声明的 `view` 是否被 strip | `teacher.tab` 丢 view、overlay 保留 | **环境（安装时 schema 旧）** | 安装时平台 < v0.7.7；升级后需**重新安装**，重启不回填 |
| 5. 通道与执行模式是否匹配 | 注册了 component 却永不渲染 | **插件侧** | process 只能声明式或 `view`（白板卡片配置 `view` 在 v0.7.7+ 亦可直接渲染）；React 组件必须 inline（白名单） |
| 6. `view` 页面是否可达 | 面板空白 / 「非法的插件视图路径」 | **插件侧（打包/路径）** | `storage/**` 是否进 ZIP；`view` 是否相对路径且无 `..`；是否引 `/plugin-sandbox/view-bridge.js` |
| 7. 权限是否授予 | 命令 403 / 元素写不进 | **环境与配置** | `whiteboard:write` 等是否声明 + 管理员批准（v0.7.2 起按已授予集合） |
| 8. 浮层是否挤占了主白板 Flex 流 | 学生端浮层一出，上课白板变 0 宽消失 | **插件侧 / 宿主** | `student.classroom.overlay` 必须使用 `floating` 定位，不得写撑满整屏的块级面板；展开/折叠务必调 `bridge.ui.resize()` |
| 9. 课堂上下文是否防御性降级 | 提示「暂无活跃班级上下文」 | **插件侧** | 单课未排班时 `classId` 为 undefined，代码缺少 `classId || 'default'` 兜底 |
| 10. 是否存在高频写请求触发 429 | 控制台 429 / 教师全班锁屏失效 | **插件侧 / 环境** | 轮询过密（<3s）或无防抖写接口耗尽写限流池；必须加去重与防抖 |
| 11. 以上都对仍不渲染 | 宿主渲染器/白名单求值异常 | **待定 → 系统侧** | 取 `GET /api/plugins` 的 `executionMode`、`x-request-id`、完整 console，做最小复现 |

> 快速自查脚本：`node test-harness/static-check.mjs .`（槽位/模式/白板/`view` 全查）、
> `OPENLEARN_TRUSTED_INLINE_PLUGINS='@scope/*' node test-harness/static-check.mjs .`（白名单校验）。
> 完整契约见 `references/ui-channel-decision.md`。

### D5. 停用 / 卸载阶段

| 现象 | 归因 |
|------|------|
| 定时器 / EventBus 订阅 / 后台进程未清理（内存或重复监听） | **插件侧**（`deactivate()` 未执行清理 SOP；注意宿主已自动注销 handler / 退订事件，插件只需处理自建资源） |
| `disposeAll` / `revokeAll` 抛错 | **系统侧** |

### D6. 归因前置的环境排除项

先排除以下"假 bug"，否则会误判为系统侧：

- [ ] **版本不匹配**：插件 `engines.openlearn` 或所用 API 的最低版本与系统不符（例：`ctx.reportProgress` 需 0.3.16+，`ctx.require` 需较新版本）。
- [ ] **未重新构建**：`dist/` 是旧产物；改完源码没跑 `npx @openlearn/plugin-sdk build`。
- [ ] **浏览器 / CDN 缓存**：前端 `frontend.js` 是旧版本；强刷或换无痕窗口复测。
- [ ] **热重载未生效**：开发模式文件监听未触发，需手动停用→激活。
- [ ] **权限未审批**：高危能力挂在 `pending_commands` 审批表里尚未批准。
- [ ] **多插件干扰**：停用其他插件后复测。
- [ ] **执行模式差异**：问题是否只在 worker / process 模式出现？v0.7.0 起第三方插件被强制以 `process` 子进程运行，先对照 §D4-W 排查插件是否触碰了被禁 API（`ctx.config`、`ctx.provide()`、`child_process`、`worker_threads`、`eval`、直接出网）。
- [ ] **默认拒绝的 ActionDescriptor**：命令是否在 `actionRegistry` 登记过描述符？未登记 → `COMMAND_NOT_REGISTERED`，属插件侧。
- [ ] **远程前端误用 React**：前端插件是否 import 了 React / 用了 DOM？远程插件前端跑在隐藏 iframe 内，用 React **必然激活失败**。
- [ ] **表名变化**：`ctx.db.table()` 前缀在两种模式下已统一为 `plugin_<安装行UUID>_`，切模式后表名变化**不再是预期行为**，应按真实问题排查。

---

## 4. "系统侧"的最小证据门槛

**判定为系统侧并生成 bug 报告，必须同时满足以下 4 条。** 任一条不满足 → 结论只能是"待定"，并列出缺哪条。

1. 能用**官方脚手架原始产物**或**最小复现插件**（建议 ≤50 行：仅 manifest + 空 `activate`）在相同系统版本、相同 `execution_mode` 下**稳定复现**。
2. 已提供具体版本号、完整复现步骤、完整错误堆栈。
3. 报错点位于宿主 / 内核 / SDK / 文档承诺范围内，**而非插件自身代码或构建配置**。
4. 已排除 D6 的全部环境项，并排除了插件间冲突。

> ⚠️ 反例：插件自己 `import { randomUUID } from 'crypto'` 被 token-enforcer 拦截，这是**插件侧**违规，不是系统 bug——即使错误信息由系统打印。

---

## 5. 对照实验 SOP（最小复现）

```
步骤 1  用 server-only 模板生成最小插件：只保留 manifest + 空 activate()
步骤 2  保持与故障插件相同的：系统版本、execution_mode、权限声明、扩展槽位声明
步骤 3  上传激活，观察结果
```

| 实验结果 | 结论 |
|---------|------|
| 最小插件也失败 | **系统侧** → 用 D2/D3/D4 精确定位，附上最小插件代码 |
| 最小插件正常，加回故障代码后失败 | **插件侧** → 二分定位到具体代码块 |
| 最小插件正常，停用其他插件后故障插件也正常 | **插件间冲突** → 定位撞车点 |
| 最小插件正常，且停用其他插件也无效 | 回到 D6，补充环境信息 |

**记录模板**：每次实验记下「系统版本 / 插件版本 / execution_mode / 实验内容 / 结果」。这些记录直接填入 bug 报告的「已排除项」一节，是说服作者的关键。

---

## 6. 已知系统问题索引（历史）

匹配到下表已修复条目 → 结论为**系统侧（旧版本缺陷）**，建议升级到修复版本即可，**不必**开新 bug；若在修复版本上仍复现 → 属新缺陷，生成报告。

| 影响版本 | 现象 / 报错 | 性质 | 状态 |
|---------|------------|------|------|
| ≤0.3.15 | 前端 `TypeError: Failed to resolve module specifier "react"`（复合导入、`as` 别名、命名空间导入） | FrontendPluginHost 转译器缺陷 | **0.3.16 已修复** |
| ≤0.3.15 | Worker 激活期异常导致 **60 秒假超时**、看门狗误熔断/重启风暴 | WorkerRuntime 缺陷 | **0.3.16 已修复**（改为 5ms fail-fast） |
| ≤0.3.15 | Worker 下 `ctx.db.migrate` 初始化版本表报 `WorkerCapabilityError`（`plugin_migrations` DDL 被拦） | ServiceHost 白名单缺陷 | **0.3.16 已修复** |
| ≤0.3.15 | Worker 内异步 DDL 未 `await` → 未捕获 Promise Rejection → 进程退出 + 看门狗重启循环 | Worker `dbWrapper` 缺陷 | **0.3.16 已修复** |
| ≤0.3.14 | `react/jsx-runtime` 不被宿主共享依赖支持（现代 `"jsx": "react-jsx"` 产物报错） | HostSharedDeps 白名单不足 | **已修复**（白名单 4 → 6）<br>⚠️ 修复版本口径不一：`tutorial §6.7` 与 `architecture` 记 **0.3.15+**，Release Notes v0.3.16 将扩充白名单列为修复项。归因时以 Release Notes 为准 |
| ≤0.3.12 | `npx openlearn-next` 报 `EUNSUPPORTEDPROTOCOL workspace:*` | 制品打包协议缺陷 | **0.3.13 已修复** |
| ≤0.3.13 | `[PluginHost] xlsx not available (optional)` 告警 | 依赖声明缺陷 | **0.3.14 已修复** |
| ≤0.7.0 | 官方 CLI 构建的远程前端插件一旦用到 React/JSX → 激活失败 `Cannot read properties of undefined (reading 'React')` | SDK CLI 前端 externals 预置硬编码 + 沙箱 realm 隔离 | **文档已在 v0.7.0 勘误**（事项 B 落地）；但 CLI externals 可配置仍待立项（事项 E）—— **写法侧正解是不写 React** |
| ≤0.7.0 | 远程插件 `registerExtensionPoint` 传 `component` → `DataCloneError` → 激活失败 | postMessage 无法克隆函数 | **不是 bug，是产品边界**；正解是走声明式贡献 |
| ≤0.6.x | 熔断 / 激活失败时 manifest 声明式贡献「闪现后消失」 | 缺少显式错误态 | **0.7.0 已修复**（事项 A 落地） |
| ≤0.4.1 | 插件更新后前端不生效：宿主 EsmLoader 对 `data:` URL 热重载无法解析裸导入 | EsmLoader 缺陷 | **需重启服务器**绕过（0.4.0 已知问题） |
| ≤0.4.1 | 课堂中高频写操作偶发 429 | `writeLimiter` 60 写/分钟/IP 偏紧 | 0.4.0 已知问题，**属环境与配置**，批量写需降频 |
| ≤0.4.1 | 扩展点渲染连续报错后插件被自动停用 | 熔断器（3 次 / 5 分钟滑窗） | 0.4.2 引入的**设计行为**，不是缺陷 |
| ≤0.7.1 | `auth: false` 的路由仍返回 401 | `auth:false` 只是**申请**公开，需管理员批准 | 0.7.0 起的**设计行为**，见 Release Notes v0.7.0 §八.2 |
| ≤0.7.1 | 插件代码相对导入逃出插件目录 | ESM loader 边界 | 0.7.2 已收紧（Issue #218），越界导入被拒属**插件侧** |
| ≤0.7.1 | 声明了权限但运行期仍被拒 | 能力判定改为按**已授予**集合（Issue #224） | 0.7.2 起的**设计行为**，需管理员审批 |
| 0.7.6–0.7.7 | 无 `frontend.js` 的插件：`contributes` / `view` 全部不注册，插件状态正常、日志无 404 | 前端 `has_frontend` 门禁 + 贡献注册排在 fetch 之后 | **已提 Issue [#350](https://github.com/aymwoo/OpenLearn-Next-V2/issues/350)**；临时解法：补空 `src/frontend.tsx` |
| 3.6.0–3.7.4（SDK） | 第三方 `import('@openlearn/plugin-sdk')` / `import { createMockContext }` 报 `ERR_MODULE_NOT_FOUND: Cannot find package 'uuid'` | SDK 打包依赖缺陷（dist 含 `from "uuid"` 但未声明） | **已提 Issue [#349](https://github.com/aymwoo/OpenLearn-Next-V2/issues/349)**；临时解法 `npm i -D uuid zod` |
| 0.7.3 | `npm i openlearn-next@0.7.3` 报 `EUNSUPPORTEDPROTOCOL workspace:*` | 制品协议缺陷 | **该版本已弃用**，升到 0.7.4 |

> 该表需在每次缓存探活时对照最新 Release Notes 维护。

> ⚠️ **归因引用规范**：引用「文档承诺」时，必须写明来源页及其版本状态。官方文档存在页与页之间版本口径不一致的情况，
> **Release Notes 是版本事实的单一真理源，平台源码是最终真理**。
> 注意区分「**系统缺陷**」与「**产品边界 / 设计行为**」：后者（如 remote 插件无 UI、熔断自动停用、auth:false 需审批）
> 不该开 bug，而应改成插件写法或告知用户操作路径。

---

## 7. 输出规范

### 7.1 对话内的简要汇总（必给，≤10 行）

```
【故障归因】系统侧（或：插件侧 / 插件间冲突 / 环境与配置 / 产品边界 / 待定）
现象：<一句话>
关键证据：
  1. <堆栈归属 / 版本核对 / 对照实验>
  2. ...
判定依据：<为什么是这一类，而非另一类>
建议动作：<修复方式 或 生成 bug 报告 或 提 Issue>
```

> 用户问「是插件的问题还是平台插件系统的问题」时，**必须落到上表 6 类之一**，并同时说清**缘由**：
> 哪一处机制导致的（默认丢包、白名单、沙箱、熔断、审批），而不是只给一个标签。

### 7.2 系统侧 → ① 生成本地 Bug 报告文档

- **模板**：`assets/bug-report-template.md`
- **落盘路径**：插件项目根目录，文件名 `BUG-REPORT-<slug>-<YYYYMMDD>.md`
  - `<slug>`：问题英文短名，如 `worker-migrate-capability-denied`
  - 日期取当前日期，如 `20260918`
- 生成后告知用户：该文件可直接发给系统作者；并提示把「最小复现插件」一并附上。

### 7.3 系统侧 → ② 向平台仓库提交 Issue（推荐，与①并行）

仓库：`aymwoo/OpenLearn-Next-V2`（缺陷 Issue 用前缀 `[缺陷] `，标签 `bug` + `needs-triage`）

**提交前三个门禁（缺一不提）**

1. 已满足第 4 节的 4 条「系统侧」证据门槛（尤其最小复现稳定复现）；
2. 已去重：仓库既有 issue（**含已关闭**）+ `docs/beta/known-issues.md`；命中已修复版本 → 建议升级；命中开放 issue → 改为补充评论；
3. 用户已看过完整标题与正文并**明确同意**——Issue 对仓库可读者公开可见，**不得静默提交**。

```bash
REPO=aymwoo/OpenLearn-Next-V2
gh issue list -R "$REPO" --state all --limit 50 \
  --search "<错误号/错误文案/模块名> in:title,body" --json number,title,state,url
rg -n "<关键词>" ~/Develop/openlearnv2/docs/beta/known-issues.md

gh auth status   # 确认 gh 已登录且对该仓库有权限

gh issue create -R "$REPO" \
  --title "[缺陷] <模块/组件>：<一句话现象>" \
  --body-file /tmp/openlearn-issue-<slug>.md \
  --label bug --label needs-triage
```

**正文三段必备**（模板 `assets/platform-issue-template.md`）

| 段 | 必须写清 |
|----|---------|
| `## 问题原因` | 具体包/文件/机制 + 触发链 + 版本口径 + 关键堆栈帧 |
| `## 影响` | 受影响对象 + 阻塞程度 + 影响版本范围 + 触发概率 + 连带影响 + 临时规避 |
| `## 建议解决方式` | 建议改动点 + 方案与权衡 + **验收标准** |

另附：环境信息（含仓库表单要求项：报告人角色=开发者、对上课的影响、版本）、复现步骤与稳定性、期望 vs 实际（附文档 URL）、
完整堆栈（不截断）、最小复现插件源码、归因证据与对照实验、已排除项、脱敏确认。

**脱敏红线**（issue 公开可见）：禁学生全名册 / 作业试卷原文 / 成绩导出 / 密码 · 班级临时口令 · Cookie · `edu_os_token` /
AI API Key（含首尾掩码）/ `.env` · `ENCRYPTION_KEY` · `bootstrap-credentials.txt` / 身份证 · 住址 · 电话 · 健康信息。
定位请求只写 `x-request-id`；指代学生用「3 班第 2 次作业」。

**幂等与失败**：同问题已有自己的开放 issue → 补充评论不开新单；`gh` 未登录/无权限/429 → 不重试刷屏，保留已渲染的正文文件，
给出手动入口 `https://github.com/aymwoo/OpenLearn-Next-V2/issues/new`。

**上报后输出**：

```
【系统侧缺陷已上报】Issue #<n> <url>
原因：<机制层一句话>
影响：<影响面 + 阻塞程度 + 规避>
建议：<修复方向>
本地留存：<BUG-REPORT-*.md 路径>
```

### 7.4 插件侧 / 产品边界 → 不生成报告、不提 Issue

给出具体修改点，并按 SKILL.md「第四步」的预检清单复查；产品边界类要明确告知用户「这是设计行为」，不是缺陷。

### 7.5 待定 → 不生成报告、不提 Issue

列出缺失的证据项（对照第 2 节清单），并给出用户可自行执行的取证命令。

---

## 来源

- 故障排查与 FAQ：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/troubleshooting/troubleshooting-faq.html
- 插件宿主架构：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-architecture.html
- 插件生命周期：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-lifecycle.html
- Manifest 规范：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-manifest-spec.html
- 安全与权限：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/architecture/security-permissions.html
- 能力权限矩阵：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-capability-matrix.html
- 信任边界矩阵：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-trust-boundary.html
- 前端沙箱能力边界：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/frontend-sandbox-capability-boundary.html
- UI 扩展槽位：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-ui-extension-slots.html
- Release Notes v0.7.7 / v0.7.6 / v0.7.5 / v0.7.4 / v0.7.3 / v0.7.2 / v0.7.1 / v0.7.0 / v0.6.x / v0.4.x（已知系统缺陷来源）
- 版本迁移指南：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/migration/version-migration.html
- 平台源码（一手真理）：`~/Develop/openlearnv2/packages/core/`、`~/Develop/openlearnv2/packages/plugin-sdk/`
