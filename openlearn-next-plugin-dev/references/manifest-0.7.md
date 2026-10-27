# Manifest 规范（v0.7.4 真源）

> 整理自官方文档 `plugin/plugin-manifest-spec.html`（`doc-version: sdk=3.7.1`）与权威 Schema
> `packages/core/esm-loader/manifest-schema.ts`。
> 平台仓库本地路径：`~/Develop/openlearnv2/docs/plugin/plugin-manifest-spec.md`。

---

## 1. 必填字段（Schema 层强制）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | 全局唯一，建议 `@org/plugin-name`。**不得包含 `:`**（actor 命名空间保护，`plugin:@evil:admin` 类伪造已被堵） |
| `name` | `string` | 显示名 |
| `version` | `string` | SemVer |
| `main` | `string` | 代码入口相对路径，如 `"index.js"`。**Schema 必填**（`z.string().min(1)`）；ZIP 安装路径会在校验前注入默认 `"index.js"`，但请始终显式声明 |

> ⚠️ 漏 `main` 是最常见的「插件装不上」原因。

---

## 2. 依赖与版本

| 字段 | 说明 |
|------|------|
| `engines.openlearn` | **宿主版本**范围（非 SDK 版本）。零主版本号会锁死在小版本区间（`^0.2.9` ≡ `>=0.2.9 <0.3.0`），推荐 `">=0.2.5"` |
| `requires` | 强依赖。格式 `@scope/domain:IServiceName@SemVerRange`，如 `"@openlearn/core:ICommandBusService@^1.0.0"`。不满足 → 抛 `SemverMismatchError` 并终止激活 |
| `optional` | 可选依赖，格式同上。宿主不阻止激活，但会把对应 `ctx.services[x]` 置为 `null`（**必须判空**） |
| `pluginDependencies` | 依赖的其他插件 ID；被依赖插件必须先处于 ACTIVE，否则拒绝激活 |
| `provides` | 本插件注册到 DI 容器的服务 Token 字符串数组，其他插件可 `ctx.resolve()` 消费 |

> **没有** `sdkVersion` 之类的 manifest 字段。SDK 版本是 npm 包的事，随平台 release 同步，不要写死。

---

## 3. 权限

`capabilitiesProposed: string[]` —— 字段名未变，但取值必须是平台真实存在的能力字符串，
完整清单与「不存在的权限」见 [`capability-matrix-0.7.md`](./capability-matrix-0.7.md)。

---

## 4. 声明式贡献点 `contributes`

| 槽位 | 字段 |
|------|------|
| `teacher.tab` | `id` `label` `icon` `position` |
| `classroom.tool` | `id` `name` `commandType` `payload` |
| `teacher.dashboard.widget` | `id` `label` `icon` `position` |
| `student.view` | `id` `label` `icon` `route` |
| `student.lesson.tool` | `id` `label` `icon` |
| `anchor:{区域}:{锚点id}` | `id` `label` `icon` `placement`(`before`/`after`，默认 `after`) |
| `help.plugin_docs` | `id` `title` `description` `markdownUrl` |
| `command_palette.item` | 数据型，`slotProps` 里带 `commandType` / `payload` |
| `locales`（v0.7.0 Issue #148） | 多语言字典：内联 `Record<lang, Record<key,string>>` 或文件路径 `Record<lang,string>`；槽位标签写 `"%tab.title%"` 由宿主按当前语言解析，回退链 `当前语言 → zh → defaultValue` |

> `contributes` 只存进 `ContributionRegistry` 供管理端枚举/预览；
> **远程插件的可见 UI 由宿主按这些声明渲染**（见 `frontend-bridge-0.7.md`）。

---

## 5. 课堂工具 `classroomTools`（旧字段，仍可用）

```ts
interface ClassroomToolConfig {
  id: string;
  name: string;
  icon?: string;          // lucide-react 图标名，如 "BarChart3"
  description?: string;
  commandType: string;    // 必须有同名 action 描述符 + registerHandler
  payload?: Record<string, unknown>;
}
```

- `payload` 里写 `'$lessonId'` / `'$classId'`，宿主在点击瞬间替换成当前课堂上下文 —— **这是工具按钮拿到 lessonId/classId 的唯一通道**。
- `teacher.dashboard.widget` 的 `id` 必须与 `manifest.classroomTools[].payload.data.teacherWidgetId` 一致（`payload.data` 是 JSON **字符串**）。
- **没有** `slot` 字段，也**没有** `order` 字段。

---

## 6. 配置 `configuration`

```json
"configuration": {
  "properties": {
    "weight": {
      "type": "number", "default": 10,
      "scope": ["platform", "class"],
      "description": "本班的评分权重"
    }
  }
}
```

- `type` ∈ `string` / `number` / `boolean` / `integer`，可配 `default` `description` `enum` `minimum` `maximum`。
- **v0.7.0（Issue #151）分层覆盖**：解析顺序 `班级 > 学校 > 平台 > manifest 默认值`；
  某个属性允许覆盖到哪一层由它的 `scope` 数组决定（缺省 `["platform"]`）。
