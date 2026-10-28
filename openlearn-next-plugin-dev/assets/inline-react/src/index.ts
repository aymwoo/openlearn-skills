/**
 * inline-react 模板 —— 带自定义 React UI 的白板挂件（教师下发 → 学生可见）
 *
 * ⚠️ 前提（缺一不可）：
 *   1. 插件必须**进程内运行（inline）**：manifest.id 必须在宿主 `OPENLEARN_TRUSTED_INLINE_PLUGINS`
 *      白名单里（支持 `*` / `前缀*`），或插件文件位于内置目录 `packages/plugins`。
 *      **id 前缀不构成信任**（`@openlearn/`、`@ext/` 都一样）。
 *   2. 改完 `.env` 必须重启服务，并重新安装/切换隔离档位，让 `plugins.execution_mode` 真正变成 inline。
 *   3. 前端**不能写 `import React`**（SDK CLI 3.7.2+ 裸说明符守卫会让构建失败），
 *      必须用宿主注入的 `globalThis.HostSharedDeps.React`。
 *
 * 本模板演示的完整链路：
 *   classroomTools 按钮 → {{commandPrefix}}.open_board（后端）
 *     → 派发内核命令 whiteboard.draw(type:'plugin')
 *     → 白板元素 data 同时带 teacherWidgetId / studentWidgetId
 *     → 前端注册 teacher.dashboard.widget + student.view 两个组件
 *     → 教师点「下发」后，学生端同一张卡片渲染 StudentWidget
 *
 * 详见 references/ui-channel-decision.md。
 */
import type { PluginContext, PlatformEvent } from '@openlearn/plugin-sdk';

/** 白板元素 data 里的 widget id：教师侧与学生侧各一个，必须与前端注册的扩展点 id 完全一致 */
const TEACHER_WIDGET_ID = '{{commandPrefix}}-teacher';
const STUDENT_WIDGET_ID = '{{commandPrefix}}-student';

// 需要在 deactivate 中释放、且宿主管不到的资源（自建订阅 / 定时器 / 连接）。
// 本模板自己订阅了事件，所以必须保留 handler 引用并显式退订。
const cleanups: Array<() => void | Promise<void>> = [];

