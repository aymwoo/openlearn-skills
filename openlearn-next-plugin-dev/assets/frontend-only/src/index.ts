import type { PluginContext } from '@openlearn/plugin-sdk';

export default {
  manifest: {
    id: '{{pluginId}}',           // 全局唯一标识
    name: '{{pluginName}}',
    version: '0.1.0',
    description: '{{description}}',
    author: '{{author}}',
    engines: { openlearn: '^5.0.0' },
    requires: [],                  // 纯前端插件不需要服务依赖
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
    ctx.log.info('Frontend-only plugin activated');
  },

  async deactivate() {},
};