- 运行期：`ctx.config.get(key, { classId })` / `ctx.config.getAll({ classId })` / `ctx.config.set(key, val, { scopeType, scopeId })`。

---

## 7. REST 路由 `api.routes`

```json
"api": {
  "routes": [
    { "method": "GET", "path": "/public-status", "auth": false },
    { "method": "POST", "path": "/submissions/:id/grade", "auth": true,
      "roles": ["teacher", "administrator"],
      "rateLimit": { "max": 60, "windowMs": 60000 } }
  ]
}
```

- `method` ∈ `GET` / `POST` / `PUT` / `DELETE` / `PATCH`。**不支持 `ALL`** —— 需要多动词匹配就分别声明多条，或用 `ctx.http.stream(method, path, handler)`。
- `path` 支持 `:id` 与 `*`；`auth` 默认 `true`；`roles` 默认 `[]`；`rateLimit.max` 默认 120，`windowMs` 默认 60000。
- ⚠️ **v0.7.0 破坏性变更**：`auth: false` 只表示「**申请**公开」，匿名放行还需管理员显式批准（安装/更新时勾选，或在插件中心批准）。未批准一律 401。
- `api.baseRoute` —— **历史遗留字段，全仓无代码按它挂载路由**，新插件请忽略（宿主会对声明它的 manifest 告警）。

---

## 8. 其他字段

| 字段 | 说明 |
|------|------|
| `deploy` | `staticRoute`（挂到 Express 主服务的 URL 前缀）、`staticDir`（插件目录下的静态文件相对路径） |
| `updateSource` | `{ "type": "github-release" \| "gitee-release", "repo": "owner/repo" }`。经 manifest passthrough，**不在 Zod 强校验范围**。原地更新（manifest.id 相同 → 保留 UUID / 配置 / 业务数据，仅换代码），降级需 `allowDowngrade` |
| `network.outbound` | **v0.7.2 新增**：出站域名申请清单。**只是申请**，写入 `plugin_network_grants` 需管理员批准（安装/更新时勾选，或插件中心逐条批准）。未批准即零白名单（fail-closed）；回环/私有/保留地址与通配符永远不可批准 |
| `execution_mode` | **不是 manifest 字段**。它是 `plugins` 表的列（`inline` / `worker` / `process`），由安装请求头 `x-execution-mode` 或 SQL 设置；v0.7.0 起第三方插件被策略层强制改写为 `process` |

---

## 9. 兼容性预检

```bash
npx openlearn-next doctor --compat-report
npx openlearn-next compat-report --target-version 0.8.0
```

检查 Engines 约束、弃用 UI 插槽、DI 服务 Token、Commands/Events，输出 `compatible` / `has_warnings` / `incompatible`，
不兼容时退出码 1。宿主对扩展点有**弃用策略**（`since` / `deprecated` / `removedIn` / `replacement`，至少保留一个次版本缓冲）。

---

## 10. 签名（社区来源插件）

```bash
npx @openlearn/plugin-sdk build --key publisher-private.pem --publisher "Alice Dev"
npx @openlearn/plugin-sdk sign --key publisher-private.pem --publisher "Alice Dev" my-plugin.zip
```

产出 `integrity`（SHA-256）+ Ed25519 `signature`，注入 ZIP 根目录的 `signature.json`，
载荷格式 `openlearn-plugin-attestation-v2\n<id>\n<version>\n<integrity>`，绑定版本防重放/防冒名。
来源为 `community` / `remote` 时，**强制**要求 integrity + 签名，否则拒绝安装（`COMMUNITY_*` 错误码）。

---

## 11. API → 最低宿主版本速查（写 `engines.openlearn` 的依据）

> **官方规则**：`engines.openlearn` 填「**你实际用到的最新 API 的最低版本**」，
> **不要一律抄 `>=0.2.5`**。安装时 `semver.satisfies(OPENLEARN_VERSION, engines.openlearn)` 为假会直接拒装；
> 写低了**不会报错**，但插件会在旧版本上装着、用到新 API 时才崩。

| 用到的能力 | 最低宿主版本 |
|------------|-------------|
| `ctx.log` / `ctx.config` / `ctx.provide()` / `ctx.require()` / 前端 `ctx.invokeCommand()` | 0.2.x |
| `teacher.panel` / `student.fullscreen` / `global.setting` 槽位 | 0.2.x |
| `anchor:*` 锚点槽位 | 0.2.6 |
| Worker 模式下 `ctx.resolve(IDatabaseToken)` 的 `exec()` 转发 | 0.3.9 |
| `ctx.http` RESTful API（`manifest.api.routes`） | 0.3.11 |
| `ctx.reportProgress()`（Worker 激活期续期） | 0.3.16 |
| **声明式 `contributes` 槽位 / 前端沙箱桥接行为 / `process` 强制执行模式 / `contributes.locales` / `configuration.properties[].scope`** | **0.7.0** |
| 能力按「**已授予**集合」判定（Issue #224） | 0.7.2 |
| `manifest.network.outbound` 出站域名申请 | 0.7.2 |

