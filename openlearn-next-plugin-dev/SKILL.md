---
name: openlearn-next-plugin-dev
slug: openlearn-next-plugin-dev
displayName: OpenLearnV2 插件开发与仓库协作助手
version: 2.4.0
description: 为 OpenLearnV2 教学平台（当前平台 v0.7.7 / SDK 3.7.4）开发插件，并协作处理 OpenLearn 相关 GitHub 仓库的 issue 与 PR。覆盖 server-only / full-stack / frontend-only 三类模板，远程前端沙箱桥接（隐藏 iframe、无 React、声明式贡献点）范式、manifest 与能力权限规范、构建与安装验证；内置 L0–L3 四层测试护栏（static-check 契约静态检查 + plugin-test-kit 契约/冒烟测试 + 真实宿主冒烟）让潜在问题在开发期就暴露；用户粘贴插件报错/堆栈时先做插件侧 vs 平台插件系统侧归因（讲清问题缘由），判为平台侧则去重后向 aymwoo/OpenLearn-Next-V2 提交缺陷 Issue（含问题原因、影响、建议解决方式）；GitHub 协作支持 issue 占位、worktree 开发、PR 提交/审查/返工/合并。当用户提到开发 OpenLearn 插件、openlearn-next 插件、教学平台插件、课堂工具，粘贴插件报错/不工作/白屏，或要处理 OpenLearn 仓库的 issue、PR、worktree 时使用此 skill。
---

> ✅ **版本基线口径（2026-10-28 核对）**：以 **npm 发布版**为准 ——
> `@openlearn/plugin-sdk` 的 `latest` = **3.7.4**（2026-10-27 05:30 发布），对应平台 **v0.7.7**。
>
> 此前记录的「上游不一致」（平台仓库 `main` 用旧 React 模板、npm 已发桥接模板）**已消除**：
> 现仓库 `main`（HEAD 2026-10-28）的 `packages/plugin-sdk/scaffold/templates/` 与 npm 3.7.4
> 的 `scaffold/templates/` **逐字节一致**（`diff -rq` 无输出），均为桥接模板。
>
> **但判定顺序不变**：两者再次冲突时，仍以 **npm 发布版为准**
> （`npx @openlearn/plugin-sdk init` 拿到的就是发布版模板），仓库 `main` 可能滞后。

# OpenLearnV2 插件开发与仓库协作指南

## 核心原则

**平台一手源优先，本地快照加速读取，规则约束保证代码正确性。**

- **一手源**：平台仓库 `~/Develop/openlearnv2/docs/` 下有一手文档源（带 `doc-version` 标记），源码 `packages/core/` / `packages/plugin-sdk/` 是最终真理。**查 API 先看源码，不要只看文档。**
- **快照**：`references/` 存着本 skill 整理的参考资料，随平台版本更新。
- **探活**：每次使用前核对平台版本 / SDK 版本 / 文档站构建版本，三者任一变化即刷新。

> ⚠️ **当前基线：平台 v0.7.7 / SDK 3.7.4**。本 skill 的模板、权限字典、前端范式均以此为准。
>
> **时效规则**：本文事实截至 **2026-10-28**。若你遇到的平台版本高于此：
> 1. 先跑第一步探活，比对 `platformVersion` / `sdkVersion` / `docSiteVersion`；
> 2. 仍不确定时，以**平台源码**为准（`~/Develop/openlearnv2/packages/core/`、`packages/plugin-sdk/`）——
>    源码是最终真理，文档与官方模板都可能滞后；
> 3. 发现本文与源码不一致时，**以源码为准**并当场指出差异，不要沿用本文的旧结论。

> 🔴 **SDK 3.7.2 起的两处破坏性变化（3.7.4 仍在）**，写代码前先记住：
>
> 1. **宿主内部类改为 type-only 导出**。`PluginRuntimeComposition` / `PluginCapabilityGateway` /
>    `PluginContextAdapter` / `PluginDistributionManager` / `PluginLifecycleManager` /
>    `PluginRuntimeAdapter` / `UnifiedExtensionRegistry` 这 7 个符号**不再有运行期值**。
>    插件里只能 `import type { ... }`；写成值导入会**编译通过、运行期 undefined**
>    （比直接报 TS1362 更难查）。宿主侧实现请从 `packages/core/plugin-host/*.js` 导入。
> 2. **CLI 新增 frontend 产物守卫**。构建时扫描 `frontend.js` 的**裸模块说明符**
>    （`from 'x'` / `import 'x'` / `require('x')` / 动态 `import('x')`；相对 `./x` 与绝对 `/x` 放行），
>    命中即输出 `✖ frontend 产物里有裸模块说明符` 并**构建失败**。
>    原因：远程前端跑在不透明源 iframe，加载方式是 `Blob` + 动态 `import()`，裸说明符无从解析；
>    宿主那段 `transformBareModuleImports` 改写发生在父页面，救不了 iframe 内的求值。
>    → 依赖必须打进 bundle（`--bundle` 默认已开），前端不要 import React / 第三方包。

---

## 任务模式判断（先做这一步）

| 用户意图 | 模式 | 入口 |
|----------|------|------|
| **粘贴插件运行报错 / 堆栈 / 白屏 / 日志**，或说「插件不工作」「装不上」「点了没反应」 | **A′：故障归因与上报** | 直接进「第六步」（先归因，后决定是否提 Issue） |
| 处理某个 GitHub issue / PR；给出编号、URL，或说「接手这个 issue」「审查/合并 PR」 | **B：仓库协作** | 下方「模式 B」+ `references/github-collaboration.md` |
| 开发 / 修改 / 排查 OpenLearn 插件 | **A：插件开发** | 「第一步 ~ 第六步」 |
| 两者都不明确 | — | 先问清楚，不要猜 |

> **A′ 的硬要求**：用户一贴报错，**不要先改代码，也不要先甩锅平台**。必须先给出
> 「这是插件自己代码的问题，还是平台插件系统的问题」的明确结论 + 缘由（机制层面的解释），
> 再决定动作。判为平台侧 → 按「第六步 B」向 `aymwoo/OpenLearn-Next-V2` 提 Issue。

- 模式 B **不需要**执行第一步的文档探活，只需读取目标仓库的 `AGENTS.md` / `CLAUDE.md` / `README.md` / `package.json`。
- 模式 B 遵守「两次主确认 + 不可逆动作单独确认」。
- 两种模式可在同一会话切换；切换时先说明当前模式。

> **本 skill 不覆盖**（遇到先说明边界，不要用本 skill 的模板硬套）：
> - 平台本体开发（`packages/core`、内核服务、数据库迁移）
> - 宿主内置插件（`packages/plugins/`，属于平台仓库而非第三方 ZIP 插件）
> - 白板 / 课件渲染器扩展（宿主 React 侧，非插件 API）
> - 插件市场审核、运营与发布流程（仅覆盖到「签名」层面）
> - 第三方前端 UI 的深度定制 —— 当前**没有**可用的自定义 UI 通道（见「实时同步」与「可见 UI 走声明式」）

---

## 工作流程

### 第一步：探活 + 版本比对

#### 1a. 四个版本信号（每次必做）

| 信号 | 获取方式 | 权威性 |
|------|----------|--------|
| **SDK latest（准绳）** | `npm view @openlearn/plugin-sdk version` 或 `npm view @openlearn/plugin-sdk dist-tags.latest` | **最高**：冲突时以它为准 |
| 平台版本 | 本地仓库 `~/Develop/openlearnv2/package.json` 的 `version` | 次高（本地可能未 pull） |
| SDK 源码版本 | `~/Develop/openlearnv2/packages/plugin-sdk/package.json` 的 `version` | 次高 |
| 文档站构建版本 | fetch 索引页，读标题中的 `OpenLearnV2 x.y.z 文档` | 最低（线上构建常滞后） |

```bash
# 一次拿到 npm latest + 两个本地版本
node -e "const p=require(process.env.HOME+'/Develop/openlearnv2/package.json');const s=require(process.env.HOME+'/Develop/openlearnv2/packages/plugin-sdk/package.json');console.log('platform',p.version,'| sdk(local)',s.version)"
npm view @openlearn/plugin-sdk version
```

> **冲突处置**：npm latest 高于本地 → 以 npm 为准，并提示用户「本地仓库未 pull 或未安装最新 SDK」；
> npm latest 低于本地 → 本地领先（预发布），仍按 npm 已发布口径写代码，避免用到未发布 API。

#### 1b. 比对缓存

读取 `references/.cache-meta.json` 的 `platformVersion` / `sdkVersion` / `docSiteVersion`：

