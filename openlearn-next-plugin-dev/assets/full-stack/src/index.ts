import type { PluginContext } from '@openlearn/plugin-sdk';
import {
  ICommandBusServiceToken,
  IActionRegistryServiceToken,
  IEventBusServiceToken,
  IDatabaseToken,
} from '@openlearn/plugin-sdk';

const cleanups: Array<() => void> = [];

export default {
  manifest: {
    id: '{{pluginId}}',           // 全局唯一标识，如 @scope/plugin-name
    name: '{{pluginName}}',
    version: '0.1.0',
    description: '{{description}}',
    author: '{{author}}',
    engines: { openlearn: '>=0.1.9' },
    requires: [
      '@openlearn/core:ICommandBusService@^1.0.0',
      '@openlearn/core:IActionRegistryService@^1.0.0',
      '@openlearn/core:IEventBusService@^1.0.0',
      '@openlearn/core:IDatabase@^1.0.0',
    ],
    capabilitiesProposed: ['lesson:read', 'lesson:write'],
    classroomTools: [
      {
        id: '{{toolId}}',
        name: '{{toolName}}',
        icon: 'Puzzle',
        commandType: '{{commandPrefix}}.open_tool',
      },
    ],
  },

  async activate(ctx: PluginContext) {
    const commandBus = ctx.services.commandBus;
    const actionRegistry = ctx.services.actionRegistry;
    const eventBus = ctx.services.eventBus;
    const db = ctx.db;

    // 必须注册 classroomTools 声明的 commandType 对应的 handler
    await commandBus.registerHandler('{{commandPrefix}}.open_tool', {
      async execute() {
        return { panel: 'teacher' };
      },
    });

    // 示例：创建数据库表
    // await ctx.db.ensureTable('items', `
    //   id TEXT PRIMARY KEY,
    //   lesson_id TEXT NOT NULL,
    //   data TEXT NOT NULL,
    //   created_at INTEGER NOT NULL
    // `);

    // 示例：注册 AI Action
    // await actionRegistry.register({
    //   id: '{{commandPrefix}}-create',
    //   commandType: '{{commandPrefix}}.create',
    //   description: '创建新记录',
    //   capabilityRequired: 'lesson:write',
    //   inputSchema: {
    //     type: 'OBJECT',
    //     properties: {
    //       lessonId: { type: 'STRING', description: '课程 ID' },
    //       title: { type: 'STRING', description: '标题' },
    //     },
    //     required: ['lessonId', 'title'],
    //   },
    // });

    // 示例：注册 Command Handler 与发布事件
    // await commandBus.registerHandler('{{commandPrefix}}.create', {
    //   async execute(command) {
    //     const payload = command.payload as any;
    //     const id = crypto.randomUUID();
    //     const itemsTable = ctx.db.table('items');
    //
    //     const rawDb = await ctx.resolve(IDatabaseToken);
    //     rawDb.prepare(`INSERT INTO ${itemsTable} (id, lesson_id, data, created_at)
    //       VALUES (?, ?, ?, ?)`).run(id, payload.lessonId, payload.title, Date.now());
    //
    //     await eventBus.publish({
    //       id: crypto.randomUUID(),
    //       type: '{{commandPrefix}}.created',
    //       source: 'plugin.{{commandPrefix}}',
    //       payload: { id, lessonId: payload.lessonId },
    //       timestamp: Date.now(),
    //       correlationId: command.id,
    //     });
    //
    //     return { id, message: `已创建: ${payload.title}` };
    //   },
    // });

    ctx.log.info('{{pluginName}} (full-stack) activated successfully');
  },

  async deactivate() {
    while (cleanups.length > 0) {
      const cleanup = cleanups.pop();
      try {
        cleanup?.();
      } catch (err) {
        console.error('Error during cleanup:', err);
      }
    }
  },
};

