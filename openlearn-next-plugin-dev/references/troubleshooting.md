# 插件故障归因与 Bug 报告 SOP

[本文件为 skill 自建的诊断方法论，依据 OpenLearnV2 官方文档 v0.3.16（插件宿主 / 生命周期 / 安全权限 / Release Notes）整理；文末列出依据来源]

当开发者报告"插件不工作 / 报错了"时，**不要立刻改代码，也不要立刻甩锅给平台**。先按本 SOP 做归因，得出明确结论后再决定动作。归因错误会导致：明明是系统缺陷却在插件里到处打补丁，或明明是插件违规却去给作者提无效 bug。

---

## 0. 归因结论只有 5 种

| 结论 | 含义 | 后续动作 |
|------|------|---------|
| **插件侧** | 插件自身代码/配置/manifest 违规 | 直接修插件（配合 SKILL.md 第四步预检清单） |
| **系统侧** | 宿主 / 内核 / SDK / 官方文档缺陷 | 生成 bug 报告文档，交用户发给系统作者 |
| **插件间冲突** | 两个插件命名空间/事件名/表名/槽位撞车 | 定位冲突双方，按命名空间规范改名 |
| **环境与配置** | 版本不匹配、未重新构建、缓存、权限未审批 | 给出修复步骤，不算缺陷 |
| **待定** | 证据不足，无法归因 | 列出缺失证据，指导用户补充后再判定 |

> 用户问"是插件的原因还是系统的原因"时，答案必须落到上表之一，并给出**证据**。

---

## 1. 三条铁律

1. **堆栈归属**：错误堆栈的顶层帧决定责任方。`dist/index.js` / `dist/frontend.js` → 插件；`packages/core/...`、`src/plugin-host/...`、`node_modules/@openlearn/...` → 系统/SDK。
2. **对照实验**：用官方脚手架原始产物或最小复现插件做控制变量实验。**能在最小插件上复现的才是系统侧。**
3. **先核版本**：任何归因之前，先确认"系统版本 vs 插件 engines vs 所用 API 的最低版本"。大量"系统 bug"其实是插件用了未来版本的 API 或声明了不兼容的 engines。

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
| `CAPABILITY_DENIED`，未在 `capabilitiesProposed` 声明 | **插件侧** | 权限声明缺失 |
| `CAPABILITY_DENIED`，已在 `capabilitiesProposed` 声明且权限名在矩阵中存在 | **系统侧** | CapabilityGuard 误判或权限矩阵与实现不同步 |
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
| `ctx.services.eventBus` | `on()` / `off()` | `subscribe()` / `unsubscribe()` | 方法名用错 → 插件侧 |
| `ctx.services.commandBus.execute()` | 自动加 `manifest.id` 前缀 | **不自动加前缀** | 未手动拼完整 type → 插件侧 |
| `ctx.db.migrate(fn)` / `IDatabaseToken` | 同步 `better-sqlite3` | 异步 `prepare().run/get/all` + `exec()`（0.3.9+） | 用同步写法或 `transaction` → 插件侧 |
| `ctx.db.table()` | 返回 manifest ID 前缀 | 返回 **UUID 前缀** | 切换执行模式导致表名变化是**已文档化行为**，不是 bug |
| `ctx.http` | 完整 | 完整（RPC 跨线程，5000ms 熔断，0.3.11+） | — |
| `ctx.pluginId` | manifest ID | UUID | 用它拼持久化键会不一致 → 插件侧 |

### D5. 停用 / 卸载阶段

| 现象 | 归因 |
|------|------|
| 定时器 / EventBus 订阅 / 后台进程未清理（内存或重复监听） | **插件侧**（`deactivate()` 未执行清理 SOP） |
| `disposeAll` / `revokeAll` 抛错 | **系统侧** |

### D6. 归因前置的环境排除项

先排除以下"假 bug"，否则会误判为系统侧：

- [ ] **版本不匹配**：插件 `engines.openlearn` 或所用 API 的最低版本与系统不符（例：`ctx.reportProgress` 需 0.3.16+，`ctx.require` 需较新版本）。
- [ ] **未重新构建**：`dist/` 是旧产物；改完源码没跑 `npx @openlearn/plugin-sdk build`。
- [ ] **浏览器 / CDN 缓存**：前端 `frontend.js` 是旧版本；强刷或换无痕窗口复测。
- [ ] **热重载未生效**：开发模式文件监听未触发，需手动停用→激活。
- [ ] **权限未审批**：高危能力挂在 `pending_commands` 审批表里尚未批准。
- [ ] **多插件干扰**：停用其他插件后复测。
- [ ] **执行模式差异**：问题是否只在 worker 出现？若是，先对照 §3-W 排查插件是否违反了文档化的 Worker API 差异（最常见的是 `ctx.config`、`ctx.provide()`、`eventBus.on/off`、`commandBus.execute` 前缀、同步 DB 写法）。
- [ ] **Worker/Inline 表名变化**：`ctx.db.table()` 在两种模式下前缀规则不同（manifest ID vs UUID），切模式后表名变化属**预期行为**，不是缺陷。

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

> 该表需在每次缓存探活时对照最新 Release Notes 维护。

> ⚠️ **归因引用规范**：引用「文档承诺」时，必须写明来源页及其版本状态（如「tutorial §6.7 记 0.3.15+，Release Notes v0.3.16 记 0.3.16」）。官方文档存在页与页之间版本口径不一致的情况，**Release Notes 是版本事实的单一真理源**。

---

## 7. 输出规范

### 7.1 对话内的简要汇总（必给，≤10 行）

```
【故障归因】系统侧（或：插件侧 / 插件间冲突 / 环境与配置 / 待定）
现象：<一句话>
关键证据：
  1. <堆栈归属 / 版本核对 / 对照实验>
  2. ...
判定依据：<为什么是这一类，而非另一类>
建议动作：<修复方式 或 生成 bug 报告>
```

### 7.2 系统侧 → 生成 Bug 报告文档

- **模板**：`assets/bug-report-template.md`
- **落盘路径**：插件项目根目录，文件名 `BUG-REPORT-<slug>-<YYYYMMDD>.md`
  - `<slug>`：问题英文短名，如 `worker-migrate-capability-denied`
  - 日期取当前日期，如 `20260918`
- 生成后告知用户：该文件可直接发送给系统作者；并提示把「最小复现插件」一并附上。

### 7.3 插件侧 → 不生成报告

给出具体修改点，并按 SKILL.md「第四步」的预检清单复查。

### 7.4 待定 → 不生成报告

列出缺失的证据项（对照第 2 节清单），并给出用户可自行执行的取证命令。

---

## 来源

- 故障排查与 FAQ：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/troubleshooting/troubleshooting-faq.html
- 插件宿主架构：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-architecture.html
- 插件生命周期：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-lifecycle.html
- Manifest 规范：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-manifest-spec.html
- 安全与权限：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/architecture/security-permissions.html
- 能力权限矩阵：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-capability-matrix.html
- Release Notes v0.3.16 / v0.3.15 / v0.3.14 / v0.3.13（已知系统缺陷来源）
- 版本迁移指南：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/migration/version-migration.html
