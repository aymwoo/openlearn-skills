/**
 * 打包脚本：把 storage/** 补进官方 CLI 产出的 ZIP。
 *
 * 为什么需要：`npx @openlearn/plugin-sdk build` 只打 manifest.json / index.js / frontend.js，
 * storage/**（view 页面与其静态资源）不会进包 → 安装后 /plugins/<id>/storage/xxx.html 404，
 * 用户看到「插件面板空白 / 正在加载…」，而构建阶段完全没有任何报错。
 *
 * 用法：npm run pack   →  生成 <name>.zip（含 storage/**）
 */
import { execSync } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import JSZip from 'jszip';

execSync('npx @openlearn/plugin-sdk build', { stdio: 'inherit' });

const zipName = readdirSync('.').find((f) => f.endsWith('.zip'));
if (!zipName) {
  console.error('✖ 未找到 CLI 产出的 .zip，先确认 build 成功');
  process.exit(1);
}

const walk = (dir, base = '') =>
  readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p, `${base}${name}/`) : [`${base}${name}`];
  });

const zip = await JSZip.loadAsync(readFileSync(zipName));
for (const rel of walk('storage')) {
  zip.file(rel, readFileSync(join('storage', rel)));
}
writeFileSync(zipName, await zip.generateAsync({ type: 'nodebuffer' }));

const entries = Object.keys(zip.files).filter((f) => !zip.files[f].dir);
console.log(`✔ 已重打包 ${zipName}（${entries.length} 个文件，含 storage/**）`);
