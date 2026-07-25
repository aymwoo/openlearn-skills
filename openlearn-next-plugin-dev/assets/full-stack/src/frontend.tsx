// frontend.tsx — {{pluginName}} 前端组件
import React, { useState, useEffect } from 'react';

let ctx: any = null;

// 组件必须用普通 function 声明，不能用箭头函数
// 原因：esbuild 打包箭头函数时可能改变闭包作用域
function MainPanel() {
  const [data, setData] = React.useState([]);

  React.useEffect(() => {
    ctx.invokeCommand('{{commandPrefix}}.list').then(setData);
  }, []);

  return React.createElement('div', { style: { padding: 16 } },
    React.createElement('h2', null, '{{pluginName}}'),
    React.createElement('p', null, '这是一个全栈插件示例'),
    React.createElement('ul', null,
      data.map((item: any) =>
        React.createElement('li', { key: item.id }, item.name || item.id)
      )
    )
  );
}

async function activate(hostCtx: any) {
  ctx = hostCtx;

  // 注册教师标签页
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
