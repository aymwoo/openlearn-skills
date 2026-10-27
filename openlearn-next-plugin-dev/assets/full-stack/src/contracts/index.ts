/**
 * 类型契约目录（跨插件服务共享）
 *
 * 把本插件**对外提供**的服务接口与 Token 定义在这里，其他插件即可通过
 * `ctx.resolve(Token)` 消费（需在两边互相声明，见下方「三步配套」）。
 *
 * Token 名格式：`@scope/domain:IServiceName`（构造时会校验，含空格/中文/特殊字符会抛 TokenError）
 *
 * 三步配套（缺一即不生效）：
 *   ① 本文件：`new Token<IMyPluginService>('{{pluginId}}:IMyPluginService', '1.0.0')`
 *   ② 本插件 manifest：`provides: ['{{pluginId}}:IMyPluginService']`
 *      —— `ctx.provide()` 时会校验 token.name 是否在 provides 中声明，未声明直接抛错
 *   ③ 消费方 manifest：`requires: ['{{pluginId}}:IMyPluginService@^1.0.0']`
 *      —— 消费方激活时要求提供方已处于 ACTIVE，否则激活被拒绝
 *
 * 不需要对外提供服务时，可以保留本文件但不使用（占位示例）。
 *
 * ⚠️ **注意**：官方 CLI 的 `build` **不会把这个目录打进 ZIP**（只打包 index.js / manifest.json /
 *    frontend.js）。因此：
 *    · 本文件的价值在于**源码分发**场景（消费方 `import ... from 'my-plugin/contracts'` 拿到类型安全）；
 *    · ZIP 分发场景：宿主 DI 是**按 Token 名字符串**解析的（`Map<tokenName, instance>`），
 *      消费方只要用**完全相同的 Token 名**自己 `new Token('<name>', '1.0.0')` 即可解析到本插件的实例。
 */

import { Token } from '@openlearn/plugin-sdk';

// ── 示例：定义一个其他插件可以消费的服务接口 ──────────────────────────

export interface IMyPluginService {
  /** 方法签名示例 */
  doSomething(input: string): Promise<string>;
}

// Token 名必须与 manifest.provides 中声明的字符串**完全一致**
export const MyPluginServiceToken = new Token<IMyPluginService>(
  '{{pluginId}}:IMyPluginService',
  '1.0.0',
);