- **三者全同** → 缓存命中，直接用本地快照（**0 额外 token**）
- **任一不同** → 告知用户「平台已更新（旧 X，新 Y）」，刷新 `references/` 与 `.cache-meta.json`
  （`docSiteVersion` 单独滞后不算更新，先看 `sdkVersion` 与 npm latest 是否一致）
- **无缓存** → 直接用本地快照

#### 1c. 刷新方式（优先本地仓库）

```bash
# 平台一手文档源
ls ~/Develop/openlearnv2/docs/
# 官方脚手架模板（模板漂移的第一现场）
ls ~/Develop/openlearnv2/packages/plugin-sdk/scaffold/templates/
```

> 官方文档站路径（线上校验用）：
> `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/`

---

### 第二步：需求讨论与预检查

与开发者逐项确认：

1. **插件用途**：面向教师还是学生？解决什么问题？
2. **核心功能**：1-5 个核心功能点
3. **插件类型**（三选一，判据是「要不要后端状态」）：
   - `server-only`：**不需要**任何后端命令/存储，只要 AI 工具与后端逻辑
   - `full-stack`：需要后端命令、数据库或 EventBus（**绝大多数课堂插件属于这类**）——
     后端逻辑 + 前端沙箱桥接（**不是** React 组件，见「Guardrail 5」）
   - `frontend-only`：确实不需要后端命令，且只需要存储/提示这类轻量前端能力
4. **可见入口方式**（关键决策）：远程插件**不能**提供 React 组件，可见 UI 走
   - `manifest.classroomTools` —— 课堂工具按钮（点击派发 commandType）
   - `manifest.contributes.<slot>` —— 声明式槽位贡献（宿主渲染）
   - `ctx.ui.registerExtensionPoint(slot, { slotProps })` —— **仅数据型**，如 `command_palette.item`
   - 内建插件（`@openlearn/` 前缀且在 `OPENLEARN_TRUSTED_INLINE_PLUGINS` 白名单）才可用命令式 React 组件
5. **权限需求 (Capabilities)**：显式核对**平台真实存在**的能力字符串（见「权限全集」一节）
6. **AI 能力与 Action 关联**：是否需要 AI Agent 调用？（必须注册 Action 且描述清晰）
7. **数据库需求**：需要哪些表？是否需要版本迁移？
8. **目标版本**：声明在 `manifest.engines.openlearn` 中的**宿主版本**范围（**不是** SDK 版本）。
   **按实际用到的 API 的最低宿主版本填写，不要一律抄 `>=0.2.5`** —— 写低了不会报错，
   但插件会在旧版本上装着、用到新 API 时才崩。速查表见 `references/manifest-0.7.md` §11：
   只用 `ctx.log`/`ctx.config` → `>=0.2.3`；用 `ctx.http` → `>=0.3.11`；
   用声明式 `contributes` 或前端沙箱行为 → `>=0.7.0`。

---

### 第三步：生成代码与编码规范

#### 1. 模板对照

| 模板 | 位置 | 生成文件 |
|------|------|---------|
| server-only | `assets/server-only/` | `package.json`, `tsconfig.json`, `src/index.ts` |
| full-stack | `assets/full-stack/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx`, `src/contracts/index.ts` |
| frontend-only | `assets/frontend-only/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx` |

> 模板与官方 CLI 脚手架（`packages/plugin-sdk/scaffold/templates/`）保持同源。
> 若两者不一致，以**官方脚手架 + 平台源码**为准，并回来修正本 skill 的模板。
>
> 生成代码后**立刻铺测试护栏**（复制 `assets/test-harness/`，见「第四步 B」）——
> 先让 L0 绿，再写业务逻辑；否则 manifest / 三件套的错会一直漏到课堂现场。

占位符：

| 占位符 | 含义 | 官方 CLI `init` 自动替换 |
|--------|------|------------------------|
| `{{name}}` | npm 包名（小写连字符） | ✅ |
| `{{pluginId}}` | 插件全局 ID，如 `@scope/plugin-name` | ✅ |
| `{{pluginName}}` | 显示名称 | ✅ |
| `{{description}}` / `{{author}}` | 描述 / 作者 | ✅ |
| `{{sdkVersion}}` | SDK 版本号 | ✅ |
| `{{commandPrefix}}` | 命令前缀（如 `classpolls`） | ❌ 手动替换 |
| `{{toolId}}` / `{{toolName}}` | classroomTools 的 id / name | ❌ 手动替换 |
| `{{tabId}}` | 前端 tab ID | ❌ 手动替换 |

#### 2. 关键编码规范与防御规则 (Mandatory Guardrails)

1. **`manifest.main` 必填**：`manifestSchema` 中 `main: z.string().min(1)` —— **缺失会导致插件装不上**。
2. **Manifest 1:1 映射约束**：声明的每个 `commandType`（`classroomTools` / `contributes`）都必须
   - 在 `activate()` 中 `registerHandler(type, { async execute(command) {...} })`（**必须是对象，不是裸函数**）；
   - **并且** 在 `actionRegistry.register()` 中登记同 `commandType` 的 ActionDescriptor。
   > 内核对命令派发实行 **default-deny**：没有 ActionDescriptor 的命令会被拒（`COMMAND_NOT_REGISTERED`，HTTP 403）。
   > 只注册 handler 不注册 action，是最常见的「课堂工具点了没反应」根因。
3. **命令类型命名空间（三种语义，别混）**：

   | 场景 | 宿主是否自动加 `manifest.id` 前缀 | 写法 |
   |------|-------------------------------|------|
   | `registerHandler(type)` | ✅ 自动加 | 短名即可（模板写 `{{commandPrefix}}.xxx` 是对的） |
   | `manifest.classroomTools[].commandType` / `manifest.contributes` 里的 commandType | ✅ 自动加 | 短名即可 |
   | 运行期 `ctx.ui.registerExtensionPoint(slot, { slotProps: { commandType } })` | ❌ **不前缀化** | **必须全限定** `{{pluginId}}.xxx` |

   > 同一个 `commandType` 字符串在 manifest 里可以写短名，但**注册 handler 时必须用完全相同的字符串**，
   > 否则 default-deny 找不到对应描述符 → `COMMAND_NOT_REGISTERED`。
4. **事件订阅 API**：`eventBus.subscribe(type, handler)` 返回 `Promise<void>`（**没有 Disposable**）；
   退订是 `eventBus.unsubscribe(type, handler)` —— 必须自己保留 handler 引用。
   宿主在停用时会自动退订并注销 handler，插件只需清理**宿主管不到**的资源（自建定时器、子进程、第三方连接）。
5. **远程前端不得使用 React / DOM**：`frontend.tsx` 里禁止 `import React`、`document.`、`window.`、`fetch(`。
   远程插件前端跑在 `sandbox="allow-scripts"` 的隐藏 iframe 里，`window.HostSharedDeps` 为 `undefined`，
   官方 CLI 构建的远程前端插件一旦用到 React/JSX 就**必然激活失败**。
   详见 `references/frontend-bridge-0.7.md`。
6. **可见 UI 走声明式**：`manifest.contributes` / `manifest.classroomTools` 由宿主渲染；
   运行期只允许注册**数据型**扩展点（`slotProps`），传 `component` 会 `DataCloneError`。
7. **数据库**：`ctx.db.ensureTable()` 是异步的必须 `await`；`ctx.db.table()` 同步返回带前缀的表名；
   `ctx.db` **没有** `prepare()` —— 需要裸 SQL 时用 `const rawDb = await ctx.resolve(IDatabaseToken)`，
   且 `await rawDb.prepare(sql).run(...)` 可同时兼容 inline（同步）与 process 沙箱（Promise）。
8. **Node 原生模块避坑**：用 `crypto.randomUUID()`（全局），不要 `import { randomUUID } from 'crypto'`；
   文件读写用 VFS API，不要 `fs` / `path`（token-enforcer 会拦截裸导入）。
9. **跨插件服务共享要三步配套**：`src/contracts/index.ts` 里 `new Token(...)` →
   本插件 manifest `provides` → 消费方 manifest `requires`。
   缺 `provides` 声明 → `ctx.provide()` 直接抛错；提供方未 ACTIVE → 消费方激活被拒。
   详见 `references/manifest-0.7.md` §13。
10. **远程前端无法自行联网**：沙箱 iframe 的 CSP 是 `connect-src 'none'`，`fetch` 与 socket 全部不可用；
    宿主也不会把事件推给 iframe。**实时同步只能轮询**（`ctx.invokeCommand` / `frontendApi`）。
    详见 `references/frontend-bridge-0.7.md` §7。
