# Changelog

本仓库所有值得记录的变更都写在这里。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
版本通过 git tag（`vX.Y.Z`）发布。

## [2.13.0] - 2026-10-29

新增一条面向课堂场景的 UI 约束：**中文文本最小 13px**。11/12px 在教室投影和白板上不可读，
但 CSS 不报错、L1 也不会失败，属于「能跑但看不清」的静默问题 —— 因此同时落成 Guardrail 与 L0 规则。

### 新增

- **Guardrail 13「中文文本字号 ≥ 13px」**：面向师生的正文 / 标签 / 按钮文本不得小于 13px；
  覆盖 `view` 页面（`<style>`、行内 `style`、`el.style.fontSize`）与 inline React
  （`fontSize` 数值 / 字符串、Tailwind `text-xs` / `text-[12px]`）。纯图标 / 装饰可用同行注释
  `font-size-ok` 豁免；`calc()` 无法静态求值，留给 L1 / 目检。
- **L0 `FONT_TOO_SMALL`**（`static-check.mjs` §7a）：`font-size` / `font` 简写 / JS 动态设置逐条检查，
  `rem` / `em` / `pt` 统一换算成 px，`clamp()` 取最小值；inline React 另查 `fontSize` 与 Tailwind 字号类。
- `verify-test-harness.sh` 新增反例 3h：同一 fixture 的 `font` 简写、`fontSize: 12`、`text-xs`
  三处必须全部命中；给 `font-size-ok` 后必须完全静默。自检 72 → **76 通过 0 失败**。

### 变更

- 模板里过小的 11px 作者标签改为 13px（`sandbox-view` 学生 / 教师页、`inline-react` 组件），
  视觉层级改由颜色承担 —— 否则模板自己就违反新规则。
- 文档同步：SKILL.md（Guardrail 13 / 完成定义 / 交付格式「已核对」）、
  `references/testing-strategy.md`（Guardrail→用例映射第 13 行）、
  `references/ui-channel-decision.md`（inline 要点 + view 桥接 API 旁）、`assets/test-harness/README.md`。

## [2.12.0] - 2026-10-29

用 skill 自身去修一个真实插件（`lab-help`）时，发现 skill 里有一条**把违法写法写成正解**的结论 ——
按它写出来的代码在真实平台上必然静默失败。本次按「写代码 → 跑护栏 → 反查 skill」的顺序纠正。

### 修正（错的是 skill，不是插件）

- **`frontend-bridge-0.7.md` 让学生端去查 `classroom_sessions`** —— 那是 SQL 黑名单表，
  直查被 `assertDatabaseAccessAllowed` 拒绝，`catch` 一吃掉就只剩「还没进入课堂」这种无从排查的表现。
  已改为：课堂上下文只认宿主注入的 `lessonId` / `classId`；缺参数时明确拒绝（409 / `active:false`）。
  平台也没有「查当前进行中课堂」的命令，**不能猜**。
- **「`lessonId` / `classId` 在学生端常为空」是错的**（至少在浮层槽位）：
  `PluginSandboxIframeView` 是 `propLessonId !== undefined ? propLessonId : storeLessonId`，
  `student.classroom.overlay` 的 slotProps 显式传 `{ studentId, studentName, lessonId, classId }`
  —— 那就是学生当前课堂，可直接信。只有走通用循环的页面级槽位才退回教师侧 store。
- **桥接上下文不是「没有 studentId」**：init 载荷含 `studentId` / `studentName`（学生侧槽位有值）。
  身份解析不要再假设「会话 userId === students.id」——学生用学号登录时它就是学号，
  应按名册先比 `id`、再比 `student_number`。

### 事实台账（26 → 27 条）

- `view-context-from-teacher-store` → **`view-context-props-override-store`**：
  claim/impact 全部重写，锚点换成 `PluginSandboxIframeView.tsx` + `StudentInteractiveOverlay.tsx`
  （旧锚点是 `context.get` 的实现，本身没消失，所以只查存在性发现不了这个错）。
- 新增 `roster-command-skips-owner-check`：`class.get_students` 的归属校验只对
  `user:<id>:<role>` 形式的 actorId 生效，插件以 `plugin:<manifest.id>` 执行时直接放行 ——
  **越权挡板得插件自己装**（教师限角色、学生要求在该班名册内）。

### 配套

- 同上一条命令的权限口径写清：`capabilitiesProposed` 要含 `management:read`，且宿主是把能力授予
  `plugin:<manifest.id>` 这个 actorId（不是 `ctx.pluginId` 的 DB UUID）。

## [2.11.0] - 2026-10-29

平台一次跨版本变更把 skill 的几条结论**变成了错的**，另有一次「护栏假装在工作」。
本次以平台 `584eb0e` 为基线重新裁决全部事实。

### 背景

- **#350**：`registerManifestContributions` 前移到 `fetch(frontend.js)` 之前，`hasFrontend=false`
  的插件直接置 `ACTIVE` 且不发请求 —— skill 里「缺 frontend.js → 所有入口消失」的因果链**整体失效**。
- **#349**：SDK 升到 `3.7.5`（npm 仍 `3.7.4`），新增 frontend 裸说明符硬拦截。
- **#358**：平台自带 AI Agent 手册与**机器可读契约**（`docs/agent/contracts/*.json` +
  `audit-tools/agent_facts.py --check`），并与本 skill 的事实表大范围重叠。
- 平台 `version` 仍是 `0.7.7`：行为变了但没升号，**版本号不能用来判断行为**。

### 新增

- `scripts/facts-check.sh` 支持**顺序断言**（`sources[].before`）：锚点存在但先后关系反了也算漂移。
  这是 `#350` 暴露的盲区——旧实现只查「字符串在不在」，顺序反转照旧全绿（已用反例验证会 ✖ 且退出码 1）。
- `scripts/facts-check.sh` 输出 **SDK 双版本行**（仓库 vs npm），并支持 `FACTS_FILE` 覆盖。
- `integration-facts.json`：`frontend-fetch-before-register` → **`frontend-register-before-fetch`**（带顺序断言）；
  新增 `official-contracts-doc`（官方契约文档锚点）与 **`process-db-shim-is-guarded`**
  （`resolve(IDatabaseToken)` 的 `prepare` 垫片同样过 sql-guard，核心表读不到）。
  元数据补 `platformCommit` / `sdkVersionInRepo` / `versionNote`。
- L0 `static-check.mjs` 支持**路由别名**识别：`const get = (p, h) => ctx.http.get(p, h)` 之后的
  `get(/x, h)` 不再被判成「未注册」（真实插件上曾因此假报 9 条 404）。
- SKILL.md 开头新增「平台已自带机器可读源」优先级表（源码 > `contracts/*.json`/facts-ledger > 平台 docs/ > 本 skill 快照）。
- SKILL.md 第六步 **B2″**：提 Issue 前先查官方契约与 facts-ledger，避免把**设计行为**报成缺陷。
- 探测命令补 `docs/agent/contracts/versions.json` 与 `agent_facts.py --check`。

### 变更（纠正错误结论）

| 原结论 | 现结论 |
|---|---|
| 缺 `frontend.js` → 所有 `contributes` 不注册、入口全消失 | **只影响隐藏前端逻辑**；入口照常显示。入口全消失先查安装期 schema strip |
| `student.view` 是页面级（`w-full h-full`） | 是 `WhiteboardWidget`（白板卡片 / 学生工作台 widget），官方 §1.1.1 的 `layoutVariant` 四类为准 |
| 槽位 122 个 | **120** 个（抽取 bug：`AnchorSlot` 的 JSDoc 里 `placement: before/after` 被当成槽位） |
| `capabilityRequired` 20 条 | **19** 条；`ai:invoke` 属第 3 套 `runtime_permission`，不是 RBAC |
| test-kit 3.3.1 | **3.3.3**（npm 与仓库一致，文档页滞后） |
| frame 桥接 9 个 op | **10** 个（名单本来就全，数字数错了） |
| 浮层修复「平台 v0.7.8+」 | **v0.7.7 已修**（commit `6e00ca3`），官方已写成 `FloatingOverlay` 铁律 |

