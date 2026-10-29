# 平台变更观察清单（文档看不出、但很容易写错的点）

> 适用基线：平台 **v0.7.7** / HEAD `b03e216`（2026-10-28 核对） / SDK 3.7.4。
>
> 存在意义：平台的**文档、README、甚至相邻两页文档之间**并不总是一致；有些行为只有一个提交记录或
> 一行源码能证明。这里记录「最容易误判 + 一错就整套方案跑偏」的条目。
>
> **触发复核的时机**：第一步探活发现 `docSiteVersion` / npm latest / 平台版本 / README 结构 / CHANGELOG 任一变化 →
> 先跑 `bash scripts/platform-drift-check.sh`，再逐条对照本文件。**文档变了不等于行为变了，行为以源码为准。**

---

## 0. 复核 SOP（每次远端文档更新后）

```bash
# 1) 平台版本与提交
cd ~/Develop/openlearnv2 && git log --oneline -10

# 2) 一键漂移检测（期望值见 §8，drift 会逐条列出）
bash <skill>/scripts/platform-drift-check.sh
#    ├─ 无 DRIFT → 只需更新 references/.cache-meta.json 的 docSiteVersion
#    ├─ 有 DRIFT → 逐条读本节 §1–§7 的「判定口径」，改 skill 对应文件
#    └─ 槽位变化 → bash <skill>/scripts/platform-drift-check.sh --write 重生成 slot-registry.json

# 3) 改完跑维护者自检
bash scripts/check-templates.sh && bash scripts/verify-test-harness.sh
```

---

## 1. `OPENLEARN_TRUSTED_INLINE_PLUGINS` 仍然存在，且支持通配符

**事实（源码）**

- `packages/core/plugin-host/execution-policy.ts`：
  `trustedInlineAllowlist()` / `isInTrustedInlineAllowlist()` / `resolvePluginExecutionMode()` 运行期读
  `process.env.OPENLEARN_TRUSTED_INLINE_PLUGINS`；`matchesTrustedInlinePattern()` 支持 `*` 与 `前缀*`。
- 相关提交：`04038ff feat(plugin): …支持通配符（* / 前缀*）`（2026-10-28，已在 HEAD 祖先链）。
- 安装向导 `src/components/PluginInstallWizard.tsx:1123` 仍提示「把 manifest.id 加进白名单并重启」。

**为什么会误判为「已移除」**

- `be8878e docs(readme): 重构 README …移除架构拓扑、环境变量与路线图`（PR #343）：根 README 不再有环境变量表
  （`grep -c OPENLEARN_TRUSTED_INLINE_PLUGINS README.md` = 0）。
- 同时 `288b776` 把「第三方自定义 UI」叙事改成「双轨制可视沙箱」，容易让人以为白名单不再需要。

**判定口径**

- 该变量**仍是**进程内运行的唯一人工开关（另一条是内置目录 `packages/plugins`）。
- **manifest id 前缀（`@openlearn/` / `@ext/`）不构成信任**；`docs/configuration/system-configuration.md` 里
  「其余非 `@openlearn/` 插件强制子进程」的措辞有歧义，以 `execution-policy.ts` 为准。
- 文档里若再次出现「白名单已废弃 / 不需要」的表述，先查 `execution-policy.ts` 是否还在读 env，再下结论。

**验证**

```bash
grep -n "OPENLEARN_TRUSTED_INLINE_PLUGINS\|endsWith('\*')" packages/core/plugin-host/execution-policy.ts
git log --oneline --all --grep="TRUSTED_INLINE_PLUGINS"
```

---

## 2. `view` 页面路径必须以 `storage/` 开头（文档示例 `views/` 是错的）

**事实（源码）**

- 安装器 `packages/core/plugin-host/install.ts:357` **只解压 `storage/` 前缀**：
  `Object.keys(zip.files).filter(name => name.startsWith('storage/'))`（更新路径同样在 ~754 行）。
- 渲染器 `src/components/PluginSandboxIframeView.tsx`：`src = /plugins/<插件>/<view>`，
  `sanitizeViewPath()` 只做安全校验（禁 `..` / 协议 / 绝对路径），**不会**把 `views/` 映射到 `storage/`。
- `docs/tutorials/plugin-frontend-guide.md:641` 的示例写的是 `"views/index.html"` —— 与安装器不符。