11. **数据库迁移**：ZIP 分发场景用 `ctx.db.ensureTable()` + `ctx.db.migrate(version, fn)`；
    **不要**依赖声明式 `migrations/*.sql` —— 官方 CLI 不打包该目录，装上后迁移会静默失效。
    详见 `references/manifest-0.7.md` §12。

#### 3. Manifest 关键字段（v0.7.x）

- `engines.openlearn`：**宿主版本**范围，按**实际用到的 API 的最低版本**填（不是一律 `>=0.2.5`）；
  速查表见 `references/manifest-0.7.md` §11。
- `main`：**必填**。
- `capabilitiesProposed`：只能是平台真实存在的能力字符串（见「权限全集」）。
- 按目标版本可用的新字段：`api.routes`（`ctx.http`，0.3.11+）、`provides`、`optional`、
  `pluginDependencies`、`contributes`（含 v0.7.0 的 `contributes.locales` 国际化）、
  `configuration.properties[].scope`（平台/学校/班级三层覆盖）、`network.outbound`（v0.7.2 出站域名申请）、
  `updateSource`、`deploy`。
- `api.baseRoute` 是**历史遗留 no-op**，新插件不要写。
- 完整字段与 Zod 校验规则见 `references/manifest-0.7.md`。

---

### 第四步：构建与脚本化预检

```bash
cd <plugin-directory>
npm install
npx @openlearn/plugin-sdk build     # 或 npm run build
```

> **上游不一致提醒**：以 **npm 发布版** `@openlearn/plugin-sdk` 为准（`npx @openlearn/plugin-sdk init` 拿到的才是桥接模板）；
> 平台仓库 `main` 分支的脚手架模板可能滞后于已发布版本（详见 `references/frontend-bridge-0.7.md` §9）。

产物：`dist/index.js`（+ 可选 `dist/frontend.js`）与根目录含 `manifest.json` 的 `.zip`。
**ZIP 根目录必须是 `manifest.json` + `index.js` +（可选）`frontend.js`**，嵌套一层目录会导致安装失败。

> ⚠️ **ZIP 里只有这三个文件**（官方 CLI 的打包内容），`migrations/` 等目录**不会**进包 —— 详见 `references/manifest-0.7.md` §12。

> **维护本 skill 模板时**（这是维护者的命令，不是给使用者的）：
> ```bash
> bash scripts/check-templates.sh          # 模板/文档一致性：main、engines、ActionDescriptor 配对、占位符、废弃写法
> bash scripts/verify-templates-build.sh   # 三套模板真实构建 + tsc --noEmit + 产物体检
> bash scripts/diff-official-scaffold.sh   # 与官方 CLI 脚手架比对契约（官方有、我们缺 → 失败）
> bash scripts/verify-test-harness.sh      # 测试护栏自检：模板 L0 必须绿 + 反例必须被抓到
> ```
> 给用户开发插件时**不要**跑这四个脚本（各文件的适用对象见「资源文件说明」）。

#### 构建产物预检清单 (Pre-flight Inspection)

- [ ] **manifest.main 存在**：`grep -q '"main"' manifest.json`
- [ ] **三件套映射**：`manifest.classroomTools[].commandType` / `contributes` 里引用的每个 commandType，
      都能在 `src/index.ts` 里找到**同名的 `actionRegistry.register` + `registerHandler`**
- [ ] **裸导入非法引用**：`grep -E '^import .+ from "[^@\./]' dist/index.js` 应无输出
- [ ] **前端产物无裸说明符**（3.7.2+ CLI 会直接拦）：`grep -nE "(from|require\(|import\() *['\"][^./]" dist/frontend.js` 应无输出
- [ ] **远程前端无 React**：`grep -nE "from ['\"]react|document\.|window\." dist/frontend.js` 应无输出
- [ ] **Worker/Process 兼容**：非 inline 模式下不得使用 `ctx.config` / `ctx.provide()` / `child_process` / `worker_threads` / `eval`
- [ ] **清理 SOP**：`deactivate()` 中处理了自建定时器 / 子进程 / 第三方连接
- [ ] **L0 + L1 已通过**：`npm run test:contract` 0 error、`npm test` 全绿（见「第四步 B」；人工预检不漏项，自动化防回归）

---

### 第四步 B：测试护栏（开发期把问题炸出来）

> **L0 未 0 error、L1 未全绿，不得进入第五步。**
> 原因很直接：平台的 default-deny、能力校验、沙箱边界只在运行期生效，
> 「能 build、能装上」不等于「能用」—— 这些正是本地测试必须提前模拟的部分。
> 完整方法论见 `references/testing-strategy.md`，护栏源码在 `assets/test-harness/`。

#### 1. 四层阶梯（成本递增，覆盖不同失效面）

| 层 | 手段 | 耗时 | 抓什么 |
|----|------|------|--------|
| **L0** | `node test-harness/static-check.mjs .` | <1s | manifest 必填项 / 权限串真伪 / 三件套配对 / 裸导入 / 前端越界 / process 禁用 API / DB 表名与分号 / type-only 误用 / 密钥泄漏 |
| **L1** | `vitest run` 的 `contract.test.ts` | ~0.3s | 声明的入口与实际注册是否一致、handler 是否为 `{execute}` 对象、`capabilityRequired` 是否真实、`inputSchema` 类型名 |
| **L2** | `vitest run` 的 `smoke.test.ts` | ~0.3s | 重复激活状态泄漏、命令执行期 `TypeError`、REST 路由 5xx、事件 payload 形状、停用未退订 |
| **L3** | 真实宿主机：上传 → 激活 → 点入口 → 停用 | 3–10 min | Mock 与生产宿主的差异（能力审批、process 沙箱、熔断、全限定 commandType） |

#### 2. 铺开（每个插件项目一次）

```bash
# 在插件项目根目录
cp -r <skill>/assets/test-harness ./test-harness
npm i -D vitest @openlearn/plugin-test-kit better-sqlite3 uuid zod
npm pkg set scripts.test:contract="node test-harness/static-check.mjs ." \
            scripts.test="vitest run --config test-harness/vitest.config.ts"
```

> `uuid` / `zod` 不是可选项：SDK 3.7.4 的 `dist/index.js` 引用了**未声明**的 `uuid`（`zod` 是 peerDep），
> 不装会在 `import('@openlearn/plugin-sdk')` 时直接 `Cannot find package 'uuid'`。属平台打包缺陷，已记入
> `references/testing-strategy.md` §6。

#### 3. 跑

```bash
npm run test:contract   # L0
npm test                # L1 + L2
```

#### 4. 六件必测事项（缺一视为未测）

1. **三件套配对**：manifest 里每个 `commandType` 同时有 `registerHandler` + ActionDescriptor（双向检查）。
2. **handler 形状**：必须是 `{ execute }` 对象；裸函数在 Mock / Worker / Process 下都报 `handler.execute is not a function`。
3. **权限真伪**：`capabilitiesProposed` 与每个 `capabilityRequired` 都 ⊆ 平台真实 20 条（`references/capability-matrix-0.7.md`）。
4. **执行期不崩**：按 `inputSchema` 造最小 payload 跑每条命令，不得出现 `TypeError` / `ReferenceError`（业务校验错误可抛）。
5. **生命周期可重入**：`activate → deactivate → activate` 不抛错，同一事件订阅数不翻倍。
6. **前端边界**：无 React / DOM / `fetch` / 裸模块说明符 / `component`（L0 静态即可；L1 只读 `slotProps`）。

#### 5. 测试先行写法

- 新增命令：**先**在 `contract.test.ts` 写期望（红）→ 实现 → 转绿。
- 命令里出现深层解构（`payload.a.b`）：**补一条 L2 用例**，让 `undefined` 在本地暴露，而不是课堂现场。
- **反向验证**：故意删掉一个 ActionDescriptor，确认 L0/L1 变红。没红过的护栏等于没有护栏。
- 改 manifest 权限/入口后，先跑 L0 再跑 L1：L0 报错信息更精确（带错误码）。

#### 6. 测试红了先归因，不要改宽断言

