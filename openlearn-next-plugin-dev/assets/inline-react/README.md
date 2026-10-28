# inline-react 模板：带自定义 React UI 的白板挂件

这是**唯一能拿到自定义 React UI 的第三方插件形态**。代价是插件以 inline（进程内）方式运行，
需要管理员在宿主侧放行。用之前先确认你接受这个前提。

## 1. 适用场景

- 教师端点击工具按钮 → 白板插入挂件 → 学生端看到同一块可交互卡片
- 需要自定义组件（输入框、列表、画板、计时器外观等），manifest 声明式槽位做不到

不适用：只需要列表/按钮/文本/跳转 → 用 `full-stack` 模板 + 声明式槽位（process 模式即可）。

## 2. 前置条件（缺一不可）

```bash
# 宿主 .env：放行本插件（前缀通配或精确 id 均可；`*` 等于全部信任，慎用）
OPENLEARN_TRUSTED_INLINE_PLUGINS=@openlearn-ext/*

# 改完重启宿主服务，然后重新安装插件或重新选择隔离档位
# 验证：GET /api/plugins 里该插件 executionMode 必须是 inline
```

- **id 前缀不构成信任**：`@openlearn/` 也不会自动进程内运行。
- 老 `.env` 未包含本插件时，插件会被静默改写成 `process`，前端激活时 `HostSharedDeps` 为 `undefined`，
  本模板会显式抛错提示（不会静默白屏）。
- 权限 `whiteboard:write` 需管理员在插件中心批准（v0.7.2 起按已授予集合判定）。

## 3. 目录

| 文件 | 作用 |
|------|------|
| `plugin.contract.json` | 设计契约：`executionMode: inline` / `uiChannel: inline-react` / `studentVisible: true` / `whiteboardWidget: true`，L0/L2 依此校验 |
| `src/index.ts` | 后端：`classroomTools` 按钮 → `open_board` → **派发 `whiteboard.draw(type:'plugin')`**；`add_note` / `list_notes` |
| `src/frontend.tsx` | 前端：从 `HostSharedDeps` 取 React，注册 `teacher.dashboard.widget` + `student.view` 两个组件 |

## 4. 关键写法（别改错）

```ts
// ✅ 正确：不 import，取宿主 React
const R = (globalThis as any).HostSharedDeps?.React;

// ❌ 错误：CLI 3.7.2+ 裸说明符守卫会让构建失败
// import React from 'react';

// ✅ 白板书写：data 必须是 JSON 字符串，两侧 widget id 都要给
await commandBus.execute({
  id: crypto.randomUUID(),
  type: 'whiteboard.draw',
  payload: {
    lessonId,
    type: 'plugin',
    data: JSON.stringify({ teacherWidgetId: '...-teacher', studentWidgetId: '...-student' }),
  },
  actorId: `plugin:${manifest.id}`,
  timestamp: Date.now(),
});
```

## 5. 验证

```bash
npm i && npx @openlearn/plugin-sdk build
node test-harness/static-check.mjs .          # L0：UI 通道 / 槽位 / 白板挂件 / 白名单
npx vitest run --config test-harness/vitest.config.ts
```

L3 真实宿主清单（缺一步就会「学生看不到」）：

1. `.env` 白名单 + 重启 + `executionMode === 'inline'`
2. 插件中心批准 `whiteboard:write`
3. 课堂内点工具按钮 → 白板出现卡片（教师视角）
4. 学生端同一课节 → 出现同一张卡片（学生视角）
5. 停用再激活 → 不重复插入、无 `HANDLER_ALREADY_EXISTS`

## 6. 排错

| 现象 | 先查什么 |
|------|---------|
| 激活报 `HostSharedDeps.React 不可用` | `executionMode` 是否为 inline（白名单/重启/重装） |
| 构建报 `frontend 产物里有裸模块说明符` | 是不是写了 `import React`；改成 `HostSharedDeps` |
| 白板有元素但显示「正在加载或未启用」 | widget id 与扩展点 id 是否一致；前端是否注册了对应槽位 |
| 学生端完全没有卡片 | 白板元素 data 是否只有 `teacherWidgetId`；是否声明并注册了 `student.view` |
| 命令 403 | `capabilitiesProposed` 是否含 `whiteboard:write`，管理员是否批准 |
