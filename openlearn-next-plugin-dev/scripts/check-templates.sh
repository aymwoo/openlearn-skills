#!/usr/bin/env bash
# check-templates.sh —— skill 自检：模板与文档一致性
#
# 用途：在修改 assets/ 模板或 SKILL.md 后跑一次，防止「模板与官方脚手架漂移」
#       这类问题再次静默发生（v1.x 的教训：模板缺 manifest.main、漏 ActionDescriptor、
#       沿用已废弃的 React 前端范式，都是靠人工 review 漏掉的）。
#
# 用法：bash scripts/check-templates.sh [skill-root]
# 退出码：0 = 全部通过；1 = 有失败项

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 1

PASS=0
FAIL=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ── 1. 模板必备字段 ────────────────────────────────────────────────────────
head_ "1. 模板必备字段（manifest.main / engines.openlearn）"

for tpl in server-only full-stack frontend-only; do
  idx="assets/$tpl/src/index.ts"
  [ -f "$idx" ] || { bad "$tpl: 缺少 src/index.ts"; continue; }

  if grep -qE "main: *'index\.js'" "$idx"; then
    ok "$tpl: manifest.main 已声明"
  else
    bad "$tpl: manifest.main 缺失（manifestSchema 中 main 为必填，缺失会导致插件装不上）"
  fi

  # engines 按「实际用到的 API 的最低宿主版本」填写（不是一律 >=0.2.5）
  case "$tpl" in
    server-only)   exp=">=0.2.5" ;;
    full-stack)    exp=">=0.7.0" ;;
    frontend-only) exp=">=0.7.0" ;;
    *)             exp="" ;;
  esac
  if [ -n "$exp" ] && grep -qE "engines: *\{ *openlearn: *'${exp}'" "$idx"; then
    ok "$tpl: engines.openlearn = '$exp'"
  else
    bad "$tpl: engines.openlearn 应为 '$exp'（按实际用到的 API 的最低宿主版本填写，详见 SKILL.md 第二步）"
  fi

  if grep -qE "sdkVersion" "assets/$tpl/package.json"; then
    ok "$tpl: package.json 使用 {{sdkVersion}} 占位（不写死 SDK 版本）"
  else
    bad "$tpl: package.json 未使用 {{sdkVersion}} 占位"
  fi
done

# ── 2. commandType ↔ ActionDescriptor 配对（内核 default-deny） ───────────
head_ "2. commandType ↔ ActionDescriptor 配对（default-deny）"

for tpl in server-only full-stack frontend-only; do
  idx="assets/$tpl/src/index.ts"
  [ -f "$idx" ] || continue

  # 取出所有 registerHandler 的 type
  handlers=$(grep -oE "registerHandler\('[^']+'" "$idx" | sed "s/registerHandler('//; s/'//" | sort -u)
  actions=$(grep -oE "commandType: *'[^']+'" "$idx" | sed "s/commandType: *'//; s/'//" | sort -u)

  if [ -z "$handlers" ]; then
    ok "$tpl: 未声明 commandType（无命令则无需 ActionDescriptor）"
    continue
  fi

  missing=""
  for h in $handlers; do
    echo "$actions" | grep -qxF "$h" || missing="$missing $h"
  done

  if [ -z "$missing" ]; then
    ok "$tpl: 每个 registerHandler 都有同名 ActionDescriptor"
  else
    bad "$tpl: 缺少 ActionDescriptor 的 commandType →$missing"
  fi
done

# ── 3. 远程前端不得使用 React / DOM ───────────────────────────────────────
head_ "3. 远程前端无 React / DOM（沙箱 iframe 内不存在 React 运行时）"