同时把 `post-install-check.sh` 的 `frontend.js` 检查与 L0 `FRONTEND_ENTRY_MISSING`
从**失败**降为**提醒**——否则纯 `view` 插件会被自己的护栏误杀。完成定义改按 `layoutVariant`
四类（Panel / WhiteboardWidget / FloatingOverlay / ActionItem）分别验证。

### 修复

- `platform-drift-check.sh` 槽位抽取**先剥注释**，并优先读平台机器抽取结果 `docs/agent/contracts/slots.json`；
  两处不一致时以机器抽取为准并打印差异。`slot-registry.json` 随之重生成（120 个，5 个 view 槽位）。
- CHANGELOG 中 `2.10.0` 段落排到了 `2.9.0` 下方，已按版本倒序归位。
- L0 SQL 表名抽取把 `ON CONFLICT ... DO UPDATE SET` 的 `SET` 当成表名，已加关键字排除。
- 移除正文里新出现的硬编码数字（槽位/权限/op 数量），改指机器可读文件。

## [2.10.0] - 2026-10-29

把「装上了 ≠ 贡献点注册了」变成可执行自检，并纠正两处会**主动误导**的判断。

起因是一次真实交付：教师页签不出现、学生浮层挤掉白板、已进课堂却提示未进入，连续三轮才定位。
事后复盘发现 `integration-facts.json` 全绿也拦不住这三件事——因为它们只写成了散文，没写成断言。

### 新增

- **`scripts/post-install-check.sh`**：安装后 60 秒自检。一次核对
  ① `frontend.js` 是否在 ZIP 内并落盘（当时认为缺失即致命；**2.11.0 已修正**：`#350` 后只影响隐藏前端逻辑）
  ② DB 里 `manifest` 是否保住每个 `view`（与 ZIP 内 `manifest.json` 逐槽位比对，直接检出被 strip 的字段）
  ③ `view` 是否在 `storage/` 下且文件真实存在 ④ 状态/执行模式。
  有 ✖ 时给出「重新上传安装（不是重新激活）+ 改过平台源码先重启」的修复指引。已在真实环境跑通正例与反例。
- `references/integration-facts.json` 新增 2 条可断言事实：
  `install-schema-strips-view`（落库按安装期 schema 解析、激活不重解析）、
  `view-context-from-teacher-store`（`lessonId`/`classId` 来自教师侧 `selectedLesson`）。
- SKILL.md 第五步新增「7. 装完立刻自检」，完成定义与交付格式同步增加自检项。
- SKILL.md 第六步 B2′：schema / 渲染器 / 解析器类缺陷**必须在平台仓库补回归用例**，含 `it.each` 覆盖全部槽位的骨架
  （本次给平台补 7 例，才真正防住 `view` 再次被 strip）。
- 第一步开头「开工前 30 秒」环境前提：真实端口（**9000**，不要猜 3000/5173）、DB 路径
  `packages/core/db/educational_os.db`、安装目录 `plugins/{安装行UUID}`、`/tmp` 小容量导致 vitest 批量假失败的
  `TMPDIR` 处理。

### 变更

- `references/scaffold.md`：「热重载…**无需重启**」是本次最大的误导源，替换为**生效矩阵**——改平台源码 / 重装 ZIP /
  改前端资源 / 换 executionMode 分别需要重启、重新安装、停用激活、强刷中的哪几项。
- `references/troubleshooting.md` §D4-UI：表格前增加**收敛顺序**（先跑自检脚本 → 再看 404 → 才轮到通道/渲染器），
  并给出判别口诀：全部入口同时消失且日志静默 ≈ `frontend.js` 缺失；只有单槽位不显示 ≈ `view` 被 strip。
- SKILL.md 版本口径拆成两句：**模板/API 面以 npm 为准，运行时行为以本地 HEAD 为准**。原口径对「本地 dev 用旧 schema」
  这类问题完全失效。
- 完成定义中「可见入口已验证」按**页面级 / 浮层级 / 白板挂件**拆成三条；浮层单独加「宿主主内容不得被挤占」。
- 移除正文里硬编码的事实条目数（原为 19/18 两处互相矛盾），改为以脚本输出为准，避免与 json 再次漂移。

### 修复

- **`verify-test-harness.sh` 与 `platform-drift-check.sh` 的进程替换 `< <(...)` 在受限环境静默失效**
  （容器 / 沙箱不提供 `/dev/fd`）。前者使模板占位符根本没被替换 → `inline-react` 假报 L0 失败（71 通过 1 失败）；
  后者使槽位列表为空 → 漂移检测逐条误报。改用管道 `find -print0 | while read -d ''` 与
  命令替换 + 参数展开，自检恢复 **72 通过 0 失败**，漂移检测正常输出（当时报「槽位 122」，实为抽取 bug，2.11.0 修正为 120）。
  这类「护栏自己坏了却假装在工作」的问题与本次主题同源，一并修掉。

## [2.9.0] - 2026-10-29

补上「插件装得上、一启用就 500」的最大一类：process 隔离模式下的**空能力门禁**（ServiceHost Barrier 2）。

### 背景

第三方 ZIP 插件被强制以 `process` 运行；`capabilitiesProposed` 声明为空（或管理员未勾选授予）时，
`effectiveCapabilities` 为空集，`ServiceHost.handleInvoke` 拒绝**一切非 get RPC**。
`activate()` 里只要有一句 `ctx.db.ensureTable` / `actionRegistry.register` / `eventBus.publish`，
启用插件就是 HTTP 500：`[WorkerRuntime] Capability denied … no granted capability, only 'get' methods allowed`。
此前 skill 只在错误码表里提了旧版错误串，L0 只校验「权限串是否真实」、不校验「是否为空」，
Mock 也不模拟这道门禁 —— 于是声明缺失在生产才炸。

### 新增

- **L0 `CAP_EMPTY_ISOLATED`**（`static-check.mjs` 7e）：隔离模式（process / worker / 非白名单 inline）
  且 `capabilitiesProposed` 为空时，扫描 `activate` 期非 get RPC 调用
  （`ensureTable` / `migrate` / `registerHandler` / `register` / `publish` / `set` / `delete` /
  `generateText` / `spawn` / `ctx.resolve(IDatabaseToken)`…）并报 error；
  纯前端桥接（只 `ctx.http.*` + `ctx.db.table()` + subscribe）不误报。
- **L1 Barrier 2 模拟**（`contract.test.ts`）：空能力时用 Proxy 录制 `activate` 期间对
  `ctx.services.*` / `ctx.db` 的调用，非 get 且不在豁免名单（`eventBus.subscribe/unsubscribe`、`db.table`）即失败。
- **集成事实** `worker-barrier-2-empty-caps`（事实表 18 → 19）：`effectiveCapabilities = 声明 ∩ 授予`、
  管理员勾选 `x-approve-capabilities` 才授予、豁免清单，全部带 `service-host.ts` / `lifecycle.ts` / `plugins.ts` 锚点。
- `verify-test-harness.sh` 新增空能力反例（拦截 + 补能力后放行 + 纯前端不误报），自检 66 → 72。

### 变更

- SKILL.md：新增 Guardrail 12（隔离模式能力门禁）；`capabilitiesProposed` 字段说明改为「申请而非授予」；
  第五步安装流程加入「勾选确认授予」；完成定义、L0/L1 能力描述、错误码表同步。
