---
name: openlearn-next-plugin-dev
slug: openlearn-next-plugin-dev
displayName: OpenLearnV2 插件开发与仓库协作助手
version: 1.1.0
description: 为 OpenLearnV2 教学平台开发插件，并协作处理 OpenLearn 相关 GitHub 仓库的 issue 与 PR。通过读取 https://openlearn-next-v2.readthedocs.io/zh-cn/latest/ 在线文档获取最新插件开发文档，与开发者讨论需求后指导开发相应插件。内置插件侧/系统侧故障归因流程，可在插件报错时判定责任方，并在确认为系统缺陷时生成可直接提交的 bug 报告；支持三类插件模板（server-only / full-stack / frontend-only）。GitHub 协作支持：接手 issue 前 assign + in-progress 占位、创建独立 worktree 开发、通过 PR 提交、审查/返工/合并 PR。当用户提到开发 OpenLearn 插件、openlearn-next 插件、教学平台插件、课堂工具，报告插件报错/不工作，或要处理 OpenLearn 仓库的 issue、PR、worktree 时使用此 skill。
---

# OpenLearnV2 插件开发与仓库协作指南

## 核心原则

**在线文档是权威来源，本地缓存加速读取，规则约束保证代码正确性。** 
skill 自带三份官方文档的本地快照（`references/`），每次使用前通过索引页探活；另有两份自建 SOP（故障归因、GitHub 协作）。缓存未过期则直接用本地，发现远端更新才重新拉取——将月消耗从 ~100K token 降至 ~22K token。

---

## 任务模式判断（先做这一步）

| 用户意图 | 模式 | 入口 |
|----------|------|------|
| 处理某个 GitHub issue / PR；给出编号、URL，或说「接手这个 issue」「审查/合并 PR」 | **B：仓库协作** | 下方「模式 B」+ `references/github-collaboration.md` |
| 开发 / 修改 / 排查 OpenLearn 插件 | **A：插件开发** | 「第一步 ~ 第六步」 |
| 两者都不明确 | — | 先问清楚，不要猜 |

- 模式 B **不需要**执行第一步的文档探活，也不需要读取插件开发文档；只需读取目标仓库的 `AGENTS.md` / `CLAUDE.md` / `README.md` / `package.json`。
- 模式 B 遵守「两次主确认 + 不可逆动作单独确认」：接管 issue 前确认占位方案；push/开 PR 前确认 diff、测试与文案；合并、清理、发布 review 等公开或不可逆动作另行确认。
- 两种模式可在同一会话切换；切换时先说明当前模式。

---

## 工作流程

### 第一步：探活 + 缓存命中或增量更新

#### 1a. 探活（每次必做，~200 token）

webfetch 索引页，**同时**提取两个版本信号：

```
https://openlearn-next-v2.readthedocs.io/zh-cn/latest/
```

1. 页面标题中的构建版本：`OpenLearnV2 x.y.z 文档`
2. 页脚的最近更新日期：`最后更新：YYYY-MM-DD (vX.Y.Z)`

> 页脚日期可能滞后于实际构建版本（曾出现页脚标 v0.3.14、实际构建已是 0.3.16）。**两个信号任一变化都视为有更新。**

#### 1b. 比对缓存

读取 `references/.cache-meta.json` 中的 `lastUpdated` 字段：

- **日期相同** → 缓存命中，直接使用 `references/` 目录下的本地快照（**0 额外 token**）
- **日期更新** → 远端有更新，告知用户"文档已更新（旧: X, 新: Y）"，然后重新拉取全量文档，更新 references 文件和 .cache-meta.json
- **首次使用（无缓存）** → 直接使用 references/ 本地快照

#### 1c. 缓存未命中时按需拉取

如果缓存不存在或已过期，按以下优先级拉取：

