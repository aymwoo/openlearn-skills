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

## 5. 白板画布内卡片（`type:'plugin'`）仍然**不认** `view`

**事实**：`src/features/whiteboard/widgets/PluginCardRenderer.tsx` 只处理 `ext.component`（React）与
`ext.render`（DOM 函数），没有 `view` 分支；`InteractiveWhiteboard.tsx` 按
`teacher.dashboard.widget`（教师）/ `student.view`（学生）查扩展点，id 用 `teacherWidgetId` / `studentWidgetId`。

**判定口径**：白板画布内的自定义卡片 → **必须 inline（白名单）**，`view` 救不了。
若未来 `PluginCardRenderer` 增加 view 分支，本 skill 的「白板必须 inline」结论才能改。

**验证**：`grep -n "hasView\|ext.view\|component" src/features/whiteboard/widgets/PluginCardRenderer.tsx`

---

## 6. 槽位注册表是版本相关的封闭集合（v0.7.7 = 122 个）

**事实**：`src/plugin-host/types.ts` 的 `ExtensionSlot` 联合类型 + `AnchorSlot` 动态模式。
`assets/test-harness/slot-registry.json` 由它生成（当前 122 个槽位 + 5 个 view 槽位）。

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

## 8. 期望值（`platform-drift-check.sh` 的比对基准）

| 信号 | 当前期望 | 漂移时更新 |
|------|---------|-----------|
| 平台版本 | `0.7.7` | `references/.cache-meta.json`、SKILL.md 头部 |
| 槽位数量 | `122` | `slot-registry.json`、`ui-channel-decision.md` §2 |
| `view` 槽位 | 上述 5 个 | `slot-registry.json.viewSlots`、§4.5.1 |
| 安装器解压前缀 | 仅 `storage/` | §2 与 L0 规则 |
| CLI 打包文件 | 3 个（index/manifest/frontend） | §3 与 `sandbox-view` 模板 |
| README 是否含白名单变量 | `0`（已被 #343 移除） | §1 的「误判来源」 |
| 白名单通配符支持 | 有（`endsWith('*')`） | §1 |
| 白板卡片是否支持 view | 否 | §5 与 SKILL 第二步通道表 |

> 本表与脚本里的 `EXPECT_*` 常量必须同步修改；只改一边会导致 CI 漂移检测误报。
