/**
 * L1 契约测试：把「生产宿主会校验、Mock 却放行」的部分显式断言出来。
 *
 * 覆盖的是平台最常见的装得上、点了崩的坑：
 *   1. manifest 必填项 / engines / 权限串真伪
 *   2. manifest 声明的 commandType ↔ registerHandler ↔ ActionDescriptor 三方配对
 *   3. ActionDescriptor 的 capabilityRequired 是否真实存在、inputSchema 类型名是否大写
 *   4. handler 是否为 { execute } 对象（裸函数在 Worker/Process/Mock 下都炸）
 *
 * 跑：npx vitest run --config test-harness/vitest.config.ts
 */

import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';
import { createMockContext } from '@openlearn/plugin-test-kit';
// @ts-expect-error 插件源码是 TS，vitest 负责转译；tsc 不检查本目录
import plugin from '../src/index.js';

const PLUGIN = plugin as {
  manifest: Record<string, any>;
  activate(ctx: any): Promise<void>;
  deactivate?(): Promise<void>;
};

/** 读取设计契约与槽位注册表（缺失时相关用例自动跳过） */
function readJson(rel: string): any {
  try {
    return JSON.parse(readFileSync(new URL(rel, import.meta.url), 'utf8'));
  } catch {
    return null;
  }
}
const CONTRACT = readJson('../plugin.contract.json');
const SLOT_REGISTRY = readJson('./slot-registry.json');
const REAL_SLOTS = new Set<string>(SLOT_REGISTRY?.slots ?? []);

/** 平台真实权限全集（20 条 RBAC + 3 条仅声明项），见 references/capability-matrix-0.7.md */
const REAL_CAPS = new Set([
  'management:write', 'lesson:write', 'whiteboard:write', 'management:read',
  'plugin:write', 'lesson:read', 'vfs:write', 'process:write',
  'assignment:manage', 'whiteboard:read', 'vfs:read', 'process:read',
  'assignment:read', 'lesson:delete', 'plugin:read', 'student:write',
  'assignment:write', 'assignment:submit', 'assignment:review',
  'class:read', 'class:write', 'student:read',
]);

const CAPS = ['OBJECT', 'STRING', 'NUMBER', 'INTEGER', 'BOOLEAN', 'ARRAY'];

/** 收集 manifest 里声明的所有 commandType（classroomTools + 递归 contributes），统一成短名 */
function declaredCommandTypes(manifest: Record<string, any>): string[] {
  const out = new Set<string>();
  const id = String(manifest.id ?? '');
  const push = (v: unknown) => {
    if (typeof v !== 'string' || !v) return;
    out.add(id && v.startsWith(`${id}.`) ? v.slice(id.length + 1) : v);
  };
  for (const t of (manifest.classroomTools as any[]) ?? []) push(t?.commandType);
  const walk = (v: any) => {
    if (!v || typeof v !== 'object') return;
    if (Array.isArray(v)) return v.forEach(walk);
    for (const [k, val] of Object.entries(v)) {
      if (k === 'commandType') push(val);
      else walk(val);
    }
  };
  walk(manifest.contributes);
  return [...out];
}

async function activateOnMock() {
  const ctx = createMockContext({
    pluginId: PLUGIN.manifest.id,
    manifest: PLUGIN.manifest,
    capabilities: (PLUGIN.manifest.capabilitiesProposed as string[]) ?? [],
  });
  await PLUGIN.activate(ctx);
  const handlers = (ctx.services.commandBus as any).handlers as Map<string, any>;
  const actions = (ctx.services.actionRegistry as any).actions as Map<string, any>;
  return { ctx, handlers, actions };
}

describe('manifest 契约', () => {
  it('main / id / version / engines 存在且形状正确', () => {
    expect(PLUGIN.manifest.main, 'main 缺失 → manifestSchema 校验失败，插件装不上').toBeTruthy();
    expect(PLUGIN.manifest.id).toBeTruthy();
    expect(String(PLUGIN.manifest.id)).not.toContain(':');
    expect(PLUGIN.manifest.version).toMatch(/^\d+\.\d+\.\d+/);
    expect(PLUGIN.manifest.engines?.openlearn, 'engines.openlearn 声明的是宿主版本范围').toMatch(/\d+\.\d+\.\d+/);
  });

  it('capabilitiesProposed 只包含平台真实权限串', () => {
    const caps = (PLUGIN.manifest.capabilitiesProposed as string[]) ?? [];
    const bogus = caps.filter((c) => !REAL_CAPS.has(c));
    expect(bogus, `捏造的权限串会静默失效：${bogus.join(', ')}`).toEqual([]);
  });

  it('engines.openlearn 不低于本插件所用 API 的最低宿主版本（人工核对项）', () => {
    // 无法自动推导 API→版本映射，这里只做下限兜底，细则见 references/manifest-0.7.md §11
    const min = String(PLUGIN.manifest.engines?.openlearn ?? '');
    expect(min, 'engines 不应低于 0.2.3（ctx.log / ctx.config 的最低版本）').toMatch(/\d+\.\d+\.\d+/);
  });
});