- `references/manifest-0.7.md` §3.1：Barrier 2 语义、豁免方法、最小声明规则、开发期拦截手段。
- `references/testing-strategy.md`：必测矩阵新增隔离模式行；Guardrail 映射补 9–12 条；
  Mock 差异表标注「Mock 不模拟 Barrier 2」。
- `references/troubleshooting.md` D3：激活期 `Capability denied … only 'get' methods allowed` 的
  插件侧 / 环境配置 / 系统侧三档归因。

## [2.8.0] - 2026-10-28

新增「生成即正确」的脚手架与 L1 视图冒烟，把 sandbox-view 的两个高频手工错误挡在本地。

### 新增

- **`scripts/new-plugin.sh`**：`bash scripts/new-plugin.sh <模板> <目录> --id @scope/name [...]`
  复制五套模板并替换**全部**占位符（官方 CLI `init` 只替换一部分）；校验 pluginId / 命令前缀，
  拒绝覆盖非空目录（`--force`），不执行 `npm i` / build。
- **`assets/test-harness/view-smoke.test.ts`**（L1）：jsdom 加载 `storage/**/*.html`，注入与平台
  `server/utils/plugin-view-bridge.ts` 同形的假桥接，断言 `onInit` 已注册、init 后真的发出
  `invokeCommand` / `api.*`、误用 `alert/confirm/fetch` 会失败、高度自适应真的调用 `bridge.ui.resize`。
  未安装 jsdom 时整组跳过，不影响其它用例。
- `check-templates.sh` 增加「生成器覆盖全部占位符 / view 冒烟存在」；
  `verify-test-harness.sh` 增加生成器实测与 view 冒烟骨架，自检 60 → 66。

### 变更

- SKILL.md 第三步给出「一条命令生成」入口；L1 描述、test-harness 安装命令（`jsdom` 可选）、
  资源清单与 `scripts/*` 适用对象同步。
- `assets/sandbox-view/README.md` 的开发流程并入生成器；`references/testing-strategy.md`
  的 L1 与必测矩阵加入 view-smoke。

## [2.7.2] - 2026-10-28

补一条「上下文不可信」：学生端拿不到 `lessonId`/`classId`。

### 新增

- `references/frontend-bridge-0.7.md` 桥接 API 面之后新增：`lessonId`/`classId` 源自**教师侧选择态**
  （`selectedLesson` / `liveClassSelectedClassId`），学生被锁进课堂后为空 → 插件页误报「还没进入课堂」。
  给出以 `classroom_sessions(ended_at IS NULL)` 为准的服务端解析 SQL，以及学生身份
  `req.actor.userId → session.studentId → students.id` 的来源链条（`server/middleware/auth.ts:61`）。

## [2.7.1] - 2026-10-28

补充「槽位布局契约」：第三方 `view` 放进 `student.classroom.overlay` 会挤掉宿主主内容。

### 新增

- `references/frontend-bridge-0.7.md` §4.2：槽位分「页面级 / 浮层级」两类；记录平台 ≤ 0.7.7 的
  `flex h-screen` 根容器 + `w-full h-full` 块级视图导致**课堂白板整块消失**的完整成因链、
  平台侧 `variant="floating"` 修复方式，以及「插件侧无法自救」（`ui.resize` 只传 height）。
- SKILL.md 构建预检清单新增一条：浮层槽位的 `view` 必须确认平台支持 `floating` 变体，
  否则改用 `student.lesson.tool`。

### 关联平台改动

- `openlearnv2`：`PluginSandboxIframeView` 新增 `variant: 'panel' | 'floating'`；
  `extension-point-renderer` 按 `FLOATING_VIEW_SLOTS` 判定（当前仅 `student.classroom.overlay`）。

## [2.7.0] - 2026-10-28

把「每次开发都要重读源码才能确认」的集成事实沉淀成可校验的事实表，并把三类只在运行期爆炸的契约缺口补进 L0。

### 新增

- **`references/integration-facts.json`**：18 条集成事实，每条绑定平台源码锚点与「写错会怎样」的 `impact`。
  覆盖 view 桥接返回形态、方法策略差异（view `api.*` 不过 `checkMethodPolicy`，隐藏前端才过）、
  网关 1MB / 5s / administrator 放行 / `:param` 模式、安装器只解压 `storage/`、CLI 三件套、
  渲染器空 view 隐藏、SQL 守卫前缀与禁用语句、`fetch(frontend.js)` 早于贡献注册、
  `@openlearn/*` 外部化 + 宿主 SDK 软链（Token 值导入合法）。
- **`scripts/facts-check.sh`**：开发前 / 平台升级后跑一次，锚点消失即提示复核（`--json` 可机读）。
  与 `platform-drift-check.sh` 分工：后者维护 skill（槽位/打包/白名单），前者服务开发（桥接/网关/DB）。
- **L0 新规则**
  - 路由配对：`ROUTE_UNREGISTERED`（声明未注册）、`ROUTE_UNDECLARED`（注册未声明）、
    `ROUTE_NOT_IN_MANIFEST`、`ROUTE_NONE_REGISTERED`、`ROUTE_NO_ROLES`（warn）。
  - SQL 守卫预检：`SQL_CORE_TABLE`、`SQL_TABLE_NOT_PREFIXED`、`SQL_FORBIDDEN_OP`、`SQL_DDL_BYPASS`（warn）。
    只检查字面量表名，模板拼接（`${T().x}`）不误报。
  - view 页面运行时：`VIEW_ALERT_BLOCKED`（无 `allow-modals`）、`VIEW_DIRECT_FETCH`（不透明源）、
    `VIEW_RESIZE_MISSING`、`VIEW_API_RESULT_UNWRAP`（`api.*` 返回裸响应体）。
- **`references/troubleshooting.md` §1b**：12 行「现象 / 错误码 → 唯一该读的平台源文件」路由表。

### 修复

- **`references/frontend-bridge-0.7.md` 补齐两处不对称**（此前全文未出现 `checkMethodPolicy`）：
  - 返回形态：`api.*` → 网关裸响应体；`invokeCommand` → 已拆层的 `result`。
  - 方法策略：view 的 `api.*` 不做策略检查（第三方无需 `api:write`/`api:admin` 即可写）；
    隐藏前端会检查（普通写需 `api:write`，高危路径需 `api:admin`）。
- `scripts/verify-test-harness.sh` 增加 runtime 反例（路由/SQL/view），自检项 47 → 60。
- **`DIST_BARE_IMPORT` 误报 `@openlearn/*`**：SDK 构建把 `@openlearn/*` 标为 external、token-enforcer
  也只拒绝其它裸说明符，宿主还会把 SDK 软链进插件 `node_modules`；原规则把 `import { IDatabaseToken }
  from '@openlearn/plugin-sdk'` 判成错误。现改为放行 `@openlearn/*`，仅报其它裸 specifier，并新增
  `sdk-externals-allowed` 事实锚定该行为。

### 变更

- `SKILL.md` 第一步与第六步接入 `facts-check.sh`；L0 描述、资源清单、`scripts/*` 适用对象同步更新。
- `references/testing-strategy.md` 必测矩阵补三行（路由配对 / 裸 SQL / view 页面运行时）。

## [2.6.1] - 2026-10-28

补丁：修复 `sandbox-view` 模板的致命缺件，并把「前端入口 / 安装期 schema」两条隐蔽根因写进文档与检查。

### 修复

