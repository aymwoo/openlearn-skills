#!/usr/bin/env bash
# verify-templates-build.sh —— 三套模板的真实构建 / 类型 / manifest 校验
#
# 支持两种 SDK 来源（按优先级自动探测）：
#   ① npm 安装的 @openlearn/plugin-sdk（CI 用）：$SKILL_ROOT/node_modules/@openlearn/plugin-sdk
#   ② 本地平台仓库：$PLATFORM_REPO/packages/plugin-sdk
#
# 用法：
#   bash scripts/verify-templates-build.sh [skill-root]
#   PLATFORM_REPO=/path/to/openlearnv2 bash scripts/verify-templates-build.sh
#   SDK_DIR=/path/to/plugin-sdk bash scripts/verify-templates-build.sh
#
# 退出码：0 = 全部通过；1 = 有失败项；2 = 环境不满足（找不到 SDK，已跳过）

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PLATFORM="${PLATFORM_REPO:-$HOME/Develop/openlearnv2}"

cd "$ROOT" || exit 1

# ── 解析 SDK 与 tsc ───────────────────────────────────────────────────────
SDK_DIR=""
if [ -n "${SDK_DIR:-}" ] && [ -f "${SDK_DIR}/cli.mjs" ]; then
  SDK_DIR="${SDK_DIR}"
elif [ -f "$ROOT/node_modules/@openlearn/plugin-sdk/cli.mjs" ]; then
  SDK_DIR="$ROOT/node_modules/@openlearn/plugin-sdk"
elif [ -f "$PLATFORM/packages/plugin-sdk/cli.mjs" ]; then
  SDK_DIR="$PLATFORM/packages/plugin-sdk"
fi

CLI="$SDK_DIR/cli.mjs"

TSC=""
for cand in "$ROOT/node_modules/.bin/tsc" "$PLATFORM/node_modules/.bin/tsc"; do
  [ -x "$cand" ] && { TSC="$cand"; break; }
done

if [ -z "$SDK_DIR" ] || [ -z "$TSC" ]; then
  printf '\033[33m⚠ 跳过\033[0m 环境不满足（需要 @openlearn/plugin-sdk 与 typescript）\n'
  printf '  · SDK_DIR=%s\n' "${SDK_DIR:-<未找到>}"
  printf '  · tsc=%s\n' "${TSC:-<未找到>}"
  printf '  CI 中通过 `npm i --no-save @openlearn/plugin-sdk@latest typescript@~5.8.0` 安装。\n'
  exit 2
fi

printf '\033[1mSDK\033[0m %s\n' "$SDK_DIR"
printf '\033[1mtsc\033[0m %s\n\n' "$TSC"

PASS=0
FAIL=0
ok()  { printf '  \033[32m✔\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31m✘\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

substitute() {
  python3 -c "
import pathlib
vals = {'name':'demo-x','pluginId':'@demo/demo-x','pluginName':'Demo X',
        'description':'demo','author':'demo','sdkVersion':'3.7.1',
        'commandPrefix':'demox','toolId':'demo-tool','toolName':'Demo Tool','tabId':'demo-tab'}
for p in pathlib.Path('.').rglob('*'):
    if p.is_file() and p.suffix in {'.ts','.tsx','.json'}:
        t = p.read_text()
        for k, v in vals.items():
            t = t.replace('{{' + k + '}}', v)
        p.write_text(t)
"
}

for tpl in server-only full-stack frontend-only; do
  printf '\033[1m%s\033[0m\n' "$tpl"

  TMP=$(mktemp -d)
  cp -r "$ROOT/assets/$tpl/." "$TMP/"
  cd "$TMP" || continue
  substitute

  # 1) 构建
  if node "$CLI" build >/tmp/build-$tpl.log 2>&1; then
    ok "官方 CLI 构建成功"
  else
    bad "构建失败："; tail -8 /tmp/build-$tpl.log | sed 's/^/      /'
    cd "$ROOT"; rm -rf "$TMP"; continue
  fi

  ZIP=$(ls ./*.zip 2>/dev/null | head -1)
  if [ -n "$ZIP" ]; then ok "产出 ZIP：$(basename "$ZIP")"; else bad "未产出 ZIP"; fi

  rm -rf out && unzip -o -q "$ZIP" -d out

  # 2) manifest 关键字段
  if python3 - <<'PY'
import json
m = json.load(open('out/manifest.json'))
assert m.get('main'), 'main missing'
assert m.get('engines', {}).get('openlearn') == '>=0.2.5', 'engines wrong'
print('ok')
PY
  then ok "manifest.json 含 main / engines.openlearn"; else bad "manifest.json 字段不合规"; fi

  # 3) 产物体检
  if grep -qE '^import .+ from "[^@./]' out/index.js; then
    bad "index.js 存在非法裸导入"; grep -E '^import .+ from "[^@./]' out/index.js | head -3 | sed 's/^/      /'
  else ok "index.js 无非法裸导入"; fi

  if [ -f out/frontend.js ]; then
    if grep -qE "from ['\"]react|ReactDOM" out/frontend.js; then
      bad "frontend.js 引用了 React（远程插件会激活失败）"
    else ok "frontend.js 无 React 引用"; fi
  fi

  # 4) 类型检查
  mkdir -p node_modules/@openlearn
  ln -sfn "$SDK_DIR" node_modules/@openlearn/plugin-sdk
  if out=$("$TSC" --noEmit -p tsconfig.json 2>&1); then
    ok "tsc --noEmit 通过（SDK 类型）"
  else
    bad "tsc 报错："; echo "$out" | head -8 | sed 's/^/      /'
  fi

  cd "$ROOT"
  rm -rf "$TMP"
done

printf '\n\033[1m结果\033[0m：通过 %d，失败 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
