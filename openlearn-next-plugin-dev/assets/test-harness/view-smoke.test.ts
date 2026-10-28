/**
 * L1：view 页面冒烟（jsdom + 与平台同形的假桥接）
 *
 * 只覆盖 sandbox-view 契约：`storage/**\/*.html` 在不透明源 iframe 里能加载、
 * 能拿到 OpenLearnPluginBridge、init 后真的发出命令/接口调用，且没有触碰被禁 API。
 * 不替代 L3 真实宿主验证。
 *
 * 依赖 jsdom（仅本文件用）：npm i -D jsdom
 * 未安装时整个套件跳过，不影响其它 L1/L2。
 */
// @ts-nocheck —— jsdom 是可选 devDependency，缺类型时不影响其它用例
import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.cwd();
const STORAGE = join(ROOT, 'storage');

const loadJsdom = async () => {
  // vitest 的 SSR 模块运行器里 Function/import 解析基准不稳定，优先用 createRequire 从项目根解析
  try {
    const { createRequire } = await import('node:module');
    return createRequire(join(process.cwd(), 'noop.js'))('jsdom');
  } catch {
    /* fallthrough */
  }
  try {
    return await Function('return import("jsdom")')();
  } catch {
    return null;
  }
};
const jsdom = await loadJsdom();

const listPages = (dir) => {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...listPages(p));
    else if (name.endsWith('.html')) out.push(p);
  }
  return out;
};

const pages = listPages(STORAGE);
const available = Boolean(jsdom) && pages.length > 0;

if (!jsdom && pages.length > 0) {
  console.warn('[view-smoke] 已跳过：未安装 jsdom（npm i -D jsdom）');
}

const makeBridge = (log) => {
  const initCallbacks = [];
  const contextCallbacks = [];
  let context = null;
  const bridge = {
    __initCallbacks: initCallbacks,
    __contextCallbacks: contextCallbacks,
    onInit(cb) {
      if (typeof cb === 'function') {
        if (context) cb(context);
        initCallbacks.push(cb);
      }
      return bridge;
    },
    onContextUpdate(cb) {
      if (typeof cb === 'function') contextCallbacks.push(cb);
      return bridge;
    },
    getContext() {
      return context;
    },
    __init(payload) {
      context = payload;
      for (const cb of initCallbacks) cb(context);
    },
    ui: {
      toast(message, type) {
        log.toasts.push({ message, type });
        return Promise.resolve();
      },
      showToast(message, type) {
        log.toasts.push({ message, type });
        return Promise.resolve();
      },
      resize(height) {
        log.resizes.push(height);
      },
    },
    invokeCommand(type, payload) {
      log.commands.push({ type, payload });
      return Promise.resolve({ ok: true, notes: [] });
    },
    api: {
      get(path) {
        log.apis.push({ method: 'GET', path });
        return Promise.resolve({ ok: true });
      },
      post(path, body) {
        log.apis.push({ method: 'POST', path, body });
        return Promise.resolve({ ok: true });
      },
      del(path) {
        log.apis.push({ method: 'DELETE', path });
        return Promise.resolve({ ok: true });
      },
    },
    storage: {
      get(key) {
        log.storage.push(['get', key]);
        return Promise.resolve(null);
      },
      set(key, value) {
        log.storage.push(['set', key, value]);
        return Promise.resolve();
      },
      delete(key) {
        log.storage.push(['delete', key]);
        return Promise.resolve();
      },
    },
  };
  return bridge;
};

const tick = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms));

describe.skipIf(!available)('view 页面冒烟（storage/**/*.html）', () => {
  for (const page of pages) {
    const rel = relative(ROOT, page);
    const html = readFileSync(page, 'utf8');

    it(`${rel} 可加载：无被禁 API、init 后链路可用、高度会回传`, async () => {
      if (/<script[^>]+type=["']module["']/i.test(html)) {
        console.warn(`[view-smoke] ${rel} 使用 type="module"，jsdom 不执行模块脚本，已跳过`);
        return;
      }

      const log = { resizes: [], commands: [], apis: [], toasts: [], storage: [], blocked: [] };
      const dom = new jsdom.JSDOM(html, {
        url: `https://plugin-view.test/${relative(STORAGE, page)}`,
        runScripts: 'dangerously',
        pretendToBeVisual: true,
        virtualConsole: new jsdom.VirtualConsole().on('jsdomError', (err) => {
          log.blocked.push(`jsdomError: ${err && err.message ? err.message : String(err)}`);
        }),
        beforeParse(window) {
          window.alert = () => {
            log.blocked.push('alert() 被调用（view iframe 没有 allow-modals）');
          };
          window.confirm = () => {
            log.blocked.push('confirm() 被调用（view iframe 没有 allow-modals）');
            return false;
          };
          window.fetch = (input) => {
            log.blocked.push(`fetch('${String(input)}') 被调用（不可用宿主 fetch，请走 bridge.api / invokeCommand）`);
            return Promise.reject(new Error('fetch is blocked in view sandbox'));
          };
          window.ResizeObserver = class {
            constructor(cb) {
              this.cb = cb;
            }
            observe() {
              setTimeout(() => {
                try {
                  this.cb([], this);
                } catch {
                  /* 页面自身回调错误由 jsdomError 兜底 */
                }
              }, 0);
            }
            unobserve() {}
            disconnect() {}
          };
          // jsdom 未实现、但真实浏览器里存在：补空实现，避免误判为页面错误
          window.scrollTo = () => {};
          window.open = () => null;
          if (window.Element) window.Element.prototype.scrollIntoView = () => {};
          window.matchMedia = window.matchMedia || (() => ({
            matches: false,
            addListener() {},
            removeListener() {},
            addEventListener() {},
            removeEventListener() {},
          }));
          window.OpenLearnPluginBridge = makeBridge(log);
        },
      });

      try {
        const bridge = dom.window.OpenLearnPluginBridge;
        expect(bridge, '页面没有拿到 OpenLearnPluginBridge').toBeTruthy();

        await tick();

        if (/\.onInit\s*\(/.test(html)) {
          expect(bridge.__initCallbacks.length, '页面引用了 onInit，但没有注册回调').toBeGreaterThan(0);
        }
        bridge.__init({ lessonId: 'lesson-test', classId: 'class-test', lang: 'zh-CN', route: '/classroom' });
        // rAF 在 jsdom 里按 ~16ms 调度，页面常在 render 后 rAF 里回传高度
        await tick(80);

        expect(log.blocked, '页面使用了沙箱里不可用的 API').toEqual([]);

        if (/invokeCommand\s*\(/.test(html)) {
          expect(log.commands.length, '页面调用了 invokeCommand，但 init 后没有发出任何命令').toBeGreaterThan(0);
        }
        if (/\bapi\s*\.\s*(get|post|del)\s*\(/.test(html)) {
          expect(log.apis.length, '页面调用了 bridge.api，但 init 后没有发出任何请求').toBeGreaterThan(0);
        }
        if (/ResizeObserver|ui\.resize\s*\(/.test(html)) {
          expect(log.resizes.length, '页面声明了高度自适应，但没有真正调用 bridge.ui.resize').toBeGreaterThan(0);
          expect(Number.isFinite(log.resizes[0]), 'bridge.ui.resize 收到的不是数字高度').toBe(true);
        } else {
          console.warn(`[view-smoke] ${rel} 没有高度自适应（建议加 ResizeObserver + bridge.ui.resize）`);
        }
      } finally {
        dom.window.close();
      }
    }, 10_000);
  }
});
