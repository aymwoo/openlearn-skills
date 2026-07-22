# OpenLearnV2 核心架构与设计

[缓存自 https://openlearn-next-v2.readthedocs.io/zh-cn/latest/architecture_review_report.html]

## 设计理念

OpenLearnV2 采用**插件驱动的命令-事件总线架构**。核心原则：
- 内核只做转发，不做业务
- 一切皆插件：课程管理、VFS、AI 规划器等均为插件
- Command → Event → Audit：数据写入通过 CommandBus，执行后 EventBus 发布，自动写入 SQLite 审计日志
- 安全纵深防御：Worker Thread 隔离 + CapabilityGuard + 高危审批 + 命名空间防欺骗

## 系统架构

三层系统架构：
- Layer 0: EventBus, CapabilityGuard, ServiceRegistry, StorageService, AIService
- Layer 1: CommandBus(EventBus), ActionRegistry
- Layer 2: ProcessManager(Kernel), PluginHost(ServiceRegistry, EsmLoader, db)
- Layer 3: WorkerManager(ServiceRegistry, CapabilityGuard, db)

## 核心子系统

| 子系统 | 职责 |
|--------|------|
| Kernel | 全局单例容器，lazy-evaluated Proxy |
| CommandBus | 命令执行管线：interceptor → Schema校验 → CapabilityGuard → 审批 → Handler |
| EventBus | 发布/订阅，支持通配符 *，审计日志 |
| ActionRegistry | AI 工具注册，Google GenAI functionDeclarations 格式 |
| CapabilityGuard | RBAC 权限控制 |
| PluginHost | 插件生命周期：安装/激活/停用/卸载/热重载 |
| ServiceRegistry | 依赖注入容器，Token 驱动，SemVer 检查 |
| ResourceTracker | 按 pluginId 管理 Disposable 资源 |
| WorkerManager | Worker Thread 隔离，RPC Proxy |

## 插件状态机

INSTALLED → ACTIVATING → ACTIVE → DEACTIVATING → INACTIVE
                                         ↓
                                       ERROR

## 激活流程

beforeActivate 中间件 → 实际激活 → afterActivate 中间件
实际激活：幂等守卫 → 状态验证 → manifest 解析 → execution_mode 分支(inline/worker) → 注册 classroomTools → 授予权限 → ACTIVE

## 停用流程（强制清理）

beforeDeactivate 中间件 → deactivate() → finally: resourceTracker.disposeAll + revokeAll → afterDeactivate
管道崩溃安全 fallback: 直接 resourceTracker.disposeAll + revokeAll

## 内核服务 Token（10 个）

| Token 常量 | 标识符 | 用途 |
|------------|--------|------|
| ICommandBusServiceToken | @openlearn/core:ICommandBusService | 命令执行 |
| IEventBusServiceToken | @openlearn/core:IEventBusService | 事件 |
| IActionRegistryServiceToken | @openlearn/core:IActionRegistryService | AI 工具 |
| ICapabilityServiceToken | @openlearn/core:ICapabilityService | 权限 |
| IProcessServiceToken | @openlearn/core:IProcessService | 进程 |
| IStorageServiceToken | @openlearn/core:IStorageService | K-V 存储 |
| IAIServiceToken | @openlearn/core:IAIService | AI 文本 |
| IDatabaseToken | @openlearn/core:IDatabase | SQL 访问 |
| IPluginHostToken | @openlearn/core:IPluginHost | 主机管理 |
| ISemesterGradeServiceToken | @openlearn/core:ISemesterGradeService | 成绩 |

## Worker Thread 三层隔离

| 层 | 机制 | 说明 |
|----|------|------|
| 物理隔离 | Worker Thread | 独立 V8 线程 |
| 通信隔离 | RPC Proxy | postMessage 序列化 |
| 权限隔离 | CapabilityGuard | 主线程侧重新检查 |

## 前端插件系统

- FrontendPluginHost：动态 import() 加载 ESM，inline/worker 双模式
- FrontendServiceRegistry 提供 5 个前端服务：FRONTEND_API_TOKEN, SOCKET_SERVICE_TOKEN, UI_SERVICE_TOKEN, STORAGE_SERVICE_TOKEN, SEMESTER_GRADE_SERVICE_TOKEN
- HostSharedDeps：window.HostSharedDeps 提供 react/react-dom/recharts/lucide-react
- JSX 必须使用经典模式 "react"，不能使用 "react-jsx"

## 扩展槽位

| Slot | 用途 | 版本 |
|------|------|------|
| teacher.tab | 教师标签页 | 1.0 |
| teacher.panel | 教师全宽面板 | 5.1 |
| teacher.dashboard.widget | 白板卡片 | 1.0 |
| student.view | 学生视图 | 1.0 |
| student.fullscreen | 学生全屏 | 5.1 |
| student.lesson.tool | 学生学习工具 | 1.0 |
| classroom.tool | 课堂工具 | 1.0 |
| global.setting | 全局设置 | 5.1 |

## 安全四层防护

1. 命名空间隔离：裸字符命令自动加 {pluginId}. 前缀 + UUID 防劫持
2. 权限声明：capabilitiesProposed，安装时声明运行时强制
3. Worker Thread 隔离：可选强化隔离
4. 审批闸门：isHighRisk Action → pending_commands 表 → 教师审批

## 权限格式

{resource}:{action}，如 lesson:read、lesson:write、whiteboard:*

管理员角色（actorId 含 :administrator 或 :admin）自动绕过高危审批和权限检查。

## 数据存储

SQLite + better-sqlite3。插件数据库通过 ctx.db API 命名空间隔离。

## 内置系统插件

| 插件 ID | 关键性 | 职责 |
|---------|--------|------|
| @openlearn/plugin-vfs | 关键 | 虚拟文件系统 |
| @openlearn/plugin-process | 关键 | 后台进程 |
| @openlearn/plugin-management | 关键 | LMS 管理 |
| @openlearn/plugin-builtin | 关键 | 课堂核心 |
| @openlearn/plugin-ai-planner | 非关键 | AI 教案 |
| @openlearn/plugin-ai-submit-injector | 非关键 | 提交注入 |
| @openlearn/plugin-assignment-eval | 非关键 | 作业评估 |
