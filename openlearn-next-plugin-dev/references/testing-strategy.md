# 插件开发期测试策略（L0–L3）

> 适用基线：平台 v0.7.7 / SDK 3.7.4 / `@openlearn/plugin-test-kit` 3.3.3（2026-10-28 核对）。
>
> 一句话：**插件测试不是追求行覆盖率，而是把平台的契约（default-deny、白名单、沙箱边界、命名空间、生命周期）
> 变成可执行断言。** 契约漏测的表现不是「单测不绿」，而是「装得上、点开就崩」。

---

## 1. 为什么必须分层

插件有四个彼此独立的失效面，任何单层测试都覆盖不到其余三层：

| 失效面 | 例子 | 谁抓得住 |
|--------|------|---------|
| 编译期 | 值导入 type-only 符号 → 编译过、运行 undefined | L0 |
| 装配期 | `classroomTools` 声明了 commandType，但缺 ActionDescriptor → 403 | L0 + L1 |
| 运行期 | `payload.student.name` 在空 payload 下崩；未 `await` 的 DDL 让进程退出 | L2 |
| 宿主联调期 | 声明式贡献被熔断、`auth:false` 未审批、process 沙箱禁 API | L3 |

> Mock 通过 ≠ 生产可用。`createMockContext()` 刻意放宽了 `ctx.provide` 声明校验、`ensureTable` 的 SEC 校验、
> 能力校验与默认拒绝。**放宽的部分正是插件最容易死的地方**，所以 L1 用集合断言直接补齐，L0 用静态规则兜底。

---

## 2. 四层测试阶梯

| 层 | 手段 | 耗时 | 跑的频率 | 失败意味着 |
|----|------|------|---------|-----------|
| **L0** | `node test-harness/static-check.mjs .` | < 1s | 每次保存 / pre-commit | manifest 或代码结构违反平台契约 |
| **L1** | `vitest run` 的 `contract.test.ts` + `view-smoke.test.ts` | ~0.3s | 每次改 manifest / 注册逻辑 / `storage/*.html` | 声明的入口与实际注册不一致、权限串是假的，或 view 页面加载即报错 / 不发命令 |
| **L2** | `vitest run` 的 `smoke.test.ts` | ~0.3s | 每次改业务逻辑 | 执行期崩溃 / 生命周期重入泄漏 / 路由 5xx |
| **L3** | 真实宿主：上传 ZIP → 激活 → 点入口 → 停用 | 3–10 min | 每次交付前 | Mock 与生产宿主的差异（能力审批、process 沙箱、熔断） |

**门禁**：L0 必须 0 error 且 L1 全绿才允许进入「构建 → 上传」；L3 只在交付前做一次。
不要为了让它绿而放宽断言——断言是契约，不是实现细节。

铺开方式见 `assets/test-harness/README.md`（复制目录 + 依赖 + 2 条 npm script；有 `storage/*.html` 时再加 `jsdom`）。

---

## 3. 必测矩阵（按插件特征勾选）

