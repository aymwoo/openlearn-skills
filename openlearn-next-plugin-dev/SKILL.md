---
name: openlearn-next-plugin-dev
slug: openlearn-next-plugin-dev
displayName: OpenLearnV2 插件开发与仓库协作助手
version: 2.0.0
description: 为 OpenLearnV2 教学平台（当前平台 v0.7.4 / SDK 3.7.x）开发插件，并协作处理 OpenLearn 相关 GitHub 仓库的 issue 与 PR。覆盖 server-only / full-stack / frontend-only 三类模板，远程前端沙箱桥接（隐藏 iframe、无 React、声明式贡献点）范式、manifest 与能力权限规范、构建与安装验证；内置插件侧/系统侧故障归因流程与可直接提交的 bug 报告；GitHub 协作支持 issue 占位、worktree 开发、PR 提交/审查/返工/合并。当用户提到开发 OpenLearn 插件、openlearn-next 插件、教学平台插件、课堂工具，报告插件报错/不工作，或要处理 OpenLearn 仓库的 issue、PR、worktree 时使用此 skill。
---

> ⚠️ **上游不一致提醒（2026-10-27 实测）**：平台仓库 `origin/main`（平台 0.7.4 / SDK 源码 3.7.0）里的
> `packages/plugin-sdk/scaffold/templates/` **仍是旧的 React 模板**；而 npm 上已发布的
> `@openlearn/plugin-sdk@3.7.1` **才是桥接模板**。
> → 插件作者应以 **npm 发布版 SDK** 为准（`npx @openlearn/plugin-sdk init` 拿到的就是桥接模板）；
> 平台仓库 `main` 分支的模板可能滞后于已发布版本。

# OpenLearnV2 插件开发与仓库协作指南

## 核心原则

**平台一手源优先，本地快照加速读取，规则约束保证代码正确性。**

- **一手源**：平台仓库 `~/Develop/openlearnv2/docs/` 下有一手文档源（带 `doc-version` 标记），源码 `packages/core/` / `packages/plugin-sdk/` 是最终真理。**查 API 先看源码，不要只看文档。**
- **快照**：`references/` 存着本 skill 整理的参考资料，随平台版本更新。
- **探活**：每次使用前核对平台版本 / SDK 版本 / 文档站构建版本，三者任一变化即刷新。

> ⚠️ **当前基线：平台 v0.7.4 / SDK 3.7.1**。本 skill 的模板、权限字典、前端范式均以此为准。

---

## 任务模式判断（先做这一步）

| 用户意图 | 模式 | 入口 |
|----------|------|------|
| 处理某个 GitHub issue / PR；给出编号、URL，或说「接手这个 issue」「审查/合并 PR」 | **B：仓库协作** | 下方「模式 B」+ `references/github-collaboration.md` |
| 开发 / 修改 / 排查 OpenLearn 插件 | **A：插件开发** | 「第一步 ~ 第六步」 |
| 两者都不明确 | — | 先问清楚，不要猜 |

- 模式 B **不需要**执行第一步的文档探活，只需读取目标仓库的 `AGENTS.md` / `CLAUDE.md` / `README.md` / `package.json`。
- 模式 B 遵守「两次主确认 + 不可逆动作单独确认」。
- 两种模式可在同一会话切换；切换时先说明当前模式。

---

## 工作流程

### 第一步：探活 + 版本比对

#### 1a. 三个版本信号（每次必做）

| 信号 | 获取方式 |
|------|----------|
| 平台版本 | 本地仓库 `~/Develop/openlearnv2/package.json` 的 `version` |
| SDK 版本 | `~/Develop/openlearnv2/packages/plugin-sdk/package.json` 的 `version` |
| 文档站构建版本 | fetch 索引页，读标题中的 `OpenLearnV2 x.y.z 文档` |

```bash
# 一次拿到两个本地版本
node -e "const p=require(process.env.HOME+'/Develop/openlearnv2/package.json');const s=require(process.env.HOME+'/Develop/openlearnv2/packages/plugin-sdk/package.json');console.log('platform',p.version,'| sdk',s.version)"
```

#### 1b. 比对缓存

读取 `references/.cache-meta.json` 的 `platformVersion` / `sdkVersion` / `docSiteVersion`：

- **三者全同** → 缓存命中，直接用本地快照（**0 额外 token**）
- **任一不同** → 告知用户「平台已更新（旧 X，新 Y）」，刷新 `references/` 与 `.cache-meta.json`
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
3. **插件类型**（三选一）：
   - `server-only`：纯后端（AI 工具 + 命令 + 事件，无 UI）
   - `full-stack`：后端逻辑 + 前端桥接（**不是** React 组件，见第四步）
   - `frontend-only`：纯前端桥接（无可见入口）
