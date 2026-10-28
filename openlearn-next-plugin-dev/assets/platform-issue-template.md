# 平台仓库 Issue 正文模板（系统侧缺陷）

> 用途：归因结论为 **系统侧** 时，向 `aymwoo/OpenLearn-Next-V2` 提交缺陷 Issue 的正文。
> 提交命令：`gh issue create -R aymwoo/OpenLearn-Next-V2 --title "[缺陷] <模块>：<现象>" --body-file <本文件渲染结果> --label bug --label needs-triage`
>
> 三段必备：**问题原因 / 影响 / 建议解决方式**。缺任一段视为不合格，会被作者以「信息不足」退回。
> 提交前必须：① 过完第六步「系统侧」4 条证据门槛；② 去过重（仓库 issue 含已关闭 + `docs/beta/known-issues.md`）；③ 用户已确认标题与正文全文。

---

## 问题原因

<!--
要求：定位到具体代码路径 / 机制，而不是「插件报错了」。
必须写清：
- 出问题的包与文件（如 packages/core/plugin-host/worker-runtime.ts）
- 具体哪一处逻辑（漏 await / 白名单漏项 / 错误被吞 / 假超时 / 类型导出缺失）
- 版本口径：引入版本、影响版本区间、当前复现在哪个版本
- 关键堆栈帧（顶层 3–5 帧的文件路径，非插件 dist/）
-->

**根因定位**：<包/文件:行 → 具体机制>

**触发链**：

1. <调用方行为，如：插件 activate() 里 `await ctx.db.migrate(...)`>
2. <平台侧路径，如：WorkerRuntime 把 DDL 转发到 ServiceHost>
3. <出错点，如：`plugin_migrations` DDL 未在白名单，抛 WorkerCapabilityError>

**版本口径**：引入于 `<x.y.z>`；影响 `<=<x.y.z>`；本报告复现于 `<x.y.z>`（SDK `<a.b.c>`）。

**关键堆栈帧**（顶层 3–5 帧）：

```
<路径:行:列>   ← 出错点（宿主/SDK 侧）
<路径:行:列>
<路径:行:列>
```

---

## 影响

<!--
要求：谁受影响 + 多严重 + 范围多大 + 有没有规避。不要只写「影响使用」。
-->

- **受影响对象**：<所有 third-party 插件 / 仅 execution_mode=process / 仅远程前端插件 / 仅使用 X API 的插件 / 所有教师端操作>
- **阻塞程度**：<插件完全不可用（激活即失败） / 功能降级（可绕过） / 仅日志噪音>
- **影响版本范围**：`<= <x.y.z>`
- **触发概率**：<必现 / 偶发（N 次中 M 次） / 特定操作后必现>
- **连带影响**：<状态机停在 ERROR / 熔断自动停用 / 看门狗重启风暴 / 数据表未建导致后续请求 500>
- **临时规避**：<有 → 写明做法，如改用 `ctx.db.ensureTable()`、改走声明式贡献、重启服务器；无 → 写「无」>

---

## 建议解决方式

<!--
要求：改哪里 + 怎么改 + 修好后什么现象算通过。可选方案要写权衡。
-->

**建议改动点**：`<包/文件/函数>`

**方案 A（推荐）**：<具体做法> —— 代价：<兼容性 / 性能 / 安全影响>

**方案 B（备选）**：<具体做法> —— 代价：<...>

**验收标准**：

- [ ] <最小复现插件在该版本上激活成功，状态机到达 ACTIVE>
- [ ] <原故障插件的命令可正常返回，无 WorkerCapabilityError>
- [ ] <无新增回归：现有 X 测试 / Y 用例仍通过>

**是否需要文档同步**：<需更新哪一页（附 URL）/ 不需要>

---

## 环境信息