| 现象 | 归属 | 动作 |
|------|------|------|
| `Cannot find package 'uuid' / 'zod'` | 环境 | 按第 2 节补依赖 |
| `handler.execute is not a function` | 插件侧 | 把裸函数改为 `{ execute }` |
| `Cannot read properties of undefined` | 插件侧 | 补判空 / 修 payload 形状 |
| 权限断言失败（串不存在） | 插件侧 | 换成真实权限串 |
| 权限正确但运行期仍被拒 | 环境与配置 | 管理员未审批（v0.7.2 起按已授予集合判定） |
| Mock 行为与生产不一致 | 产品边界 | 见 `references/testing-strategy.md` §5，补 L3，**不改断言迎合 Mock** |
| test-kit 自身报错 | 环境 | 核对 vitest 版本 / `server.deps.inline` / `better-sqlite3` |

#### 7. L3 真实宿主冒烟

交付前按 `references/testing-strategy.md` §7 的 10 步清单跑一遍，重点四项：
**课堂工具按钮点击** · **Ctrl+K 条目派发（验证全限定 commandType）** · **AI 自然语言触发 Action** · **停用再激活无重复**。

---

### 第五步：安装与验证

在 OpenLearn 管理后台上传 `.zip`：

1. **管理后台** → 系统设置 → 插件中心 → 上传插件
2. **激活插件**：检查服务日志输出带 `[Plugin:<id>]` 前缀；注意第三方插件会被强制以 `process` 模式运行
3. **工具验证**：若声明了 `classroomTools`，进课堂白板确认按钮出现、点击有事件流回显
4. **AI 工具测试**：发送自然语言命令，确认 Agent 能识别并触发 Actions
5. **路由验证**：`api.routes` 声明 `auth: false` 的接口**还需管理员批准**才会匿名放行，否则 401

### 完成定义（全部满足才算做完）

- [ ] 官方 CLI 构建成功，产出 `.zip`
- [ ] 生成的 `manifest.json` 通过平台 `manifestSchema` 校验（`main` 必填、字段合法）
- [ ] 每个 `commandType` 都有同名 ActionDescriptor（否则 `COMMAND_NOT_REGISTERED`）
- [ ] 管理后台能激活，服务日志无 `[Plugin:<id>]` 错误
- [ ] 可见入口已按第二步选定的通道验证（课堂工具按钮 / 命令面板条目 / toast）
- [ ] `engines.openlearn` 与实际用到的 API 匹配（见 `references/manifest-0.7.md` §11）
- [ ] L0 静态契约检查 0 error（`npm run test:contract`）
- [ ] L1/L2 契约 + 冒烟测试全绿（`npm test`）
- [ ] L3 真实宿主冒烟通过（按钮点击 / Ctrl+K 派发 / AI 触发 / 停用再激活）

### 交付格式（每次生成插件后按此汇报）

```
【插件】<pluginId> · <类型> · engines >=<x.y.z>
文件：<生成的相对路径清单>
构建：npm install && npx @openlearn/plugin-sdk build
安装：上传 <dist 中的 zip 文件名>
已实现：<功能点 1..N>
测试：L0 <0 error|N error> · L1/L2 <n passed / n failed> · L3 <已跑|未跑（原因）>
已核对：main / ActionDescriptor 配对 / 权限串 / 可见入口
待办：<需要用户做的事，如"管理员批准出站域名"、"申请某权限">
```

---

### 第六步：故障归因（插件侧 vs 系统侧）

当开发者报告「插件报错 / 不工作」时，**先归因，再动手**。完整方法见 `references/troubleshooting.md`，此处为速用版。

#### 0. 受理：用户直接粘贴报错时的固定动作

用户往往只贴一段报错（甚至只贴半截堆栈）。**按顺序做，不要跳步**：

1. **把报错归类到阶段**（决定查哪张表）：构建期 / 安装（上传）期 / 激活期 / 运行期 / 停用期。
   - `✖ frontend 产物里有裸模块说明符`、TS 报错 → 构建期
   - `Import of "x" is not allowed`、`manifest 校验失败` → 安装期
   - `ACTIVATING → ERROR`、`WorkerActivateError` / `WorkerTimeoutError` → 激活期
   - 命令 500 `COMMAND_NOT_REGISTERED`、前端白屏、事件不推送、DB 报错 → 运行期
2. **提取五要素**：平台版本 / SDK 版本 · `execution_mode`（inline / worker / process）· **堆栈顶层 3–5 帧的文件路径** · 触发操作 · 是否已用最小插件复现。
   - 缺版本号 → 先跑 `npx openlearn-next@<ver> doctor` 或读 `GET /health` 的 `version`，禁止用「最新版」代替。
   - 缺堆栈顶层路径 → 让用户贴完整堆栈（**不截断**），这决定归属。
3. **定位到源码再下结论**：在 `~/Develop/openlearnv2/packages/core/`、`packages/plugin-sdk/` 里
   用报错文案/符号名搜一次，确认是「平台按设计行事」还是「平台实现有缺陷」。
   - 报错文案能搜到 → 看该处是否有意抛错（default-deny、token-enforcer、熔断、权限审批），
     是设计行为就是**插件侧或产品边界**，不是系统缺陷。
   - 搜不到 / 逻辑明显写错（漏 await、白名单漏项、错误被吞、假超时）→ 才是系统侧。
4. **最小复现优先于口头判断**：先让用户用 server-only 模板做 ≤50 行插件（只留 manifest + 空 `activate`）
   复现；**能复现的才是系统侧**。
5. **输出归因 + 缘由**（格式见下），然后才决定是否改代码 / 提 Issue。

> ❗ 常见误判：报错文案由平台打印 ≠ 平台缺陷。
> 例：`import { randomUUID } from 'crypto'` 被拦是插件违规；声明了未授予的权限被拒是审批流程；
> 远程插件传 `component` 报 `DataCloneError` 是产品边界（remote 插件没有自定义 UI 通道）。

**高频报错的归属速查（先查表，再逐项验证；本表给方向，不给免验证结论）**

| 报错 / 现象 | 归属 | 缘由（机制层） |
|---|---|---|
| `✖ frontend 产物里有裸模块说明符`（构建失败） | 插件侧 | 沙箱 iframe 用 Blob + 动态 `import()` 加载，无 importmap，裸说明符无从解析；CLI 3.7.2+ 主动拦截 |
| `PluginRuntimeComposition is undefined` / 值导入宿主内部类 | 插件侧 | 3.7.2 起 7 个宿主内部类仅 type-only 导出，运行期无值 |
| `Import of "x" is not allowed` | 插件侧 | token-enforcer 白名单拒绝裸导入（`crypto` / `fs` / 第三方裸包） |
| `COMMAND_NOT_REGISTERED` / 403 | 插件侧 | 内核 default-deny：该 `commandType` 没有 ActionDescriptor |
| `COMMAND_CAPABILITY_DENIED` | 插件侧 / 配置 | 0.7.2 起按**已授予**集合判定，声明了但未审批 |
| `Cannot read properties of undefined (reading 'React')` | 插件侧 | 远程前端用了 React，沙箱内 `HostSharedDeps` 不存在 |
| `DataCloneError`（`registerExtensionPoint` 传 `component`） | 产品边界 | postMessage 无法克隆函数；远程插件就没有自定义 UI 通道 |
| 插件被自动停用 + 扩展点报错 | 产品边界 | 熔断器 3 次 / 5 分钟滑窗，设计行为 |
| `api.routes` 声明 `auth:false` 仍 401 | 产品边界 | `auth:false` 只是**申请**公开，需管理员批准 |
| Worker 下 `ctx.db.migrate` 报 `WorkerCapabilityError`（≤0.3.15） | 系统侧（已修复） | ServiceHost DDL 白名单漏 `plugin_migrations` |
| Worker 激活异常变 60 秒假超时（≤0.3.15） | 系统侧（已修复） | 看门狗误熔断 |
| `EUNSUPPORTEDPROTOCOL workspace:*`（安装） | 系统侧（已修复） | 制品打包带了 workspace 协议 |
| 声明式贡献「闪现后消失」（≤0.6.x） | 系统侧（已修复） | 缺显式错误态渲染 |
| 以上都不匹配 / 无堆栈 / 无版本号 | 待定 | 先补**五要素**与完整堆栈，再判 |

> 命中「已修复」行：先确认用户版本是否在受影响区间。升级后仍复现 → 属**回归**，可提 Issue 并引原修复记录。
> 完整「已知系统问题索引」与阶段决策树见 `references/troubleshooting.md` §3 与 §6。

**三条铁律**