export default {
  manifest: {
    id: '{{pluginId}}',
    name: '{{pluginName}}',
    version: '0.1.0',
    // manifest.main 必填（manifestSchema 为 min(1)）
    main: 'index.js',
    description: '{{description}}',
    author: '{{author}}',
    // 用到 classroomTools 声明式入口 + 前端运行期扩展点 + whiteboard.draw → >=0.7.0
    engines: { openlearn: '>=0.7.0' },
    requires: [
      '@openlearn/core:ICommandBusService@^1.0.0',
      '@openlearn/core:IActionRegistryService@^1.0.0',
      '@openlearn/core:IEventBusService@^1.0.0',
      '@openlearn/core:IDatabase@^1.0.0',
    ],
    // whiteboard:write 是派发 whiteboard.draw 的必需权限；管理员须在插件中心批准（v0.7.2 起按已授予集合判定）
    capabilitiesProposed: ['whiteboard:write', 'whiteboard:read'],
    classroomTools: [
      {
        id: '{{toolId}}',
        name: '{{toolName}}',
        icon: 'StickyNote',
        // 点击后由宿主派发该命令；payload 里的 $lessonId / $classId 在点击瞬间替换
        commandType: '{{commandPrefix}}.open_board',
        payload: { lessonId: '$lessonId', classId: '$classId' },
      },
    ],
  },

  async activate(ctx: PluginContext) {
    const { commandBus, actionRegistry, eventBus } = ctx.services;

    // ============================================================
    // 0. 表：插件自有数据（表名由 ctx.db.table('notes') 生成，自带命名空间前缀）
    // ============================================================
    await ctx.db.ensureTable(
      'notes',
      'id TEXT PRIMARY KEY, lesson_id TEXT NOT NULL, text TEXT NOT NULL, author TEXT, created_at INTEGER NOT NULL',
    );
    const notesTable = ctx.db.table('notes');

    // ============================================================
    // 1. Actions：default-deny，每个 commandType 都必须有描述符
    // ============================================================
    await actionRegistry.register({
      id: '{{commandPrefix}}-open-board',
      commandType: '{{commandPrefix}}.open_board',
      description: '把便签板挂件下发到当前白板，教师与学生都会看到同一块板',
      capabilityRequired: 'whiteboard:write',
      inputSchema: {
        type: 'OBJECT',
        properties: {
          lessonId: { type: 'STRING', description: '当前课节 ID' },
          classId: { type: 'STRING', description: '当前班级 ID' },
        },
        required: ['lessonId'],
      },
    });

    await actionRegistry.register({
      id: '{{commandPrefix}}-add-note',
      commandType: '{{commandPrefix}}.add_note',
      description: '在白板便签板上新增一条便签',
      capabilityRequired: 'whiteboard:write',
      inputSchema: {
        type: 'OBJECT',
        properties: {
          lessonId: { type: 'STRING', description: '当前课节 ID' },
          text: { type: 'STRING', description: '便签内容' },
          anonymous: { type: 'BOOLEAN', description: '是否匿名' },
        },
        required: ['lessonId', 'text'],
      },
    });

    await actionRegistry.register({
      id: '{{commandPrefix}}-list-notes',
      commandType: '{{commandPrefix}}.list_notes',
      description: '列出当前课节白板便签板上的全部便签',
      capabilityRequired: 'whiteboard:read',
      inputSchema: {
        type: 'OBJECT',
        properties: { lessonId: { type: 'STRING', description: '当前课节 ID' } },
        required: ['lessonId'],
      },
    });

    // ============================================================
    // 2. Handler：open_board 必须真的写白板（这是「学生端看不到」的第一大根因）
    // ============================================================
    await commandBus.registerHandler('{{commandPrefix}}.open_board', {
      async execute(command) {
        const payload = command.payload as { lessonId?: string; classId?: string };
        if (!payload?.lessonId) throw new Error('缺少 lessonId：请从课堂内点击工具按钮（payload 会自动注入上下文）');

        // 白板元素 data 必须是 JSON 字符串，且教师/学生两侧 widget id 都要给
        const data = JSON.stringify({
          teacherWidgetId: TEACHER_WIDGET_ID,
          studentWidgetId: STUDENT_WIDGET_ID,
          width: 520,
          height: 420,
        });

        const result = await commandBus.execute({
          id: crypto.randomUUID(),
          type: 'whiteboard.draw',
          payload: { lessonId: payload.lessonId, type: 'plugin', data },
          actorId: `plugin:${'{{pluginId}}'}`,
          timestamp: Date.now(),
        });

        await eventBus.publish({
          id: crypto.randomUUID(),
          type: '{{commandPrefix}}.board_opened',
          source: 'plugin.{{pluginId}}',
          payload: { lessonId: payload.lessonId },
          timestamp: Date.now(),
          correlationId: command.id,
        });

        return result;
      },
    });

    await commandBus.registerHandler('{{commandPrefix}}.add_note', {
      async execute(command) {
        const p = command.payload as { lessonId?: string; text?: string; anonymous?: boolean };
        if (!p?.lessonId || !p?.text) throw new Error('lessonId 与 text 必填');
        const author = p.anonymous ? '匿名' : (command.actorId ?? 'unknown');
        const row = { id: crypto.randomUUID(), lesson_id: p.lessonId, text: p.text, author, created_at: Date.now() };

        const rawDb = await (ctx.resolve as any)('@openlearn/core:IDatabase');
        const db = rawDb?.prepare ? rawDb : null;
        if (db) {
          db.prepare(`INSERT INTO ${notesTable} (id, lesson_id, text, author, created_at) VALUES (?, ?, ?, ?, ?)`).run(
            row.id, row.lesson_id, row.text, row.author, row.created_at,
          );
        } else {
          // inline 模式下 ctx.resolve(IDatabaseToken) 可用；缺失说明运行环境不符合预期
          throw new Error('数据库不可用：请确认插件以 inline 模式运行');
        }

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
        if (!rawDb?.prepare) throw new Error('数据库不可用：请确认插件以 inline 模式运行');
        const rows = rawDb
          .prepare(`SELECT id, text, author, created_at FROM ${notesTable} WHERE lesson_id = ? ORDER BY created_at ASC`)
          .all(p.lessonId);
        return { notes: rows };
      },
    });

    // 事件只做日志；真实的跨端同步靠前端轮询 + 白板事件（见 frontend.tsx）
    const onNoteAdded = (event: PlatformEvent) => {
      ctx.log.debug(`[event] ${event.type}`, event.payload as Record<string, unknown> | undefined);
    };
    await eventBus.subscribe('{{commandPrefix}}.note_added', onNoteAdded);
    cleanups.push(() => eventBus.unsubscribe('{{commandPrefix}}.note_added', onNoteAdded));

    ctx.log.info('{{pluginName}} (inline-react) activated');
  },

  async deactivate() {
    // 宿主会注销 command handler 与自己的订阅；这里只清插件自己登记的资源。
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
