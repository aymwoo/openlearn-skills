import type { PluginContext } from '@openlearn/plugin-sdk';
import {
  ICommandBusServiceToken,
  IActionRegistryServiceToken,
  IEventBusServiceToken,
  IDatabaseToken,
} from '@openlearn/plugin-sdk';

export default {
  manifest: {
    id: '{{pluginId}}',           // 全局唯一标识，如 @scope/plugin-name
    name: '{{pluginName}}',
    version: '0.1.0',
    description: '{{description}}',
    author: '{{author}}',
    engines: { openlearn: '^5.0.0' },
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
    // TODO: 在此处注册 AI Action 和 Command Handler
    // ============================================================

    // 示例：注册一个 Action
    // await actionRegistry.register({
    //   id: '{{commandPrefix}}-hello',
    //   commandType: '{{commandPrefix}}.hello',
    //   description: '打招呼',
    //   capabilityRequired: 'lesson:read',
    //   inputSchema: {
    //     type: 'OBJECT',
    //     properties: {
    //       name: { type: 'STRING', description: '名字' },
    //     },
    //     required: ['name'],
    //   },
    // });

    // 示例：注册一个 Command Handler
    // await commandBus.registerHandler('{{commandPrefix}}.hello', {
    //   async execute(command) {
    //     const payload = command.payload as any;
    //     return { message: `Hello, ${payload.name}!` };
    //   },
    // });

    ctx.log.info('Plugin activated');
  },

  async deactivate() {
    // TODO: 清理资源
    // ctx.db.dropAllTables() 由 PluginHost 自动调用
  },
};
