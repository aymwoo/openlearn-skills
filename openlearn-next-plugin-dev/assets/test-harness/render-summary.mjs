#!/usr/bin/env node
/**
 * 把 `static-check.mjs --json` 的输出渲染成 GitHub Job Summary 的 Markdown 表格。
 *
 * 为什么单独一个脚本：把 JSON 转成可读报告的逻辑如果塞进 workflow 的 `run:` 里，
 * 会变成一大坨内联 YAML，难读也难测；独立脚本还能让插件作者在本地复现 CI 里
 * 看到的同一张表（`node render-summary.mjs report.json`）。
 *
 * 用法：
 *   node render-summary.mjs <report.json>            # 打到 stdout（本地预览）
 *   GITHUB_STEP_SUMMARY=... node render-summary.mjs   # 追加到 Job Summary
 *
 * 退出码：0 = 渲染成功（是否阻断由调用方按 fail-on 判定）；1 = 报告文件不可读。
 *
 * @module
 */
import { appendFileSync, readFileSync } from 'node:fs';

const reportPath = process.argv[2];
if (!reportPath) {
  console.error('用法: node render-summary.mjs <report.json>');
  process.exit(1);
}

let report;
try {
  report = JSON.parse(readFileSync(reportPath, 'utf-8'));
} catch (e) {
  console.error(`✖ 无法读取报告 ${reportPath}：${e.message}`);
  process.exit(1);
}

const errors = Array.isArray(report.errors) ? report.errors : [];
const warns = Array.isArray(report.warns) ? report.warns : [];
const oks = Array.isArray(report.ok) ? report.ok : [];

const esc = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
const cell = (s) => esc(s).slice(0, 300);

function table(title, rows) {
  if (!rows.length) return '';
  const lines = [
    `### ${title}（${rows.length}）`,
    '',
    '| 规则 | 文件 | 说明 |',
    '| --- | --- | --- |',
    ...rows.map((r) => `| \`${cell(r.code)}\` | ${cell(r.file || '-')} | ${cell(r.message)} |`),
    '',
  ];
  return lines.join('\n');
}

const out = [];
out.push(`## OpenLearn 插件 L0 契约静态检查`);
out.push('');
out.push(`- 插件目录：\`${cell(report.root)}\``);
out.push(`- **error ${errors.length}** · warn ${warns.length} · ok ${oks.length}`);
out.push('');

if (errors.length) {
  out.push(table('❌ 阻断项（error）', errors));
} else {
  out.push('### ✅ 无阻断项');
  out.push('');
}

if (warns.length) {
  out.push(table('⚠️ 提示项（warn）', warns));
}

if (errors.length === 0 && warns.length === 0) {
  out.push('全部检查通过。');
  out.push('');
}

const markdown = out.join('\n');

// 本地预览：没有 GITHUB_STEP_SUMMARY 就打到 stdout
if (process.env.GITHUB_STEP_SUMMARY) {
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, markdown);
} else {
  console.log(markdown);
}