- **`assets/sandbox-view/` 缺少 `src/frontend.tsx`**（真实 bug）：
  宿主按 `has_frontend` 判断是否激活前端，且 `registerManifestContributions()` 在
  `fetch(frontend.js)` **之后**；CLI 又只在存在 `src/frontend.tsx` 时才产出 `dist/frontend.js`。
  结果是 **view-only 插件的所有 manifest 贡献都不会注册**（页面永远空白，日志里连 404 都没有）。
  已补空桥接入口，并在模板 README 把它列为不可删除项。
- 新增 L0 检查 **`FRONTEND_ENTRY_MISSING`**：声明了 `contributes`/`view`（或契约要求 UI 通道）
  却没有前端入口时直接报错。

### 记录（`platform-change-watchlist.md` 新增两节）

- **§7.1 `frontend.js` 不是可选文件**：`core.ts` 的 `has_frontend` → `useClassroomSlice` 跳过激活 →
  `plugin-host.ts` fetch-before-register 的完整证据链；含「只有 classroomTools 时半残」的难查情形。
- **§7.2 安装期 schema 决定落库**：`view` 在 v0.7.7 才进 `teacher.tab`/`teacher.panel` schema，
  旧版本安装过的插件 manifest 已被 zod strip，**升级平台不会回填**，必须重装；
  解释了「`teacher.tab` 丢 view、`student.classroom.overlay` 保留」的不对称现象。

### 同步更新

- `ui-channel-decision.md`：§4.5.2 新增「必须提供 `src/frontend.tsx`」前置（含最小代码），失败模式表补两行。
- `troubleshooting.md` D4-UI：新增 4b（无 frontend.js）/ 4c（DB 里 view 被 strip）两条检查。
- `frontend-bridge-0.7.md` §4.1：新增「存在性契约」——`has_frontend` 门禁、fetch-before-register、
  CLI 产出条件、最小占位入口与 `unzip -l | grep frontend.js` 自检；
  §5.5 开头补两个必踩前提；§5 决策树修正「id 前缀构成信任」的错误表述。
- `SKILL.md` 构建预检清单新增 `unzip -l dist/*.zip | grep -q frontend.js`。
- `platform-drift-check.sh`：新增第 7 项检查（`has_frontend` 门禁 2 处 + fetch-before-register 顺序），
  期望值写入 `.cache-meta.json`；现为 10 项。

### 已验证

- `verify-templates-build.sh` 29/29（`sandbox-view` 现在也会产出并校验 `frontend.js`）。
- `verify-test-harness.sh` 47/47（新增 `FRONTEND_ENTRY_MISSING` 反例）。
- `platform-drift-check.sh` 10/10 无漂移。
- L1/L2：`sandbox-view` 18 passed；模板 L0 0 error。

## [2.6.0] - 2026-10-28

新增**平台变更观察清单**与**漂移检测**，专门记录「文档看不出来 / 文档本身写错」的高风险事实。
起因：平台同日完成 README 精简（#343）与双轨制可视沙箱（#344/#345），很容易让人误判
「白名单已移除」「view 放 views/ 下」，两种误判都会让插件方案直接跑偏。

### 新增

- `references/platform-change-watchlist.md`：8 条「文档与代码不一致」事实 + 复核 SOP：
  1. `OPENLEARN_TRUSTED_INLINE_PLUGINS` **仍存在**（`04038ff` 起支持 `*` / `前缀*`），只是 README 不再公开环境变量表；
  2. `view` 页面**必须以 `storage/` 开头**——安装器只解压 `storage/**`，教程里的 `views/index.html` 示例对 ZIP 插件是错的；
  3. SDK CLI 仍只打三件套（`index.js`/`manifest.json`/`frontend.js`），`storage/**` 需自写 pack；`sign` 另写 `signature.json`；
  4. `view` 槽位集合在每个版本可能扩张（当前 5 个显式声明；overlay 走 passthrough 可用但非长期契约）；
  5. 白板画布卡片（`type:'plugin'`）**仍不支持 `view`**，自定义卡片仍需 inline；
  6. 槽位是版本相关封闭集合（v0.7.7 = 122）；
  7. `execution_mode` 以服务端求值 + `GET /api/plugins` 为准，manifest 自述无效；
  8. 漂移期望值表（脚本与文档共用口径）。
- `scripts/platform-drift-check.sh`：一键比对 8 项事实（版本 / 槽位数 / view 槽位 / install 解压前缀 /
  CLI 打包 / README 是否重新公开白名单 / 通配符 / 白板 view 支持）；`--write` 按源码重生成
  `slot-registry.json`（保留分组），漂移时退出码 1 并指向 watchlist 条目。
- `references/.cache-meta.json` 新增 `watchlist` 期望值块（单一真源，供脚本读取）。

### 变更

- 第一步探活新增**第五个信号：文档结构变化**（README/教程/CHANGELOG），并规定「先跑漂移检测，再下结论」；
  附 5 行「观察到 → 不要急着认为 → 以什么为准」对照表。
- L0 `VIEW_NOT_IN_STORAGE` 由 warn 升级为 **error**（含教程示例错误的说明），避免本地能跑、安装后 404。
- 模式 A 红线新增：文档冲突以安装器/运行器为准；每次回答前先确认版本信号。

### 已验证

- `platform-drift-check.sh` 8/8 无漂移（平台 v0.7.7 / HEAD `b03e216`）；`--write` 重生成仍为 122 槽位 / 5 view 槽位。
- `check-templates.sh` 54/54、`verify-test-harness.sh` 46/46（新增 `VIEW_NOT_IN_STORAGE` 反例）。

## [2.5.0] - 2026-10-28

补上第三方插件**自定义 UI 的唯一可行通道**——声明式可视沙箱视图（`view`），
以及开发 `@ext/lab-help` 时实测出来的四个必踩陷阱。

### Added

- `references/frontend-bridge-0.7.md` 新增 §5.5：
  - `view` 完整链路（manifest → registerManifestContributions → PluginSandboxIframeView → view-bridge.js → `ctx.http`）
  - 桥接 API 面清单（`onInit` / `api.get|post|del` / `invokeCommand` / `ui.toast|resize` / `storage.*`）与 `.html` 的 CSP 口径
  - `view` 路线自检清单 8 条
- SKILL.md 构建产物预检清单新增 6 条：`view` 存在性断言、`storage/` 前缀、桥接引用与 `ui.resize`、
  身份敏感请求不走 `invokeCommand`、`api.routes` 限流、静态文件入包。

### Fixed / 记录

- **zod 会 strip `view`**：`contributes["teacher.tab"|"teacher.panel"|"student.view"]` 条目缺 `view` 字段声明，
  `manifestSchema.parse()` 后字段消失 → 宿主退回占位空态、面板空白且无任何报错。
  平台 0.7.7 已补字段与回归用例；本文给出自检断言写法（`student.classroom.overlay` 走
  `frontendSlotEntrySchema(.passthrough)`，本就保留）。
- **第三方强制 `process` 模式**：`execution-policy` 会把非授信 id 的 inline/worker 一律改写为 process，
  故 group-points 那套「inline + 真 React 组件」对第三方不成立。
- **`invokeCommand` 身份丢失**：`/sandbox-command` 用 `pluginActorIdFor()`，`command.actorId` 恒为插件，
  拿不到 `userId`/`role`；身份敏感业务必须走 `bridge.api.*` → `ctx.http`（`req.actor`）。
- **机房同出口 IP 打爆限流**：网关限流键含 `clientIp`，40 台机 × 5 秒轮询 = 480/分钟 > 默认 120/分钟，
  需在 `manifest.api.routes` 逐端点放大。
- **CLI `pack` 不带静态文件**：只写 `index.js`/`manifest.json`/`frontend.js`；安装侧只解压 `storage/**`，
  因此 HTML 必须放 `storage/` 且需自写打包脚本（附打包期 view 路径守卫的做法）。

### 同版本补充：UI 通道判定与测试护栏