**后果**：写 `views/index.html` 的插件，本地/源码内置能跑，**打包成 ZIP 安装后 iframe 404 →
面板空白 / 「正在加载插件视图…」**，构建与安装阶段都不报错。

**判定口径**

- ZIP 插件：`view` 必须是 `storage/<相对路径>`，且 `storage/**` 必须由自写打包脚本补进 ZIP
  （SDK CLI 只打 `manifest.json` / `index.js` / `frontend.js`）。
- 内置插件（文件在 `packages/plugins`）：源文件直接可服务，`views/` 也可能工作 —— 所以文档示例可能是
  按内置插件写的，不能套到 ZIP 插件上。
- L0 已强制：`VIEW_NOT_IN_STORAGE`（error）+ `VIEW_FILE_MISSING` + `VIEW_BRIDGE_MISSING`。

**验证**

```bash
grep -n "startsWith('storage/')" packages/core/plugin-host/install.ts
grep -rn "views/.*\.html" docs/tutorials/plugin-frontend-guide.md
```

---

## 3. SDK CLI 打包仍然只有三件套

**事实**：`packages/plugin-sdk/cli.mjs` 的 `zip.file(...)` 只有 `index.js` / `manifest.json` / `frontend.js`；
`migrations/` 只告警不打包（Issue #321）。

**补充事实**：CLI 的 `sign` 命令会额外写入 `signature.json`（Ed25519 清单签名，仅签名时出现），
它不是默认打包内容，但会让 ZIP 多一个文件 —— 排查「包里为什么多了 signature.json」时看这里。

**判定口径**：任何 `storage/**`、`views/**`、静态资源都需要自写 `pack` 脚本（模板 `assets/sandbox-view/scripts/pack.mjs`）。
若未来 CLI 开始打包 `storage/`，本条的「自写打包」要求即可删除。

**验证**：`grep -n "zip.file(" packages/plugin-sdk/cli.mjs`

---

## 4. 双轨制 `view` 的槽位集合可能在版本间扩张

**事实**：`packages/core/esm-loader/manifest-schema.ts` 中显式声明 `view: z.string()` 的槽位当前是 **5 个**：
`teacher.panel` / `teacher.tab` / `teacher.dashboard.widget` / `student.view` / `student.lesson.tool`
（提交 `d704086` 首版只覆盖 `teacher.tab` / `teacher.panel`，后续提交陆续补齐）。

`contributes` 顶层是 `.passthrough()`，且 `student.classroom.overlay` 等槽位用
`frontendSlotEntrySchema`（`z.object({id}).passthrough()`）——**`view` 会透传并生效**，
但没有被 schema「显式声明」，属于**可用但不承诺长期契约**。

**判定口径**

- 新版本若新增 `view` 槽位：更新 `assets/test-harness/slot-registry.json` 的 `viewSlots` 与
  `references/ui-channel-decision.md` §4.5.1。
- 想在 overlay 上放 `view`：可以，但 L0 会给 `VIEW_SLOT_UNSUPPORTED` 警告；正式产品优先用显式槽位。

**验证**：`grep -n "view: z.string" packages/core/esm-loader/manifest-schema.ts`

---

## 5. 白板画布内卡片（`type:'plugin'`）已支持双轨制 `view`（无需必须 inline）

**事实（源码）**：
- `src/features/whiteboard/widgets/PluginCardRenderer.tsx` 现已支持 `const viewPath = (ext as any).slotProps?.view || ext.view;` 分支，当检测到 `viewPath` 时，渲染 `<PluginSandboxIframeView variant="panel" />`，并向沙箱透传 `lessonId` 与 `classId`。
- `InteractiveWhiteboard.tsx` 按 `teacher.dashboard.widget`（教师端）/ `student.view`（学生端）检索扩展点，ID 对应图元数据中的 `teacherWidgetId` 与 `studentWidgetId`。

**判定口径**：
- **`process` 模式的第三方插件现在完全可以拥有白板卡片**！
- 做法：在 `manifest.contributes` 中注册 `teacher.dashboard.widget` 与 `student.view`，将它们分别指向 `view: "storage/teacher.html"` 与 `view: "storage/student.html"`。
- 白板卡片会被宿主的统一窗口框架（`WidgetFrame`）包裹，获得标题栏、拖拽移动与拉伸尺寸把手，插件视图以沙箱 iframe 方式沉浸渲染。
- 若需写 React inline 组件，则依然受白名单机制约束；但对绝大多数第三方插件，直接采用 `view` 沙箱视图即可，不再强制要求 inline 白名单。

