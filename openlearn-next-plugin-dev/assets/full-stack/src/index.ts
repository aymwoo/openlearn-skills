import type { PluginContext } from '@openlearn/plugin-sdk';
import { IDatabaseToken } from '@openlearn/plugin-sdk';

const cleanups: Array<() => void | Promise<void>> = [];

export default {
  manifest: {
    id: '{{pluginId}}', // 全局唯一标识，如 @scope/plugin-name（不得含 ':'）
    name: '{{pluginName}}',
    version: '0.1.0',
    // manifest.main 在 manifestSchema 层必填（z.string().min(1)）——缺失会导致插件装不上
    main: 'index.js',
    description: '{{description}}',
    author: '{{author}}',
    // 宿主版本范围（不是 SDK 版本）。按**实际用到的 API 的最低宿主版本**填写，
    // 不要一律抄 >=0.2.5 —— 写低了不会报错，但插件会在旧版本上装着、用到新 API 时才崩。
    // 本模板用到 classroomTools 声明式贡献 + 前端沙箱桥接（均 0.7.0 起）→ >=0.7.0
    engines: { openlearn: '>=0.7.0' },
    requires: [
      '@openlearn/core:ICommandBusService@^1.0.0',
      '@openlearn/core:IActionRegistryService@^1.0.0',
      '@openlearn/core:IEventBusService@^1.0.0',
      '@openlearn/core:IDatabase@^1.0.0',
    ],
    capabilitiesProposed: ['lesson:read', 'lesson:write'],
    // 跨插件服务共享：本插件对外提供的服务 Token（与 src/contracts/index.ts 里的定义对应）。
    // 写在这里的每个字符串，都必须与 contracts 中 `new Token(...)` 的 name 完全一致，
    // 否则 activate() 里 ctx.provide() 会抛错并提示正确写法。
    // 注意：只有真正调用了 ctx.provide(token, impl) 后，其他插件才能解析到；
    // 宿主 DI 按 Token **名字字符串**解析，消费方用同名 Token 即可（无需依赖本插件的包）。
    provides: ['{{pluginId}}:IMyPluginService'],
    // 课堂工具：宿主渲染按钮，点击后派发 commandType。
    // $lessonId / $classId 由宿主在点击瞬间替换成当前课堂上下文。
    classroomTools: [
      {
        id: '{{toolId}}',
        name: '{{toolName}}',
        icon: 'Puzzle', // lucide-react 图标名
        commandType: '{{commandPrefix}}.open_tool',
        payload: { lessonId: '$lessonId', classId: '$classId' },
      },
    ],
  },

  async activate(ctx: PluginContext) {
    const { commandBus, actionRegistry, eventBus } = ctx.services;

    // ============================================================
    // 1. 数据库：ctx.db.ensureTable 是异步的，必须 await
    // ============================================================
    // 表名由 ctx.db.table() 生成（自带 plugin_<安装行UUID>_ 前缀），
    // 绝不要手工拼接表名。
    await ctx.db.ensureTable(
      'items',
      `
      id TEXT PRIMARY KEY,
      lesson_id TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL
    `,
    );

    // ============================================================
    // 2. 注册 AI Action —— 与下面的 handler 一一对应（default-deny 规则）
    // ============================================================
    await actionRegistry.register({
      id: '{{commandPrefix}}-create',
      commandType: '{{commandPrefix}}.create',
      description: '在当前课堂创建一条 {{pluginName}} 记录',
      capabilityRequired: 'lesson:write',
      inputSchema: {
        type: 'OBJECT',
        properties: {
          lessonId: { type: 'STRING', description: '课程 ID' },
          title: { type: 'STRING', description: '记录标题' },
        },
        required: ['lessonId', 'title'],
      },
    });

    // 课堂工具的 commandType 同样需要 action 描述符，否则点击被拒
    await actionRegistry.register({
      id: '{{commandPrefix}}-open-tool',
      commandType: '{{commandPrefix}}.open_tool',
      description: '打开 {{pluginName}} 课堂工具面板',
      capabilityRequired: 'lesson:read',
      inputSchema: {
        type: 'OBJECT',
        properties: {
          lessonId: { type: 'STRING', description: '当前课程 ID' },
          classId: { type: 'STRING', description: '当前班级 ID' },
        },
        required: [],
      },
    });

    // ============================================================
    // 3. Command Handler
    // ============================================================
    await commandBus.registerHandler('{{commandPrefix}}.create', {
      async execute(command) {
        const payload = command.payload as { lessonId?: string; title?: string };

        const id = crypto.randomUUID();
        const itemsTable = ctx.db.table('items');

        // ctx.db 只有 4 个方法（ensureTable/table/dropAllTables/migrate），没有 prepare()。
        // 需要写行时取裸库：inline 下 prepare().run() 同步返回，process 沙箱下返回 Promise，
        // 因此统一加 await 即可跨模式工作。
        const rawDb = await ctx.resolve(IDatabaseToken);
        await rawDb
          .prepare(
            `INSERT INTO ${itemsTable} (id, lesson_id, content, created_at) VALUES (?, ?, ?, ?)`,
          )
          .run(id, payload?.lessonId ?? '', payload?.title ?? '', Date.now());

        await eventBus.publish({
          id: crypto.randomUUID(),
          type: '{{commandPrefix}}.created',
          source: 'plugin.{{pluginId}}',
          payload: { id, lessonId: payload?.lessonId ?? null },
          timestamp: Date.now(),
          correlationId: command.id,
        });

        return { id, message: `已创建: ${payload?.title ?? ''}`, table: itemsTable };
      },
    });

    // 课堂工具 handler：远程（process 沙箱）插件的前端跑在隐藏 iframe 里，
    // 无法渲染面板 —— 课堂工具只能在后端做事（写库、发事件、回一条结果）。
    await commandBus.registerHandler('{{commandPrefix}}.open_tool', {
      async execute(command) {
        const payload = command.payload as { lessonId?: string; classId?: string };
        return {
          opened: true,
          pluginId: '{{pluginId}}',
          lessonId: payload?.lessonId ?? null,
          classId: payload?.classId ?? null,
        };
      },
    });

    ctx.log.info('{{pluginName}} (full-stack) activated successfully');
  },

  async deactivate() {
    while (cleanups.length > 0) {
      const cleanup = cleanups.pop();
      try {
        await cleanup?.();
      } catch (err) {
        console.error('Error during cleanup:', err);
      }
    }
    console.log('{{pluginName}} (full-stack) deactivated');
  },
};
