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

## 来源

- 官方文档：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin/plugin-manifest-spec.html
- Schema 源码：`packages/core/esm-loader/manifest-schema.ts`
