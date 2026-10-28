import { defineConfig } from 'vitest/config';

/**
 * OpenLearnV2 插件测试配置。
 *
 * 运行：npx vitest run --config test-harness/vitest.config.ts
 *
 * 注意：
 * - `@openlearn/plugin-test-kit` 以 **TS 源码** 发布（main: index.ts），
 *   部分 vitest 版本会把 node_modules 外置，导致无法直接 import TS 入口 → 用 inline 兜底。
 * - 若你的项目根已有 vitest.config.ts，把 test.include / server.deps.inline 两段合并过去即可。
 */
export default defineConfig({
  test: {
    environment: 'node',
    root: process.cwd(),
    include: ['test-harness/**/*.test.ts'],
    // test-kit 依赖真实 SQLite（better-sqlite3 内存库），fork 隔离比线程稳
    pool: 'forks',
    server: {
      deps: {
        inline: ['@openlearn/plugin-test-kit'],
      },
    },
  },
});