| 要做什么 | 拉取哪份 | 估算 token | 本地文件 |
|----------|---------|-----------|---------|
| 查 API 签名、Action/Handler/Event 怎么写 | **插件开发完全指南** | ~12,000 | `references/plugin-development-tutorial.md` |
| 理解架构原理、安全模型 | **架构总览** | ~8,000 | `references/architecture.md` |
| 初始化项目、构建打包、CLI 命令 | **脚手架指南** | ~4,000 | `references/scaffold.md` |
| 排查报错、判断插件侧/系统侧、写 bug 报告 | **故障排查与归因 SOP** | ~3,000 | `references/troubleshooting.md` |

> 全部为多页汇编或单页快照，具体来源 URL 见 `.cache-meta.json` 与各文件末尾的「来源」节。

拉取后更新 references/ 和 .cache-meta.json。

---

### 第二步：需求讨论与预检查

获取最新文档后，与开发者进行结构化讨论，逐项确认：

1. **插件用途**：面向教师还是学生？解决什么问题？
2. **核心功能**：列举 1-5 个核心功能点
3. **插件类型**（三选一）：
   - `server-only`：纯后端（AI 工具 + 命令 + 事件，无 UI）
   - `full-stack`：全栈（后端逻辑 + React 前端）
   - `frontend-only`：纯前端（仅 UI 面板或课堂工具）
4. **UI 扩展点**（full-stack / frontend-only 时确认）：
   - `teacher.tab` — 教师侧边栏标签页（管理页）
   - `teacher.dashboard.widget` — 白板可拖拽卡片（课堂交互，需匹配 teacherWidgetId）
   - `teacher.panel` — 教师独立全宽面板（v0.1.9+）
   - `student.view` — 学生端全屏视图
   - `student.fullscreen` — 学生全屏视图/考试模式（v0.1.9+）
   - `classroom.tool` — 课堂工具架按钮
   - `global.setting` — 全局设置页扩展（v0.1.9+）
   - `anchor:<区域>:<锚点id>` — 在宿主原生按钮/元素前后插入（v0.2.6+，如 `anchor:whiteboard-toolbar:rollcall`）
   - `nav.user_menu` — 顶部 Header 用户菜单扩展
5. **权限需求 (Capabilities)**：显式核对需申请的权限列表（见后文权限全集字典）
6. **AI 能力与 Action 关联**：是否需要 AI Agent 调用？（必须注册 Action 且描述清晰）
7. **数据库需求**：需要哪些表？是否需要版本迁移？
8. **目标版本**：声明在 `manifest.engines.openlearn` 中的**宿主版本**兼容范围，推荐 `>=0.2.5`（**不是** SDK 版本）

---

### 第三步：生成代码与编码规范

方案确认后，根据插件类型选择对应模板生成代码。

#### 1. 模板对照

| 模板 | 位置 | 生成文件 |
|------|------|---------|
| server-only | `assets/server-only/` | `package.json`, `tsconfig.json`, `src/index.ts` |
| full-stack | `assets/full-stack/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx` |
| frontend-only | `assets/frontend-only/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx` |

将 `{{placeholder}}` 替换为用户确认的参数：
- `{{pluginId}}` → 如 `@teacher-li/class-polls`
- `{{pluginName}}` → 显示名称
- `{{description}}` → 功能描述
- `{{author}}` → 作者名
- `{{commandPrefix}}` → 命令前缀（如 `classpolls`）
- `{{toolId}}` / `{{toolName}}` → classroomTools 配置
- `{{tabId}}` → 前端 tab ID

#### 2. 关键编码规范与防御规则 (Mandatory Guardrails)

1. **Manifest 1:1 映射约束**：`manifest.classroomTools` 中声明的所有 `commandType`，必须在 `activate()` 中通过 `ctx.services.commandBus.registerHandler()` 注册对应的 Handler！
2. **React 导入与 JSX 模式**：`frontend.tsx` 第一行**推荐显式导入 React** (`import React from 'react';`)。在经典模式下（`"jsx": "react"`，≤0.3.14 唯一可用）省略会直接报 `ReferenceError: React is not defined`；0.3.15+ 启用自动 JSX 运行时时可不显式导入，但必须把 `react` / `react-dom` / `react-dom/client` / `react/jsx-runtime` 全部标记为 `external`。
3. **classroom.tool 挂载规范（防挤压/防遮挡）**：
   - 槽位组件必须保持为**单纯的图标按钮**（尺寸与画笔/点名按钮对齐）。
   - 展开的控制面板、全屏弹窗或遮罩，必须通过 `ReactDOM.createPortal(..., document.body)` 挂载到 `document.body`，绝对禁止在工具栏 DOM 内直接扩展大尺寸面板。
