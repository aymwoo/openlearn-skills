import type { PluginContext, PlatformEvent } from '@openlearn/plugin-sdk';

// 需要在 deactivate 中释放、且宿主 ResourceTracker 覆盖不到的资源。
// 宿主在停用时会自动注销 command handler、退订 EventBus 订阅、清理内部定时器；
// 这里只放自建定时器 / 子进程 / 第三方连接。
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
    // 本模板用到 actionRegistry + commandBus + eventBus + ctx.db（均 0.2.x 起）→ >=0.2.5
    engines: { openlearn: '>=0.2.5' },
    // 强依赖的宿主服务 Token。格式：@scope/domain:IServiceName@SemVerRange
    requires: [
      '@openlearn/core:ICommandBusService@^1.0.0',
      '@openlearn/core:IActionRegistryService@^1.0.0',
      '@openlearn/core:IEventBusService@^1.0.0',
    ],
    // 权限声明。取值必须是平台真实存在的能力字符串（见 references/capability-matrix-0.7.md）
    capabilitiesProposed: ['lesson:read'],
  },

  async activate(ctx: PluginContext) {
    const { commandBus, actionRegistry, eventBus } = ctx.services;

    // ============================================================
    // 1. 注册 AI Action（ActionDescriptor）
    // ============================================================
    // Guardrail：内核对命令派发实行 default-deny —— 只有在 actionRegistry
    // 登记过描述符的 commandType 才允许被派发。因此「每个 registerHandler
    // 的 type 都必须有同名 action 描述符」，否则调用会得到
    // COMMAND_NOT_REGISTERED（HTTP 403）。
    await actionRegistry.register({
      id: '{{commandPrefix}}-hello',
      commandType: '{{commandPrefix}}.hello',
      description: '向指定学生发送一条问候消息',
      capabilityRequired: 'lesson:read',
      // GenAI function declaration 格式，类型名大写
      inputSchema: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING', description: '被问候人姓名' },
        },
        required: ['name'],
      },
    });

    // ============================================================
    // 2. 注册 Command Handler
    // ============================================================
    // 第二个参数必须是实现了 execute(command) 的对象，不能是裸函数。
    // commandType 会由宿主自动加上 manifest.id 命名空间前缀。
    await commandBus.registerHandler('{{commandPrefix}}.hello', {
      async execute(command) {
        const payload = command.payload as { name?: string };

        // 发布 EventBus 事件通知订阅者
        await eventBus.publish({
          id: crypto.randomUUID(),
          type: '{{commandPrefix}}.greeted',
          source: 'plugin.{{pluginId}}',
          payload: { name: payload?.name ?? '' },
          timestamp: Date.now(),
          correlationId: command.id,
        });

        return { message: `Hello, ${payload?.name ?? ''}!` };
      },
    });

    // ============================================================
    // 3. 订阅 EventBus 事件
    // ============================================================
    // subscribe(type, subscriber) 返回 Promise<void>，没有 Disposable；
    // 要退订必须自己保留 handler 引用，再调 unsubscribe(type, handler)。
    const onGreeted = (event: PlatformEvent) => {
      ctx.log.info(`[event] ${event.type}`, event.payload as Record<string, unknown> | undefined);
    };
    await eventBus.subscribe('{{commandPrefix}}.*', onGreeted);
    cleanups.push(async () => {
      await eventBus.unsubscribe('{{commandPrefix}}.*', onGreeted);
    });

    ctx.log.info('{{pluginName}} (server-only) activated successfully');
  },

  async deactivate() {
    // 释放自建资源（宿主已自动清理 handler / 订阅 / 定时器）
    while (cleanups.length > 0) {
      const cleanup = cleanups.pop();
      try {
        await cleanup?.();
      } catch (err) {
        console.error('Error during cleanup:', err);
      }
    }
    console.log('{{pluginName}} (server-only) deactivated');
  },
};