1. **堆栈归属**：顶层帧在 `dist/index.js`、`dist/frontend.js` → 插件侧；在 `packages/core/...`、`src/plugin-host/...`、`node_modules/@openlearn/...` → 系统 / SDK 侧。
2. **对照实验**：官方脚手架原始产物、或 ≤50 行最小复现插件（仅 manifest + 空 `activate`）能否稳定复现——**能复现的才是系统侧**。
3. **先核版本与执行模式**：平台版本 / SDK 版本 / 插件 `engines.openlearn` / **实际执行模式（inline / worker / process）**。
   大量「系统 bug」其实是插件用了未来版本 API、声明了不兼容 engines，或依赖了被 process 沙箱禁用的能力。

**判为「系统侧」的 4 个必要条件（缺一即只能给「待定」）**

1. 官方脚手架原始产物或最小复现插件稳定复现；
2. 具体版本号、复现步骤、完整堆栈（不截断）齐全；
3. 报错点位于宿主 / 内核 / SDK / 文档承诺范围内，而非插件自身代码或构建配置；
4. 已排除：版本不匹配、产物未重新构建、浏览器缓存、热重载未生效、权限未审批、插件间冲突、
   **被强制改写为 process 执行模式**、**远程前端误用 React**。

**结论与动作**

| 结论 | 动作 |
|------|------|
| **插件侧** | 指出具体修改点，走第四步预检清单复查；**不生成报告、不提 Issue** |
| **系统侧** | ① 生成 bug 报告：`<插件项目根目录>/BUG-REPORT-<slug>-<YYYYMMDD>.md`（模板 `assets/bug-report-template.md`）；② 按「第六步 B」向平台仓库提 Issue（用户确认后执行） |
| **插件间冲突** | 定位命名空间 / 事件名 / 表名 / 槽位 id 撞车的双方并改名；**不提 Issue** |
| **环境与配置** | 给出修复步骤（升级 / 重建 / 强刷 / 重新审批 / 加白名单），不算缺陷；**不提 Issue** |
| **产品边界 / 设计行为** | 改插件写法或告知用户操作路径（如 remote 插件无 UI、熔断停用、`auth:false` 需审批）；**绝不提 Issue** |
| **待定** | 列出缺失的证据项与取证命令，收齐后重判；**不提 Issue** |

**必给的简要汇总（≤10 行）**

```
【故障归因】<插件侧 / 系统侧 / 插件间冲突 / 环境与配置 / 产品边界 / 待定>
现象：<一句话>
关键证据：
  1. <堆栈归属 / 版本与执行模式核对 / 对照实验>
判定依据：<为什么是这一类，而非另一类；哪一处机制导致的>
缘由：<机制层解释：默认丢包 / 白名单 / 沙箱隔离 / 熔断 / 审批流程 / 漏 await …>
建议动作：<修复方式 | 已生成报告：<路径> | 待提 Issue | 已提 Issue #<n>>
```

> 生成报告前务必确认已包含：**具体版本号、完整堆栈、最小复现插件**。缺这三项通常会被系统作者以「信息不足」退回。

### 第六步 B：系统侧缺陷上报（向平台仓库提 Issue）

> 仅在第六步结论为 **系统侧** 时执行。这是「问题缘由 → 影响 → 修复建议」的正式上行通道。
> 完整命令与异常处理见 `references/github-collaboration.md` §1A；正文模板：`assets/platform-issue-template.md`。

**固定仓库**：`aymwoo/OpenLearn-Next-V2`（缺陷模板前缀 `[缺陷] `，标签用仓库已有的 `bug` / `needs-triage`）

#### B1. 三项前置门禁（缺一即不提）

1. **证据门禁**：第六步「系统侧」4 个必要条件全部满足（尤其**最小复现稳定复现**）。
2. **去重门禁**：先查平台仓库既有 issue（含已关闭）与 `docs/beta/known-issues.md`。
   - 命中已修复版本 → 建议升级，不提新 Issue（升级后仍复现 → 属回归，提 Issue 并在正文注明「回归」与原 Issue 号）。
   - 命中开放 issue → **改为在该 issue 补充评论**（需用户确认），不重复开单。
3. **同意门禁**：把最终标题 + 正文完整展示给用户，明确确认后才 `gh issue create`。
   **绝不静默提交**（Issue 对仓库可读者公开可见）。

```bash
REPO=aymwoo/OpenLearn-Next-V2
# 去重：关键词 <错误号/错误文案/模块名>，含已关闭
gh issue list -R "$REPO" --state all --limit 50 \
  --search "<关键词> in:title,body" --json number,title,state,url,closedAt
# 同时对照仓库内的已知问题清单
rg -n "<关键词>" ~/Develop/openlearnv2/docs/beta/known-issues.md
```

#### B2. Issue 正文（三段必备，缺任一段视为不合格）

| 段 | 必须写清 | 常见不合格写法 |
|----|---------|---------------|
| `## 问题原因` | 定位到**具体代码路径 / 机制**：哪个包哪个文件哪一处逻辑（如 `packages/core/plugin-host/worker-runtime.ts` 的 DDL 白名单），版本口径（引入/影响版本），关键堆栈帧 | 「插件报错了」「可能是 bug」 |
| `## 影响` | 谁受影响（哪些插件类型 / 哪种执行模式 / 哪些用户角色）、阻塞程度（停用 / 降级 / 可绕过）、影响版本范围、是否有临时规避 | 「影响使用」 |
| `## 建议解决方式` | 改哪个文件/机制、可选方案与权衡、**验收标准**（修好后什么现象算通过） | 「请修复」 |

另必须含：**环境信息**（平台精确版本 `GET /health` / `npx openlearn-next@<ver> doctor`、SDK 版本、插件 id+版本、`execution_mode`、`engines.openlearn`、Node/浏览器/OS）、
**复现步骤 + 稳定性**、**期望 vs 实际**（附文档 URL 承诺）、**完整堆栈（不截断）**、**最小复现插件源码**、**已排除项**、**对照实验记录**、
以及仓库缺陷表单要求的三项：报告人角色（开发者）、对上课的影响、版本。

#### B3. 执行

```bash
REPO=aymwoo/OpenLearn-Next-V2
BODY=/tmp/openlearn-issue-<slug>.md   # 由 assets/platform-issue-template.md 渲染

gh issue create -R "$REPO" \
  --title "[缺陷] <模块/组件>：<一句话现象>" \
  --body-file "$BODY" \
  --label bug --label needs-triage
```

- 标题：`[缺陷] <模块/组件>：<现象>`，如 `[缺陷] plugin-host/worker：ctx.db.migrate 首启被 DDL 白名单拦截`。一句话说清「哪里 + 什么现象」。
  仓库既有 issue 里也有 `fix(plugin-host): …` 与 `[P1][文档] …` 写法，**沿用近期同类风格即可**，但模块 + 现象两者必须齐。
- 标签只用仓库已有 `bug` / `needs-triage`；**不自创标签、不 assign 他人、不在正文 @ 维护者**。
- 正文以自由格式提交（`gh issue create` 无法填写 yml 表单），所以把表单必填字段以纯文本列进「环境信息」。
- 最小复现插件体积小就把源码贴进正文；否则说明「可提供 zip，需要时提供」。

#### B4. 脱敏红线（仓库 issue 公开可见）

提交前逐项自查，命中即删：学生姓名全名册 / 作业或试卷原文 / 成绩导出 · 密码、班级临时口令、Cookie、`edu_os_token` ·
AI API Key（**连首尾几位掩码也不行**）· `.env`、`ENCRYPTION_KEY`、`bootstrap-credentials.txt` 内容 · 身份证 / 住址 / 电话 / 健康信息。
需要定位请求时只写 `x-request-id`；需要指代学生时用「3 班第 2 次作业」。

#### B5. 幂等与失败回退

| 情况 | 动作 |
|------|------|
| 已提过同问题（自己的 issue 仍在开放） | 不再新开，改为补充评论（需确认） |
| 同关键词有他人开放 issue | 不重复开单，建议在其下评论或订阅 |
| `gh` 未登录 / 无权限 | 不重试刷屏；保留本地 `BUG-REPORT-*.md`，并给出 `https://github.com/aymwoo/OpenLearn-Next-V2/issues/new` 手动提交指引 |
| 网络失败 / 429 | 报告原文错误，保留已渲染的正文文件路径，不自动循环重试 |
| 提交成功 | 输出 issue 号与 URL，并提示用户把本地报告的附件（zip / 日志）按需补到 issue |

#### B6. 上报后的输出（≤8 行）

```
【系统侧缺陷已上报】
Issue：#<n> <url>
原因：<一句话机制层原因（哪个包/哪处逻辑）>
影响：<影响面 + 阻塞程度 + 规避方案>
建议：<修复方向>
本地留存：<BUG-REPORT-*.md 路径>
```

---

### 模式 A 红线

