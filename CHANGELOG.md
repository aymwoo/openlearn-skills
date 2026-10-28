# Changelog

本仓库所有值得记录的变更都写在这里。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
版本通过 git tag（`vX.Y.Z`）发布。

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