4. **前后端 Socket.IO + EventBus 实时同步架构**：
   - **后端发**：Handler 变更数据后，发布 EventBus 事件 (`prefix.action_done`)，并通过 Socket.IO 服务向前端频道/房间广播。
   - **前端收**：前端在 `useEffect` / 组件挂载时监听 Socket 事件，收到更新后触发 state 刷新。
5. **全生命周期清理 SOP (Resource Cleanup SOP)**：
   - 在 `deactivate()` 函数中，**必须**显式取消订阅 EventBus (`subscription.unsubscribe()`)、清除所有 `setInterval`/`setTimeout` 定时器、注销监听器、以及调用 `processManager` 停止后台进程。
6. **数据库表命名与操作**：使用 `ctx.db.ensureTable()` + `ctx.db.table()`，绝不手动拼接 SQL 表名。
7. **Node.js 原生模块避坑**：用 `crypto.randomUUID()` 代替 `import { randomUUID } from 'crypto'`；文件读写必须使用系统提供的 VFS API，不可直接引入 `fs` / `path`。

#### 3. Manifest 关键字段（v0.3.x）

- `engines.openlearn`：填**宿主版本**兼容范围（推荐 `>=0.2.5`）；SDK 版本随平台 release 同步、**勿写死**。
- 按目标版本可用的新字段：`api.routes`（配合 `ctx.http` 注册 REST 路由，0.3.11+）、`provides`（对外暴露服务，供其他插件 `requires`）、`optional`、`pluginDependencies`、`contributes`（声明式贡献点，仅供管理后台枚举）、`updateSource`（热更新源）、`deploy`、`configuration.showInDashboard`。
- 完整字段与 Zod 校验规则见 `references/scaffold.md`「Manifest 字段全表」与 `references/plugin-development-tutorial.md §3.1`。

---

### 第四步：构建与脚本化预检

代码生成后，指导开发者或自动化执行构建：

```bash
cd <plugin-directory>
npm install
npx @openlearn/plugin-sdk build
```

#### 构建产物预检清单 (Pre-flight Inspection)

- [ ] **React 显式导入检查**：`grep 'import React from "react"' dist/frontend.js` 或检查 Bundle 头部包含 React 全局/模块引用。
- [ ] **三件套映射检查**：`manifest.json` 中所有的 `classroomTools[].commandType` 均已在 `src/index.ts` 注册了 `registerHandler`。
- [ ] **裸导入非法引用检查**：执行 `grep -E '^import .+ from "[^@\./]' dist/index.js` 应无输出。
- [ ] **JSX 模式检查**：目标为 **≤0.3.14** 时，构建产物中**不得**出现 `react/jsx-runtime` 引用；**0.3.15+** 允许自动模式，但仍需确认 `react/jsx-runtime` 已标记 `external`（版本口径不一，稳妥做法是直接标记 external）。
- [ ] **Worker 兼容检查**：若插件声明 worker 模式，确认未使用 `ctx.config` / `ctx.provide()`，`eventBus` 用 `subscribe/unsubscribe`，`commandBus.execute` 手动加了前缀（详见速查字典 §5）。
- [ ] **生命周期清理检查**：`deactivate()` 中包含了定时器与 EventBus 监听器的取消注册代码。

---

### 第五步：安装与验证

提醒开发者在 OpenLearn 管理后台上传 `dist/<plugin-name>.zip`：

