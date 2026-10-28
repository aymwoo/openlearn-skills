/**
 * L2 冒烟测试：真的把插件跑起来，让运行时崩溃在开发阶段暴露。
 *
 * 覆盖：
 *   1. activate → deactivate → 再次 activate（暴露模块级状态泄漏）
 *   2. 按 inputSchema 造最小 payload，逐个执行命令（暴露 undefined 取值、未 await、事件 payload 缺失）
 *   3. 逐个派发 manifest.api.routes（暴露 5xx / 未捕获异常）
 *   4. 停用后订阅是否释放（暴露 subscribe 未保留 handler 引用）
 *
 * 跑：npx vitest run --config test-harness/vitest.config.ts
 */

import { describe, it, expect } from 'vitest';
import { createMockContext } from '@openlearn/plugin-test-kit';
// @ts-expect-error 插件源码是 TS，vitest 负责转译
import plugin from '../src/index.js';

const PLUGIN = plugin as {
  manifest: Record<string, any>;
  activate(ctx: any): Promise<void>;
  deactivate?(): Promise<void>;
};

/** 用 ActionDescriptor.inputSchema 造一份「最小但合法」的 payload */
function buildPayload(schema: any): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const props = schema?.properties ?? {};
  for (const [key, def] of Object.entries<any>(props)) {
    switch (def?.type) {
      case 'STRING': out[key] = def.enum?.[0] ?? 'test-value'; break;
      case 'NUMBER': case 'INTEGER': out[key] = 1; break;
      case 'BOOLEAN': out[key] = false; break;
      case 'ARRAY': out[key] = []; break;
      case 'OBJECT': out[key] = {}; break;
      default: out[key] = null;
    }
  }
  return out;
}

function classify(err: unknown): string {
  if (err instanceof Error) return `${err.name}: ${err.message}`;
  return String(err);
}

async function boot() {
  const ctx = createMockContext({
    pluginId: PLUGIN.manifest.id,
    manifest: PLUGIN.manifest,
    capabilities: (PLUGIN.manifest.capabilitiesProposed as string[]) ?? [],
  });
  await PLUGIN.activate(ctx);
  return ctx;
}

describe('生命周期', () => {
  it('activate 可在同一进程内重复执行（无模块级状态泄漏）', async () => {
    const ctx = await boot();
    expect((ctx.services.commandBus as any).handlers.size).toBeGreaterThan(0);

    await PLUGIN.deactivate?.();
    await PLUGIN.activate(ctx);
    expect((ctx.services.commandBus as any).handlers.size).toBeGreaterThan(0);
    await PLUGIN.deactivate?.();
  });

  it('deactivate 不抛错，且重复调用安全', async () => {
    await boot();
    await expect(PLUGIN.deactivate?.()).resolves.not.toThrow();
    if (PLUGIN.deactivate) await expect(PLUGIN.deactivate()).resolves.not.toThrow();
  });
});

describe('命令执行冒烟（按 inputSchema 造最小 payload）', () => {
  it('每个命令都能执行：不出现 TypeError / ReferenceError', async () => {
    const ctx = await boot();
    const handlers = (ctx.services.commandBus as any).handlers as Map<string, any>;
    const actions = [...((ctx.services.actionRegistry as any).actions as Map<string, any>).values()] as any[];
    expect(handlers.size).toBeGreaterThan(0);

    const crashes: string[] = [];
    for (const [type, handler] of handlers) {
      const descriptor = actions.find((a) => a.commandType === type);
      const command = {
        id: `test-${type}`,
        type,
        payload: buildPayload(descriptor?.inputSchema),
        actorId: 'user:test-teacher',
        timestamp: Date.now(),
      };
      try {
        await handler.execute(command);
      } catch (err) {
        const c = classify(err);
        // 业务校验报错（抛出带 code 的错误）是合法的；崩溃（TypeError 取值）不是
        if (/^(TypeError|ReferenceError)/.test(c)) crashes.push(`${type} → ${c}`);
      }
    }
    expect(crashes, `命令执行期崩溃（多为 payload 解构 / event payload 缺字段）：\n${crashes.join('\n')}`).toEqual([]);
  });

  it('执行后产生的事件 payload 是结构化对象', async () => {
    const ctx = await boot();
    const handlers = (ctx.services.commandBus as any).handlers as Map<string, any>;
    const actions = [...((ctx.services.actionRegistry as any).actions as Map<string, any>).values()] as any[];
    const entries = [...handlers.entries()].filter(([, h]) => typeof (h as any)?.execute === 'function');
    if (entries.length === 0) return; // 裸函数已由 contract.test.ts 报错，这里不级联失败
    const [type, handler] = entries[0];
    const descriptor = actions.find((a) => a.commandType === type);
    try {
      await handler.execute({
        id: `test-${type}`,
        type,
        payload: buildPayload(descriptor?.inputSchema),
        actorId: 'user:test-teacher',
        timestamp: Date.now(),
      });
    } catch {
      // 执行期崩溃由上一条用例负责报错；这里只检查「已经发出的事件」形状
    }
    for (const event of (ctx.services.eventBus as any).publishCalls as any[]) {
      expect(event.type, '事件必须有 type').toBeTruthy();
      expect(event.payload === undefined, `事件 ${event.type} 的 payload 不应为 undefined`).toBe(false);
    }
  });
});

describe('REST 路由冒烟', () => {
  const routes: any[] = (PLUGIN.manifest.api?.routes as any[]) ?? [];
  it.skipIf(routes.length === 0)('每条路由都不返回 5xx', async () => {
    const ctx = await boot();
    const actor = { actorId: 'user:test-teacher', username: 't', role: 'teacher' };
    const failures: string[] = [];
    for (const r of routes) {
      const path = String(r.path).replace(/:[^/]+/g, 'test-id');
      try {
        const res = await ctx.http.handle({
          method: r.method, path, params: {}, query: {}, headers: {}, body: {},
          ip: '127.0.0.1', actor,
        } as any);
        if ((res?.status ?? 200) >= 500) failures.push(`${r.method} ${path} → ${res.status}`);
      } catch (err) {
        failures.push(`${r.method} ${path} → 未捕获异常 ${classify(err)}`);
      }
    }
    expect(failures, `路由在开发阶段就 5xx：\n${failures.join('\n')}`).toEqual([]);
  });
});

describe('停用清理（宿主兜底之外的资源）', () => {
  it('订阅被释放：重复 activate 不会让同一事件被投递两次', async () => {
    const ctx = await boot();
    await PLUGIN.deactivate?.();
    await PLUGIN.activate(ctx);
    const subscribers = (ctx.services.eventBus as any).subscribers as Map<string, Set<Function>>;
    for (const [eventType, set] of subscribers) {
      expect(set.size, `事件 ${eventType} 存在重复订阅：停用未 unsubscribe`).toBeLessThanOrEqual(1);
    }
    await PLUGIN.deactivate?.();
  });
});