新增 **UI 通道可行性判定**，并把「教师点了按钮、学生端什么也看不到」这类错配变成可在开发期自动拦截的契约。
同时修正两处会直接误导方案设计的平台事实错误。

#### 新增

- **UI 通道决策真源** `references/ui-channel-decision.md`：
  - 四条通道：声明式槽位 / **`view` 沙箱 HTML 页面（v0.7.6+，process 可用）** / inline React / 内置插件；
  - 执行模式判定（`execution_mode` 由服务端 `resolvePluginExecutionMode()` 计算，manifest 自述无效）；
  - 白名单机制（支持 `*` / `前缀*`，改完需重启 + 重装/切档位）、122 个真实槽位、白板挂件端到端契约、失败模式对照表。
- **第二步 P0 门禁**：写代码前必须回答「谁看 / 什么 UI / 什么模式 / 凭什么 inline / 数据怎么到学生端」，
  并把结论落成 `<插件根>/plugin.contract.json`；不确定就停，不得先写一版注定渲染不出来的 React。
- **沙箱 HTML `view` 通道**（补上此前缺失的能力）：`contributes.<slot>.view = 'storage/x.html'` +
  `/plugin-sandbox/view-bridge.js`（toast / resize / invokeCommand / api / storage / 上下文同步），
  并说明 `storage/**` 必须自写打包脚本补进 ZIP。
- **新模板**：
  - `assets/sandbox-view/`：process + `view` 页面（教师 Tab / 学生视图），含 `scripts/pack.mjs`；
  - `assets/inline-react/`：inline + 白板挂件（`teacher.dashboard.widget` + `student.view` 成对组件，
    React 只从 `globalThis.HostSharedDeps` 取，附「下发→学生可见」全链路）。
- **测试护栏升级**：
  - `assets/test-harness/slot-registry.json`（122 个真实槽位 + 5 个 `view` 槽位，由平台源码生成）；
  - L0 新增：`UI_MODE_MISMATCH` / `CONTRACT_MODE_CONFLICT` / `SLOT_UNKNOWN` / `SLOT_NOT_DECLARED` /
    `SLOT_NOT_REGISTERED` / `INLINE_TRUST_MISSING` / `INLINE_NOT_WHITELISTED` / `WHITEBOARD_*` /
    `STUDENT_ENTRY_MISSING` / `VIEW_PATH_UNSAFE` / `VIEW_FILE_MISSING` / `VIEW_BRIDGE_MISSING` / `VIEW_PACK_HINT`；
  - L2 新增契约驱动断言：`classroomTools` 命令必须真的派发 `whiteboard.draw(type:'plugin')` 且
    `data` 同含 `teacherWidgetId` / `studentWidgetId`；
  - 三个既有模板补 `plugin.contract.json`；`verify-test-harness.sh` 覆盖 5 个模板 + 3 组反例。
- **排障**：`troubleshooting.md` 新增 `D4-UI`（教师有反应、学生看不到的 8 层检查表）。

#### 修正（会误导方案设计的事实错误）

- **「`@openlearn/` 前缀 + 白名单才可用 React」→ 错**：id 前缀不构成任何信任，`execution-trust-boundary` /
  `ui-channel-decision` 统一为「内置目录 或 `OPENLEARN_TRUSTED_INLINE_PLUGINS`」。
- **「第三方插件没有自定义 UI 通道」→ 过时**：v0.7.6 起有 `view` 沙箱 HTML；本 skill 此前只覆盖到 v0.7.0 的边界。
  只有**白板画布内卡片**和**必须复用宿主 React 的组件**才需要 inline。
- 模板 `full-stack/src/frontend.tsx` 的 `registerExtensionPoint` commandType 已是全限定（2.4.0 修复，此处补记）。

#### 已验证

- `check-templates.sh` 54/54（新增 5 个模板的契约 / `view` / 桥接校验）。
- `verify-templates-build.sh` 28/28：5 个模板全部通过官方 CLI 构建 + `tsc --noEmit` + manifest 字段校验。
- `verify-test-harness.sh` 45/45（5 模板正例 + UI 错配 / `view` 配置错 / 通用缺陷三组反例）。
- L1/L2：server-only / full-stack 18 passed、inline-react 21 passed、sandbox-view 18 passed；缺陷夹具稳定报错。
- `sandbox-view` 模板 `npm run pack` 实测产出含 `storage/**` 的 ZIP（4 个文件）。

## [2.4.0] - 2026-10-28

两条主线：**用户贴报错时能判定「插件自己 vs 平台插件系统」并把系统侧缺陷直接上报**，
以及**四层测试护栏让潜在问题在开发期暴露**。同时修掉模板里一个会让远程前端命令找不到的真实 bug。

### 新增

- **报错归因入口（任务模式 A′）**：用户粘贴插件报错/堆栈/白屏时，先归因再动手。
  - 「第六步 §0 受理固定动作」：判阶段 → 提取五要素（平台/SDK 版本、`execution_mode`、堆栈顶层帧、触发操作、是否最小复现）→ **回源码搜报错文案**确认是设计行为还是实现缺陷 → 最小复现。
  - **高频报错归属速查表**（15 行）：每条给出归属（插件侧 / 产品边界 / 系统侧已修复 / 待定）+ **机制层缘由**，如 `COMMAND_NOT_REGISTERED`=内核 default-deny 缺 ActionDescriptor、`DataCloneError`=postMessage 不能克隆函数。
  - 归因结论从 5 类扩为 **6 类**，新增「产品边界 / 设计行为」并明确**绝不提 Issue**；汇总格式新增 `缘由` 字段。
- **系统侧缺陷上报（第六步 B）**：固定仓库 `aymwoo/OpenLearn-Next-V2`。
  - 三道门禁：证据（4 条门槛）→ 去重（仓库 issue **含已关闭** + `docs/beta/known-issues.md`）→ **同意**（标题+正文全文给用户确认，绝不静默创建）。
  - 正文**三段必备**：`问题原因`（包/文件/机制 + 触发链 + 版本口径 + 堆栈帧）、`影响`（受影响对象 + 阻塞程度 + 版本区间 + 规避）、`建议解决方式`（改动点 + 方案权衡 + 验收标准）。
  - 脱敏红线（名册/作业原文/口令/Cookie/`edu_os_token`/API Key 含掩码）、幂等与失败回退（重复 issue 改评论、`gh` 不可用给 `issues/new` 手动入口）。
  - 新增 `assets/platform-issue-template.md`；`references/github-collaboration.md` 新增 §1A 完整 SOP + 异常表 + 命令速查 + 红线。
- **L0–L3 四层测试护栏（第四步 B）**：
  - `assets/test-harness/static-check.mjs`（零依赖 L0，<1s）：manifest 必填项 / 权限串真伪 / **三件套双向配对** / 裸导入 / 前端越界 / process 禁用 API / DB 表名与分号 / type-only 误用 / 密钥泄漏 / 扩展点未全限定。
  - `contract.test.ts`（L1）：声明的 commandType 是否真有 handler + ActionDescriptor、handler 是否 `{execute}` 对象、`capabilityRequired` 是否真实、`inputSchema` 类型名。
  - `smoke.test.ts`（L2）：重复激活状态泄漏、按 schema 造 payload 跑命令抓 `TypeError`、REST 路由 5xx、事件 payload、停用未退订（订阅翻倍）。
  - `references/testing-strategy.md`：L0–L3 阶梯、按插件特征的必测矩阵、**8 条 Guardrail → 用例映射**、Mock 与生产宿主 8 处差异、环境坑、L3 十步冒烟清单、CI 片段。
  - `scripts/verify-test-harness.sh`：护栏自检（模板 L0 必须绿 + 含缺陷反例必须报出 14 个预期错误码）。
  - 门禁：L0 0 error + L1 全绿才允许进入构建/上传；完成定义、交付格式、红线同步更新。

