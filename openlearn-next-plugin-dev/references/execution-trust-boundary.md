# 执行模式与信任边界（v0.7.7 真源，SDK 3.7.4）

> 整理自官方文档 `reference/plugin-trust-boundary.html`（`doc-version: sdk=3.7.4`）与源码
> `packages/core/plugin-host/execution-policy.ts`、`packages/core/worker-runtime/plugin-net-preload.cjs`。
> 平台仓库本地路径：`~/Develop/openlearnv2/docs/reference/plugin-trust-boundary.md`。
>
> **v0.7.0 起，第三方插件不再运行在宿主的 inline / worker 里。**

---

## 1. 执行模式对照

| 模式 | 适用对象 | 崩溃隔离 | 文件系统 | 子进程 / Worker | eval / new Function | 网络 |
|------|----------|----------|----------|-----------------|-------------------|------|
| `inline` | 宿主内建插件、数据库迁移等必要扩展 | ❌ 与宿主同上下文 | 宿主用户全部权限 | ✅ | ✅ | 不可拦截 |
| `worker_threads` | 宿主内稳定插件 | ✅ 线程级 | 宿主用户全部权限 | ✅ | ✅ | ⚠️ 原生不受限 |
| `process` + `rw/ro` | **第三方 / 社区插件（默认）** | ✅ 进程级 | 仅 `pluginDir` + 宿主 `node_modules` | ❌ 禁止 | ❌ 禁止 | 🛡️ 默认拒绝 + 获批域名由宿主代发 |
| `process` + `off` | 合法需要 spawn / 原始联网 / 写外部路径 | ✅ 进程级 | 全部用户权限 | ✅ | ✅ | ✅ 完全放行（逃生舱，需人工审批 + 审计） |

> **默认执行模式**：第三方插件强制默认 `process + rw`。
> `execution-policy.ts` 会把所有非内置、且不在 `OPENLEARN_TRUSTED_INLINE_PLUGINS` 中的插件
> **强制改写（coerce）为 `process` 模式**，禁止使用 `inline` 与 `worker_threads`。
> 需要进程内运行的自研插件必须显式加白名单。

---

## 2. Node Permission Model（process 模式）

| policy | 含义 |
|--------|------|
| `rw` | 读插件目录 / 共享依赖 + 写插件目录（默认） |
| `ro` | 全部只读 |
| `off` | 关闭权限模型（逃生舱） |

构造的 flags（Node v22+ / v24+）：

```text
--permission
--disallow-code-generation-from-strings
--allow-fs-read=<pluginDir>/*
--allow-fs-write=<pluginDir>/*          # 仅 rw
--allow-fs-read=<root>/node_modules/*   # 共享依赖
```

**固定不提供**：`--allow-child-process`、`--allow-worker` —— 否则插件可拉起不受权限模型约束的孙进程 / worker，沙箱形同虚设。

---

## 3. 网络沙箱

`process` 模式下通过 `plugin-net-preload.cjs` + 宿主 IPC 代理（`ol-net-proxy`）实现闭环：

- **原始连接彻底阻断**：Socket、UDP (`dgram`)、DNS (`dns.lookup`/`resolve*`)、TLS 与 HTTP2 底层连接均抛 `ERR_ACCESS_DENIED`。
- **应用层受控代发**：`fetch` / `http(s).request` 只放行 `plugin_network_grants` 中**管理员已批准**的域名，由宿主代发；宿主侧内建防 SSRF 校验（阻断环回、私有 IP、云元数据地址、DNS 重绑定）。
- **批准方式**：安装/更新时勾选「批准出站域名」（`x-approve-network-hosts`），或事后在插件中心 → 插件设置 →「出站网络域名」逐条批准/撤销（`GET/POST/DELETE /api/plugins/:id/network-grants`，仅 administrator）。
- **fail-closed**：未批准即零白名单，插件发起的任何出站请求都会被拒。
- **永远不可批准**：环回 / 私有 / 保留地址与通配符。

