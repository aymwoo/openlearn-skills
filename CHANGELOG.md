# Changelog

本仓库所有值得记录的变更都写在这里。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
版本通过 git tag（`vX.Y.Z`）发布。

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