1. **管理后台** → 系统设置 → 插件中心 → 上传插件
2. **激活插件**：检查服务日志输出带 `[Plugin:<id>]` 前缀
3. **UI 工具验证**：若声明了 `classroomTools`，进入课堂白板，验证工具栏图标正常显示且无布局挤压
4. **AI 工具测试**：发送自然语言命令测试 AI Agent 是否能够正确识别并触发 Actions

---

### 第六步：故障归因（插件侧 vs 系统侧）

当开发者报告「插件报错 / 不工作」时，**先归因，再动手**。不要立刻改代码，也不要立刻断言是平台问题。**完整方法见 `references/troubleshooting.md`，此处为速用版。**

**三条铁律**

1. **堆栈归属**：顶层帧在 `dist/index.js`、`dist/frontend.js` → 插件侧；在 `packages/core/...`、`src/plugin-host/...`、`node_modules/@openlearn/...` → 系统 / SDK 侧。
2. **对照实验**：官方脚手架原始产物、或 ≤50 行最小复现插件（仅 manifest + 空 `activate`）能否稳定复现——**能复现的才是系统侧**。
3. **先核版本**：系统版本 / 插件 `engines.openlearn` / 所用 API 的最低版本。大量「系统 bug」其实是插件用了未来版本 API 或声明了不兼容 engines。

**判为「系统侧」的 4 个必要条件（缺一即只能给「待定」）**

1. 官方脚手架原始产物或最小复现插件稳定复现；
2. 具体版本号、复现步骤、完整堆栈（不截断）齐全；
3. 报错点位于宿主 / 内核 / SDK / 文档承诺范围内，而非插件自身代码或构建配置；
4. 已排除：版本不匹配、产物未重新构建、浏览器缓存、热重载未生效、权限未审批、插件间冲突。

**结论与动作**

| 结论 | 动作 |
|------|------|
| **插件侧** | 指出具体修改点，走第四步预检清单复查；**不生成报告** |
| **系统侧** | 生成 bug 报告：`<插件项目根目录>/BUG-REPORT-<slug>-<YYYYMMDD>.md`（模板 `assets/bug-report-template.md`），并提示用户可直接发送给系统作者 |
| **插件间冲突** | 定位命名空间 / 事件名 / 表名 / 槽位 id 撞车的双方并改名 |
| **环境与配置** | 给出修复步骤（升级 / 重建 / 强刷 / 重新审批），不算缺陷 |
| **待定** | 列出缺失的证据项与取证命令，收齐后重判 |

**必给的简要汇总（≤10 行）**

```
【故障归因】<插件侧 / 系统侧 / 插件间冲突 / 环境与配置 / 待定>
现象：<一句话>
关键证据：
  1. <堆栈归属 / 版本核对 / 对照实验>
判定依据：<为什么是这一类，而非另一类>
建议动作：<修复方式 或 已生成 bug 报告：<路径>>
```

> 生成报告前务必确认已包含：**具体版本号、完整堆栈、最小复现插件**。缺这三项的报告通常会被系统作者以「信息不足」退回。

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

预检（任一不满足就停）：

1. issue 仍为 OPEN；
2. 未 assign 给其他人；若已 assign 给自己则幂等继续；
3. 没有引用该 issue 的开放 PR 或他人远程分支；
4. 正文有可验证的验收标准。

确认后执行「占位三件套」：

```bash
gh issue edit <n> -R <repo> --add-assignee @me
gh issue edit <n> -R <repo> --add-label in-progress   # 缺失时先创建
gh issue comment <n> -R <repo> --body-file <占位评论>
```

> 标签只按需创建 `in-progress`（色值 `#e36209`）。评论需包含负责人与分支名，方便其他人避让；本地 worktree 路径不必公开。

### B2. 创建 worktree

- 平台：`~/Develop/openlearn-issue-<n>`
- 插件：`~/Develop/openlearn-plugins/<repo>-issue-<n>`
- 分支：`<type>/issue-<n>-<slug>`，从 `origin/main` 创建。
- 路径已存在时：同分支且干净 → 复用；否则停止，绝不覆盖。
- 不碰主 clone 的工作区。