describe('命令三件套配对（default-deny 的必测项）', () => {
  it('manifest 声明的每个 commandType 都有 handler', async () => {
    const { handlers } = await activateOnMock();
    const missing = declaredCommandTypes(PLUGIN.manifest).filter((t) => !handlers.has(t));
    expect(missing, `这些 commandType 没有 registerHandler，点击会失败：${missing.join(', ')}`).toEqual([]);
  });

  it('manifest 声明的每个 commandType 都有 ActionDescriptor', async () => {
    const { actions } = await activateOnMock();
    const types = new Set([...actions.values()].map((a: any) => a.commandType));
    const missing = declaredCommandTypes(PLUGIN.manifest).filter((t) => !types.has(t));
    expect(missing, `缺 ActionDescriptor → COMMAND_NOT_REGISTERED (403)：${missing.join(', ')}`).toEqual([]);
  });

  it('每个 handler 都有同名 ActionDescriptor（反向检查）', async () => {
    const { handlers, actions } = await activateOnMock();
    const types = new Set([...actions.values()].map((a: any) => a.commandType));
    const missing = [...handlers.keys()].filter((t) => !types.has(t));
    expect(missing, `只注册 handler 不注册 action 是最常见的"点了没反应"根因：${missing.join(', ')}`).toEqual([]);
  });

  it('handler 必须是 { execute } 对象，不是裸函数', async () => {
    const { handlers } = await activateOnMock();
    const bad = [...handlers.entries()]
      .filter(([, h]) => typeof (h as any)?.execute !== 'function')
      .map(([t]) => t);
    expect(bad, `裸函数在 Mock / Worker / Process 下都会报 handler.execute is not a function：${bad.join(', ')}`).toEqual([]);
  });
});

describe('ActionDescriptor 质量（决定 AI 能否选对 + 授权是否通过）', () => {
  it('capabilityRequired 必须是真实权限串', async () => {
    const { actions } = await activateOnMock();
    const bad = [...actions.values()]
      .filter((a: any) => !a.capabilityRequired || !REAL_CAPS.has(a.capabilityRequired))
      .map((a: any) => `${a.commandType} → ${a.capabilityRequired}`);
    expect(bad, `缺权限或权限串不存在：${bad.join(' | ')}`).toEqual([]);
  });

  it('description 足够具体', async () => {
    const { actions } = await activateOnMock();
    const bad = [...actions.values()]
      .filter((a: any) => typeof a.description !== 'string' || a.description.trim().length < 6)
      .map((a: any) => a.commandType);
    expect(bad, `描述过短，AI 选不准、用户看不懂：${bad.join(', ')}`).toEqual([]);
  });

  it('inputSchema 的类型名使用大写 GenAI 枚举', async () => {
    const { actions } = await activateOnMock();
    const bad: string[] = [];
    for (const a of actions.values() as any) {
      const props = a.inputSchema?.properties ?? {};
      for (const [k, v] of Object.entries<any>(props)) {
        if (v?.type && !CAPS.includes(String(v.type))) bad.push(`${a.commandType}.${k}: ${v.type}`);
      }
    }
    expect(bad, `类型名应为 OBJECT / STRING / NUMBER / INTEGER / BOOLEAN / ARRAY：${bad.join(', ')}`).toEqual([]);
  });
});


describe('UI 通道契约（plugin.contract.json）', () => {
  it('契约中的槽位都存在于平台真实注册表', () => {
    if (!CONTRACT) return;
    if (REAL_SLOTS.size === 0) return;
    const slots: string[] = Array.isArray(CONTRACT.slots) ? CONTRACT.slots : [];
    const unknown = slots.filter((s) => !s.startsWith('anchor:') && !REAL_SLOTS.has(s));
    expect(unknown, `槽位不在平台注册表（写错不会报错，只会永远不渲染）：${unknown.join(', ')}`).toEqual([]);
  });

  it('executionMode 与 uiChannel 自洽', () => {
    if (!CONTRACT) return;
    const { executionMode, uiChannel } = CONTRACT;
    if (executionMode === 'process') {
      expect(uiChannel, 'process 模式下不能是 inline-react：自定义组件无法渲染').not.toBe('inline-react');
    }
    if (executionMode === 'inline' && uiChannel === 'inline-react') {
      expect(CONTRACT.trustedInlineAllowlistEntry, 'inline 需要宿主白名单条目（id 前缀不构成信任）').toBeTruthy();
    }
  });

  it('学生可见时存在学生侧槽位', () => {
    if (!CONTRACT || CONTRACT.studentVisible !== true) return;
    const slots: string[] = Array.isArray(CONTRACT.slots) ? CONTRACT.slots : [];
    expect(slots.some((s) => s.startsWith('student.')), `studentVisible=true 但没有 student.* 槽位：${slots.join(', ')}`).toBe(true);
  });
});
