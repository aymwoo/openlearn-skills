#!/usr/bin/env bash
# verify-test-harness.sh —— 维护本 skill 时校验测试护栏自身是否有效
#
# 做三件事：
#   1. assets/test-harness/static-check.mjs 语法检查
#   2. 正例：三套模板替换占位符后，L0 必须 0 error
#   3. 反例：手写一个含已知缺陷的插件，L0 必须非零退出且报出预期错误码
#
# 说明：L1/L2（vitest）需要 npm 依赖（vitest / plugin-test-kit / better-sqlite3 / uuid / zod），
#       本脚本不做网络安装；如需端到端验证，按 README 在临时项目里跑一次。
#
# 用法：bash scripts/verify-test-harness.sh
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$SKILL_DIR/assets/test-harness/static-check.mjs"
TMP="$(mktemp -d)"
PASS=0
FAIL=0
trap 'rm -rf "$TMP"' EXIT

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31m✖\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
head() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ── 1. 语法 ────────────────────────────────────────────────────────────────
head "1. static-check.mjs 语法"
if node --check "$CHECKER" 2>/dev/null; then ok "node --check 通过"; else bad "node --check 失败"; fi

# ── 2. 正例：三套模板 ──────────────────────────────────────────────────────
head "2. 正例：模板替换占位符后 L0 应 0 error"
substitute() {
  local f="$1"
  sed -i \
    -e 's/{{pluginId}}/@demo\/probe/g' \
    -e 's/{{pluginName}}/Probe/g' \
    -e 's/{{description}}/probe/g' \
    -e 's/{{author}}/tester/g' \
    -e 's/{{commandPrefix}}/probe/g' \
    -e 's/{{toolId}}/probe-tool/g' \
    -e 's/{{toolName}}/Probe Tool/g' \
    -e 's/{{tabId}}/probe-tab/g' \
    -e 's/{{name}}/probe/g' \
    -e 's/{{sdkVersion}}/3.7.4/g' \
    "$f"
}

for tpl in server-only full-stack frontend-only inline-react sandbox-view; do
  dir="$TMP/$tpl"
  cp -r "$SKILL_DIR/assets/$tpl" "$dir"
  # 用管道而非进程替换 <(...)：受限环境（容器/沙箱不提供 /dev/fd）下进程替换会静默失败，
  # 导致占位符没被替换却继续跑校验，得到「假失败」或「假通过」。
  find "$dir" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.json' \) -print0 \
    | while IFS= read -r -d '' f; do substitute "$f"; done
  # inline 模板需要在白名单环境里校验；其他模板不受影响
  if out=$(OPENLEARN_TRUSTED_INLINE_PLUGINS='@demo/*' node "$CHECKER" "$dir" 2>&1) && ! grep -q '✖' <<<"$out"; then
    ok "$tpl：L0 通过"
  else
    bad "$tpl：L0 报错"
    grep '✖' <<<"$out" | sed 's/^/      /'
  fi
done

# ── 3. 反例：已知缺陷插件必须被抓到 ────────────────────────────────────────
head "3. 反例：含已知缺陷的插件必须报错"
BAD="$TMP/bad-plugin"
mkdir -p "$BAD/src"
cat > "$BAD/src/index.ts" <<'EOF'
import { exec } from 'child_process';
const KEY = 'sk-abcdefghijklmnopqrstuvwxyz123456';
export default {
  manifest: {
    id: '@demo/bad:plugin',
    name: 'Bad',
    version: '0.1.0',
    engines: {},
    capabilitiesProposed: ['user:read'],
    classroomTools: [{ id: 'open', name: 'Open', commandType: 'bad.open' }],
  },
  async activate(ctx: any) {
    await ctx.services.actionRegistry.register({ id: 'bad-1', commandType: 'bad.thing', description: 'x' });
    ctx.services.commandBus.registerHandler('bad.other', { execute: async () => ({}) });
    await ctx.db.ensureTable('bad-name', 'id TEXT; DROP TABLE x');
    ctx.db.migrate(2, async () => {});
    ctx.db.prepare('select 1');
  },
};
EOF
cat > "$BAD/src/frontend.tsx" <<'EOF'
import React from 'react';
export const A = () => { document.title = 'x'; return null; };
EOF

if out=$(node "$CHECKER" "$BAD" 2>&1); then
  bad "反例未被拦截（退出码 0）"