```bash
git -C <local> fetch origin --prune
git -C <local> worktree add -b <branch> <worktree> origin/main
```

### B3. 开发与本地验证

- 先读仓库 `AGENTS.md` / `CLAUDE.md` / `README.md` / `package.json`，以其约定为准。
- 平台：worktree 内先 `pnpm install --frozen-lockfile`；改动用例 `pnpm vitest run <path>`；开 PR 前跑 `pnpm lint && pnpm lint:strict`，全量测试交给 CI。
- 插件：只跑 `package.json` 中实际存在的脚本；`interactive-courseware` 的 `build` 会 bump 版本，非必要不跑。
- 提交：`<type>(<scope>): <中文摘要>（Issue #<n>）`，1-3 个逻辑提交，不夹带无关改动。

### B4. 提交 PR（确认门 2）

push 前展示 diff stat、提交列表、测试命令与结果、PR 标题/正文，确认后：

```bash
git -C <worktree> push -u origin <branch>
gh pr create -R <repo> --base main --head <branch> --title "<title>" --body-file <body>
```

PR 正文必须包含：`## 变更内容`、`## 关联 Issue`（`Closes #<n>`）、`## 测试计划`（真实命令与结果）、UI 改动的 `## 截图`、`## 风险与回滚`。一个 issue 一个 PR。

### B5. CI

```bash
timeout 600 gh pr checks <pr> -R <repo> --watch --interval 30
```

- 本次改动导致的失败 → 自动修 1 轮并重推。
- 环境/flaky/基线失败 → 停止汇报，不反复重跑。
- CI 未绿不合并。

### B6. 审查 PR

- 先输出只读状态卡（作者、CI、评审、可合并、改动量、关联 issue、未解决评论），再让用户选动作：审查 / 修评论 / 合并 / 仅解释。
- 评审意见先在对话里出草稿，确认后才 `gh pr review`。
- 自己的 PR 不能 approve，只能 comment；有阻塞项不得 approve。
- 不替别人 resolve 讨论串。

### B7. 返工

- 按 review thread 逐条修复，回复 commit hash；普通 push 优先。
- `--force-with-lease` 仅限自己的 PR 分支 + 确认；永不 force-push main。
- 意见要求扩大范围时先汇报，等用户决定。

### B8. 合并

仅在用户明确说「合并」时执行，且满足：CI 全绿、mergeable、无 changes-requested、评论已处理、用户再次确认最终 commit message。

```bash
HEAD_SHA=$(gh pr view <pr> -R <repo> --json headRefOid --jq .headRefOid)
gh pr merge <pr> -R <repo> --squash --match-head-commit "$HEAD_SHA" --subject "<title>" --body "<summary + Closes #n>"
```

> 不使用 `--delete-branch`：分支正被 worktree 占用时，gh 删除本地分支会失败。合并后先校验，再按 B9 显式删除远程/本地分支。
> `--match-head-commit` 防止确认后 PR 又追加提交；被拒绝说明头指针已变，重新审查后再合并。

合并后校验 PR 状态与 issue 是否自动关闭；不加 `--admin` / `--auto`。

### B9. 清理

- 合并后先删远程分支（若仍存在），再移除 worktree、删除本地分支；每一步都先询问。
- 有未提交改动时永不删除。
- PR 关闭未合并：保留 worktree，移除 `in-progress`，留言先确认。
- 开工前巡检陈旧 worktree，只列出、不自动删。

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

在 `ctx.services` 或通过 `ctx.resolve(Token)` 获取的核心服务列表及 API 方法签名：

