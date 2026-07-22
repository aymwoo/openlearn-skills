---
name: openlearn-next-plugin-dev
description: 为 OpenLearnV2 教学平台开发插件。通过读取 https://openlearn-next-v2.readthedocs.io/zh-cn/latest/ 在线文档获取最新插件开发文档，与开发者讨论需求后指导开发相应插件。支持三类插件模板（server-only / full-stack / frontend-only）。当用户提到开发 OpenLearn 插件、openlearn-next 插件、教学平台插件、或课堂工具时使用此 skill。
---

# OpenLearnV2 插件开发

## 核心原则

**在线文档是权威来源，本地缓存加速读取。** skill 自带三份文档的本地快照（`references/`），每次使用前通过索引页探活。缓存未过期则直接用本地，发现远端更新才重新拉取——将月消耗从 ~100K token 降至 ~22K token。

## 工作流程

### 第一步：探活 + 缓存命中或增量更新

#### 1a. 探活（每次必做，~200 token）

webfetch 索引页检查「最后更新」日期：

```
https://openlearn-next-v2.readthedocs.io/zh-cn/latest/
```

提取文档底部的「最后更新：YYYY-MM-DD」。

#### 1b. 比对缓存

读取 `references/.cache-meta.json` 中的 `lastUpdated` 字段：

- **日期相同** → 缓存命中，直接使用 `references/` 目录下的本地快照（**0 额外 token**）
- **日期更新** → 远端有更新，告知用户"文档已更新（旧: X, 新: Y）"，然后重新拉取全量文档，更新 references 文件和 .cache-meta.json
- **首次使用（无缓存）** → 直接使用 references/ 本地快照

#### 1c. 缓存未命中时按需拉取

如果缓存不存在或已过期，按以下优先级拉取：

| 要做什么 | 拉取哪份 | 估算 token | 本地文件 |
|----------|---------|-----------|---------|
| 查 API 签名、Action/Handler/Event 怎么写 | **插件开发完全指南** | ~12,000 | `references/plugin-development-tutorial.md` |
| 理解架构原理、安全模型 | **架构总览** | ~8,000 | `references/architecture.md` |
| 初始化项目、构建打包、CLI 命令 | **脚手架指南** | ~4,000 | `references/scaffold.md` |

拉取后更新 references/ 和 .cache-meta.json。

#### 1d. 本地缓存可覆盖大部分场景

references/ 中的本地快照已包含：
- 完整 API 接口文档（PluginContext、Manifest、所有 Service 接口）
- 命令-事件-Action 三件套模式与完整代码示例
- 前端插件开发指南（扩展槽位、HostSharedDeps、JSX 配置）
- 安全权限模型（四层防护、审批流程、Token Enforcer 白名单）
- CLI 脚手架命令参考与常见问题

典型的"开发新插件"场景可直接使用缓存，只有遇到以下情况才需要在线拉取：文档版本不一致、用户提到新 SDK/CLI 版本、缓存中找不到需要的 API。

**Token 消耗对比**：

| 场景 | 纯在线方案 | 缓存+探活方案 |
|------|-----------|-------------|
| 日常开发（命中缓存） | ~10,000 | **~200** |
| 文档更新后首次 | ~10,000 | ~12,200 |
| 月均（10 次使用，1 次更新） | ~100,000 | **~14,000**

### 第二步：需求讨论

获取最新文档后，与开发者进行结构化讨论，逐项确认：

1. **插件用途**：面向教师还是学生？解决什么问题？
2. **核心功能**：列举 1-5 个核心功能点
3. **插件类型**（三选一）：
   - `server-only`：纯后端（AI 工具 + 命令 + 事件，无 UI）
   - `full-stack`：全栈（后端逻辑 + React 前端）
   - `frontend-only`：纯前端（仅 UI 面板或课堂工具）
4. **UI 扩展点**（full-stack / frontend-only 时确认）：
   - `teacher.tab` — 教师侧边栏标签页（管理页）
   - `teacher.dashboard.widget` — 白板可拖拽卡片（课堂交互，需匹配 teacherWidgetId）
   - `teacher.panel` — 教师独立全宽面板（v2.5+）
   - `student.view` — 学生端全屏视图
   - `student.fullscreen` — 学生全屏视图/考试模式（v2.5+）
   - `classroom.tool` — 课堂工具架按钮
   - `global.setting` — 全局设置页扩展（v2.5+）
5. **权限需求**：检查在线文档中可用的权限字符串列表
6. **AI 能力**：是否需要 AI Agent 调用？（需注册 Action）
7. **数据库需求**：需要哪些表？是否需要版本迁移？
8. **目标版本**：声明在 `manifest.engines.openlearn` 中的版本

### 第三步：生成代码

方案确认后，根据插件类型选择对应模板生成代码。

#### 模板对照

| 模板 | 位置 | 生成文件 |
|------|------|---------|
| server-only | `assets/server-only/` | `package.json`, `tsconfig.json`, `src/index.ts` |
| full-stack | `assets/full-stack/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx` |
| frontend-only | `assets/frontend-only/` | `package.json`, `tsconfig.json`, `src/index.ts`, `src/frontend.tsx` |