4. **可见入口方式**（关键决策）：远程插件**不能**提供 React 组件，可见 UI 走
   - `manifest.classroomTools` —— 课堂工具按钮（点击派发 commandType）
   - `manifest.contributes.<slot>` —— 声明式槽位贡献（宿主渲染）
   - `ctx.ui.registerExtensionPoint(slot, { slotProps })` —— **仅数据型**，如 `command_palette.item`
   - 内建插件（`@openlearn/` 前缀且在 `OPENLEARN_TRUSTED_INLINE_PLUGINS` 白名单）才可用命令式 React 组件
5. **权限需求 (Capabilities)**：显式核对**平台真实存在**的能力字符串（见「权限全集」一节）
6. **AI 能力与 Action 关联**：是否需要 AI Agent 调用？（必须注册 Action 且描述清晰）
7. **数据库需求**：需要哪些表？是否需要版本迁移？
8. **目标版本**：声明在 `manifest.engines.openlearn` 中的**宿主版本**范围，推荐 `>=0.2.5`（**不是** SDK 版本）

---

### 第三步：生成代码与编码规范

#### 1. 模板对照

| 模板 | 位置 | 生成文件 |
|------|------|---------|
| server-only | `assets/server-only/` | `package.json`, `tsconfig.json`, `src/index.ts` |
| full-stack | `assets/full-stack/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx` |
| frontend-only | `assets/frontend-only/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx` |

> 模板与官方 CLI 脚手架（`packages/plugin-sdk/scaffold/templates/`）保持同源。
> 若两者不一致，以**官方脚手架 + 平台源码**为准，并回来修正本 skill 的模板。

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
3. **命令类型命名空间**：`registerHandler` 的 type 会被宿主自动加上 `manifest.id` 前缀；
   但 `ctx.invokeCommand` 与 manifest 声明里的 `commandType` **必须写全限定名**（`{{pluginId}}.xxx`）。
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

#### 3. Manifest 关键字段（v0.7.x）

- `engines.openlearn`：**宿主版本**范围，推荐 `>=0.2.5`（零主版本号会锁死在小版本区间）。
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
> 平台仓库 `main` 分支的脚手架模板可能滞后于已发布版本（详见 `references/frontend-bridge-0.7.md` §8）。

产物：`dist/index.js`（+ 可选 `dist/frontend.js`）与根目录含 `manifest.json` 的 `.zip`。
**ZIP 根目录必须是 `manifest.json` + `index.js` +（可选）`frontend.js`**，嵌套一层目录会导致安装失败。

#### 构建产物预检清单 (Pre-flight Inspection)

- [ ] **manifest.main 存在**：`grep -q '"main"' manifest.json`
- [ ] **三件套映射**：`manifest.classroomTools[].commandType` / `contributes` 里引用的每个 commandType，
      都能在 `src/index.ts` 里找到**同名的 `actionRegistry.register` + `registerHandler`**
- [ ] **裸导入非法引用**：`grep -E '^import .+ from "[^@\./]' dist/index.js` 应无输出
- [ ] **远程前端无 React**：`grep -nE "from ['\"]react|document\.|window\." dist/frontend.js` 应无输出
- [ ] **Worker/Process 兼容**：非 inline 模式下不得使用 `ctx.config` / `ctx.provide()` / `child_process` / `worker_threads` / `eval`
- [ ] **清理 SOP**：`deactivate()` 中处理了自建定时器 / 子进程 / 第三方连接

---

### 第五步：安装与验证

在 OpenLearn 管理后台上传 `.zip`：

1. **管理后台** → 系统设置 → 插件中心 → 上传插件
2. **激活插件**：检查服务日志输出带 `[Plugin:<id>]` 前缀；注意第三方插件会被强制以 `process` 模式运行
3. **工具验证**：若声明了 `classroomTools`，进课堂白板确认按钮出现、点击有事件流回显
4. **AI 工具测试**：发送自然语言命令，确认 Agent 能识别并触发 Actions
5. **路由验证**：`api.routes` 声明 `auth: false` 的接口**还需管理员批准**才会匿名放行，否则 401

---

### 第六步：故障归因（插件侧 vs 系统侧）

当开发者报告「插件报错 / 不工作」时，**先归因，再动手**。完整方法见 `references/troubleshooting.md`，此处为速用版。

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
| **插件侧** | 指出具体修改点，走第四步预检清单复查；**不生成报告** |
| **系统侧** | 生成 bug 报告：`<插件项目根目录>/BUG-REPORT-<slug>-<YYYYMMDD>.md`（模板 `assets/bug-report-template.md`） |
| **插件间冲突** | 定位命名空间 / 事件名 / 表名 / 槽位 id 撞车的双方并改名 |
| **环境与配置** | 给出修复步骤（升级 / 重建 / 强刷 / 重新审批 / 加白名单），不算缺陷 |
| **待定** | 列出缺失的证据项与取证命令，收齐后重判 |

**必给的简要汇总（≤10 行）**

```
【故障归因】<插件侧 / 系统侧 / 插件间冲突 / 环境与配置 / 待定>
现象：<一句话>
关键证据：
  1. <堆栈归属 / 版本与执行模式核对 / 对照实验>
判定依据：<为什么是这一类，而非另一类>
建议动作：<修复方式 或 已生成 bug 报告：<路径>>
```

