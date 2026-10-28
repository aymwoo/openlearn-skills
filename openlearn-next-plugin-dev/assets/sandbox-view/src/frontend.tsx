/**
 * 空桥接入口 —— 只为让 CLI 产出 dist/frontend.js。
 *
 * 为什么必须有：
 *   宿主激活远程插件时会**无条件** fetch `/plugins/<id>/frontend.js`
 *   （`plugin-host.ts` 的 activateRemotePlugin / `useClassroomSlice` 的 has_frontend 门禁），
 *   而 `registerManifestContributions()` 排在这个 fetch **之后**：
 *     - 没有 frontend.js → API 返回 has_frontend=false → 前端直接跳过激活 →
 *       所有 manifest 贡献（teacher.tab / view / classroomTools 的 store 语义桥）都不会注册；
 *     - 有文件但 404 → 激活抛错，同样注册不到。
 *   `view` 页面本身跑在宿主沙箱 iframe 里，不需要这里做任何事；
 *   但**这个入口文件不能省**。
 *
 * 约束：不能出现任何裸模块说明符（`import x from 'y'` / `require('y')`），
 *       否则 SDK CLI 3.7.2+ 会在构建期直接失败。
 */
export default {
  async activate() {
    // 页面逻辑在 storage/*.html，由宿主 PluginSandboxIframeView 承载；这里无需注册。
  },
  async deactivate() {
    // 没有运行期扩展点需要注销。
  },
};
