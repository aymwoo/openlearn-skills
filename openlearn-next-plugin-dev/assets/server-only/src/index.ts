import type { PluginContext } from '@openlearn/plugin-sdk';
import {
  ICommandBusServiceToken,
  IActionRegistryServiceToken,
  IEventBusServiceToken,
  IDatabaseToken,
} from '@openlearn/plugin-sdk';

// 记录活动订阅与清理函数列表，用于 deactivate 时精确清理
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
    capabilitiesProposed: ['lesson:read'],
  },

  async activate(ctx: PluginContext) {
    const commandBus = ctx.services.commandBus;
    const actionRegistry = ctx.services.actionRegistry;
    const eventBus = ctx.services.eventBus;
    const db = ctx.db;

    // ============================================================
    // 1. 数据库初始化 (示例)
    // ============================================================
    // await db.ensureTable('records', `
    //   id TEXT PRIMARY KEY,
    //   name TEXT NOT NULL,
    //   created_at INTEGER NOT NULL
    // `);

    // ============================================================
    // 2. 注册 AI Action (可被 AI Agent 自然语言识别并触发)
    // ============================================================
    // await actionRegistry.register({
    //   id: '{{commandPrefix}}-hello',
    //   commandType: '{{commandPrefix}}.hello',
    //   description: '发送问候信息',
    //   capabilityRequired: 'lesson:read',
    //   inputSchema: {
    //     type: 'OBJECT',
    //     properties: {
    //       name: { type: 'STRING', description: '被问候人姓名' },
    //     },
    //     required: ['name'],
    //   },
    // });

    // ============================================================
    // 3. 注册 Command Handler
    // ============================================================
    // await commandBus.registerHandler('{{commandPrefix}}.hello', {
    //   async execute(command) {
    //     const payload = command.payload as any;
    //     
    //     // 发布 EventBus 事件通知其他订阅者
    //     await eventBus.publish({
    //       id: crypto.randomUUID(),
    //       type: '{{commandPrefix}}.greeted',
    //       source: 'plugin.{{commandPrefix}}',
    //       payload: { name: payload.name },
    //       timestamp: Date.now(),
    //       correlationId: command.id,
    //     });
    //
    //     return { message: `Hello, ${payload.name}!` };
    //   },
    // });

    // ============================================================
    // 4. 订阅 EventBus 事件示例 (带销毁清理注册)
    // ============================================================
    // const sub = eventBus.subscribe('{{commandPrefix}}.*', (event) => {
    //   ctx.log.info(`[Event Received] ${event.type}:`, event.payload);
    // });
    // if (sub && typeof sub.dispose === 'function') {
    //   cleanups.push(() => sub.dispose());
    // }

    ctx.log.info('{{pluginName}} (server-only) activated successfully');
  },

  async deactivate() {
    // 执行所有注册的清理闭包（如注销订阅、定时器、进程等）
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