| 服务 Token | 别名 / 获取途径 | 核心 API 方法及用途 |
| :--- | :--- | :--- |
| `ICommandBusServiceToken` | `ctx.services.commandBus` | `registerHandler(type, handler)`: 注册命令处理逻辑<br>`execute(command)`: 执行命令管线<br>`unregisterHandler(type)`: 注销命令 |
| `IEventBusServiceToken` | `ctx.services.eventBus` | `publish(event)`: 发布事件<br>`subscribe(pattern, listener)`: 订阅事件（支持 `*` 通配符，返回 `Disposable`） |
| `IActionRegistryServiceToken` | `ctx.services.actionRegistry` | `register(action)`: 注册 AI 工具（供 Agent 检索）<br>`unregister(actionId)`: 注销 AI 工具 |
| `IDatabaseToken` | `ctx.db` / `ctx.resolve(IDatabaseToken)` | `ensureTable(tableName, schema)`: 创建表<br>`table(tableName)`: 获取安全表名<br>`prepare(sql).run(...args)`: 执行原始 SQL 语句 |
| `ICapabilityServiceToken` | `ctx.services.capability` | `check(actor, capability)`: 检查权限<br>`grant(actor, capability)`: 授权 |
| `IProcessManagerServiceToken` | `ctx.services.processManager` | `spawn(options)`: 派生后台进程<br>`kill(pid)`: 终止进程 |
| `IStorageServiceToken` | `ctx.services.storage` | `get(key)` / `set(key, val)` / `delete(key)`: 简易 Key-Value 键值对存储 |
| `IAIServiceToken` | `ctx.services.ai` | `generateText(prompt, options)`: 快速调用宿主配置的 LLM 文本生成能力 |

---

### 2. Capabilities 权限全集字典

声明在 `manifest.capabilitiesProposed` 中的标准权限格式为 `{resource}:{action}`。常见权限分类如下：

| 权限字符串 | 权限描述 | 风险等级 | 说明 |
| :--- | :--- | :--- | :--- |
| `lesson:read` | 读取课程及课堂数据 | 低 | 查询课程基本信息、学生列表 |
| `lesson:write` | 修改课程及课堂数据 | 中 | 创建/更新课堂任务、点名记录 |
| `whiteboard:read` | 读取白板内容及板书 | 低 | 导出白板元素、抓取快照 |
| `whiteboard:write` | 绘制/修改白板内容 | 中 | 向白板插入图形、文本、清空白板 |
| `user:read` | 获取用户基础信息 | 低 | 获取教师/学生的姓名、角色、Avatar |
| `system:process` | 运行后台进程/定时任务 | **高** | 触发 `ProcessManager` 创建子进程 |
| `ai:invoke` | 直接调用 AI 大模型接口 | 中 | 使用 `ctx.services.ai` 消耗 Tokens |
| `network:fetch` | 允许发起外部 HTTP 请求 | **高** | 需要动态审批白板域名 |

---

### 3. UI 扩展槽位 Context & Props 全景表

前端扩展槽位组件被 Host 渲染时传递的 `props` 以及适用的挂载场景：

| 槽位 ID (`pointId`) | 说明与适用场景 | Host 传递的标准 `props` 类型 |
| :--- | :--- | :--- |
| `teacher.tab` | 教师侧边栏独立标签页 | `{ ctx: HostContext, lessonId: string, currentTab: string }` |
| `teacher.dashboard.widget` | 白板工作台可拖拽卡片 | `{ ctx: HostContext, widgetId: string, isEditing: boolean }` |
| `teacher.panel` | 教师端独立全宽全屏面板 (v0.1.9+) | `{ ctx: HostContext, onClose: () => void }` |
| `student.view` | 学生端主视图/内容区 | `{ ctx: HostContext, lessonId: string, studentId: string }` |
| `student.fullscreen` | 学生全屏遮罩/答题模式 | `{ ctx: HostContext, lockExit: boolean, onSubmit: (data: any) => void }` |
| `classroom.tool` | 课堂底部工具架图标按钮 | `{ ctx: HostContext, isActive: boolean, toggleActive: () => void }` |
| `global.setting` | 插件全局配置组件 | `{ ctx: HostContext, saveConfig: (cfg: any) => Promise<void> }` |
| `anchor:<区域>:<锚点id>` | 在宿主原生按钮/元素前后插入按钮（**v0.2.6+**），如 `anchor:whiteboard-toolbar:rollcall` | `{ placement, position, component }` |
| `nav.user_menu` | 顶部 Header 用户菜单扩展 | — |

