/**
 * sandbox-view 模板 —— 第三方插件（process 模式）拿到自定义界面的**推荐**方式。
 *
 * 原理（平台 v0.7.6+ 双轨制 UI）：
 *   manifest 的 contributes 条目写 `view: "storage/xxx.html"`，
 *   宿主用不透明源 iframe（sandbox="allow-scripts allow-forms allow-downloads"）加载
 *   `/plugins/<插件>/<view>`，并注入 `/plugin-sandbox/view-bridge.js`。
 *   页面里用 `window.OpenLearnPluginBridge` 调命令/接口/storage/toast。
 *
 * 为什么不用 React：
 *   - process 模式跑在隐藏 iframe，没有 DOM / React；
 *   - 想拿真 React 组件必须 inline + 宿主白名单（见 inline-react 模板）；
 *   - 大多数"自定义界面"用 HTML/CSS/原生 JS 就够了，`view` 不需要任何白名单。
 *
 * 注意：官方 CLI 只打 manifest.json/index.js/frontend.js，
 *       `storage/**` 必须用 `npm run pack`（scripts/pack.mjs）补进 ZIP。
 */
import type { PluginContext, PlatformEvent } from '@openlearn/plugin-sdk';

// 自建订阅需要保留引用，在 deactivate 中释放
const cleanups: Array<() => void | Promise<void>> = [];

export default {
  manifest: {
    id: '{{pluginId}}',
    name: '{{pluginName}}',
    version: '0.1.0',
    main: 'index.js',
    description: '{{description}}',
    author: '{{author}}',
    // 用 contributes 的可视沙箱视图 → >=0.7.6
    engines: { openlearn: '>=0.7.6' },
    requires: [
      '@openlearn/core:ICommandBusService@^1.0.0',
      '@openlearn/core:IActionRegistryService@^1.0.0',
      '@openlearn/core:IEventBusService@^1.0.0',
      '@openlearn/core:IDatabase@^1.0.0',
    ],
    capabilitiesProposed: ['lesson:read', 'lesson:write'],
    contributes: {
      'teacher.tab': [
        {
          id: '{{commandPrefix}}-teacher',
          label: '{{pluginName}}',
          icon: 'StickyNote',
          view: 'storage/teacher.html',
        },
      ],
      'student.view': [
        {
          id: '{{commandPrefix}}-student',
          label: '{{pluginName}}',
          icon: 'StickyNote',
          view: 'storage/student.html',
        },
      ],
    },
  },

  async activate(ctx: PluginContext) {
    const { commandBus, actionRegistry, eventBus } = ctx.services;

    await ctx.db.ensureTable(
      'notes',
      'id TEXT PRIMARY KEY, lesson_id TEXT NOT NULL, text TEXT NOT NULL, author TEXT, created_at INTEGER NOT NULL',
    );
    const notesTable = ctx.db.table('notes');

    // ── Actions：default-deny，每个 commandType 都要有描述符 ──────────────
    await actionRegistry.register({
      id: '{{commandPrefix}}-add-note',
      commandType: '{{commandPrefix}}.add_note',
      description: '在便签板新增一条便签',
      capabilityRequired: 'lesson:write',
      inputSchema: {
        type: 'OBJECT',
        properties: {
          lessonId: { type: 'STRING', description: '课节 ID' },
          text: { type: 'STRING', description: '便签内容' },
        },
        required: ['lessonId', 'text'],
      },
    });

    await actionRegistry.register({
      id: '{{commandPrefix}}-list-notes',
      commandType: '{{commandPrefix}}.list_notes',
      description: '列出当前课节的便签',
      capabilityRequired: 'lesson:read',
      inputSchema: {
        type: 'OBJECT',
        properties: { lessonId: { type: 'STRING', description: '课节 ID' } },
        required: ['lessonId'],
      },
    });

    // ── Handlers：view 页面通过 bridge.invokeCommand 调到这里 ─────────────
    await commandBus.registerHandler('{{commandPrefix}}.add_note', {
      async execute(command) {
        const p = command.payload as { lessonId?: string; text?: string };
        if (!p?.lessonId || !p?.text) throw new Error('lessonId 与 text 必填');
        const rawDb = await (ctx.resolve as any)('@openlearn/core:IDatabase');
        if (!rawDb?.prepare) throw new Error('数据库不可用');

        const row = {
          id: crypto.randomUUID(),
          lesson_id: p.lessonId,
          text: p.text,
          author: command.actorId ?? 'unknown',
          created_at: Date.now(),
        };
        rawDb
          .prepare(`INSERT INTO ${notesTable} (id, lesson_id, text, author, created_at) VALUES (?, ?, ?, ?, ?)`)
          .run(row.id, row.lesson_id, row.text, row.author, row.created_at);

        await eventBus.publish({
          id: crypto.randomUUID(),
          type: '{{commandPrefix}}.note_added',
          source: 'plugin.{{pluginId}}',
          payload: { lessonId: p.lessonId, id: row.id },
          timestamp: Date.now(),
          correlationId: command.id,
        });

        return { id: row.id };
      },
    });

    await commandBus.registerHandler('{{commandPrefix}}.list_notes', {
      async execute(command) {
        const p = command.payload as { lessonId?: string };
        if (!p?.lessonId) throw new Error('lessonId 必填');
        const rawDb = await (ctx.resolve as any)('@openlearn/core:IDatabase');
        if (!rawDb?.prepare) throw new Error('数据库不可用');
        const rows = rawDb
          .prepare(`SELECT id, text, author, created_at FROM ${notesTable} WHERE lesson_id = ? ORDER BY created_at ASC`)
          .all(p.lessonId);
        return { notes: rows };
      },
    });

    const onNoteAdded = (event: PlatformEvent) => {
      ctx.log.debug(`[event] ${event.type}`, event.payload as Record<string, unknown> | undefined);
    };
    await eventBus.subscribe('{{commandPrefix}}.note_added', onNoteAdded);
    cleanups.push(() => eventBus.unsubscribe('{{commandPrefix}}.note_added', onNoteAdded));

    ctx.log.info('{{pluginName}} (sandbox-view) activated');
  },

  async deactivate() {
    while (cleanups.length > 0) {
      const cleanup = cleanups.pop();
      try {
        await cleanup?.();
      } catch (err) {
        console.error('Error during cleanup:', err);
      }
    }
  },
};