1. 默认**只生成文件与命令**，不替用户执行 `npm install` / 构建 / 上传 / 激活（用户明确要求时才执行）。
2. 不覆盖用户项目中已存在的文件；目标目录非空时先说明并确认。
3. 不修改用户的 git 状态（不 commit / 不打 tag / 不 push），除非用户明确要求。
4. 权限字符串、宿主版本、槽位名等**不确定时不猜**：先查 `references/`，仍不确定就问用户。
5. 需求有歧义时先问，不擅自扩大范围（尤其"要不要建表""要不要申请高危权限""要不要占新槽位"）。
6. 归因未达「系统侧」证据门槛时，**不生成 bug 报告、不提 Issue**，只给结论与取证命令。
7. 提 Issue 是**公开可见动作**：必须先把标题 + 正文全文给用户看并得到明确同意，绝不静默 `gh issue create`。
8. 不代替用户编造证据：缺版本号、缺完整堆栈、缺最小复现时，先要证据，不拿猜测填进 Issue。
9. **交付前必须给出测试结果**：L0 0 error + L1/L2 全绿；没跑就是没跑，不许写「应该没问题」。
10. **测试失败不改宽断言**：先按「第四步 B」第 6 节归因，是插件问题就改实现，是 Mock 差异就补 L3。

---

## 模式 B：GitHub Issue / PR 协作工作流

> 详细命令、异常处理与输出模板见 `references/github-collaboration.md`。本节只给流程骨架与不可跳过的门禁。

### B0. 适用范围与仓库定位

- 默认仓库：`aymwoo/OpenLearn-Next-V2`（平台）与 `openlearn-next/*`（插件）。
- 定位顺序：issue/PR URL → 当前目录 git remote → 已知本地路径 → 询问。
- 本地路径：平台 `~/Develop/openlearnv2`；插件 `~/Develop/openlearn-plugins/<repo>`。
- 本地不存在时先问是否 clone；绝不跨到无关仓库。
- 无 `project` scope：不要尝试更新 Projects 看板，统一用 assignee + `in-progress` 标签表达状态。

### B1. 接管 issue：先占位，再开发

预检（任一不满足就停）：issue 仍 OPEN；未 assign 给其他人（已 assign 给自己则幂等继续）；
没有引用该 issue 的开放 PR 或他人远程分支；正文有可验证的验收标准。

```bash
gh issue edit <n> -R <repo> --add-assignee @me
gh issue edit <n> -R <repo> --add-label in-progress   # 缺失时先创建
gh issue comment <n> -R <repo> --body-file <占位评论>
```

### B2. 创建 worktree

- 平台：`~/Develop/openlearn-issue-<n>`；插件：`~/Develop/openlearn-plugins/<repo>-issue-<n>`
- 分支：`<type>/issue-<n>-<slug>`，从 `origin/main` 创建
- 路径已存在时：同分支且干净 → 复用；否则停止，绝不覆盖

```bash
git -C <local> fetch origin --prune
git -C <local> worktree add -b <branch> <worktree> origin/main
```

### B3. 开发与本地验证

- 先读仓库 `AGENTS.md` / `CLAUDE.md` / `README.md` / `package.json`，以其约定为准。
- 平台：worktree 内先 `pnpm install --frozen-lockfile`；改动用例 `pnpm vitest run <path>`；
  开 PR 前跑 `pnpm lint && pnpm lint:strict`（即 `tsc --noEmit`），全量测试交给 CI。
- 插件：只跑 `package.json` 中实际存在的脚本；`interactive-courseware` 的 `build` 会 bump 版本，非必要不跑。
- 提交：`<type>(<scope>): <中文摘要>（Issue #<n>）`，1-3 个逻辑提交，不夹带无关改动。

### B4. 提交 PR（确认门 2）

push 前展示 diff stat、提交列表、测试命令与结果、PR 标题/正文，确认后：

```bash
git -C <worktree> push -u origin <branch>
gh pr create -R <repo> --base main --head <branch> --title "<title>" --body-file <body>
```

PR 正文必须包含：`## 变更内容`、`## 关联 Issue`（`Closes #<n>`）、`## 测试计划`（真实命令与结果）、
UI 改动的 `## 截图`、`## 风险与回滚`。一个 issue 一个 PR。

### B5. CI

```bash
timeout 600 gh pr checks <pr> -R <repo> --watch --interval 30
```

本次改动导致的失败 → 自动修 1 轮并重推；环境/flaky/基线失败 → 停止汇报，不反复重跑；CI 未绿不合并。

### B6. 审查 PR

先输出只读状态卡（作者、CI、评审、可合并、改动量、关联 issue、未解决评论），再让用户选动作：
审查 / 修评论 / 合并 / 仅解释。评审意见先在对话里出草稿，确认后才 `gh pr review`。
自己的 PR 不能 approve，只能 comment；有阻塞项不得 approve；不替别人 resolve 讨论串。

### B7. 返工

按 review thread 逐条修复，回复 commit hash；普通 push 优先。
`--force-with-lease` 仅限自己的 PR 分支 + 确认；永不 force-push main。
意见要求扩大范围时先汇报，等用户决定。

### B8. 合并

仅在用户明确说「合并」时执行，且满足：CI 全绿、mergeable、无 changes-requested、评论已处理、用户再次确认最终 commit message。

```bash
HEAD_SHA=$(gh pr view <pr> -R <repo> --json headRefOid --jq .headRefOid)
gh pr merge <pr> -R <repo> --squash --match-head-commit "$HEAD_SHA" --subject "<title>" --body "<summary + Closes #n>"
```

> 不使用 `--delete-branch`（分支正被 worktree 占用时，gh 删除本地分支会失败）。
> `--match-head-commit` 防止确认后 PR 又追加提交；被拒绝说明头指针已变，重新审查后再合并。
> 合并后校验 PR 状态与 issue 是否自动关闭；不加 `--admin` / `--auto`。

### B9. 清理

合并后先删远程分支（若仍存在），再移除 worktree、删除本地分支；每一步都先询问。
有未提交改动时永不删除。PR 关闭未合并：保留 worktree，移除 `in-progress`，留言先确认。
开工前巡检陈旧 worktree，只列出、不自动删。

### 模式 B 红线

1. 绝不直接 push `main`；所有变更走分支 + PR。
2. 绝不未经明确指令合并 PR。
3. 绝不 force-push main 或共享分支。
4. 绝不自动删除 worktree / 分支；清理必须确认。
5. 绝不覆盖已存在的目录或分支。
6. 绝不未经确认发布公开内容（assign、评论、review、approve、合并）。
7. 不确定就停：仓库、权限、归属、验收标准任一不清楚，先问用户。

---

## 知识库与速查字典 (Reference Dictionaries)

### 1. 内核 Service Token & 接口方法速查

`ctx.services`（**9 个**，其中 `pointsDimension` / `pointsLedger` 在非 inline 模式恒为 `null`，使用前必须判空）：

| 服务 Token | 获取途径 | 核心 API |
| :--- | :--- | :--- |
| `ICommandBusServiceToken` | `ctx.services.commandBus` | `registerHandler(type, { execute })`（自动加 manifest.id 前缀）<br>`unregisterHandler(type)`<br>`execute(command)` / `createCommand(type, payload, actorId)` |
| `IEventBusServiceToken` | `ctx.services.eventBus` | `publish(event)`<br>`subscribe(type, handler): Promise<void>`<br>`unsubscribe(type, handler)` |
| `IActionRegistryServiceToken` | `ctx.services.actionRegistry` | `register(descriptor)`（必填 `id` `commandType` `description` `inputSchema` `capabilityRequired`；可选 `isHighRisk` `exposeToAgent`）<br>`unregister(id)` |
| `IDatabaseToken` | `ctx.resolve(IDatabaseToken)` | 裸 better-sqlite3；inline 同步、process 沙箱为 Promise 代理 —— 统一 `await` 使用 |
| `ICapabilityServiceToken` | `ctx.services.capability` | `check(actor, cap)` / `grant(actor, cap)` / `revokeAll(actor)` |
| `IProcessServiceToken` | `ctx.services.processManager` | `spawn(options)` / `kill(pid)`（**process 沙箱下禁用子进程**） |
| `IStorageServiceToken` | `ctx.services.storage` | `get(key)` / `set(key, val)` / `delete(key)` |
| `IAIServiceToken` | `ctx.services.ai` | `generateText(prompt, options)` |
| `IPointsLedgerServiceToken` / `IPointsDimensionRegistryToken` | `ctx.services.pointsLedger` / `pointsDimension` | 积分流水 / 维度注册（可空） |

