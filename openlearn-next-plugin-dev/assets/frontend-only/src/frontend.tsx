// frontend.tsx — {{pluginName}} 纯前端组件
// 注意：React 由 window.HostSharedDeps.React 提供
// JSX 必须使用经典转换模式

let ctx: any = null;

function MainPanel() {
  const [count, setCount] = React.useState(0);

  return React.createElement('div', { style: { padding: 16 } },
    React.createElement('h2', null, '{{pluginName}}'),
    React.createElement('p', null, `计数器: ${count}`),
    React.createElement('button', {
      onClick: () => setCount(c => c + 1),
      style: { padding: '8px 16px', fontSize: '16px' }
    }, '+1')
  );
}

async function activate(hostCtx: any) {
  ctx = hostCtx;

  hostCtx.ui.registerExtensionPoint('teacher.tab', {
    id: '{{tabId}}',
    label: '{{pluginName}}',
    icon: 'Layout',
    component: MainPanel,
    position: 10,
  });
}

function deactivate() {}

export default { activate, deactivate };