使用 Create-React-App: 读取对应模板文件，将 `{{placeholder}}` 替换为用户确认的参数：

- `{{pluginId}}` → 如 `@teacher-li/class-polls`
- `{{pluginName}}` → 显示名称
- `{{description}}` → 功能描述
- `{{author}}` → 作者名
- `{{commandPrefix}}` → 命令前缀（如 `classpolls`）
- `{{toolId}}` / `{{toolName}}` → classroomTools 配置
- `{{tabId}}` → 前端 tab ID

模板提供了启动代码骨架，需要在 TODO 标记处填充根据需求讨论确认的实际业务逻辑。

#### 关键编码规范

编写代码时，结合在线文档确认以下规范：

1. **manifest.classroomTools 必须有对应的 Handler**：即使只为了触发前端面板，也要注册空 handler
2. **数据库表命名**：使用 `ctx.db.ensureTable()` + `ctx.db.table()`，不要手动拼接
3. **事件命名**：过去式，格式 `{commandPrefix}.action_done`
4. **Action description**：用中文，这是 AI Agent 理解工具用途的关键
5. **前端组件**：用 `function` 声明不用箭头函数；`jsx: "react"` 经典模式；`default export` 是 `{ activate, deactivate }`
6. **避免 Node.js 内置模块**：用 `crypto.randomUUID()` 替代 `import { randomUUID } from 'crypto'`；用 VFS API 替代 `fs`

### 第四步：构建与检查

生成代码后，给出构建和验证指令：

```bash
cd <plugin-directory>
npm install
npx @openlearn/plugin-sdk build
```

检查清单：
- [ ] `dist/index.js` 无非法裸导入：`grep -E '^import .+ from "[^@\./]' dist/index.js` 应无输出
- [ ] 前端 JSX 为经典模式（构建产物中无 `react/jsx-runtime` 引用）
- [ ] `manifest.json` 与代码中 manifest 一致
- [ ] 所有 `classroomTools[].commandType` 都有对应的 handler

### 第五步：安装测试

提醒开发者在 OpenLearn 管理后台上传 `dist/<plugin-name>.zip`：

1. 系统设置 → 插件中心 → 上传插件
2. 激活插件
3. 如声明了 `classroomTools`，进入课堂白板查看工具栏
4. 服务端日志带 `[Plugin:<id>]` 前缀

## 核心概念速查

以下是最常被问到的基础概念，在线文档提供完整细节。

### 插件最小结构

```typescript
export default {
  manifest: {
    id: '@scope/name',        // 全局唯一
    name: '名称', version: '0.1.0',
    engines: { openlearn: '>=0.1.9' },
    requires: ['@openlearn/core:ICommandBusService@^1.0.0'],
    capabilitiesProposed: ['lesson:read'],
  },
  async activate(ctx) { /* 注册 Action、Handler、Event */ },
  async deactivate() { /* 清理 */ },
};
```

### 三件套模式

```
Action   → actionRegistry.register()     AI 可调用
  ↓ (关联 commandType)
Command  → commandBus.registerHandler()  业务逻辑
  ↓ (执行后发布)
Event    → eventBus.publish()           审计日志 + 实时推送
```

### 七个内核服务

| 服务 | `ctx.services.xxx` | 用途 |
|------|-------------------|------|
| CommandBus | `.commandBus` | 注册/执行命令 |
| EventBus | `.eventBus` | 发布/订阅事件 |
| ActionRegistry | `.actionRegistry` | 注册 AI 工具 |
| Capability | `.capability` | 权限管理 |
| Process | `.processManager` | 后台进程 |
| Storage | `.storage` | K-V 存储 |
| AI | `.ai` | 文本生成 |

其他通过 `ctx.resolve(Token)` 获取：`IDatabaseToken`、`IPluginHostToken` 等。

### 权限格式

`{resource}:{action}`，如 `lesson:read`、`lesson:write`、`whiteboard:*`

## 资源文件说明

| 文件 | 说明 |
|------|------|
| `references/.cache-meta.json` | 缓存元信息（lastUpdated 日期），用于探活比对 |
| `references/plugin-development-tutorial.md` | 插件开发完全指南本地快照（API、Action/Handler/Event、前端、安全） |
| `references/architecture.md` | 架构总览本地快照（CommandBus、生命周期、Worker Thread、DI、安全模型） |
| `references/scaffold.md` | 脚手架指南本地快照（CLI 命令、模板、常见问题） |
| `assets/server-only/` | server-only 插件模板 |
| `assets/full-stack/` | full-stack 插件模板 |
| `assets/frontend-only/` | frontend-only 插件模板 |

### 在线文档地址

| 文档 | URL |
|------|-----|
| 索引页（探活用） | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/` |
| 插件开发完全指南 | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/plugin-development-tutorial.html` |
| 架构总览 | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/architecture_review_report.html` |
| 脚手架指南 | `https://openlearn-next-v2.readthedocs.io/zh-cn/latest/scaffold.html` |