**本 skill 三套模板的取值与依据**：

| 模板 | `engines.openlearn` | 依据 |
|------|--------------------|------|
| `server-only` | `>=0.2.5` | 只用 actionRegistry / commandBus / eventBus / ctx.db（均 0.2.x 起） |
| `full-stack` | `>=0.7.0` | 额外用到 `classroomTools` 声明式贡献 + 前端沙箱桥接（均 0.7.0 起） |
| `frontend-only` | `>=0.7.0` | 前端沙箱桥接本身即 0.7.0 起 |

> 若你降级到更低版本，必须自己确认没用上上表里更高版本的 API。

---

## 12. 声明式 SQL 迁移：机制与陷阱

**机制**（v0.7.0，Issue #142）：插件包根目录放 `migrations/NNN_name.sql`（按版本自然序升序），
宿主在激活前自动执行尚未应用的增量迁移。

- 执行记录表：`plugin_declared_migrations`（含 checksum）
- 支持 `-- UP` / `-- DOWN` 分段解析
- 占位符 `{{prefix}}` / `{{table_prefix}}` 自动展开为插件私有表前缀
- 每条迁移在事务内原子执行，失败自动回滚
- **降级保护**：数据库中的最高迁移版本 **高于** 包内声明版本时，**拒绝激活**

### ⚠️ 陷阱：官方 CLI 不打包 `migrations/`，ZIP 分发下迁移会**静默失效**

| 环节 | 事实 |
|------|------|
| 打包 | 官方 CLI 的 `build` 只把 `index.js` / `manifest.json` /（可选）`frontend.js` 放进 ZIP —— **不含 `migrations/`** |
| 安装 | 宿主解包 ZIP 时只落盘这三个文件 + `storage/` 前缀的静态资源 —— **没有 `migrations/`** |
| 激活 | 迁移器读 `<pluginDir>/migrations`，**目录不存在就静默跳过**（`fs.existsSync` 为 false） |

**结果**：按官方文档写 `migrations/001_init.sql`、用官方 CLI 打包 → `.sql` 根本不在 ZIP 里 →
装上后**一条迁移都不会执行，而且没有任何报错**。

**因此**：

- **ZIP 分发场景**请用 `ctx.db.ensureTable()` + `ctx.db.migrate(targetVersion, upgradeFn)`（官方 CLI 模板的做法）；
- 若确实要用声明式迁移，需自行把 `migrations/` 塞进 ZIP（CLI 暂未支持），或走源码安装。

---

## 13. 跨插件服务共享（`provides` + `contracts`）

插件 A 提供服务、插件 B 消费，需要**三步配套**，缺一即不生效：

**① 提供方：定义契约**（`src/contracts/index.ts`）

```ts
import { Token } from '@openlearn/plugin-sdk';

export interface IMyPluginService {
  doSomething(input: string): Promise<string>;
}

export const MyPluginServiceToken = new Token<IMyPluginService>(
  '@scope/plugin-name:IMyPluginService',   // Token 名格式：@scope/domain:IServiceName
  '1.0.0',
);
```

> `Token` 构造时会校验名称格式（含空格、中文或特殊字符会抛 `TokenError`）。

**② 提供方：manifest 声明 `provides`**

```json
"provides": ["@scope/plugin-name:IMyPluginService"]
```

> `ctx.provide(token, impl)` 会校验 `token.name` **必须**在 `manifest.provides` 中声明，否则直接抛错并提示正确写法。

**③ 消费方：manifest 声明 `requires`**

```json
"requires": ["@scope/plugin-name:IMyPluginService@^1.0.0"]
```

> 消费方激活时，宿主校验该 token 能在提供方的 `provides` 中找到；**提供方必须已处于 ACTIVE**，
> 否则消费方激活被拒绝（跨插件依赖未满足）。

**宿主 DI 按 Token 名字字符串解析**（`ServiceRegistry` 内部是 `Map<tokenName, instance>`），
所以消费方**不必依赖提供方的 npm 包**——只要用完全相同的 Token 名自己声明即可：

```ts
// 消费方插件内（与提供方名字一致即可）
const Token = new Token<{ doSomething(input: string): Promise<string> }>(
  '@scope/provider-name:IMyPluginService',
  '1.0.0',
);
const svc = await ctx.resolve(Token);   // 解析到提供方注册的实例
```

> ⚠️ **官方 CLI 不打包 `contracts/` 目录**（只打包 index.js / manifest.json / frontend.js），
> 因此 `src/contracts/` 的价值在于**源码分发**时的类型安全；
> ZIP 分发场景靠上面的「同名 Token」即可跨插件解析。

---

## 来源

- 官方文档：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-manifest-spec.html
- Schema 源码：`packages/core/esm-loader/manifest-schema.ts`