**验证**：`grep -n "PluginSandboxIframeView\|ext.view" src/features/whiteboard/widgets/PluginCardRenderer.tsx`

---

## 6. 槽位注册表是版本相关的封闭集合（v0.7.7）

**事实**：`src/plugin-host/types.ts` 的 `ExtensionSlot` 联合类型 + `AnchorSlot` 动态模式。
`assets/test-harness/slot-registry.json` 由它生成（条数见文件内 `count`；当前 5 个 view 槽位）。

**判定口径**：每次平台小版本升级都要重生成；否则 L0 的 `SLOT_UNKNOWN` 会把新槽位误报、或漏掉已删除槽位。

**验证 / 重生成**

```bash
bash <skill>/scripts/platform-drift-check.sh          # 报告数量/内容 drift
bash <skill>/scripts/platform-drift-check.sh --write  # 重写 slot-registry.json
```

---

## 7. `execution_mode` 以服务端求值为准，manifest 自述无效

**事实**：`src/plugin-host/plugin-host.ts` 前端只用 `existingPlugin?.executionMode`（来自
`GET /api/plugins` 的 DB 列，由 `resolvePluginExecutionMode()` 计算）；代码注释明确禁止读
`manifest.executionMode`（否则第三方包可绕过沙箱）。

**判定口径**：排查"为什么我的 React 不渲染"时，**永远先查 API 返回的 `executionMode` 与
`executionModeCoerced`**，不要看 manifest 里写了什么，也不要看 `.env` 里"应该有"。

**验证**

```bash
curl -s -b cookie.txt http://localhost:3000/api/plugins | jq '.[] | {id, executionMode, executionModeCoerced}'
```

---

---

## 7.1 `frontend.js` 的注册门禁（**v0.7.7 + PR #350 起已放宽**）

**现状（源码，2026-10-29 / 平台 584eb0e）**

- `src/plugin-host/plugin-host.ts` `activateRemotePlugin()`：**先** `registerManifestContributions()`，
  **再**判断 `hasFrontend`；`hasFrontend` 为假时直接置 `ACTIVE` 并 return，**不请求** `frontend.js`。
- 同文件 `catch` 分支走 `unregisterPluginResources(..., { preserveManifestContributions: true })`
  —— 即使 `frontend.js` 404，**声明式贡献仍留在 store**（#292 契约）。
- `src/hooks/useClassroomSlice.ts` 中原有的 `if (!plugin.has_frontend) continue;` 已移除。
- 回归用例：`src/plugin-host/__tests__/declarative-and-view-only-activation.test.ts`
  （三条：纯 view 插件成功注册且不发请求 / 404 时贡献保留 / retry 可恢复）。

**结论（当前口径）**

| 情况 | 现在的表现 |
|------|------------|
| 无 `frontend.js` | **声明式贡献照常注册、入口照常显示**；只是没有隐藏前端逻辑（自定义命令、定时任务、store 订阅） |
| 有 `frontend.js` 但 404 | 插件状态 `ERROR`，但 `teacher.tab` / `view` 等入口**仍然显示**（贡献被 preserve） |
| 需要插件自身命令（`invokeCommand` 到自家 command） | **必须**有 `frontend.js`，否则命令不存在 |

**⚠ 已被推翻的旧结论**：本条曾写「没有前端产物 → 所有 `contributes` 都不注册 → 页面空白且日志无 404」。
在 v0.7.7 + #350 之后该因果**不再成立**。若你看到入口全消失，请先按下面顺序查，不要先怀疑 `frontend.js`：

1. `bash scripts/post-install-check.sh <pluginId> --zip <包>` → 看 DB manifest 里 `view` 是否还在；
2. 不在 → 是安装期 schema 的问题（见 §7.2），重装即可；
3. 在 → 再看渲染器（`renderer-hides-empty-view` 事实）与槽位是否写对（`slot-registry.json`）。

**历史（仅用于理解旧机器行为）**：`frontend-fetch-before-register` 曾是 skill 的一条集成事实，
#350 合并后已替换为 `frontend-register-before-fetch`（带顺序断言，`facts-check.sh` 可检出反向）。

**验证**