| 项 | 值 |
|----|----|
| 报告人角色 | 开发者（仓库缺陷表单要求项） |
| 对上课的影响 | <停课 / 出错但能上课 / 不确定（表单要求项）> |
| OpenLearnV2 版本 | `<GET /health 的 version，或 npx openlearn-next@<ver> doctor 输出>` |
| `@openlearn/plugin-sdk` 版本 | `<a.b.c>` |
| 故障插件 | `<@scope/name> / <version>` |
| `execution_mode` | `inline` / `worker` / `process` |
| `engines.openlearn` | `<如 >=0.7.0>` |
| `x-request-id` | `<有则填，没有留空>` |
| 运行时 | Node `<ver>` / `<浏览器 + 版本>` / `<OS>` |
| 部署方式 | `npx openlearn-next` / 本地源码 / Docker |
| 多插件环境 | 是 / 否（停用后是否仍复现：<是/否>） |

---

## 复现步骤

1. <步骤一>
2. <步骤二>
3. <步骤三>

**复现稳定性**：每次必现 / 偶发（约 N 次中 M 次） / 特定操作后必现

---

## 期望行为 vs 实际行为

- **期望**：<依据文档哪一条约定（附文档 URL）应发生什么>
- **实际**：<实际报错原文 / 现象>

---

## 完整堆栈与日志（不截断）

### 服务端（`[Plugin:<id>]` 前缀）

```
<完整日志>
```

### 浏览器 Console

```
<完整报错与堆栈>
```

---

## 最小复现插件（≤50 行）

> 仅 manifest + 空 `activate()`；与故障插件保持相同的 `execution_mode` 与权限声明。

```typescript
// src/index.ts
export default {
  manifest: {
    id: '@report/min-repro',
    name: 'Minimal Repro',
    version: '0.0.1',
    engines: { openlearn: '<与故障插件一致>' },
    requires: [/* ... */],
    capabilitiesProposed: [/* ... */],
  },
  async activate(ctx) {
    // 触发故障的最少行数
  },
};
```

---

## 归因证据（为什么是系统侧，不是插件问题）

| 证据 | 内容 |
|------|------|
| 堆栈归属 | 顶层帧位于 `<packages/core/... / src/plugin-host/... / @openlearn/...>`，非插件 `dist/` |
| 对照实验 | 官方脚手架原始产物 / 最小复现插件**同样复现**（见下表） |
| 版本核对 | 所用 API 在该版本**已支持**：<文档 URL + 最低版本> |
| 已知问题比对 | 不在 `docs/beta/known-issues.md`；与既有 issue #<n> 不重复（检索关键词：<...>） |

**对照实验记录**

| 实验 | 平台版本 | SDK | 插件 | execution_mode | 结果 |
|------|---------|-----|------|----------------|------|
| 1 | | | 官方脚手架原始产物 | | 失败 / 正常 |
| 2 | | | 最小复现插件 | | 失败 / 正常 |
| 3 | | | 故障插件 | | 失败 / 正常 |
| 4 | | | 故障插件（停用其他插件） | | 失败 / 正常 |

---

## 已排除项

- [ ] 版本匹配：`engines.openlearn` 与所用 API 最低版本均满足
- [ ] 已重新 `npx @openlearn/plugin-sdk build`，`dist/` 为最新产物
- [ ] 已强刷 / 无痕窗口排除浏览器与 CDN 缓存
- [ ] 已停用→重新激活（排除热重载未生效）
- [ ] 高危权限已审批（不在 `pending_commands`）
- [ ] 已停用其他插件复测（排除插件间冲突）
- [ ] 不是产品边界 / 设计行为（remote 插件无自定义 UI、熔断自动停用、`auth:false` 需审批等）
- [ ] 未误用被 process 沙箱禁用的能力（子进程 / `eval` / 直接 `ctx.config`）

---

## 脱敏确认（提交前自查）

- [ ] 无学生姓名全名册 / 作业或试卷原文 / 成绩导出
- [ ] 无密码、班级临时口令、Cookie、`edu_os_token`
- [ ] 无 AI API Key（含首尾掩码）
- [ ] 无 `.env`、`ENCRYPTION_KEY`、`storage/bootstrap-credentials.txt` 内容
- [ ] 无身份证 / 住址 / 电话 / 健康信息
