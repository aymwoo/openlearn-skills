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
  while IFS= read -r f; do substitute "$f"; done < <(find "$dir" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.json' \))
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
  for code in VIEW_PATH_UNSAFE VIEW_NOT_IN_STORAGE VIEW_FILE_MISSING VIEW_BRIDGE_MISSING VIEW_PACK_HINT; do
    if grep -q "\[$code\]" <<<"$out"; then ok "命中 $code"; else bad "漏报 $code"; fi
  done
fi

# ── 4. L1/L2 骨架自检（不联网） ─────────────────────────────────────────────
head "4. L1/L2 用例文件自检"
for f in contract.test.ts smoke.test.ts vitest.config.ts README.md; do
  if [[ -s "$SKILL_DIR/assets/test-harness/$f" ]]; then ok "$f 存在且非空"; else bad "$f 缺失或为空"; fi
done
grep -q 'REAL_CAPS' "$SKILL_DIR/assets/test-harness/contract.test.ts" && ok "契约测试含权限全集断言" || bad "契约测试缺权限全集断言"
grep -q 'TypeError|ReferenceError' "$SKILL_DIR/assets/test-harness/smoke.test.ts" && ok "冒烟测试含崩溃分类断言" || bad "冒烟测试缺崩溃分类断言"
grep -q 'inline' "$SKILL_DIR/assets/test-harness/vitest.config.ts" && ok "vitest 配置含 test-kit inline 兜底" || bad "vitest 配置缺 inline 兜底"
grep -q 'whiteboardWidget' "$SKILL_DIR/assets/test-harness/smoke.test.ts" && ok "冒烟测试含白板挂件下发断言" || bad "冒烟测试缺白板挂件断言"
[[ -s "$SKILL_DIR/assets/test-harness/slot-registry.json" ]] && ok "槽位注册表存在" || bad "槽位注册表缺失"

printf '\n\033[1m结果\033[0m：通过 %d，失败 %d\n' "$PASS" "$FAIL"
printf '提示：L1/L2 端到端验证需在临时插件里 npm i -D vitest @openlearn/plugin-test-kit better-sqlite3 uuid zod 后按 README 运行。\n'
[[ "$FAIL" -eq 0 ]]