```bash
# 顺序：注册行号必须小于 fetch 行号
grep -n "registerManifestContributions(pluginId, manifest)\|const url = \`/plugins/" src/plugin-host/plugin-host.ts
grep -n "if (!hasFrontend)" src/plugin-host/plugin-host.ts
grep -c "if (!plugin.has_frontend)" src/hooks/useClassroomSlice.ts   # 应为 0
```

---

## 7.2 安装期 schema 决定 manifest 落库内容：升级平台不会回填被 strip 的 `view`

**事实（源码）**

- 安装/更新时用 `manifestSchema.parse()` 校验，校验后的对象写进 `manifest.json` 与
  `plugins.manifest`（`install.ts` 192 / 333 / 735，`INSERT INTO plugins` 198 / 521）。
- 激活只做 `JSON.parse(row.manifest)`（`core.ts:258-270` 等），**不会**重新用新 schema 解析。
- `teacher.tab` / `teacher.panel` 的 `view` 字段是 `d704086`（**v0.7.7**）才补进 schema 的；
  `student.classroom.overlay` 走 `frontendSlotEntrySchema`（`.passthrough()`），任何版本都保留。

**典型症状（本次事故）**

```
DB 里 teacher.tab[0]       → { id, label, icon, position }   ← view 消失
DB 里 student.classroom.overlay[0] → { id, label, view }     ← view 还在
```

→ 说明**安装那一刻**跑的是 v0.7.7 之前的 schema：zod 默认 strip 未声明键，`view` 被丢掉并原样落库。
之后即使把平台升到 v0.7.7，DB 里仍是旧结果，重启也不会修复。

**判定口径**

- 出现上述不对称（声明式槽位丢字段、passthrough 槽位保留），先查**安装时的平台版本**，而不是当前版本。
- 修复必须**重新安装/更新插件**（让新 schema 重新解析）或手工重写 `plugins.manifest`；
  只升级平台/重启服务无效。
- 新字段上线初期（如 `view` 在 v0.7.6→v0.7.7 之间）最容易踩：同一插件在旧机装、新机跑就会不一致。

**验证**

```sql
-- 看落库的 manifest 里 view 是否还在
SELECT id, version, substr(manifest, 1, 400) FROM plugins WHERE manifest LIKE '%teacher.tab%';
```

```bash
git log --oneline -S "view: z.string" -- packages/core/esm-loader/manifest-schema.ts
```

## 8. 课堂互动工具（`classroomTools`）下发机制与 SQL-Guard 核心表隔离禁忌

**事实（源码）**：
- `packages/core/plugin-host/sql-guard.ts`：内置核心表黑名单 `FORBIDDEN_CORE_TABLES`，包含 `whiteboard_elements`、`users`、`students`、`classes`、`lessons` 等。在 `process` 子进程模式下，直接执行针对核心表的 SQL 操作（如 `prepare("INSERT INTO whiteboard_elements...")`）会被平台直接拦截拒绝。
- `src/components/LiveClassroomView.tsx:handleExecuteTool`：教师点击白板工具栏 🧩「互动工具」下的插件条目时，前端向 `/api/commands` 派发请求。若 `commandType` 是平台标准命令（如 `whiteboard.draw`），它会穿透插件命名空间直接由平台内核处理，并在白板数据库写入图元后广播 `whiteboard.element_drawn`。

**后果（高频大坑）**：
- 开发者误在 `manifest.classroomTools` 配置自定义命令（如 `stickynotes.open_board`），并在插件后端 handler 中试图通过 SQL 直接写 `whiteboard_elements`。
- 结果：插件后端被 `sql-guard` 抛错拦截；前端虽然收到 command 执行结果的 200 并显示「✓ 工具下发成功」，但**白板画布上根本没有图元生成**。

**判定口径**：
- **推荐做法（声明式下发）**：`manifest.classroomTools` 的 `commandType` 直接写 `whiteboard.draw`，载荷指定 `type: "plugin"`，并在 `data` JSON 字符串中配置 `teacherWidgetId`、`studentWidgetId`、`title`、初始宽高坐标。
- **总线代发做法**：若下发前需执行业务判断，必须在 manifest 声明申请 `whiteboard:write` 权限，在 handler 中调用 `ctx.services.commandBus.execute({ type: 'whiteboard.draw', payload: ... })`，**绝不可直接用 SQL 读写 `whiteboard_elements`**。