else
  ok "反例被拦截（非零退出）"
  for code in MANIFEST_MAIN MANIFEST_ID_COLON ENGINES_MISSING CAP_UNKNOWN PAIR_HANDLER_MISSING \
              PAIR_ACTION_MISSING ACTION_CAP_MISSING PROCESS_FORBIDDEN_API FRONTEND_REACT \
              FRONTEND_DOM DB_TABLE_NAME DB_SCHEMA_SEMICOLON DB_NO_PREPARE SECRET_LEAK; do
    if grep -q "\[$code\]" <<<"$out"; then ok "命中 $code"; else bad "漏报 $code"; fi
  done
fi

# ── 3b. 反例：UI 通道错配必须被抓到 ─────────────────────────────────────────
head "3b. 反例：process 下想上 React UI / 白板挂件未闭环"
UI_BAD="$TMP/ui-bad"
mkdir -p "$UI_BAD/src"
cat > "$UI_BAD/plugin.contract.json" <<'JSON'
{
  "executionMode": "process",
  "uiChannel": "inline-react",
  "studentVisible": true,
  "whiteboardWidget": true,
  "slots": ["teacher.tab", "classroom.float"]
}
JSON
cat > "$UI_BAD/src/index.ts" <<'TS'
export default {
  manifest: {
    id: '@demo/ui-bad', name: 'Bad', version: '0.1.0', main: 'index.js',
    engines: { openlearn: '>=0.7.0' }, capabilitiesProposed: ['lesson:read'],
    contributes: { 'teacher.tab': [{ id: 'b', label: 'B' }] },
  },
  async activate(ctx: any) {
    await ctx.services.actionRegistry.register({ id: 'b-open', commandType: 'bad.open', description: '打开面板', capabilityRequired: 'lesson:read', inputSchema: { type: 'OBJECT', properties: {} } });
    await ctx.services.commandBus.registerHandler('bad.open', { async execute() { return { opened: true }; } });
  },
};
TS
cat > "$UI_BAD/src/frontend.tsx" <<'TSX'
function Panel() { return null; }
export default { activate(ctx: any) { ctx.ui.registerExtensionPoint('teacher.tab', { id: 'b', component: Panel }); } };
TSX
if out=$(node "$CHECKER" "$UI_BAD" 2>&1); then
  bad "UI 反例未被拦截（退出码 0）"
else
  ok "UI 反例被拦截（非零退出）"
  for code in UI_MODE_MISMATCH CONTRACT_MODE_CONFLICT WHITEBOARD_WIDGET_NEEDS_INLINE \
              WHITEBOARD_DRAW_MISSING WHITEBOARD_WIDGET_ID_MISSING WHITEBOARD_CAP_MISSING \
              STUDENT_ENTRY_MISSING STUDENT_WIDGET_SLOT_MISSING SLOT_UNKNOWN; do
    if grep -q "\[$code\]" <<<"$out"; then ok "命中 $code"; else bad "漏报 $code"; fi
  done
fi

# ── 3c. 反例：view（沙箱 HTML）配置错必须被抓到 ────────────────────────────
head "3c. 反例：view 路径非法 / 文件缺失 / 漏桥接脚本"
VIEW_BAD="$TMP/view-bad"
mkdir -p "$VIEW_BAD/src" "$VIEW_BAD/storage"
cat > "$VIEW_BAD/plugin.contract.json" <<'JSON'
{
  "executionMode": "process",
  "uiChannel": "sandbox-view",
  "studentVisible": true,
  "whiteboardWidget": false,
  "slots": ["student.view"],
  "viewFiles": ["../etc/passwd", "views/legacy.html", "storage/missing.html"]
}
JSON
cat > "$VIEW_BAD/src/index.ts" <<'TS'
export default {
  manifest: {
    id: '@demo/view-bad', name: 'VB', version: '0.1.0', main: 'index.js',
    engines: { openlearn: '>=0.7.6' }, capabilitiesProposed: [],
    contributes: { 'student.view': [{ id: 'vb', label: 'VB', view: 'storage/nobridge.html' }] },
  },
  async activate() {},
};
TS
printf '<!doctype html><html><body>no bridge</body></html>' > "$VIEW_BAD/storage/nobridge.html"
mkdir -p "$VIEW_BAD/views" && printf '<!doctype html><html></html>' > "$VIEW_BAD/views/legacy.html"

if out=$(node "$CHECKER" "$VIEW_BAD" 2>&1); then
  bad "view 反例未被拦截（退出码 0）"