for tpl in full-stack frontend-only; do
  fe="assets/$tpl/src/frontend.tsx"
  [ -f "$fe" ] || { bad "$tpl: 缺少 src/frontend.tsx"; continue; }

  if grep -nE "from ['\"]react|ReactDOM|document\.|window\." "$fe" | grep -v "^\s*[0-9]*: *\*" | grep -qv "^\s*[0-9]*: *//"; then
    bad "$tpl: frontend.tsx 中出现 React / DOM 用法（远程插件必然激活失败）"
    grep -nE "from ['\"]react|ReactDOM|document\.|window\." "$fe" | head -5 | sed 's/^/      /'
  else
    ok "$tpl: frontend.tsx 干净（仅注释中提及 React）"
  fi

  if grep -q "export default { activate, deactivate }" "$fe"; then
    ok "$tpl: frontend.tsx 导出 { activate, deactivate }（宿主硬契约）"
  else
    bad "$tpl: frontend.tsx 未按契约导出 { activate, deactivate }"
  fi

  # 沙箱 iframe 的 CSP 是 connect-src 'none' —— 前端不得自行联网 / 用 socket
  if grep -nE "socket\.io-client|socket\.(on|off|emit)|[^a-zA-Z]fetch\(" "$fe" | grep -vE "^[0-9]+: *\*" >/dev/null; then
    bad "$tpl: frontend.tsx 出现 socket / fetch（沙箱 iframe CSP 为 connect-src 'none'，无法联网）"
    grep -nE "socket\.io-client|socket\.(on|off|emit)|[^a-zA-Z]fetch\(" "$fe" | head -5 | sed 's/^/      /'
  else
    ok "$tpl: frontend.tsx 无 socket / fetch（符合沙箱无网络约束）"
  fi
done

# ── 4. 跨插件服务契约（provides / contracts）─────────────────────────────
head_ "4. 跨插件服务契约（provides ↔ contracts）"

cs="assets/full-stack/src/contracts/index.ts"
if [ -f "$cs" ]; then
  ok "full-stack: 存在 src/contracts/index.ts"
  if grep -q "provides:" "assets/full-stack/src/index.ts"; then
    ok "full-stack: manifest 声明了 provides"
  else
    bad "full-stack: manifest 未声明 provides（contracts 中的 Token 需在 provides 声明，否则 ctx.provide() 抛错）"
  fi
else
  bad "full-stack: 缺少 src/contracts/index.ts（跨插件服务共享的契约目录）"
fi

# ── 5. 占位符与 SKILL.md 对齐 ─────────────────────────────────────────────
head_ "5. 占位符与 SKILL.md 对齐"

used=$(grep -rhoE '\{\{[a-zA-Z]+\}\}' assets/ | sort -u)
for p in $used; do
  if grep -qF "$p" SKILL.md; then
    ok "占位符 $p 已在 SKILL.md 说明"
  else
    bad "占位符 $p 未在 SKILL.md 中说明"
  fi
done

# ── 5. SKILL.md 引用的本地文件都存在 ─────────────────────────────────────
head_ "6. SKILL.md 引用的本地文件都存在"

missing=""
for f in $(grep -oE '`?(references|assets)/[A-Za-z0-9._/-]+`?' SKILL.md | tr -d '`' | sort -u); do
  [ -e "$f" ] || missing="$missing $f"
done
if [ -z "$missing" ]; then
  ok "SKILL.md 引用的本地文件全部存在"
else
  bad "SKILL.md 引用了不存在的文件 →$missing"
fi

# ── 6. 已废弃 API 残留检查 ────────────────────────────────────────────────
head_ "7. 已废弃 API / 错误码残留检查（仅查 SKILL.md 与 assets/）"

# 只查“每次都会被读到”的文件（SKILL.md 与模板）。历史快照（references/architecture.md、
# references/scaffold.md、references/plugin-development-tutorial.md）保留旧写法用于溯源，
# 新参考文档（capability-matrix 等）会**故意**写出错误写法以作警示，故不纳入本项。
scan_targets=$(find SKILL.md assets -type f 2>/dev/null)

stale_patterns=(
  'subscription\.unsubscribe'
  '返回 `?Disposable'
  '(^|[^_A-Za-z])CAPABILITY_DENIED'
  "engines: *\{ *openlearn: *'>=0\.1\.9"
  'socket\.off'
  '见第四步'
)
for pat in "${stale_patterns[@]}"; do
  hits=$(echo "$scan_targets" | xargs grep -rnE "$pat" 2>/dev/null)
  if [ -z "$hits" ]; then
    ok "无残留：$pat"
  else
    bad "存在已废弃写法「$pat」："
    echo "$hits" | head -3 | sed 's/^/      /'
  fi
done

# 正确的新口径必须出现在 SKILL.md
for pat in 'COMMAND_NOT_REGISTERED' 'COMMAND_CAPABILITY_DENIED' 'manifest\.main'; do
  if grep -qE "$pat" SKILL.md; then
    ok "SKILL.md 含新口径：$pat"
  else
    bad "SKILL.md 缺少新口径：$pat"
  fi
done

# ── 汇总 ──────────────────────────────────────────────────────────────────
printf '\n\033[1m结果\033[0m：通过 %d，失败 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