**验证**：
```bash
grep -n "whiteboard_elements" packages/core/plugin-host/sql-guard.ts
grep -n "whiteboard.draw" src/components/LiveClassroomView.tsx
```

---

## 9. 课堂浮层（`student.classroom.overlay`）布局隔离、多浮层防重叠与 `resize` 联动

**事实（源码）**：
- `src/plugin-host/extension-point-renderer.tsx`：`FLOATING_VIEW_SLOTS = new Set(['student.classroom.overlay'])`。对浮层槽位采用 `variant="floating"`（固定定位）渲染，避免作为普通 Flex Item 插入 `App.tsx` 的 `flex h-screen` 横向容器中。若未做隔离，普通 `w-full h-full` 块级面板会把主工作区（白板）的宽度挤占为 0 像素（表现为「学生端一出现浮层，上课白板就消失了」）。
- 宿主在渲染同一槽位的多个浮层组件时，按 `index * 316px` 动态向右平移（Dock 布局），防止多个插件（如求助灯与便签）在左下角完全重叠遮挡。
- 插件沙箱通过 `window.OpenLearnPluginBridge.ui.resize(height)` 通知宿主调整容器高度。

**判定口径**：
- 为 `student.classroom.overlay` 编写 `view` 页面时，禁止写撑满屏幕的固定尺寸面板。
- 页面应支持「最小化悬浮球/胶囊条」与「展开弹窗」双态，在状态切换时务必调用 `bridge.ui.resize()`（如最小化 46px，展开 420px），让宿主容器收缩，把屏幕空间还给白板教学。

---

## 10. 课堂上下文缺失时的优雅降级（`classId || 'default'`）与写限流防范

**事实（源码）**：
- 教师单课备课试讲、直接进入白板调试或尚未排定班级时，宿主传给插件的 `classId` 可能是 `null` 或 `undefined`。
- 平台服务端对 `/api` 写请求设置了写限流池（开发环境放宽至 600 次/分，旧版生产环境为 60 次/分），高频短轮询或无防抖的状态同步会迅速耗尽限流池，导致后续所有写操作（包括关键的教师全班锁定学生屏幕 `lock_lesson`）被 HTTP 429 拦截。

**判定口径**：
- **上下文防御性降级**：插件前端与后端处理 `classId` 与 `lessonId` 时，禁止使用硬断言（`if (!classId) throw ...`）；统一采用 `classId || 'default'` 优雅降级，并在前端监听 `bridge.onContextUpdate` 实现班级切换时的自动数据热重载。
- **避免 429 限流**：插件视图与后端的交互优先采用 `eventBus` 实时通知；若必须轮询，间隔建议 `>= 3000ms`；任何状态回写（如页码、环节同步）必须在前端做「值变更比较」与「500ms 防抖」，严禁无变化重复刷接口。

---

## 11. 期望值（`platform-drift-check.sh` 的比对基准）

| 信号 | 当前期望 | 漂移时更新 |
|------|---------|-----------|
| 平台版本 | `0.7.7` | `references/.cache-meta.json`、SKILL.md 头部 |
| 槽位数量 | 见 `slot-registry.json` 的 `count`（勿写死；`platform-drift-check.sh` 会比对） | `slot-registry.json`、`ui-channel-decision.md` §2 |
| `view` 槽位 | 上述 5 个 | `slot-registry.json.viewSlots`、§4.5.1 |
| 安装器解压前缀 | 仅 `storage/` | §2 与 L0 规则 |
| CLI 打包文件 | 3 个（index/manifest/frontend） | §3 与 `sandbox-view` 模板 |
| README 是否含白名单变量 | `0`（已被 #343 移除） | §1 的「误判来源」 |
| 白名单通配符支持 | 有（`endsWith('*')`） | §1 |
| 白板卡片是否支持 view | 是 | §5 与 SKILL 第二步通道表 |
| `has_frontend` 跳过激活 | **否（0 处，`#350` 已移除）** | §7.1；回退会报漂移 |
| 前端 fetch 在贡献注册之前 | **否（注册已前移）** | §7.1 与 `facts-check.sh` 的 `frontend-register-before-fetch` |
| 安装期 schema 落库、不回填 | 是 | §7.2 |

> 本表与脚本里的 `EXPECT_*` 常量必须同步修改；只改一边会导致 CI 漂移检测误报。
