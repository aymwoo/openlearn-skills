import type { PluginContext } from '@openlearn/plugin-sdk';

export default {
  manifest: {
    id: '{{pluginId}}',           // 全局唯一标识，如 @scope/plugin-name
    name: '{{pluginName}}',
    version: '0.1.0',
    description: '{{description}}',
    author: '{{author}}',
    engines: { openlearn: '>=0.1.9' },
    requires: [],                  // 纯前端插件不需要后端服务依赖
    capabilitiesProposed: [],
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
    // 纯前端插件如果声明了 classroomTools，也需要注册空 handler 防止调度 404
    if (ctx.services.commandBus) {
      await ctx.services.commandBus.registerHandler('{{commandPrefix}}.open_tool', {
        async execute() {
          return { status: 'ok' };
        },
      });
    }

    ctx.log.info('{{pluginName}} (frontend-only) activated successfully');
  },

  async deactivate() {},
};

