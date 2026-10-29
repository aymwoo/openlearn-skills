# 插件测试护栏（test-harness）

把「装得上、点开就崩」「AI 能选中但执行没反应」「开发模式好使、process 模式炸」这类问题
提前到本地 `npm test` 阶段。整套护栏不依赖真实平台，秒级跑完。

严格来说不是「测试覆盖率」问题，而是**契约覆盖率**问题：平台有大量 default-deny / 白名单 / 沙箱边界，
单测能过、上传也能装，但运行期被拦。这里把那些契约显式断言出来。

---

## 1. 铺开（复制到插件项目根目录）

```bash
# 在插件项目根目录执行
cp -r <skill>/assets/test-harness ./test-harness

# test-kit 以 TS 源码发布，且当前 sdk 声明缺两个运行期依赖，必须一起装
npm i -D vitest @openlearn/plugin-test-kit better-sqlite3 uuid zod

# 有 storage/*.html（sandbox-view）时再加：view-smoke 用它加载页面；未安装则整组跳过
npm i -D jsdom
```

`package.json` 建议补两条脚本：

```json
{
  "scripts": {
    "test:contract": "node test-harness/static-check.mjs .",
    "test": "vitest run --config test-harness/vitest.config.ts"
  }
}
```

跑：

```bash
npm run test:contract   # L0：静态契约检查（<1s，零依赖）
npm test                # L1+L2：契约测试 + 冒烟测试
```

> 已有 `vitest.config.ts` 的项目：把 `test-harness/vitest.config.ts` 里的
> `test.include` 与 `server.deps.inline` 两段合并进根配置即可，不必 `--config`。

---

## 2. 各文件各自抓什么

| 文件 | 层 | 抓的问题 | 典型报错 |
|------|----|---------|---------|
| `static-check.mjs` | L0 静态 | manifest 必填项 / 权限串捏造 / **隔离模式空能力门禁** / 三件套缺失 / **UI 通道（executionMode·槽位真伪·白名单·白板挂件闭环·`view` 页面）** / **路由配对 / SQL 守卫 / view 运行时** / **中文字号 ≥ 13px** / 裸导入 / 前端越界 / process 禁用 API / DB 契约 / 密钥泄漏 | `UI_MODE_MISMATCH` `SLOT_UNKNOWN` `CAP_EMPTY_ISOLATED` `WHITEBOARD_WIDGET_NEEDS_INLINE` `VIEW_BRIDGE_MISSING` `ROUTE_UNREGISTERED` `SQL_CORE_TABLE` `FONT_TOO_SMALL` |
| `slot-registry.json` | 平台真源 | v0.7.7 的真实扩展槽位全集 + 5 个 `view` 槽位（与平台 `docs/agent/contracts/slots.json` 同源） | `SLOT_UNKNOWN` |
| `contract.test.ts` | L1 契约 | manifest 声明的 commandType 是否真有 handler + ActionDescriptor；handler 是否为 `{execute}` 对象；`capabilityRequired` 是否真实；`inputSchema` 类型名大写；**`capabilitiesProposed` 为空时 activate 是否调了非 get RPC（Proxy 录制，复现 ServiceHost Barrier 2）** | `COMMAND_NOT_REGISTERED` / `handler.execute is not a function` / `DataCloneError` / `only 'get' methods allowed` |
| `view-smoke.test.ts` | L1 视图 | `storage/**/*.html` 能否在 jsdom 里加载并拿到 `OpenLearnPluginBridge`；`onInit` 是否注册、init 后是否真的发出 `invokeCommand` / `api.*` 调用；是否误用 `alert/confirm/fetch`；是否真的回传 `ui.resize` | `页面使用了沙箱里不可用的 API` / `init 后没有发出任何命令` / `没有真正调用 bridge.ui.resize` |
| `smoke.test.ts` | L2 冒烟 | 重复激活的状态泄漏；命令执行期 `TypeError`；REST 路由 5xx；事件 payload 形状；停用未退订；**契约驱动：白板挂件必须真的派发 `whiteboard.draw`** | `Cannot read properties of undefined` / 订阅翻倍 / `没有派发 whiteboard.draw` |

L0 是**启发式**（正则 + 注释遮蔽），用于秒级反馈；L1/L2 才是语义保证。两者一起跑，不要只留一个。

### 设计契约 `plugin.contract.json`

放在插件根目录，由需求阶段确定（模板：`references/ui-channel-decision.md` §6）。L0/L2 用它判断：