> 版本口径提示：上表部分槽位在官方文档中带「v3.2 / v5.2」等旧标签，但自平台 v0.2.3 起宿主 API 版本已与发行版本统一。**具体可用性与 props 以 `references/plugin-development-tutorial.md §6.4` 与 `references/architecture.md §8` 为准。** 锚点渲染是命令式的（`ctx.ui.registerExtensionPoint`），`manifest.contributes` 中的声明仅供管理后台枚举。

---

### 4. 前端共享依赖 (HostSharedDeps) 白名单

宿主通过 `window.HostSharedDeps` 全局提供以下共享运行时，**切勿重复打入插件 bundle**（构建时全部标记为 `external`）：

| 共享对象 | NPM 包 | 内容 |
|---------|--------|------|
| `React` | `react` | React 核心与 Hooks |
| `ReactDOM` | `react-dom` | DOM 渲染与 `createPortal` |
| `ReactDOMClient` | `react-dom/client` | 现代 Root API (`createRoot`) |
| `jsxRuntime` | `react/jsx-runtime` | 现代 JSX 运行时 (`jsx`/`jsxs`) |
| `Recharts` | `recharts` | 图表库 |
| `LucideReact` | `lucide-react` | 图标库 |

- **JSX 模式**：平台 **0.3.15+** 已内置 `react/jsx-runtime` 映射，经典模式（`"jsx": "react"`）与自动模式（`"jsx": "react-jsx"`）均可；**≤0.3.14 只能用经典模式**，否则报 `Failed to resolve module specifier "react/jsx-runtime"`。
  > 口径提示：`tutorial §6.7` 与 `architecture` 均记为 0.3.15+，Release Notes v0.3.16 将白名单由 4 扩充至 6。**不同来源口径不一，归因时以 Release Notes 为准，写代码时按“稳妥优先”处理。**
  > **稳妥做法**：无论目标版本，都把 `react/jsx-runtime` 一并标记为 `external`，并优先用经典模式 + 显式 `import React`。
- `@openlearn/plugin-sdk` 也由宿主提供，不必打包。
- **必须自行打包（宿主不共享）**：`socket.io-client`、`zustand`、`motion`、`react-konva`/`konva`、`react-markdown`、`xlsx`、`jspdf` 等。

---

### 5. Worker 与 Inline 模式 API 差异（必读）

插件可能在 `execution_mode: 'worker'` 下运行，**此时部分 API 不可用或方法名不同**。写代码和排查故障时都要先确认执行模式：

| API | Inline | Worker |
|-----|--------|--------|
| `ctx.config` / `ctx.provide()` | 可用 | ❌ 不可用 |
| `ctx.services.eventBus` | `on()` / `off()` | `subscribe()` / `unsubscribe()` |
| `ctx.services.commandBus.execute()` | 自动加 `manifest.id` 前缀 | **不自动加前缀**，需手动拼完整 type |
| `ctx.db.migrate()` / `IDatabaseToken` | 同步 `better-sqlite3` | 异步 `prepare().run/get/all` + `exec()`（0.3.9+），无 `transaction` |
| `ctx.db.table()` | 返回 manifest ID 前缀 | 返回 **UUID 前缀**（切模式会导致表名变化，属预期行为） |
| `ctx.http` | 完整 | 完整（RPC 跨线程，5000ms 熔断，0.3.11+） |
| `ctx.log` / `ctx.manifest` | 可用 | 可用 |

> 插件违反上表属于**插件侧**问题；已按上表适配仍失败，才可能是**系统侧**。完整归因流程见 `references/troubleshooting.md`。

---

## 调试 SOP 与故障排查指南 (Troubleshooting SOP)

> 本表是「症状 → 直接处理」的速查。**若需判定责任方（插件侧还是系统侧）并产出 bug 报告，请先走第六步，并阅读 `references/troubleshooting.md`。**