| 插件特征 | 必须断言 | 层 | 参考错误 |
|---------|---------|----|---------|
| 任何插件 | `manifest.main` / `id` / `version` / `engines.openlearn` 存在 | L0+L1 | 装不上 |
| 任何插件 | `capabilitiesProposed` ⊆ 平台真实 20 条 | L0+L1 | 声明了不生效 |
| `process` / 非白名单 `inline` | `capabilitiesProposed` 为空但 `activate` 调了非 get RPC → `CAP_EMPTY_ISOLATED`；L1 用 Proxy 录制 activate 期调用 | L0+L1 | 激活 500：`only 'get' methods allowed`（ServiceHost Barrier 2） |
| 有 `classroomTools` / `contributes` | 每个 commandType 都有 handler **且** 有 ActionDescriptor | L0+L1 | `COMMAND_NOT_REGISTERED` 403 |
| 注册 handler | handler 是 `{ execute }` 对象，不是裸函数 | L1 | `handler.execute is not a function` |
| 注册 Action | `capabilityRequired` 真实存在、`description` 具体、`inputSchema` 类型大写 | L0+L1 | 授权被拒 / AI 选不准 |
| 运行期扩展点 | commandType 写**全限定** `manifest.id.xxx` | L0 | 命令找不到（不自动前缀化） |
| 命令里解构 payload | 按 `inputSchema` 造最小 payload 执行不崩 | L2 | `Cannot read properties of undefined` |
| `ctx.db.ensureTable` | 表名正则、schema 无分号 ≤4000 字符、调用被 `await` | L0 | 生产宿主拒绝 / 进程退出 |
| `ctx.db.migrate` | 首启可执行、重复执行幂等 | L2 | 迁移未生效 / 重复建表 |
| EventBus 订阅 | 停用后订阅数量不翻倍（保留 handler 引用并 `unsubscribe`） | L2 | 事件重复投递 |
| `manifest.api.routes` | 每条路由不返回 5xx；`auth:false` 已知需审批 | L2+L3 | 白屏 / 401 |
| `manifest.api.routes` ↔ `ctx.http` | 方法 + 路径**双向逐字**一致（声明未注册=404；注册未声明=永远调不到） | L0 | `ROUTE_UNREGISTERED` / `ROUTE_UNDECLARED` |
| 裸 SQL（`IDatabaseToken`） | 字面量表名属于 `plugin_*`；无 ATTACH/PRAGMA/VACUUM/TRIGGER/VIEW；DDL 走 `ensureTable/migrate` | L0 | sql-guard 运行期拒绝 |
| `view` 页面（`storage/*.html`） | 无 `alert/confirm`、无直连 `fetch`、调 `bridge.ui.resize`、`api.*` 返回值不取 `.result`（L0）；jsdom 中能加载、`onInit` 后真的发出命令 / 接口、无未捕获脚本错误（L1） | L0+L1 | 弹窗失效 / 请求失败 / 判定恒错 / 页面空白 |
| 远程前端 | 无 React / DOM / `fetch` / 裸模块说明符 / `component` | L0 | 激活失败 |
| 远程前端 | 前端只做轮询与数据型扩展点 | L2（人工）+ L3 | 收不到推送 |
| AI Action | 每个 Action 对应 `capabilityRequired` 与实际命令语义一致 | L1（人工核对） | 越权或功能缺失 |

---

## 4. Guardrail → 测试用例映射

`SKILL.md` 第三步的 12 条编码规范，每条都有对应的自动化断言，避免「doc 上写了但没人执行」：

| Guardrail | 断言位置 | 规则 |
|-----------|---------|------|
| 1. `manifest.main` 必填 | L0 `MANIFEST_MAIN` · L1 manifest 用例 | 缺失即 error |
| 2. Manifest 1:1 映射（handler + action） | L0 `PAIR_*` · L1 三条配对用例 | 缺任一即 error |
| 3. 命令命名空间三语义 | L0 `EXT_POINT_PREFIX` · L1 短名断言 | 运行期必须全限定 |
| 4. 事件订阅无 Disposable | L2 重复激活用例 | 停用后同一事件订阅数 ≤1 |
| 5. 远程前端无 React / DOM | L0 `FRONTEND_*` | 命中即 error |
| 6. 可见 UI 走声明式 | L0 `FRONTEND_COMPONENT` · L1 只读 slotProps | 传函数即 error |
| 7. DB 契约（await / 表名 / 分号） | L0 `DB_*` · L2 迁移冒烟 | 违规即 error |
| 8. 清理 SOP | L2 `deactivate` 重复调用 + 订阅释放 | 抛错或翻倍即失败 |
| 9. 跨插件服务三步配套 | L0 provides/requires 检查 · L3 激活顺序 | 缺 `provides` 即抛错 |
| 10. 远程前端只能轮询 | L0 `FRONTEND_DOM` / `VIEW_DIRECT_FETCH` · L3 实测 | 收不到推送 |
| 11. 迁移用 `ensureTable`/`migrate` | L0 `DB_NO_PREPARE` · L2 迁移冒烟 | 声明式迁移静默失效 |
| 12. 隔离模式能力门禁 | L0 `CAP_EMPTY_ISOLATED` · L1 Barrier 2 用例 | 激活 500：`only 'get' methods allowed` |

---

## 5. Mock 与生产宿主的差异（官方口径，测试必须补偿）

| 行为 | Mock | 生产宿主 | 补偿手段 |
|------|------|---------|---------|
| `ctx.provide` | 不校验 `manifest.provides` | token.name 必须出现在 `manifest.provides`，否则抛错 | L0 检查 provides；L3 验证 |
| `ensureTable` / `table()` | 无 SEC 校验 | 表名正则、schema ≤4000、禁分号 | L0 静态检查 |
| `ctx.db` | 内存 SQLite（per-test） | 共享库 + `plugin_<uuid>_` 前缀 | L2 用 `ctx.db.table()`，不手拼表名 |
| `ctx.require` | 直接抛错 | 白名单共享模块 | 用 `customTokens` 注入替代 |
| `pointsDimension` / `pointsLedger` | 恒 `null` | inline 有值；worker/process 也是 `null` | 代码必须判空（L1 可断言不崩） |
| `commandBus.registerHandler` | 不补前缀 | 自动补 `manifest.id.` | 断言用短名；联调用全限定 |
| 能力校验 / 默认拒绝 | 不校验 | 校验 `capabilityRequired` + ActionDescriptor + 管理员授权 | L1 集合断言 |
| ServiceHost Barrier 2（空能力禁非 get RPC） | **不模拟**：Mock 里 `ctx.db.ensureTable` 等照常成功 | 已授予能力为空时，任何非 get RPC 抛 `Capability denied … only 'get' methods allowed` | L0 `CAP_EMPTY_ISOLATED`；L1 用 Proxy 录制 activate 期调用自行复现；L3 验真实激活 |
| EventBus 通配 | 只认 `'*'`，不认 `prefix.*` | 支持模式匹配 | 断言「订阅已注册」，投递交给 L3 |

