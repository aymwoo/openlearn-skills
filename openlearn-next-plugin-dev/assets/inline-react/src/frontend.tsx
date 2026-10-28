/**
 * inline-react 前端 —— 有自定义 React UI，因此只在 **inline（进程内）** 模式下有意义。
 *
 * 铁律：
 *  1. 这里**不能写任何 import**（含 `import React`）：SDK CLI 3.7.2+ 会拦裸模块说明符，
 *     构建直接失败。React 从宿主注入的 `globalThis.HostSharedDeps.React` 取。
 *  2. 组件必须使用**宿主那份 React**（hooks 才能正常工作）；自己 bundle 一份会导致 Invalid hook call。
 *  3. 插件被强制降级为 process 时，`HostSharedDeps` 不存在 → activate 里显式抛错，
 *     而不是静默失败（否则用户只看到「什么都没发生」）。
 *  4. 扩展点 id 必须与后端 `whiteboard.draw` 里写入的 `teacherWidgetId` / `studentWidgetId` 完全一致。
 */

type PluginCtx = {
  pluginId: string;
  invokeCommand: (type: string, payload?: Record<string, unknown>) => Promise<any>;
  ui: {
    registerExtensionPoint: (slot: string, config: Record<string, unknown>) => void;
    unregisterExtensionPoint: (slot: string, id: string) => void;
  };
  log?: { info: (m: string, meta?: Record<string, unknown>) => void };
};

const TEACHER_WIDGET_ID = '{{commandPrefix}}-teacher';
const STUDENT_WIDGET_ID = '{{commandPrefix}}-student';

let R: any = null;          // 宿主 React
let ctxRef: PluginCtx | null = null;

const h = (type: any, props?: any, ...children: any[]) => R.createElement(type, props, ...children);

/** 轮询便签列表：沙箱内无法接收宿主推送，inline 也建议保持一致写法 */
function useNotes(lessonId: string | undefined) {
  const [notes, setNotes] = R.useState([] as Array<{ id: string; text: string; author: string }>);
  const [error, setError] = R.useState(null as string | null);

  const load = () => {
    if (!lessonId || !ctxRef) return;
    ctxRef
      .invokeCommand('list_notes', { lessonId })
      .then((res) => {
        setNotes(Array.isArray(res?.notes) ? res.notes : []);
        setError(null);
      })
      .catch((e: any) => setError(String(e?.message ?? e)));
  };

  R.useEffect(() => {
    if (!lessonId) return;
    load();
    const timer = setInterval(load, 3000);
    return () => clearInterval(timer);
  }, [lessonId]);

  return { notes, error, reload: load };
}

function NoteBoard(props: { lessonId?: string; title: string; allowAnonymous?: boolean }) {
  const { lessonId, title, allowAnonymous } = props;
  const { notes, error, reload } = useNotes(lessonId);
  const [text, setText] = R.useState('');
  const [anonymous, setAnonymous] = R.useState(false);
  const [busy, setBusy] = R.useState(false);

  const submit = () => {
    if (!lessonId || !text.trim() || busy) return;
    setBusy(true);
    ctxRef
      ?.invokeCommand('add_note', { lessonId, text: text.trim(), anonymous: allowAnonymous ? anonymous : false })
      .then(() => {
        setText('');
        reload();
      })
      .finally(() => setBusy(false));
  };

  return h(
    'div',
    { style: { fontFamily: 'system-ui, sans-serif', fontSize: 13, padding: 8, height: '100%', overflow: 'auto' } },
    h('div', { style: { fontWeight: 600, marginBottom: 6 } }, title),
    error ? h('div', { style: { color: '#b91c1c', marginBottom: 6 } }, `加载失败：${error}`) : null,
    h(
      'div',
      { style: { display: 'flex', gap: 6, marginBottom: 8 } },
      h('input', {
        value: text,
        placeholder: '写一条便签…',
        onChange: (e: any) => setText(e.target.value),
        onKeyDown: (e: any) => { if (e.key === 'Enter') submit(); },
        style: { flex: 1, border: '1px solid #d1d5db', borderRadius: 6, padding: '4px 8px' },
      }),
      allowAnonymous
        ? h(
            'label',
            { style: { display: 'flex', alignItems: 'center', gap: 4, whiteSpace: 'nowrap' } },
            h('input', { type: 'checkbox', checked: anonymous, onChange: (e: any) => setAnonymous(e.target.checked) }),
            '匿名',
          )
        : null,
      h(
        'button',
        {
          onClick: submit,
          disabled: busy || !text.trim(),
          style: { border: '1px solid #6366f1', background: busy ? '#c7d2fe' : '#6366f1', color: '#fff', borderRadius: 6, padding: '4px 10px' },
        },
        busy ? '发送中…' : '贴上',
      ),
    ),
    notes.length === 0
      ? h('div', { style: { color: '#9ca3af' } }, '还没有便签，写下第一条吧')
      : h(
          'ul',
          { style: { listStyle: 'none', padding: 0, margin: 0, display: 'grid', gap: 6 } },
          ...notes.map((n: { id: string; text: string; author: string }) =>
            h(
              'li',
              { key: n.id, style: { background: '#fef9c3', border: '1px solid #fde68a', borderRadius: 6, padding: '6px 8px' } },
              h('div', { style: { whiteSpace: 'pre-wrap' } }, n.text),
              h('div', { style: { color: '#a16207', fontSize: 11, marginTop: 2 } }, n.author),
            ),
          ),
        ),
  );
}

/** 教师视角：白板卡片（id 与后端 teacherWidgetId 一致） */
function TeacherWidget(props: { lessonId?: string }) {
  return h(NoteBoard, { lessonId: props.lessonId, title: '便签板（教师）', allowAnonymous: true });
}

/** 学生视角：白板卡片（id 与后端 studentWidgetId 一致） */
function StudentWidget(props: { lessonId?: string }) {
  return h(NoteBoard, { lessonId: props.lessonId, title: '便签板', allowAnonymous: true });
}

export default {
  async activate(ctx: PluginCtx) {
    R = (globalThis as any).HostSharedDeps?.React;
    if (!R) {
      throw new Error(
        'HostSharedDeps.React 不可用：本插件需要以 inline（进程内）模式运行。' +
          '请把 manifest.id 加进宿主 OPENLEARN_TRUSTED_INLINE_PLUGINS 并重启，再重新安装/切换隔离档位。',
      );
    }
    ctxRef = ctx;

    ctx.ui.registerExtensionPoint('teacher.dashboard.widget', { id: TEACHER_WIDGET_ID, component: TeacherWidget });
    ctx.ui.registerExtensionPoint('student.view', { id: STUDENT_WIDGET_ID, component: StudentWidget });

    ctx.log?.info('inline-react frontend activated', { teacher: TEACHER_WIDGET_ID, student: STUDENT_WIDGET_ID });
  },

  async deactivate(ctx: PluginCtx) {
    ctx.ui.unregisterExtensionPoint('teacher.dashboard.widget', TEACHER_WIDGET_ID);
    ctx.ui.unregisterExtensionPoint('student.view', STUDENT_WIDGET_ID);
    ctxRef = null;
  },
};