else
  ok "view 反例被拦截（非零退出）"
  for code in VIEW_PATH_UNSAFE VIEW_NOT_IN_STORAGE VIEW_FILE_MISSING VIEW_BRIDGE_MISSING VIEW_PACK_HINT FRONTEND_ENTRY_MISSING; do
    if grep -q "\[$code\]" <<<"$out"; then ok "命中 $code"; else bad "漏报 $code"; fi
  done
fi

# ── 3d. 反例：路由未注册 / SQL 守卫 / view 运行时 ───────────────────────────
head "3d. 反例：路由配对 / SQL 守卫 / view 运行时"
RUNTIME_BAD="$TMP/runtime-bad"
mkdir -p "$RUNTIME_BAD/src" "$RUNTIME_BAD/storage"
cat > "$RUNTIME_BAD/manifest.json" <<'JSON'
{
  "id": "@demo/runtime-bad", "name": "RB", "version": "0.1.0", "main": "index.js",
  "engines": { "openlearn": ">=0.7.6" },
  "api": { "routes": [{ "method": "GET", "path": "/declared", "roles": ["teacher"] }] },
  "contributes": { "teacher.tab": [{ "id": "rb", "label": "RB", "view": "storage/page.html" }] }
}
JSON
cat > "$RUNTIME_BAD/src/index.ts" <<'TS'
ctx.http.post('/declared', h);
const q1 = `SELECT * FROM users WHERE id = 1`;
const q2 = `PRAGMA table_info(x)`;
const q3 = `CREATE TABLE foo (id TEXT)`;
const q4 = `SELECT * FROM ${t} WHERE a = 1`;
TS
cat > "$RUNTIME_BAD/storage/page.html" <<'HTML'
<script src="/plugin-sandbox/view-bridge.js"></script>
<script>
  alert('x');
  fetch('/api/x');
  const r = await api.get('state');
  r.result.a;
</script>
HTML

if out=$(node "$CHECKER" "$RUNTIME_BAD" 2>&1); then
  bad "runtime 反例未被拦截（退出码 0）"
else
  ok "runtime 反例被拦截（非零退出）"
  for code in ROUTE_UNREGISTERED ROUTE_UNDECLARED SQL_CORE_TABLE SQL_FORBIDDEN_OP \
              SQL_DDL_BYPASS VIEW_ALERT_BLOCKED VIEW_DIRECT_FETCH VIEW_RESIZE_MISSING \
              VIEW_API_RESULT_UNWRAP; do
    if grep -q "\[$code\]" <<<"$out"; then ok "命中 $code"; else bad "漏报 $code"; fi
  done
  # 动态表名（${t}）不能被误报为「非插件前缀表」
  if grep -q "SQL_TABLE_NOT_PREFIXED" <<<"$out"; then bad "误报 SQL_TABLE_NOT_PREFIXED（模板拼接表名不应算字面量表名）"; else ok "模板拼接表名未误报"; fi
fi

# ── 3e. @openlearn/* 是合法外部化，只有其它裸说明符才算裸导入 ────────────────
head "3e. @openlearn/* 外部化 vs 其它裸导入"
SDK_OK="$TMP/sdk-ok"; SDK_BAD="$TMP/sdk-bad"
for d in "$SDK_OK" "$SDK_BAD"; do
  mkdir -p "$d/src" "$d/dist"
  cat > "$d/manifest.json" <<'JSON'
{ "id": "@demo/sdk-import", "name": "SDK", "version": "0.1.0", "main": "index.js", "engines": { "openlearn": ">=0.7.6" }, "capabilitiesProposed": ["lesson:read"] }
JSON
  printf 'export function activate(ctx) {}\nexport function deactivate() {}\n' > "$d/src/index.ts"
done
printf 'import { IDatabaseToken } from "@openlearn/plugin-sdk";\nexport function activate(ctx) { ctx.resolve(IDatabaseToken); }\nexport function deactivate() {}\n' > "$SDK_OK/dist/index.js"
printf 'import fs from "fs";\nexport function activate(ctx) {}\nexport function deactivate() {}\n' > "$SDK_BAD/dist/index.js"

out=$(node "$CHECKER" "$SDK_OK" 2>&1 || true)
if grep -q "\[DIST_BARE_IMPORT\]" <<<"$out"; then bad "@openlearn/* 被误报为裸导入"; else ok "@openlearn/* 未误报为裸导入"; fi
out=$(node "$CHECKER" "$SDK_BAD" 2>&1 || true)
if grep -q "\[DIST_BARE_IMPORT\]" <<<"$out"; then ok "其它裸说明符（fs）仍被抓到"; else bad "其它裸说明符漏报"; fi