| 现象 / 报错信息 | 可能原因 | 解决办法 (SOP) |
| :--- | :--- | :--- |
| `ReferenceError: React is not defined` | `frontend.tsx` 缺少显式 `import React from 'react';` 或 esbuild 把 JSX 转为了自动注入模式 | 1. 确保 `frontend.tsx` 第一行为 `import React from 'react';`<br>2. ≤0.3.14 检查 tsconfig/esbuild 用经典模式（`jsx: 'transform'` / `"jsx": "react"`）；0.3.15+ 两种模式均可 |
| `CAPABILITY_DENIED: Required capability 'xxx' missing` | 插件未在 `manifest.capabilitiesProposed` 申请该权限，或未获得用户/管理员批准 | 1. 在 `manifest.capabilitiesProposed` 中补充对应的权限字符串<br>2. 在 OpenLearn 管理后台重新激活插件并确认授权 |
| `TOKEN_NOT_FOUND: Service Token 'xxx' is not registered` | 在 `manifest.requires` 中遗漏了所需依赖服务的 Token | 检查代码中调用的 `ctx.services` 或 `ctx.resolve(Token)`，确保在 `manifest.requires` 数组中添加对应的包 Token 声明 |
| `HANDLER_ALREADY_EXISTS: CommandType 'xxx' is already registered` | 试图对同一个 commandType 多次调用 `registerHandler` | 检查插件是否有重复激活逻辑，或前一次 `deactivate` 未成功注销 handler |
| 白板工具栏样式错乱/工具按钮被挤压 | `classroom.tool` 槽位直接渲染了带有 `width/height` 的弹窗或 Modal DOM | 使用 `ReactDOM.createPortal(JSX, document.body)` 将弹窗面板挂载到 `document.body`，让槽位组件本身仅保持图标尺寸 |
| 无法收发 Socket.IO 实时消息 | 前后端 channel 名称未统一，或前端未解绑导致重复监听 | 格式化频道命名规则（如 `prefix.action_done`），并在组件卸载时在 `useEffect` 清理函数中调用 `socket.off(...)` |

---

## 资源文件说明

| 文件 | 说明 |
|------|------|
| `references/.cache-meta.json` | 缓存元信息（lastUpdated 日期 + docSiteVersion 构建版本），用于探活比对 |
| `references/plugin-development-tutorial.md` | 插件开发完全指南本地快照（API、Action/Handler/Event、前端、安全） |
| `references/architecture.md` | 架构总览本地快照（CommandBus、生命周期、Worker Thread、DI、安全模型） |
| `references/scaffold.md` | 脚手架指南本地快照（CLI 命令、模板、构建、测试、常见问题） |
| `references/troubleshooting.md` | **故障归因 SOP**（证据清单、归因决策树、系统侧证据门槛、最小复现实验、已知系统问题索引、输出规范） |
| `references/github-collaboration.md` | **GitHub Issue/PR 协作 SOP**（仓库定位、issue 预检与占位、worktree、PR 模板、CI、审查、返工、合并、清理、异常表、输出模板、红线） |
| `assets/bug-report-template.md` | **系统侧 Bug 报告模板**（环境信息、复现步骤、完整堆栈、最小复现插件、对照实验、已排除项） |
| `assets/server-only/` | server-only 插件模板（已增加完整清理 SOP 与 Token 注释） |
| `assets/full-stack/` | full-stack 插件模板（包含 Socket 架构、Portal 防挤压与规范导入） |
| `assets/frontend-only/` | frontend-only 插件模板（全槽位 Props 与响应式组件示范） |

### 在线文档地址

| 文档 | URL |
|------|-----|
| 索引页（探活用） | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/` |
| 插件开发完全指南 | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/tutorials/plugin-development-tutorial.html` |
| 架构总览（多页汇编入口） | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/architecture/system-overview.html` |
| 插件宿主与生命周期 | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-architecture.html` |
| 脚手架指南 | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/sdk/scaffold-cli.html` |
| 故障排查 FAQ | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/troubleshooting/troubleshooting-faq.html` |
| Release Notes（已知缺陷） | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/release-notes/v0.3.16.html` |