`ctx` 上还有：`ctx.i18n.t(key, default?, params?)`、`ctx.config.get(key, { classId })`、`ctx.http`（REST 路由）、
`ctx.contributions.list()`、`ctx.require(moduleName)`、`ctx.manifest`、`ctx.pluginId`、`ctx.log`。

### 2. Capabilities 权限全集（v0.7.7 / SDK 3.7.4 真源，20 条，与官方矩阵逐条一致）

平台真实存在 **20 条** `resource:action` 权限：

`management:read` `management:write` `lesson:read` `lesson:write` `lesson:delete`
`whiteboard:read` `whiteboard:write` `student:write` `plugin:read` `plugin:write`
`vfs:read` `vfs:write` `process:read` `process:write`
`assignment:read` `assignment:write` `assignment:submit` `assignment:review` `assignment:manage`

**⚠️ 不存在、写了也不生效的写法**（平台文档明文「切勿捏造」）：

| 捏造写法 | 正确做法 |
|----------|----------|
| `user:read` | `management:read` |
| `system:process` | `process:read` / `process:write` |
| `ai:invoke` | AI 层用 `capability_*` ID，不是 RBAC 字符串 |
| `network:fetch` | `manifest.network.outbound` 申请 + 管理员批准域名白名单 |

> 完整映射、4 套「能力」机制的辨析、错误码见 `references/capability-matrix-0.7.md`。

### 3. UI 扩展槽位与真实 Props

**所有**经 `ExtensionPointRenderer` 渲染的槽位组件都收到：

```ts
{ lessonId: string | null, classId: string | null, route?: string, ...slotProps }
```

- `student.view` 额外收到 `{ studentId }`（仅 `StudentDashboardPanel` 调用点）
- `teacher.tab` 的 panel 形态额外收到 `{ renderType: 'panel' }`；button 形态由宿主自行渲染导航按钮
- **没有** `HostContext`、**没有** per-slot 的 `userId` / `role` / `socket` 注入

常用槽位（全集 **120** 个 —— 以源码 `src/plugin-host/types.ts` 的 `ExtensionSlot` 联合类型为准；
官方文档 2026-10-26 记 115，槽位仍在持续新增）：

| 槽位 | 说明 |
|------|------|
| `teacher.tab` | 教师侧边栏标签页（声明式：`id` `label` `icon` `position`） |
| `teacher.panel` | 教师独立全宽面板 |
| `teacher.dashboard.widget` | 教师仪表盘小组件 |
| `student.view` / `student.lesson.tool` / `student.fullscreen` | 学生端视图 / 课中工具 / 全屏考试 |
| `classroom.tool` | 课堂工具架按钮（声明式：`id` `name` `commandType` `payload`） |
| `global.setting` / `nav.user_menu` | 全局设置页 / 顶部用户菜单 |
| `editor.palette_item` | 备课画板图元（**不是** `palette.item`） |
| `command_palette.item` | 命令面板条目（数据型，远程插件的可见入口通道） |
| `anchor:<区域>:<锚点id>` | 宿主原生按钮前后插入（如 `anchor:whiteboard-toolbar:rollcall`） |

> 远程插件**只能注册数据型扩展点**（`slotProps`）。传 `component` 会 `DataCloneError` 导致激活失败。

### 4. 共享依赖与打包口径（v0.7.x）

| 场景 | 口径 |
|------|------|
| 宿主共享（仅 inline / 宿主父 realm 有效） | `react` `react-dom` `react-dom/client` `react/jsx-runtime` `recharts` `lucide-react` |
| **远程（process 沙箱）插件前端** | `window.HostSharedDeps` 为 `undefined` —— **不得依赖 React**，官方 CLI 构建的远程前端插件用 React/JSX 必然激活失败 |
| 必须自行打包（**仅 inline 内建插件有意义**） | `socket.io-client` `zustand` `motion` `react-konva`/`konva` `react-markdown` `exceljs`（**不是 xlsx**）`jspdf` `jspdf-autotable` `uuid` —— 远程插件前端连 socket 都用不了（见 §5 实时同步） |
| `ctx.require()` 白名单 | `recharts` `react-markdown` `jspdf` `jspdf-autotable` `exceljs` `lucide-react` `uuid` |

### 5. 执行模式差异（v0.7.x）

v0.7.0 起第三方插件被策略层**强制改写为 `process` 子进程模式**（`inline` / `worker_threads` 仅限受信任的内建插件）。

| 能力 | inline | process 沙箱（第三方默认） |
|-------|--------|---------------------------|
| `ctx.config` / `ctx.provide()` | ✅ | ❌ 不可用 |
| `ctx.services.eventBus` | `subscribe` / `unsubscribe` | `subscribe` / `unsubscribe`（同名，签名一致） |
| `commandBus.execute()` 命令前缀 | 自动加 `manifest.id` | 手动拼全限定名 |
| `ctx.db.migrate(version, fn)` | 同步 better-sqlite3 | 异步 `prepare().run/get/all`（**无** `exec` / `transaction`） |
| `ctx.db.table()` 前缀 | `plugin_<安装行UUID>_` | 同左（**两模式已统一**） |
| `ctx.pluginId` | 安装行 UUID | 同左（`ctx.manifest.id` 才是 manifest ID） |
| 文件访问 | 宿主全部权限 | 仅插件目录 + 宿主 `node_modules`（只读） |
| `child_process` / `worker_threads` / `eval` | ✅ | ❌ 全部禁止 |
| 出站网络 | 不受限 | 默认拒绝，仅管理员批准域名由宿主代发 |
| `ctx.http` | 完整 | 完整（RPC 跨进程，5000ms 熔断） |
| **前端实时同步** | 可用 socket / DOM | ❌ **只能轮询**：iframe CSP `connect-src 'none'`，且宿主不向 iframe 推事件（见下方说明） |

> 完整信任边界见 `references/execution-trust-boundary.md`。

#### 远程前端为什么只能轮询

沙箱 iframe 的 CSP 是 `default-src 'none'; script-src 'unsafe-inline' blob:; **connect-src 'none'**; style-src 'none'; img-src 'none'`，
且宿主只向 iframe 发三种消息（`load` / `reply` / `deactivate`），**没有事件推送通道**。

因此远程插件里：

- ❌ `fetch` 被 CSP 禁掉（连宿主自己的 API 都连不上）
- ❌ 自带 `socket.io-client` 也连不上
- ✅ **只能轮询**：`ctx.invokeCommand(type, payload)` 或 `ctx.services.frontendApi.get(path)`（均由宿主代发 HTTP）
- ✅ 用户反馈：`ctx.ui.showToast(...)`（宿主代发，iframe 内唯一可用的弹提示通道）
- ✅ 可见界面：只能靠 manifest 声明式贡献（宿主渲染）与课堂事件流

详见 `references/frontend-bridge-0.7.md` §7。

---

## 调试 SOP 与故障排查指南 (Troubleshooting SOP)

> 本表是「症状 → 直接处理」的速查。**若需判定责任方（插件侧 vs 平台插件系统侧）、讲清缘由并决定是否向平台仓库提 Issue，请先走第六步，并阅读 `references/troubleshooting.md`。**