```jsonc
{
  "executionMode": "process",           // process | inline
  "uiChannel": "sandbox-view",          // declarative | polling | sandbox-view | inline-react
  "studentVisible": true,
  "whiteboardWidget": false,
  "slots": ["teacher.tab", "student.view"],
  "viewFiles": ["storage/teacher.html", "storage/student.html"]   // sandbox-view 时必填
}
```

| 没写契约会怎样 | 写了契约能拦住什么 |
|---|---|
| L0 只能给 `CONTRACT_MISSING` 警告，无法判断「process 里写 React」「studentVisible 却只有 teacher.tab」 | `UI_MODE_MISMATCH` / `CONTRACT_MODE_CONFLICT` / `STUDENT_ENTRY_MISSING` / `WHITEBOARD_*` / `VIEW_*` |

> 老项目可以先不写契约：L0 仍会跑基础检查，只是 UI 通道类规则退化为 warn。

---

## 3. 必须知道的 6 个环境坑

| 坑 | 现象 | 解法 |
|----|------|------|
| `@openlearn/plugin-sdk` 3.7.4 的 `dist/index.js` 引用了未声明的 `uuid` | `Cannot find package 'uuid' ...` | `npm i -D uuid zod`（`zod` 是 peerDep，运行期也需要） |
| `plugin-test-kit` 以 **TS 源码**发布（`main: index.ts`） | 部分 vitest 版本把 node_modules 外置 → 无法 import TS | 已在 `vitest.config.ts` 配 `server.deps.inline`；vitest 5 不配也能跑 |
| `better-sqlite3` 是原生模块（peerDep） | 未安装时 `createMockContext()` 直接抛 | `npm i -D better-sqlite3`；CI 用预编译二进制，通常几秒装完 |
| Mock 的命令总线**不补插件前缀** | 单测里 `poll.create`，生产日志是 `ext-poll.poll.create` | 断言短名；与平台联调时用 `${manifest.id}.${短名}` |
| Mock 的能力校验 / default-deny **不生效** | 权限写错也能过单测 | 这是 `contract.test.ts` 存在的理由：直接对 `capabilitiesProposed` 与 `capabilityRequired` 做集合断言 |
| Mock 的 EventBus 只支持 `'*'` 精确通配，**不匹配 `prefix.*` 模式** | 插件订阅 `demo.*` 收不到 mock 里 publish 的 `demo.greeted` | 断言「已注册订阅者」而非投递次数；投递行为交给 L3 真实宿主验证 |
| jsdom 不执行 `type="module"` 脚本、也没有真实的 `ResizeObserver` / `scrollTo` | `view-smoke` 里模块页被跳过；RO 由测试桩触发一次 | 页面用经典 `<script>`；高度自适应用 `ResizeObserver` 或显式调 `bridge.ui.resize` |

完整差异表见平台文档 `docs/sdk/plugin-test-kit.md` §2，以及 `references/testing-strategy.md` 第 6 节。

---

## 4. 红线

1. **测试通过 ≠ 生产可用**：Mock 放宽了 `provide` / `ensureTable` / 能力校验，第 3 节的差异必须靠 L3 冒烟补齐。
2. **不要把测试改成迎合实现**：断言失败先判断是实现错还是断言错，别直接放宽期望。
3. **不要在测试里连真实数据库 / 真实网络**：需要外部依赖时用 `customTokens` 注入桩。
4. **不要提交带真实 API Key / 学生数据的 fixture**：L0 的 `SECRET_LEAK` 会拦，但别依赖它兜底。
5. **`storage/**` 记得打包**：官方 CLI 只打三件套，`view` 页面必须自写 `pack.mjs` 补进 ZIP
   （`sandbox-view` 模板已带），否则装上去就是空白面板。

---

## 5. 建议的落地顺序（新插件从第一天开始）

1. 生成模板后立刻 `cp -r test-harness` 并 `npm run test:contract` —— 先让 L0 绿。
2. 写 manifest 时同步写 `contract.test.ts` 的期望（先红后绿），特别是每个 `commandType`。
3. 每加一个命令：L0 + L1 跑一次；命令里出现 `payload.x.y` 解构时，补 L2 的最小 payload 用例。
4. 提交前：L0 0 error、L1/L2 全绿、`npm run build` 成功，三条齐了再上传。
5. 上传后按 L3 清单做一次真实宿主冒烟（见 `references/testing-strategy.md` §7）。
