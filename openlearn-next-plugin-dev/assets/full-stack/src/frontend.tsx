// frontend.tsx — {{pluginName}} 前端组件
import React, { useState, useEffect } from 'react';
import ReactDOM from 'react-dom';

let ctx: any = null;

// ============================================================
// 1. 独立浮层面板组件（使用 createPortal 挂载到 document.body，防挤压工具栏）
// ============================================================
function ToolOverlayPanel({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  if (!isOpen) return null;

  return ReactDOM.createPortal(
    React.createElement('div', {
      style: {
        position: 'fixed',
        top: 80,
        right: 20,
        width: 320,
        backgroundColor: '#ffffff',
        boxShadow: '0 10px 25px rgba(0,0,0,0.15)',
        borderRadius: 8,
        padding: 16,
        zIndex: 9999,
      }
    },
      React.createElement('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center' } },
        React.createElement('h3', { style: { margin: 0, fontSize: 16 } }, '{{pluginName}} 控制台'),
        React.createElement('button', { onClick: onClose, style: { border: 'none', background: 'transparent', cursor: 'pointer' } }, '✕')
      ),
      React.createElement('p', { style: { color: '#666', fontSize: 14, marginTop: 8 } }, '插件实时交互与控制面板'),
    ),
    document.body
  );
}

// ============================================================
// 2. 课堂工具栏按钮组件（在白板工具栏仅渲染纯粹的图标按钮）
// ============================================================
function ClassroomToolButton() {
  const [isOpen, setIsOpen] = useState(false);

  return React.createElement(React.Fragment, null,
    React.createElement('button', {
      onClick: () => setIsOpen(!isOpen),
      style: {
        width: 40,
        height: 40,
        borderRadius: '50%',
        border: 'none',
        backgroundColor: isOpen ? '#3b82f6' : '#f3f4f6',
        color: isOpen ? '#ffffff' : '#374151',
        cursor: 'pointer',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      },
      title: '{{pluginName}}'
    }, '🧩'),
    React.createElement(ToolOverlayPanel, {
      isOpen: isOpen,
      onClose: () => setIsOpen(false)
    })
  );
}

// ============================================================
// 3. 教师后台 Tab 管理页组件
// ============================================================
function MainTabPanel(props: { lessonId?: string }) {
  const [items, setItems] = useState<any[]>([]);

  useEffect(() => {
    // 示例：调用插件注册的后端 Command
    if (ctx) {
      ctx.invokeCommand('{{commandPrefix}}.list').then((res: any) => {
        if (Array.isArray(res)) setItems(res);
      }).catch(console.error);
    }
  }, [props.lessonId]);

  return React.createElement('div', { style: { padding: 24 } },
    React.createElement('h2', null, '{{pluginName}} - 管理面板'),
    React.createElement('p', null, '这是全栈插件的管理标签页，课程 ID: ' + (props.lessonId || '未指定')),
  );
}

async function activate(hostCtx: any) {
  ctx = hostCtx;

  // 注册 1：教师侧边栏标签页
  hostCtx.ui.registerExtensionPoint('teacher.tab', {
    id: '{{tabId}}',
    label: '{{pluginName}}',
    icon: 'Layout',
    component: MainTabPanel,
    position: 10,
  });

  // 注册 2：课堂白板工具栏按钮 (匹配 classroomTools 声明)
  hostCtx.ui.registerExtensionPoint('classroom.tool', {
    id: '{{toolId}}',
    name: '{{toolName}}',
    component: ClassroomToolButton,
  });
}

function deactivate() {
  ctx = null;
}

export default { activate, deactivate };