# ── 3f. 一键脚手架：生成 sandbox-view 后占位符清零、L0 0 error ─────────────
head "3f. 一键脚手架（new-plugin.sh）"
GEN="$TMP/gen-sandbox-view"
if bash "$SKILL_DIR/scripts/new-plugin.sh" sandbox-view "$GEN" \
    --id @demo/gen-sandbox-view --name "Gen Demo" --prefix gen --description "generator test" --author tester \
    >/tmp/new-plugin.log 2>&1; then
  ok "生成 sandbox-view 成功"
else
  bad "生成失败："; tail -5 /tmp/new-plugin.log | sed 's/^/      /'
fi
if grep -rq '{{' "$GEN" --include='*.ts' --include='*.tsx' --include='*.html' --include='*.json' --include='*.mjs' 2>/dev/null; then
  bad "生成物仍有未替换占位符"
else
  ok "占位符已全部替换"
fi
if node "$CHECKER" "$GEN" >/tmp/gen-l0.log 2>&1; then
  ok "生成物通过 L0（0 error）"
else
  bad "生成物 L0 未通过："; tail -8 /tmp/gen-l0.log | sed 's/^/      /'
fi

# ── 3g. 反例：隔离模式空能力清单 + 非 get RPC（Barrier 2）──────────────────
head "3g. 反例：空 capabilitiesProposed 但 activate 调用非 get RPC"
CAP_BAD="$TMP/cap-bad"
mkdir -p "$CAP_BAD/src"
cat > "$CAP_BAD/src/index.ts" <<'TS'
export default {
  manifest: {
    id: '@demo/cap-bad', name: 'CB', version: '0.1.0', main: 'index.js',
    engines: { openlearn: '>=0.7.6' },
    api: { routes: [{ method: 'GET', path: '/state', roles: ['teacher'] }] },
  },
  async activate(ctx: any) {
    await ctx.db.ensureTable('notes', 'id TEXT PRIMARY KEY, text TEXT');
    ctx.http.get('/state', () => ({ ok: true }));
  },
};
TS
if out=$(node "$CHECKER" "$CAP_BAD" 2>&1); then
  bad "空能力反例未被拦截（退出码 0）"
else
  ok "空能力反例被拦截（非零退出）"
  if grep -q "\[CAP_EMPTY_ISOLATED\]" <<<"$out"; then ok "命中 CAP_EMPTY_ISOLATED"; else bad "漏报 CAP_EMPTY_ISOLATED"; fi
fi
sed -i "s/engines: { openlearn: '>=0.7.6' },/engines: { openlearn: '>=0.7.6' }, capabilitiesProposed: ['lesson:read'],/" "$CAP_BAD/src/index.ts"
out=$(node "$CHECKER" "$CAP_BAD" 2>&1 || true)
if grep -q "\[CAP_EMPTY_ISOLATED\]" <<<"$out"; then bad "补上能力后仍误报 CAP_EMPTY_ISOLATED"; else ok "补上能力后不再报"; fi

FE_EMPTY="$TMP/fe-empty"
mkdir -p "$FE_EMPTY/src"
cat > "$FE_EMPTY/src/index.ts" <<'TS'
export default {
  manifest: {
    id: '@demo/fe-empty', name: 'FE', version: '0.1.0', main: 'index.js',
    engines: { openlearn: '>=0.7.0' }, capabilitiesProposed: [],
  },
  async activate(ctx: any) { ctx.log?.info?.('pure frontend'); },
};
TS
out=$(node "$CHECKER" "$FE_EMPTY" 2>&1 || true)
if grep -q "\[CAP_EMPTY_ISOLATED\]" <<<"$out"; then bad "纯前端空能力被误报"; else ok "纯前端空能力（零服务调用）不误报"; fi

# ── 3h. 反例：中文字号 < 13px 必须被抓到 ────────────────────────────────────
head "3h. 反例：中文字号小于 13px（view / inline React）"
FONT_BAD="$TMP/font-bad"
mkdir -p "$FONT_BAD/src" "$FONT_BAD/storage"
cat > "$FONT_BAD/manifest.json" <<'JSON'
{
  "id": "@demo/font-bad", "name": "FB", "version": "0.1.0", "main": "index.js",
  "engines": { "openlearn": ">=0.7.6" },
  "contributes": { "teacher.tab": [{ "id": "fb", "label": "FB", "view": "storage/page.html" }] }
}
JSON
cat > "$FONT_BAD/src/frontend.tsx" <<'TSX'
const label = { style: { fontSize: 12 } };
const cls = { className: 'text-xs' };
export default { async activate() {}, async deactivate() {} };
TSX
cat > "$FONT_BAD/storage/page.html" <<'HTML'
<!doctype html>
<html lang="zh-CN"><head><style>body { font: 12px/1.5 system-ui; }</style></head>
<body>
  <p>中文正文</p>
  <script src="/plugin-sandbox/view-bridge.js"></script>
  <script>window.OpenLearnPluginBridge.ui.resize(document.body.scrollHeight);</script>