| 现象 / 报错信息 | 可能原因 | 解决办法 (SOP) |
| :--- | :--- | :--- |
| `ReferenceError: React is not defined` | 前端用了经典 JSX 但没显式导入 React | **远程插件正解是不写 React**：改走 manifest 声明式贡献；若确为内建 inline 插件，第一行 `import React from 'react';` 并确认 `react` 已 external |
| `Cannot read properties of undefined (reading 'React')` | 远程前端插件用了 React —— 宿主注入的 `window.HostSharedDeps` 在沙箱 iframe 内不存在 | 移除 React / JSX 依赖，改用 `manifest.contributes` 与 `ctx.ui.showToast` |
| `DataCloneError`（激活失败） | 在 `registerExtensionPoint` 里传了 `component` 函数 | 改为**数据型**扩展点：`{ id, label, slotProps: { commandType, payload } }` |
| `COMMAND_NOT_REGISTERED` / HTTP 403 | 命令没有 ActionDescriptor（default-deny） | 在 `actionRegistry.register()` 里为该 `commandType` 登记描述符（`capabilityRequired` 必填） |
| `COMMAND_CAPABILITY_DENIED` | 权限未声明或未获批（v0.7.2 起按**已授予**能力集判定） | 在 `capabilitiesProposed` 声明**真实存在**的权限串，并在管理后台批准 |
| `TOKEN_NOT_FOUND: Service Token 'xxx' is not registered` | `manifest.requires` 漏声明 | 补 `requires`：`@scope/domain:IServiceName@^x.y.z` |
| `HANDLER_ALREADY_EXISTS` | 同一 commandType 重复注册 | 检查是否重复激活；宿主已在停用时自动注销 handler |
| `empty manifestCapabilities, only 'get' methods allowed` | process/worker 模式下 `capabilitiesProposed` 为空 | 声明真实存在的权限串 |
| `Import of "<module>" is not allowed` | 产物残留裸导入（`crypto`/`fs`/`path`/第三方裸包） | 用 `crypto.randomUUID()`；文件走 VFS；依赖必须打进 bundle |
| `✖ frontend 产物里有裸模块说明符`（CLI 构建失败，3.7.2+） | `frontend.js` 里残留 `from 'x'` / `require('x')` / `import('x')` 形式的裸说明符 | 前端不要 import React / 第三方包；能力全走 `ctx.services.*`，依赖交给 bundler 内联（相对路径不受影响） |
| `PluginRuntimeComposition is undefined` / 值导入宿主内部类得到 `undefined` | 3.7.2 起这 7 个符号是 **type-only** 导出 | 改 `import type`；宿主内部实现从 `packages/core/plugin-host/*.js` 取，插件本不该直接 new 它们 |
| 白板工具栏样式错乱 / 按钮被挤压 | `classroom.tool` 槽位里塞了面板 DOM | 远程插件根本不能渲染 UI；可见入口改走 `classroomTools` 声明 + 后端命令 |
| 远程插件前端无法自行联网 / 收不到推送 | 沙箱 iframe CSP 为 `connect-src 'none'`，宿主也不向 iframe 推事件 | 改为**轮询**：`ctx.invokeCommand(...)` 或 `frontendApi.get(...)`（均由宿主代发）；反馈用 `ctx.ui.showToast` |
| 声明式迁移未执行（表不存在） | 官方 CLI 不打包 `migrations/`，装上后迁移被静默跳过 | 改用 `ctx.db.ensureTable()` + `ctx.db.migrate(version, fn)`（见 `references/manifest-0.7.md` §12） |
| 插件能装但点开就报错 / 二次激活失败 | 被强制改写为 process 模式后触碰了被禁 API | 对照「执行模式差异」表排查 `ctx.config` / `ctx.provide()` / 子进程 / `eval` |
| `api.routes` 返回 401（声明了 `auth:false`） | `auth:false` 只是**申请**公开 | 管理员在插件中心批准公开路由，或改 `auth:true` |

---

## 资源文件说明

| 文件 | 说明 |
|------|------|
| `references/.cache-meta.json` | 缓存元信息（platformVersion / sdkVersion / docSiteVersion / lastUpdated），用于探活比对 |
| `references/capability-matrix-0.7.md` | **权限字符串真源**（20 条真实权限 + 不存在的权限 + 4 套能力机制辨析 + 错误码） |
| `references/frontend-bridge-0.7.md` | **远程前端沙箱桥接范式**（隐藏 iframe、无 React/DOM、声明式贡献点、可见入口决策树、**§7 实时同步只能轮询**、§9 上游不一致） |
| `references/manifest-0.7.md` | **manifest 权威规范**（必填字段、新字段、api.routes、configuration.scope、签名、**§11 API→最低宿主版本、§12 声明式迁移陷阱、§13 跨插件服务共享**） |
| `references/execution-trust-boundary.md` | **执行模式与信任边界**（process 强制默认、Node permission、网络白名单） |
| `references/plugin-development-tutorial.md` | 插件开发完全指南本地快照（API、Action/Handler/Event、前端、安全） |
| `references/architecture.md` | 架构总览本地快照（CommandBus、生命周期、Worker Thread、DI、安全模型） |
| `references/scaffold.md` | 脚手架指南本地快照（CLI 命令、模板、构建、测试、常见问题） |
| `references/testing-strategy.md` | **开发期测试策略**（L0–L3 阶梯、必测矩阵、Guardrail→用例映射、Mock 与生产宿主 8 处差异、环境坑、L3 冒烟清单、CI 片段） |
| `assets/test-harness/` | **插件测试护栏（用户侧）**：`static-check.mjs`（零依赖 L0 契约静态检查）+ `contract.test.ts`（L1）+ `smoke.test.ts`（L2）+ `vitest.config.ts` + `README.md`，复制到插件项目即用 |
| `references/troubleshooting.md` | **故障归因 SOP**（受理报错的五要素、证据清单、归因决策树、系统侧证据门槛、最小复现实验、已知系统问题索引、输出规范、上报 issue 衔接） |
| `references/github-collaboration.md` | **GitHub Issue/PR 协作 SOP**（仓库定位、**§1A 缺陷 Issue 创建**、issue 预检与占位、worktree、PR 模板、CI、审查、返工、合并、清理、异常表、输出模板、红线） |
| `assets/bug-report-template.md` | **系统侧 Bug 报告模板**（本地留存版：环境信息、复现步骤、完整堆栈、最小复现插件、对照实验、已排除项） |
| `assets/platform-issue-template.md` | **平台仓库 Issue 正文模板**（三段必备：问题原因 / 影响 / 建议解决方式，附环境、堆栈、最小复现、去重与脱敏清单） |
| `assets/server-only/` | server-only 插件模板（含 ActionDescriptor 配对、清理 SOP） |
| `assets/full-stack/` | full-stack 插件模板（命令/事件/数据表 + 前端沙箱桥接） |
| `assets/frontend-only/` | frontend-only 插件模板（桥接上下文与提示通道示范） |
| `scripts/check-templates.sh` | **自检脚本**：校验模板的 `main` / `engines` / ActionDescriptor 配对 / 远程前端无 React / 占位符与 SKILL.md 对齐 / 废弃 API 残留。修改模板后必跑 |
| `scripts/verify-templates-build.sh` | **构建验证**：三套模板用官方 SDK CLI 真实构建 + `tsc --noEmit` + 产物体检（manifest 字段 / 裸导入 / React 残留）。支持 npm 安装的 SDK 或本地平台仓库 |
| `scripts/verify-test-harness.sh` | **测试护栏自检**：`static-check.mjs` 语法 + 三套模板替换占位符后 L0 必须 0 error + 含缺陷反例必须报出 14 个预期错误码 + L1/L2 文件骨架校验 |
| `scripts/diff-official-scaffold.sh` | **脚手架漂移检测**：与官方 CLI 脚手架逐项比对契约（manifest 字段 / `main` / `engines` / command 配对 / 前端是否误用 React / 占位符）。官方有、我们缺 → 判失败。`DIFF_ADVISORY=1` 转为仅预警 |

> **谁该跑 `scripts/*`**：这三个脚本是**维护本 skill** 用的（改模板、改 SKILL.md、升级平台基线时跑），
> CI 也会自动跑。**给用户开发插件时不要跑它们** —— 用户侧只需要第四步里的构建命令与预检清单。

### 在线文档地址（线上校验用）

| 文档 | URL |
|------|-----|
| 索引页（探活用） | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/` |
| 插件开发完全指南 | `.../tutorials/plugin-development-tutorial.html` |
| Manifest 规范 | `.../plugin/plugin-manifest-spec.html` |
| 插件生命周期 | `.../plugin/plugin-lifecycle.html` |
| 能力权限矩阵 | `.../reference/plugin-capability-matrix.html` |
| 前端沙箱能力边界 | `.../plugin/frontend-sandbox-capability-boundary.html` |
| 信任边界矩阵 | `.../reference/plugin-trust-boundary.html` |
| UI 扩展槽位 | `.../reference/plugin-ui-extension-slots.html` |
| 宿主共享依赖 | `.../reference/plugin-host-shared-deps.html` |
| 数据库 API | `.../reference/plugin-database-api.html` |
| 脚手架指南 | `.../sdk/scaffold-cli.html` |
| SDK API 参考 | `.../sdk/plugin-sdk.html` |
| 故障排查 FAQ | `.../troubleshooting/troubleshooting-faq.html` |
| Release Notes | `.../release-notes/v0.7.7.html`（线上构建若仍停在 0.7.4，改看仓库 `~/Develop/openlearnv2/docs/release-notes/`） |

> 文档站路径在版本间会变动（例：`plugin-update-distribution` 从 `plugin/` 移到 `reference/`）。
> **以平台仓库 `~/Develop/openlearnv2/docs/` 的一手源为准**，线上只用于校验版本号与最终确认。
