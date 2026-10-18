# Changelog

本仓库所有值得记录的变更都写在这里。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
版本通过 git tag（`vX.Y.Z`）发布。

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
