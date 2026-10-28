import type { PluginContext } from '@openlearn/plugin-sdk';

/**
 * {{pluginName}} — 前端型插件 manifest。
 *
 * 纯前端模板不注册任何服务端命令处理器，因此 manifest 里**不声明**
 * classroomTools / contributes 中的命令型贡献 —— 声明了没有 handler 接，
 * 用户点按钮只会得到 "No handler registered" 错误。
 *
 * 需要可见入口时请改用 `--template full-stack`：课堂工具、命令面板条目等
 * 声明式贡献都必须配一个服务端命令处理器。
 */
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
    // 本模板用到前端沙箱桥接（0.7.0 起）→ >=0.7.0
    engines: { openlearn: '>=0.7.0' },
    requires: [], // 纯前端插件不需要后端服务依赖
    // 本模板 activate 只调 ctx.log（无 RPC），所以可以留空。
    // 一旦在这里加 ctx.db.* / storage / actionRegistry / publish 等非 get 调用，
    // 必须先声明真实能力，否则 process 模式下 ServiceHost 会拒绝：
    // 「Capability denied … only 'get' methods allowed」（L0 报 CAP_EMPTY_ISOLATED）。
    capabilitiesProposed: [],
  },

  async activate(ctx: PluginContext) {
    ctx.log?.info?.('{{pluginName}} (frontend-only) activated successfully');
  },

  async deactivate() {
    console.log('{{pluginName}} (frontend-only) deactivated');
  },
};