---

## 6. 环境坑（实测，2026-10-28）

1. **`@openlearn/plugin-sdk@3.7.4` 的 `dist/index.js` 引用了未声明的 `uuid`**
   → `Cannot find package 'uuid' imported from .../@openlearn/plugin-sdk/dist/index.js`。
   当前是**平台侧打包缺陷**（`dependencies` 只声明了 `esbuild` / `jszip`，`zod` 是 peerDep，`uuid` 完全缺失）。
   临时解法：`npm i -D uuid zod`。已按 SKILL.md 第六步 B 上报：**Issue [#349](https://github.com/aymwoo/OpenLearn-Next-V2/issues/349)**（影响 3.6.0–3.7.4，修复后本条可删）。
2. **`@openlearn/plugin-test-kit` 以 TS 源码发布**（`main: index.ts`）。vitest 5 能直接转译；
   更老的 vitest 可能外置 node_modules → 用 `server.deps.inline: ['@openlearn/plugin-test-kit']`（harness 已配）。
3. **`better-sqlite3` 是 peerDep 且为原生模块**：未装时 `createMockContext()` 直接抛；预编译二进制通常几秒装完。
4. **`--reporter=basic` 在 vitest 5 已移除**，会报 `ERR_LOAD_URL`；用默认 reporter 或 `--reporter=dot`。
5. **测试目录不在模板 tsconfig 的 `include` 里**：`npm run build` 不会编译测试，无需改动 `tsconfig`；
   若要把测试纳入 `tsc --noEmit`，需 `allowImportingTsExtensions` 或统一用 `.js` 后缀导入（harness 已用 `.js`）。

---

## 7. L3 真实宿主冒烟清单（交付前 10 分钟）

```text
1. 上传 ZIP → 插件中心显示版本正确
2. 激活 → 服务端日志无 [Plugin:<id>] ERROR；状态机到达 ACTIVE
3. 高危权限/出站域名：确认审批状态（pending_commands 为空）
4. classroomTools：白板出现按钮 → 点击 → 命令返回 → 前端收到回显
5. command_palette 条目：Ctrl+K 可见 → 回车能派发（验证全限定 commandType）
6. AI Action：自然语言触发 → Agent 选中正确 Action（验证 description / inputSchema）
7. api.routes：curl 命中（auth:true 带教师 Cookie；auth:false 确认已批准）
8. 停用 → 再激活：无重复按钮 / 无重复事件；日志无 `HANDLER_ALREADY_EXISTS`
9. 卸载：数据表按预期保留或清理（看 manifest 约定）
```

> 任何一步失败，先按 `SKILL.md` 第六步归因（插件侧 / 系统侧 / 环境与配置 / 产品边界），
> 不要直接把测试期望改宽。

---

## 8. CI 建议（可选）

```yaml
- run: npm ci
- run: node test-harness/static-check.mjs .
- run: npx vitest run --config test-harness/vitest.config.ts
- run: npx @openlearn/plugin-sdk build
- uses: actions/upload-artifact@v4
  with: { name: plugin-zip, path: dist/*.zip }
```

CI 只做 L0–L2；L3 需要真实宿主，留在交付前人工执行。

---

## 9. 来源

- `@openlearn/plugin-test-kit` 文档：`~/Develop/openlearnv2/docs/sdk/plugin-test-kit.md`（§2 差异表、§4 命名空间）
- 插件数据库 API：`~/Develop/openlearnv2/docs/reference/plugin-database-api.md`（表名/SEC 校验）
- 能力权限矩阵：`references/capability-matrix-0.7.md`
- 前端沙箱边界：`references/frontend-bridge-0.7.md`
- `uuid` 缺失实测：`npm pack @openlearn/plugin-test-kit@3.3.3` + `node -e "import('@openlearn/plugin-sdk')"`
