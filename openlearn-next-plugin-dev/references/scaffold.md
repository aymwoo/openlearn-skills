# OpenLearn Plugin 脚手架开发指南

[缓存自 https://openlearn-next-v2.readthedocs.io/zh-cn/latest/scaffold.html]

## 快速开始

```bash
npx @openlearn/plugin-sdk init --name hello-world
cd hello-world && npm install
npx @openlearn/plugin-sdk build
# 产物：hello-world.zip
```

交互式创建：`npx @openlearn/plugin-sdk init`（CLI 引导填写名称、描述、作者、模板）

## 三种模板

### server-only（纯后端）
- 注册 AI Action + 命令处理器 + 事件，无前端
- 生成：`src/index.ts`, `package.json`, `tsconfig.json`

### full-stack（全栈）
- 服务端逻辑 + React 前端组件
- 生成：`src/index.ts`, `src/frontend.tsx`, `package.json`, `tsconfig.json`
- 前端外部化 react/react-dom/recharts/lucide-react

### frontend-only（纯前端）
- 仅 UI 面板或课堂工具，无服务端命令
- 生成：`src/index.ts`（最小化 manifest）, `src/frontend.tsx`

## 项目结构

```
my-plugin/
├── package.json          # 依赖 @openlearn/plugin-sdk: ^3.2.0
├── tsconfig.json         # jsx: "react", moduleResolution: "bundler"
├── src/index.ts          # export default { manifest, activate, deactivate? }
├── src/frontend.tsx      # (full-stack/frontend-only)
└── dist/                 # 构建产物
    ├── index.js / frontend.js / my-plugin.zip
```

## 入口文件结构

```typescript
export default {
  manifest: {
    id: '@yourname/my-plugin',
    name: '我的插件',
    version: '0.1.0',
    requires: ['@openlearn/core:ICommandBusService@^1.0.0'],
    capabilitiesProposed: ['lesson:read'],
    classroomTools: [{ id: '...', name: '...', icon: '...', commandType: '...' }],
    engines: { openlearn: '>=2.5.0' },
  },
  async activate(ctx) { /* 注册 Action、Handler */ },
  async deactivate() { /* 清理 */ },
};
```

## 数据库使用

```typescript
await ctx.db.ensureTable('polls', 'id TEXT PRIMARY KEY, ...');
const tableName = ctx.db.table('polls');  // → plugin_@scope_name_polls
const db = await ctx.resolve(IDatabaseToken);
db.prepare(`INSERT INTO ${tableName} ...`).run(...);
```

## 构建打包

```bash
npx @openlearn/plugin-sdk build          # 构建 + ZIP
npx @openlearn/plugin-sdk build --watch  # Watch 模式
```

构建流程：验证 → esbuild 打包 → manifest 提取 → ZIP

## CLI 命令

### init
```bash
npx @openlearn/plugin-sdk init [--name] [--description] [--author] [--template]
```
模板：server-only | full-stack | frontend-only

### build
```bash
npx @openlearn/plugin-sdk build [--watch|-w]
```
需在项目根目录运行。

## 安装调试

1. 管理后台 → 系统设置 → 插件中心 → 上传插件 (my-plugin.zip)
2. 激活插件
3. classroomTools 声明后进入白板可见工具栏

## 测试

```bash
npm install --save-dev @openlearn/plugin-test-kit vitest
```

```typescript
import { createMockContext } from '@openlearn/plugin-test-kit';
const ctx = createMockContext();
await plugin.activate(ctx);
```

## 常见问题

### crypto 导入错误
```typescript
// ❌ import { randomUUID } from 'crypto';
// ✅ const id = crypto.randomUUID();
```

### 上传前自检
```bash
grep -E '^import .+ from "[^@\./]' dist/index.js  # 应无输出
```

### React hooks 不工作
确认 package.json 有 `"peerDependencies": { "react": ">=17" }`

### AI 工具发现
actionRegistry.register() 的 description 用中文写清楚

### 插件间通信
通过 EventBus：`{pluginId}.{action}_done`（过去式）

### 文件系统
使用 VFS API，manifest 中声明 vfs:read/vfs:write

### 数据库表命名
使用 ctx.db.ensureTable() + ctx.db.table()，不手动拼接
