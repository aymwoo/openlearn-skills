// frontend.tsx — {{pluginName}} 纯前端组件
import React, { useState } from 'react';
import ReactDOM from 'react-dom';

let ctx: any = null;

// 浮层/弹窗组件：通过 Portal 挂载到 document.body 防止挤压白板工具栏
function FloatingToolModal({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  if (!isOpen) return null;

  return ReactDOM.createPortal(
    React.createElement('div', {
      style: {
        position: 'fixed',
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
        width: 360,
        backgroundColor: '#ffffff',
        boxShadow: '0 20px 40px rgba(0,0,0,0.2)',
        borderRadius: 12,
        padding: 24,
        zIndex: 9999,
      }
    },
      React.createElement('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center' } },
        React.createElement('h3', { style: { margin: 0, fontSize: 18 } }, '{{pluginName}}'),
        React.createElement('button', { onClick: onClose, style: { border: 'none', background: 'transparent', cursor: 'pointer', fontSize: 16 } }, '✕')
      ),
      React.createElement('p', { style: { marginTop: 12, color: '#4b5563' } }, '纯前端课堂互动小工具'),
    ),
    document.body
  );
}

// 课堂工具架图标按钮组件
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
        backgroundColor: isOpen ? '#2563eb' : '#e5e7eb',
        color: isOpen ? '#ffffff' : '#1f2937',
        cursor: 'pointer',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      },
      title: '{{pluginName}}'
    }, '🛠️'),
    React.createElement(FloatingToolModal, {
      isOpen: isOpen,
      onClose: () => setIsOpen(false)
    })
  );
}

// 教师管理 Tab 页组件
function MainPanel() {
  const [count, setCount] = useState(0);

  return React.createElement('div', { style: { padding: 24 } },
    React.createElement('h2', null, '{{pluginName}}'),
    React.createElement('p', null, `状态计数器: ${count}`),
    React.createElement('button', {
      onClick: () => setCount(c => c + 1),
      style: { padding: '8px 16px', borderRadius: 6, border: '1px solid #d1d5db', cursor: 'pointer' }
    }, '增加计数')
  );
}

async function activate(hostCtx: any) {
  ctx = hostCtx;

  // 1. 注册侧边栏管理页
  hostCtx.ui.registerExtensionPoint('teacher.tab', {
    id: '{{tabId}}',
    label: '{{pluginName}}',
    icon: 'Layout',
    component: MainPanel,
    position: 10,
  });

  // 2. 注册课堂工具架按钮
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

