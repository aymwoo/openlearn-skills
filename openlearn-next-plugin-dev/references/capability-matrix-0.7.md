# 能力权限矩阵（v0.7.7 真源，SDK 3.7.4）

> 本文件整理自 OpenLearnV2 官方文档 `reference/plugin-capability-matrix.html`（`doc-version: sdk=3.7.4`）与源码
> `packages/core/capability/guard/capability-guard.ts`、`packages/core/registry/index.ts`。
> 平台仓库本地路径：`~/Develop/openlearnv2/docs/reference/plugin-capability-matrix.md`。
>
> **权限字符串是「平台真实存在」的封闭集合，捏造会静默失效。**

---

## 0. 先分清四套互不相干的「能力」机制

平台里有四个都叫 capability 的东西，混用会导致归因失败：

| # | 机制 | 载体 | 用途 |
|---|------|------|------|
| 1 | **Capability 字符串 RBAC** | `resource:action`，如 `lesson:read` | `capabilitiesProposed` 声明 + `capabilityRequired` 校验 —— **本文件讲的就是这套** |
| 2 | `RuntimePermissionManager` | `lesson:control` / `stage:navigate` / `whiteboard:draw` / `quiz:submit` / `plugin:execute` / `ai:invoke` / `session:manage` | 运行时细粒度开关，**不能**写进 `capabilitiesProposed` |
| 3 | Capability Provider 框架 | `CapabilityRole` 枚举 + `cap_analytics_insight` 之类的 descriptor id | 平台内建能力（如 analytics）的对外暴露 |
| 4 | AI function calling ID | `capability_chat` / `capability_whiteboard` / `capability_tool` …（`packages/core/ai-capability/capabilities/` 下 7 个） | AI 层能力描述符，**不是** RBAC 字符串 |

> 只有第 1 套能写进 `manifest.capabilitiesProposed`。

---

## 1. 真实权限全集（`capabilityRequired` / `capabilitiesProposed` 可用）

**19 条**（真值源：平台 `docs/agent/contracts/capabilities.json` 的 `command_required`；
文档里流传的「20 条」是把 `quiz:write` 算进来了，而它并不在 `capabilityRequired` 里。
校验：`python3 audit-tools/agent_facts.py --check`）：

| 权限字符串 | 覆盖的主要动作 |
|------------|----------------|
| `management:write` | `user.create` `user.update` `user.delete`(高危) `class.create` `class.add_student` `class.update` `class.delete` `student.create` `student.update` `student.delete` `class.remove_student` `class.template_download` `student.template_download` `student.add_note` `assignment.create` `assignment.submit` `assignment.grade` `schedule.create` `attendance.record` `student.set_progress` `lab.create` `lab.assign_seat` `schedule.cancel` |
| `lesson:write` | `lesson.create` `lesson.update` `lesson.update_timeline` `lesson.add_segment` `lesson.remove_segment` `courseware.upload` `courseware.confirm` `courseware.save_score_config` `courseware.regrade_attempts` `courseware.delete` `ai.apply_recommendation`(高危) |
| `whiteboard:write` | `whiteboard.draw` `whiteboard.update` `whiteboard.delete` `whiteboard.clear` `whiteboard.batch_draw` `whiteboard.duplicate` |
| `management:read` | `user.list` `class.list` `student.list` `class.get_students` `lab.list` `schedule.list` |
| `plugin:write` | `plugin.install`(高危) `plugin.install_zip`(高危) `plugin.update_zip`(高危) `plugin.toggle`(高危) `plugin.uninstall`(高危) |
| `lesson:read` | `courseware.get_score_config` `courseware.list_score_configs` `courseware.get_attempt_raw_data` `courseware.list` |
| `vfs:write` | `vfs.write_file` `vfs.mkdir` |
| `process:write` | `process.spawn` `process.kill` `ai.start_generation` |
| `assignment:manage` | `assignment.create` `assignment.assign_peer_reviews` `assignment.grade` |
| `whiteboard:read` | `whiteboard.query` `whiteboard.get_element` |
| `vfs:read` | `vfs.read_file` `vfs.list_dir` |
| `process:read` | `process.list` `process.logs` |
| `assignment:read` | `assignment.list` `assignment.get` |
| `lesson:delete` | `lesson.delete`（高危） |
| `plugin:read` | `plugin.info`（显式 `isHighRisk: false`） |
| `student:write` | `courseware.submit_attempt` |
| `assignment:write` | `ai.apply_grade`（高危） |
| `assignment:submit` | `assignment.submit` |
| `assignment:review` | `assignment.peer_review` |