> 生成报告前务必确认已包含：**具体版本号、完整堆栈、最小复现插件**。缺这三项通常会被系统作者以「信息不足」退回。

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

### 2. Capabilities 权限全集（v0.7.4 真源）

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
| 必须自行打包 | `socket.io-client` `zustand` `motion` `react-konva`/`konva` `react-markdown` `exceljs`（**不是 xlsx**）`jspdf` `jspdf-autotable` `uuid` |
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

> 完整信任边界见 `references/execution-trust-boundary.md`。

---

## 调试 SOP 与故障排查指南 (Troubleshooting SOP)

> 本表是「症状 → 直接处理」的速查。**若需判定责任方并产出 bug 报告，请先走第六步，并阅读 `references/troubleshooting.md`。**

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
| 白板工具栏样式错乱 / 按钮被挤压 | `classroom.tool` 槽位里塞了面板 DOM | 远程插件根本不能渲染 UI；可见入口改走 `classroomTools` 声明 + 后端命令 |
| 无法收发 Socket.IO 实时消息 | 频道名不统一，或前端未解绑 | 统一 `{{pluginId}}.<action>_done` 命名；组件卸载时 `socket.off(...)` |
| 插件能装但点开就报错 / 二次激活失败 | 被强制改写为 process 模式后触碰了被禁 API | 对照「执行模式差异」表排查 `ctx.config` / `ctx.provide()` / 子进程 / `eval` |
| `api.routes` 返回 401（声明了 `auth:false`） | `auth:false` 只是**申请**公开 | 管理员在插件中心批准公开路由，或改 `auth:true` |

---

## 资源文件说明

| 文件 | 说明 |
|------|------|
| `references/.cache-meta.json` | 缓存元信息（platformVersion / sdkVersion / docSiteVersion / lastUpdated），用于探活比对 |
| `references/capability-matrix-0.7.md` | **权限字符串真源**（20 条真实权限 + 不存在的权限 + 4 套能力机制辨析 + 错误码） |
| `references/frontend-bridge-0.7.md` | **远程前端沙箱桥接范式**（隐藏 iframe、无 React/DOM、声明式贡献点、可见入口决策树） |
| `references/manifest-0.7.md` | **manifest 权威规范**（必填字段、新字段、api.routes、configuration.scope、签名） |
| `references/execution-trust-boundary.md` | **执行模式与信任边界**（process 强制默认、Node permission、网络白名单） |
| `references/plugin-development-tutorial.md` | 插件开发完全指南本地快照（API、Action/Handler/Event、前端、安全） |
| `references/architecture.md` | 架构总览本地快照（CommandBus、生命周期、Worker Thread、DI、安全模型） |
| `references/scaffold.md` | 脚手架指南本地快照（CLI 命令、模板、构建、测试、常见问题） |
| `references/troubleshooting.md` | **故障归因 SOP**（证据清单、归因决策树、系统侧证据门槛、最小复现实验、已知系统问题索引、输出规范） |
| `references/github-collaboration.md` | **GitHub Issue/PR 协作 SOP**（仓库定位、issue 预检与占位、worktree、PR 模板、CI、审查、返工、合并、清理、异常表、输出模板、红线） |
| `assets/bug-report-template.md` | **系统侧 Bug 报告模板**（环境信息、复现步骤、完整堆栈、最小复现插件、对照实验、已排除项） |
| `assets/server-only/` | server-only 插件模板（含 ActionDescriptor 配对、清理 SOP） |
| `assets/full-stack/` | full-stack 插件模板（命令/事件/数据表 + 前端沙箱桥接） |
| `assets/frontend-only/` | frontend-only 插件模板（桥接上下文与提示通道示范） |
| `scripts/check-templates.sh` | **自检脚本**：校验模板的 `main` / `engines` / ActionDescriptor 配对 / 远程前端无 React / 占位符与 SKILL.md 对齐 / 废弃 API 残留。修改模板后必跑 |
| `scripts/verify-templates-build.sh` | **构建验证**：三套模板用官方 SDK CLI 真实构建 + `tsc --noEmit` + 产物体检（manifest 字段 / 裸导入 / React 残留）。支持 npm 安装的 SDK 或本地平台仓库 |
| `scripts/diff-official-scaffold.sh` | **脚手架漂移检测**：与官方 CLI 脚手架逐项比对契约（manifest 字段 / `main` / `engines` / command 配对 / 前端是否误用 React / 占位符）。官方有、我们缺 → 判失败。`DIFF_ADVISORY=1` 转为仅预警 |

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
| Release Notes | `.../release-notes/v0.7.4.html` |

> 文档站路径在版本间会变动（例：`plugin-update-distribution` 从 `plugin/` 移到 `reference/`）。
> **以平台仓库 `~/Develop/openlearnv2/docs/` 的一手源为准**，线上只用于校验版本号与最终确认。