</body></html>
HTML
if out=$(node "$CHECKER" "$FONT_BAD" 2>&1); then
  bad "字号反例未被拦截（退出码 0）"
else
  ok "字号反例被拦截（非零退出）"
  hits=$(grep -c "\[FONT_TOO_SMALL\]" <<<"$out" || true)
  if [[ "$hits" -ge 3 ]]; then ok "命中 3 处 FONT_TOO_SMALL（font 简写 / fontSize / text-xs）"; else bad "FONT_TOO_SMALL 只命中 $hits 处（期望 ≥3）"; fi
fi
# 同行 font-size-ok 注释必须能豁免；清掉 TS 里的两处后应完全静默
rm -f "$FONT_BAD/src/frontend.tsx"
sed -i 's|font: 12px/1.5 system-ui;|font: 12px/1.5 system-ui; /* font-size-ok: 图标页 */|' "$FONT_BAD/storage/page.html"
out=$(node "$CHECKER" "$FONT_BAD" 2>&1 || true)
if grep -q "\[FONT_TOO_SMALL\]" <<<"$out"; then bad "font-size-ok 豁免失效"; else ok "font-size-ok 豁免生效"; fi

# ── 4. L1/L2 骨架自检（不联网） ─────────────────────────────────────────────
head "4. L1/L2 用例文件自检"
for f in contract.test.ts smoke.test.ts view-smoke.test.ts vitest.config.ts README.md; do
  if [[ -s "$SKILL_DIR/assets/test-harness/$f" ]]; then ok "$f 存在且非空"; else bad "$f 缺失或为空"; fi
done
grep -q 'OpenLearnPluginBridge' "$SKILL_DIR/assets/test-harness/view-smoke.test.ts" && ok "view 冒烟含桥接契约断言" || bad "view 冒烟缺桥接契约断言"
grep -q 'describe.skipIf' "$SKILL_DIR/assets/test-harness/view-smoke.test.ts" && ok "view 冒烟在缺少 jsdom 时可跳过" || bad "view 冒烟缺少 jsdom 缺失兜底"
grep -q 'REAL_CAPS' "$SKILL_DIR/assets/test-harness/contract.test.ts" && ok "契约测试含权限全集断言" || bad "契约测试缺权限全集断言"
grep -q 'Barrier 2' "$SKILL_DIR/assets/test-harness/contract.test.ts" && ok "契约测试含 Barrier 2 空能力断言" || bad "契约测试缺 Barrier 2 断言"
grep -q 'CAP_EMPTY_ISOLATED' "$SKILL_DIR/assets/test-harness/static-check.mjs" && ok "L0 含隔离模式能力门禁规则" || bad "L0 缺 CAP_EMPTY_ISOLATED"
grep -q 'FONT_TOO_SMALL' "$SKILL_DIR/assets/test-harness/static-check.mjs" && ok "L0 含中文字号下限规则" || bad "L0 缺 FONT_TOO_SMALL"
grep -q 'TypeError|ReferenceError' "$SKILL_DIR/assets/test-harness/smoke.test.ts" && ok "冒烟测试含崩溃分类断言" || bad "冒烟测试缺崩溃分类断言"
grep -q 'inline' "$SKILL_DIR/assets/test-harness/vitest.config.ts" && ok "vitest 配置含 test-kit inline 兜底" || bad "vitest 配置缺 inline 兜底"
grep -q 'whiteboardWidget' "$SKILL_DIR/assets/test-harness/smoke.test.ts" && ok "冒烟测试含白板挂件下发断言" || bad "冒烟测试缺白板挂件断言"
[[ -s "$SKILL_DIR/assets/test-harness/slot-registry.json" ]] && ok "槽位注册表存在" || bad "槽位注册表缺失"

printf '\n\033[1m结果\033[0m：通过 %d，失败 %d\n' "$PASS" "$FAIL"
printf '提示：L1/L2 端到端验证需在临时插件里 npm i -D vitest @openlearn/plugin-test-kit better-sqlite3 uuid zod 后按 README 运行。\n'
[[ "$FAIL" -eq 0 ]]