**仅出现在 `capabilitiesProposed`、从未作为 `capabilityRequired`**（声明它们无害，但也拿不到任何能力）：

`class:read` `class:write` `student:read`

---

## 2. ⚠️ 不存在的权限（切勿捏造）

以下字符串在源码中**根本不存在**，写进 manifest 只会得到「声明了但不生效」的假象：

| 捏造的写法 | 正确做法 |
|------------|----------|
| `user:read` / `user:write` | 用 `management:read` / `management:write` |
| `system:process` | 用 `process:read` / `process:write` |
| `ai:invoke` 当作 RBAC 权限用 | 它确实存在，但属于**第 3 套注册** `runtime_permission`（连同 `lesson:control` `plugin:execute` `quiz:submit` `session:manage` `stage:navigate` `whiteboard:draw`），不是 `capabilityRequired`。写成 `capabilitiesProposed` 拿不到 RBAC 能力；AI 调用走 `capability_*` ID |
| `network:fetch` / `net:*` | 出站网络不走 RBAC：由 `manifest.network.outbound` 申请 + `plugin_network_grants` 域名白名单管控 |
| `courseware:*` | 用 `lesson:read` / `lesson:write`（教师侧）、`student:write`（学生提交） |
| `classroom:*` `class:*` | `class:read` / `class:write` 仅作声明项存在 |
| `analytics:*` | 用 Provider descriptor `cap_analytics_insight` |
| `storage:write` | 仅测试代码出现过，生产无消费点；持久化用 `ctx.services.storage` |

---

## 3. 声明与生效

- **声明**：只在 `manifest.capabilitiesProposed`（字符串数组）。运行期没有「声明新权限」的 API。
- **授予**：宿主在 `activatePlugin` 时把 `capabilitiesProposed` 里的每条 `grant(actorId, cap)`，actor 为 `plugin:${manifest.id}`。授予失败会 rethrow 并中止激活。
- **v0.7.2 变更（Issue #224）**：运行时判定改用「**已授予**」能力集，不再按「已声明」放行 —— 即管理员未审批的权限，即使声明了也不生效。
- **Worker/process 模式额外门禁**：`ServiceHost` 持有 `manifestCapabilities`；数组为空时，除 `get` 外的 RPC 方法全部被拒（`empty manifestCapabilities, only 'get' methods allowed`）。这是 Token 白名单，与 RBAC 字符串是两回事。
- **通配符**：`lesson:*` 之类的部分通配受支持（`res` 或 `act` 命中 `*` 即通过）；`*:*:*` / `*` 是超级管理员绕过。

---

## 4. 高危与错误码

- **「高危」不是权限字符串的属性**，而是**命令动作**的属性：`ActionDescriptor.isHighRisk?: boolean`。高危动作会进入 `pending_commands` 审批队列，非管理员需 `approved=true`。
- **实际错误码**（不要写 `CAPABILITY_DENIED`，该常量不存在）：

| 错误码 | 含义 |
|--------|------|
| `COMMAND_NOT_REGISTERED` | 命令没有在 actionRegistry 登记描述符 → 内核 default-deny 拒绝（HTTP 403） |
| `COMMAND_CAPABILITY_DENIED` | 已登记但 actor 缺少所需能力（未声明或未获批） |

> 典型误判：插件只 `registerHandler()` 而漏了 `actionRegistry.register()` → 报的是「命令未注册」而不是「权限不足」，很容易被误归因成系统缺陷。

---

## 5. 高危动作清单（`isHighRisk: true`）

`user.delete`（`management:write`）· `plugin.install` / `plugin.install_zip` / `plugin.update_zip` / `plugin.toggle` / `plugin.uninstall`（`plugin:write`）· `ai.apply_recommendation`（`lesson:write`）· `ai.apply_grade`（`assignment:write`）· `lesson.delete`（`lesson:delete`）

---

## 6. 与本文相关的源码位置

| 位置 | 作用 |
|------|------|
| `packages/core/capability/guard/capability-guard.ts` | 能力校验实现、默认 actor 授权表 |
| `packages/core/registry/index.ts` | `ActionDescriptor` 定义（含 `isHighRisk` / `exposeToAgent`） |
| `packages/core/esm-loader/manifest-schema.ts` | `capabilitiesProposed` 的 Zod 校验 |
| `packages/core/plugin-host/index.ts` | 激活期 `grant()` 逻辑 |
| `packages/core/plugin-host/context-builder.ts` | `warnOnMissingActionDescriptor`（default-deny 预检告警） |

---

## 来源

- 官方文档：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-capability-matrix.html
- Manifest 规范：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-manifest-spec.html