### 修复

- **模板 bug（full-stack）**：`src/frontend.tsx` 的 `registerExtensionPoint` 把 commandType 写成 `{{commandPrefix}}.create`，运行期注册**不前缀化** → 命令找不到。改为 `{{pluginId}}.{{commandPrefix}}.create`（由新增的 L0 检查抓出）。
- `references/troubleshooting.md`：§0 对齐 6 类结论并标注是否提 Issue；§7 拆成「本地报告 / 提交 Issue / 插件侧与产品边界 / 待定」四节。

### 已验证

- `check-templates.sh` 39 项全过；`verify-test-harness.sh` 26 项全过（三套模板 L0 均 0 error，反例命中 14 个错误码）。
- L1/L2 在 server-only 与 full-stack 模板上均 **15 passed / 1 skipped**；在 6 缺陷夹具上稳定 **6 failed**，每条指向具体根因。
- 静态检查已消除注释示例、TS 泛型、slotProps 引用三类误报（注释遮蔽 + 描述符锚定）。

### 上报

- 验证测试护栏时发现平台侧缺陷：`@openlearn/plugin-sdk` 3.6.0–3.7.4 的 `dist/index.js` 裸导入 `uuid` 但未声明依赖，第三方 `import` SDK 即 `ERR_MODULE_NOT_FOUND`。已按第六步 B 提交
  [Issue #349](https://github.com/aymwoo/OpenLearn-Next-V2/issues/349)，并记入 `troubleshooting.md` 已知问题索引与 `testing-strategy.md` §6。

## [2.2.0] - 2026-10-28

把版本基线从 SDK 3.7.1 抬到 **npm 发布版 latest `3.7.4`**（对应平台 v0.7.7），并补上 3.7.2 引入的两处破坏性变化。

### 变更

- **版本基线**：`SDK 3.7.1 / 平台 v0.7.4` → `SDK 3.7.4 / 平台 v0.7.7`（SKILL.md 头部、description、
  `references/.cache-meta.json`、四篇 references 的版本头）。
- **探活升级为四个信号**：新增 `npm view @openlearn/plugin-sdk version` 作为**最高权威**，
  并写明冲突处置（npm 高于本地 → 以 npm 为准；本地领先 → 仍按 npm 已发布口径写代码）。
- **上游不一致提醒改写为「已消除」**：平台仓库 `main`（0.7.7 / HEAD 2026-10-28）的
  `scaffold/templates/` 与 npm 3.7.4 的**逐字节一致**（`diff -rq` 无输出），此前「仓库仍是 React 模板」的勘误已修复；
  但「冲突时以 npm 为准」的判定顺序保留。
- **新增 SDK 3.7.2 破坏性变化**（3.7.4 仍在）：
  1. 7 个宿主内部类（`PluginRuntimeComposition` / `PluginCapabilityGateway` / `PluginContextAdapter` /
     `PluginDistributionManager` / `PluginLifecycleManager` / `PluginRuntimeAdapter` / `UnifiedExtensionRegistry`）
     改为 **type-only 导出**，值导入编译通过但运行期 `undefined`；
  2. 官方 CLI 新增 **frontend 产物裸说明符守卫**（`✖ frontend 产物里有裸模块说明符`，构建期失败）。
- **排障与预检**：SKILL.md 排障表与 `references/troubleshooting.md` §D2 各补两条现象；
  构建预检清单加 `dist/frontend.js` 裸说明符 grep。

### 已验证（未变的契约）

- 三套模板与 npm 3.7.4 的 `scaffold/templates` **契约一致**（`diff-official-scaffold.sh` 通过，无漂移）。
- 权限字典 **20 条**与官方 3.7.4 矩阵逐条一致；`check-templates.sh` 39 项全过。
- `docSiteVersion` 仍记 0.7.4：readthedocs 线上构建滞后于仓库与 npm，只作探活信号，不作事实来源。

## [2.1.0] - 2026-10-27

修复 v2.0.0 残留的运行时行为错误，并把模式 A 的文档纪律拉到与模式 B 同等水平。

> **对使用者有影响**：模板生成的插件 `engines.openlearn` 从 `>=0.2.5` 收紧为
> `full-stack` / `frontend-only` 用 `>=0.7.0`（server-only 仍为 `>=0.2.5`）。
> 这是官方明文规则（“填你实际用到的最新 API 的最低版本，不要一律抄 `>=0.2.5`”）的正确写法，
> 但意味着生成的插件不再能装到 0.7.0 以前的宿主。

### 修复（会让开发者写出跑不通的代码）

- **实时同步**：v2.0.0 残留的 Socket.IO 排障指引在沙箱模型下**不可执行**。已补充真实约束：
  沙箱 iframe 的 CSP 为 `connect-src 'none'`（`server.ts` 的 `/plugin-sandbox/frame` 路由），
  桥接只有 9 个 op（`server/utils/plugin-sandbox-frame.ts`），宿主只向 iframe 发
  `load` / `reply` / `deactivate` 三种消息（**无事件推送**）→ **远程插件只能轮询**。
  新增 `references/frontend-bridge-0.7.md` §7 与 SKILL.md 的对应章节。
- **`engines.openlearn` 填法**：改从“推荐 `>=0.2.5`”为**按实际用到的 API 填**，并新增
  「API → 最低宿主版本」速查表（`references/manifest-0.7.md` §11）；
  模板随之调整（server-only `>=0.2.5`，full-stack / frontend-only `>=0.7.0`）。
- **声明式 SQL 迁移的静默失效**：官方 CLI 的 `build` 只打包 `index.js` / `manifest.json` /
  `frontend.js`，**不含 `migrations/`**；宿主解包也只落盘这三个 + `storage/` 前缀的静态资源，
  而迁移器在目录不存在时**静默跳过** → 按官方文档写 `migrations/*.sql` 的 ZIP 插件
  **一条迁移都不执行且不报错**。已在 `references/manifest-0.7.md` §12 写清并给出替代方案
  （`ctx.db.ensureTable()` + `ctx.db.migrate(version, fn)`）。
- **跨插件服务共享（provides / contracts）**：此前零覆盖。新增 `references/manifest-0.7.md` §13
  （三步配套 + DI 按 Token 名字字符串解析 + CLI 不打包 `contracts/` 的含义），
  模板新增 `assets/full-stack/src/contracts/index.ts` 与 manifest 的 `provides` 声明。

### 文档纪律（模式 A 对齐模式 B）

- **模式 A 红线**：新增 6 条（默认只生成文件不代跑构建、不覆盖已有文件、不动用户 git 状态、
  不确定时不猜、歧义先问、归因未达门槛不生成 bug 报告）。
- **完成定义 + 交付格式**：新增 6 项完成检查清单与统一的交付汇报模板。
- **适用范围声明**：明确本 skill **不覆盖**平台本体开发、内置插件、白板/课件渲染器、
  插件市场运营、第三方前端深度定制。
- **命令类型命名空间三语义**：区分「`registerHandler` 自动加前缀」「manifest 声明自动加前缀」
  「运行期 `registerExtensionPoint` 不前缀、必须全限定」，消除与模板写法（短名）的矛盾。
- **模板选择判据**：由“三个名字”改为“要不要后端状态”的判断规则。
- **交叉引用修正**：模板对照表的“见第四步”改为“见 Guardrail 5”。
- **脚本接线**：三个自检脚本从只出现在资源表 → 接入第四步流程，并注明“维护者用，使用者不要跑”。

### 脚本

- `check-templates.sh`：33 → **39 项**（新增 engines 按模板校验、前端禁 socket/fetch、
  contracts 与 provides 配对、废弃写法 `socket.off` / “见第四步” 残留检测）。
- `diff-official-scaffold.sh`：`engines.openlearn` 改为**比较最低版本**——我们更严格（按实际 API 填）
  记为 info，不再误报为漂移；更低才判失败。
- `verify-templates-build.sh`：manifest 断言改为按模板区分 engines 期望值。

### 新增参考

- `references/manifest-0.7.md` §11 API→最低宿主版本、§12 声明式迁移陷阱、§13 跨插件服务共享
- `references/frontend-bridge-0.7.md` §7 实时同步的真实通道（并重写 §6 打包口径）

## [2.0.0] - 2026-10-27

> **破坏性版本**：从 v1.1.0 升到 v2.0.0。本次发布推翻了 v1.x 的插件前端心智模型
> （“插件前端 = React 组件”），模板产物形态与 API 口径均已改变，旧版模板不再适用。

**破坏性更新**：插件开发域知识从平台 v0.3.16 全面刷新到 **v0.7.4 / SDK 3.7.1**。
v1.x 的模板与规则建立在一个已被推翻的心智模型上（“插件前端 = React 组件”），会直接产出装不上的插件。

### 破坏性变更

- **模板补 `manifest.main`**：`manifestSchema` 中 `main: z.string().min(1)` 为必填，v1.x 三套模板全缺 → 插件装不上。
- **模板改为沙箱桥接形态**：`frontend.tsx` 不再是 React 组件。v0.7.0 起远程插件前端跑在 `sandbox="allow-scripts"` 的隐藏 iframe 内，
  `window.HostSharedDeps` 为 `undefined`，传 `component` 会 `DataCloneError`；官方 CLI 构建的远程前端插件一旦用到 React/JSX **必然激活失败**。
- **模板补 ActionDescriptor**：内核对命令派发实行 default-deny，只 `registerHandler()` 不 `actionRegistry.register()` 的命令会被拒（`COMMAND_NOT_REGISTERED`）。
- **模板 `engines.openlearn` 从 `>=0.1.9` 改为 `>=0.2.5`**（与官方脚手架一致；零主版本号会锁死在小版本区间）。
- **模板 SDK 版本改用 `{{sdkVersion}}` 占位**，不再写死 `^3.2.0`；`package.json` 补 `build` / `dev` 脚本。
- **frontend-only 模板不再声明 `classroomTools`**（无服务端 handler 时声明了必然 404）。
- **能力权限字典整表替换**：v1.x 列的 8 条权限中 4 条（`user:read` `system:process` `ai:invoke` `network:fetch`）在源码中**不存在**；现改为平台真实的 20 条。
- **错误码修正**：`CAPABILITY_DENIED` 不存在，实际为 `COMMAND_NOT_REGISTERED` / `COMMAND_CAPABILITY_DENIED`。
- **事件订阅 API 修正**：不存在 `Disposable` 与 `subscription.unsubscribe()`；实际为 `subscribe(type, handler): Promise<void>` + `unsubscribe(type, handler)`。
- **槽位 Props 修正**：不存在 `HostContext`；真实注入为 `{ lessonId, classId, route? }` + `slotProps`。
- **Worker/Inline 差异表修正**：表前缀已统一为 `plugin_<安装行UUID>_`（与执行模式无关）；`ctx.pluginId` 两模式均为 UUID；`ctx.db.migrate` 签名为 `(targetVersion, fn)`。
- **执行模式认知更新**：v0.7.0 起第三方插件被强制改写为 `process` 子进程，不再跑 inline / worker Thread。

### 新增

- **CI 工作流 `.github/workflows/ci.yml`**：四个 job —— `self-check`（模板/文档一致性）、
  `scaffold-diff`（与 npm 发布版 SDK 的官方脚手架比对，阻塞）、
  `build-verify`（三套模板真实构建 + `tsc --noEmit`，阻塞）、
  `platform-head-diff`（与平台仓库 HEAD 比对，仅预警，用于提前发现下一次发版的模板变更）。
- **`scripts/diff-official-scaffold.sh`** + **`scripts/scaffold-fingerprint.py`**：官方脚手架漂移检测。
  把双方抽成「契约指纹」（manifest 字段、`main`、`engines`、command 配对、前端是否误用 React、占位符）逐项对比，
  **官方有、我们缺即判失败** —— 这正是 v1.x 漏掉 `manifest.main`、沿用 React 前端范式的根因。
  支持 `DIFF_ADVISORY=1` 转为仅预警模式。
- **`scripts/verify-templates-build.sh`** 改为双模式：优先用 npm 安装的 `@openlearn/plugin-sdk`（CI 用），
  回退到本地平台仓库的 SDK；类型检查器同理（本地 `node_modules/.bin/tsc` → 平台仓库的）。
- **`references/capability-matrix-0.7.md`**：权限字符串真源（20 条真实权限 + 不存在的权限 + 4 套能力机制辨析 + 错误码 + 高危清单）。
- **`references/frontend-bridge-0.7.md`**：远程前端沙箱桥接范式（执行环境、能力边界、可见入口决策树、HostSharedDeps 现状、自检清单）。
- **`references/manifest-0.7.md`**：manifest 权威规范（必填字段、依赖声明、`contributes.locales`、`configuration.scope`、`api.routes`、签名）。
- **`references/execution-trust-boundary.md`**：执行模式与信任边界（process 强制默认、Node permission model、网络沙箱与域名审批）。
- **`scripts/check-templates.sh`**：模板自检（`main` / `engines` / ActionDescriptor 配对 / 远程前端无 React / 占位符对齐 / 废弃 API 残留），33 项。
- **`scripts/verify-templates-build.sh`**：三套模板的真实构建 + `tsc --noEmit` 校验（依赖本地平台仓库的 SDK）。
- **探活改为三信号**：平台版本 / SDK 版本 / 文档站构建版本，任一变化即刷新；并引入平台仓库 `docs/` 作为一手文档源。
- **`references/.cache-meta.json`**：新增 `platformVersion` / `sdkVersion` 字段与各文档的本地源路径。

### 变更

- frontmatter 版本 `1.1.0 → 2.0.0`，description 补入沙箱桥接范式与当前基线版本。
- `SKILL.md` 重写：权限字典、槽位 Props、共享依赖、执行模式差异表、调试 SOP 表全部按 v0.7.4 重写；
  新增“可见入口方式”决策项与 default-deny guardrail。
- `references/troubleshooting.md`：错误码修正、Worker/Inline 差异表修正、已知系统问题索引补入 v0.4.0–v0.7.4 条目、
  新增“系统缺陷 vs 产品边界”的区分（remote 插件无 UI、熔断自动停用、`auth:false` 需审批均属后者）。
- `references/architecture.md` / `references/scaffold.md` / `references/plugin-development-tutorial.md`：
  标记为 0.3.16 历史快照并加“已知与当前行为的差异”横幅；修正 `scaffold.md` 中裸函数 `registerHandler` 的错误示例。
- `assets/bug-report-template.md`：执行模式字段补 `process`，影响面与规避方案提示对齐 v0.7 语义。
- `README.md`、`skills.sh.json` 同步更新说明。

### 上游不一致记录

实测发现：平台仓库 `origin/main`（平台 0.7.4 / SDK 源码 3.7.0）的 `scaffold/templates/` **仍是旧的 React 模板**，
而 npm 已发布的 `@openlearn/plugin-sdk@3.7.1` **才是沙箱桥接模板**。
因此 skill 以 **npm 发布版 SDK** 为对齐基线，CI 的阻塞项比对 npm 发布版，
同时用 `platform-head-diff` 对平台仓库 HEAD 做非阻塞预警。

### 验证

三套模板均通过：官方 SDK CLI（3.7.1）构建成功、生成的 `manifest.json` 通过平台 `manifestSchema` 校验、
`tsc --noEmit` 对 SDK 3.7.1 类型零报错、产物 `frontend.js` 无 React 引用、`index.js` 无非法裸导入。

## [1.1.0] - 2026-10-18

新增 GitHub Issue / PR 协作能力：接手 issue 前先占位，开发在独立 worktree 完成，所有变更通过 PR 提交，并覆盖审查、返工与合并。

### 新增

- **任务模式判断**：`SKILL.md` 顶部新增模式分流——A 插件开发（第一步 ~ 第六步）/ B GitHub 仓库协作；模式 B 跳过文档探活，只读取目标仓库约定。
- **模式 B 工作流**：`SKILL.md` 新增「GitHub Issue / PR 协作工作流」章节（B0 ~ B9），覆盖仓库定位、issue 预检与占位、worktree、开发验证、PR 提交、CI、审查、返工、合并、清理与红线。
- **`references/github-collaboration.md`**：完整执行手册，含：
  - 平台仓库 `aymwoo/OpenLearn-Next-V2` 与 `openlearn-next/*` 插件仓库的本地路径映射；
  - issue 预检（状态、assignee、重复 PR/分支、验收标准）；
  - 「assign @me + `in-progress` 标签 + 占位评论」三件套，缺失标签按需创建；
  - worktree 命名（`~/Develop/openlearn-issue-<n>`、`~/Develop/openlearn-plugins/<repo>-issue-<n>`）与分支命名（`<type>/issue-<n>-<slug>`）；
  - PR 正文模板（变更内容 / `Closes #n` / 真实测试计划 / 截图 / 风险回滚）；
  - CI 等待与失败分类、PR 状态卡、审查草稿与发布、review thread 返工、squash 合并、worktree 清理；
  - 异常处理表、命令速查、四类输出模板与 10 条红线。

### 变更

- frontmatter 版本 `1.0.1 → 1.1.0`，`displayName` 改为「OpenLearnV2 插件开发与仓库协作助手」，description 增加 issue/PR 触发词。
- `README.md`、`skills.sh.json` 同步更新技能说明。

### 设计约束

- 公开动作分级确认：两次主确认（接管 issue 前确认占位方案；push/开 PR 前确认 diff、测试与文案）+ 合并、清理、发布 review 等不可逆动作单独确认。
- 平台 `main` 无分支保护，skill 以「CI 全绿 + squash + 删除分支 + 不 `--admin`/`--auto`」作为唯一防线。
- 无 `project` scope，不使用 Projects 看板，统一用 assignee + `in-progress` 标签表达状态。

## [1.0.1] - 2026-09-19

新增「插件侧 / 系统侧」故障归因能力，并把内置文档缓存从 0.1.x 时代全面刷新到 OpenLearnV2 v0.3.16。

### 新增

- **故障归因工作流**：`SKILL.md` 新增「第六步：故障归因（插件侧 vs 系统侧）」，给出五类归因结论（插件侧 / 系统侧 / 插件间冲突 / 环境与配置 / 待定）、三条判定铁律（堆栈归属、对照实验、先核版本）、判为「系统侧」的 4 项必要条件，以及固定的简要汇总格式。
- **`references/troubleshooting.md`**：完整诊断参考——证据采集清单、按故障阶段的归因决策树、Worker/Inline 差异边界、系统侧证据门槛、最小复现对照实验 SOP、已知系统问题索引（含修复版本）、Bug 报告输出规范。
- **`assets/bug-report-template.md`**：系统侧 Bug 报告模板，含环境信息、最小复现步骤、完整堆栈、最小复现插件、对照实验记录、已排除项自检清单、文档不符之处。
- `SKILL.md` 新增「Worker 与 Inline 模式 API 差异（必读）」速查表。
- 扩展槽位补充 `anchor:*`（v0.2.6+，含白板工具栏锚点）与 `nav.user_menu`。
- Manifest 关键字段补充：`api.routes`、`provides`、`optional`、`pluginDependencies`、`contributes`、`updateSource`、`deploy`、`configuration.showInDashboard`。
- 探活机制增加构建版本比对（索引页页脚日期可能滞后于实际构建版本，现同时对页面标题中的 `OpenLearnV2 x.y.z` 版本号进行检查）。
- 补充 skillhub 发布元数据（`slug` / `displayName` / `version`），使 skill 可通过 `skillhub publish` 直接发布与更新。

### 变更

- **文档缓存全面刷新至 v0.3.16**（旧缓存为 0.1.x 时代，且 3 个来源 URL 已全部 404）：
  - `references/plugin-development-tutorial.md`：重拉新版教程（约 86KB，14 章），来源更新为 `/tutorials/plugin-development-tutorial.html`。
  - `references/architecture.md`：重写为四层 Platform Kernel 速查（内核服务 Token 10 → 16，生命周期状态机 5 → 7 态，新增 `HotReloadController`、`ctx.http` + PluginApiGateway 六道防线）。
  - `references/scaffold.md`：由 SDK / Test Kit / 示例 / 数据库 API 等 15 个页面汇编（CLI、模板、构建、测试、常见问题），补齐 `@openlearn/plugin-test-kit` 与 `ctx.http.handle()` 路由测试。
- `references/.cache-meta.json`：版本更新至 0.3.16，记录多页来源与版本口径提示。
- 在线文档地址表修正为重构后的新路径（旧 `plugin-development-tutorial.html`、`architecture_review_report.html`、`scaffold.html` 均已 404）。
- HostSharedDeps 白名单更新为 6 项（新增 `react-dom/client`、`react/jsx-runtime`）；JSX 模式改为版本相关（0.3.15+ 经典/自动均可，≤0.3.14 仅经典），React 显式导入规范相应调整。
- `engines.openlearn` 推荐值更新为 `>=0.2.5`（宿主版本，非 SDK 版本）；注明 SDK 版本随平台 release 同步、勿写死。
- 插件模板增强：浮层/弹窗改用 `ReactDOM.createPortal(..., document.body)` 防挤压白板工具栏；补充生命周期清理 SOP（订阅、定时器、后台进程）与命令-事件三件套示例。
- `README.md` 技能说明补充故障归因能力。

### 修复

- 修正激活超时描述：原记为「ACTIVATING 不超过 10 秒」，实际为 Inline 5000ms / Worker 60000ms（Worker 可通过 `ctx.reportProgress()` 滑动续期）。
- 标注官方文档存在的版本口径矛盾：`react/jsx-runtime` 支持版本在不同页面记为 0.3.15+ / 0.3.16，归因时以 Release Notes 为准。

## [1.0.0] - 2026-07-22

初始版本（含 2026-07-22 ~ 2026-07-26 的全部提交）。

### 新增

- `openlearn-next-plugin-dev` skill：面向 OpenLearnV2 教学平台的插件开发助手，通过在线文档获取最新 API，与开发者讨论需求后生成插件代码，支持 `server-only` / `full-stack` / `frontend-only` 三类模板。
- 内置三份官方文档本地快照（`references/`）+ 索引页探活机制，降低重复拉取的 token 消耗。
- 命令-事件-Action 三件套模式、权限声明、扩展槽位、Worker 隔离等开发规范与速查字典。
- 插件模板：显式 React 导入、`classroom.tool` 槽位图标按钮规范与 Portal 防挤压指引、轻量订阅者模式状态同步示例。
- `README.md` 与 skills.sh 仓库页面配置。

[1.1.0]: https://github.com/aymwoo/openlearn-skills/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/aymwoo/openlearn-skills/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/aymwoo/openlearn-skills/releases/tag/v1.0.0