> `inline` 与 `worker_threads` 不受 `plugin-net-preload.cjs` 约束，但策略层已把第三方插件全部赶到 `process` 模式。

---

## 4. 五大能力面速查

| 能力面 | inline | worker_threads | process (rw/ro) | process (off) |
|--------|--------|----------------|------------------|---------------|
| 读插件目录 | ✅ | ✅ | ✅ | ✅ |
| 写插件目录 | ✅ | ✅ | ✅ | ❌（ro） |
| 读宿主源码 / `.env` / 迁移 | ✅ | ✅ | ❌ | ✅ |
| 读写宿主数据库库文件 | ✅ | ✅ | 仅 `plugin_*` 命名空间 | ✅ |
| 拉起子进程 | ✅ | ✅ | ❌ | ✅ |
| 创建 worker | ✅ | ✅ | ❌ | ✅ |
| `eval` / `new Function` | ✅ | ✅ | ❌ | ✅ |
| 出站网络 | ✅ | ⚠️ 不受限 | 🛡️ 默认拒绝 + 获批域名代发 | ✅ |
| CPU hog / 死循环 | 全宿主影响 | 吃 CPU（有 watchdog） | 进程级（P2 待补配额） | 同左 |

---

## 5. 对插件作者的实际影响

1. **`ctx.config` / `ctx.provide()` 在非 inline 模式不可用** —— 第三方插件默认就是 process 模式，别在代码里依赖它们。
2. **不能用 `child_process` / `worker_threads`** —— 需要 spawn 的插件要走 `process + off` 逃生舱并人工审批。
3. **不能用 `eval` / `new Function` / 字符串代码生成**。
4. **不能读宿主源码、`.env`、迁移文件**。
5. **不能自己联网** —— 只能声明 `network.outbound` 申请，由管理员批准后由宿主代发。
6. **文件访问限于插件目录 + 宿主 `node_modules`（只读）**。
7. `ctx.services` 在 worker/process 模式下受 Token 白名单限制：`manifestCapabilities` 为空时除 `get` 外的 RPC 全被拒。

---

## 6. 服务 RPC 白名单

宿主 `ServiceHost` 使用 `allowedServiceTokens`：

| 平台 | Token 集合 |
|------|-----------|
| 后端进程（worker / process） | `BASE_WORKER_SERVICE_TOKENS` + 按 `manifest.requires/optional/capabilitiesProposed` 计算 |
| 浏览器 worker | 受 `SENSITIVE_FRONTEND_SERVICE_TOKENS` 与 DependencyGuide 约束 |

> `allowedServiceTokens` 为 `undefined` 时**必须等价于只读/禁止 RPC**，不能静默放行全部 token。
> Token 白名单是 RPC 边界，**不等于** Node 文件系统权限 —— 文件权限仍由 `--permission` 控制。

---

## 7. 分发来源与身份认证（Issue #143）

| 插件来源 | 完整性 | 签名 | 策略 |
|----------|--------|------|------|
| `builtin` | 宿主内置 | 免验签 | 同级信任 |
| `local` | 可选 | 可选 | 管理员直传；有签名则强验，未签名允许显式放行并记录审计 |
| `community` / `remote` | **强制** SHA-256 `integrity` | **强制** Ed25519 | 缺哈希/缺签名/未配置公钥/篡改一律拒绝（`COMMUNITY_*`） |

已安装插件在宿主升级重启时不强制二次验签。

---

## 8. 归因提醒

- 「插件起不来 / 起不来第二次」优先看：**是否被 coerce 成 process 模式**、**manifestCapabilities 是否为空**、**是否触碰了被禁的 API**。
- **切忌**把 `worker_threads` 对用户描述成「沙箱」——它只是资源崩溃隔离。

---

## 来源

- 官方文档：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-trust-boundary.html
- 权限矩阵：https://openlearn-next-v2.readthedocs.io/zh-cn/latest/reference/plugin-capability-matrix.html
