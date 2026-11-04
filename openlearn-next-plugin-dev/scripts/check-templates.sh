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
SKIP=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33m⊘\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ── 1. 模板必备字段 ────────────────────────────────────────────────────────
head_ "1. 模板必备字段（manifest.main / engines.openlearn）"

for tpl in server-only full-stack frontend-only inline-react sandbox-view; do
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
    inline-react)  exp=">=0.7.0" ;;
    sandbox-view)  exp=">=0.7.6" ;;
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

for tpl in server-only full-stack frontend-only inline-react sandbox-view; do
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

# ── 3b. inline-react：React 只能来自 HostSharedDeps ────────────────────────
head_ "3b. inline-react 模板：不写 import React（否则 CLI 裸说明符守卫构建失败）"

fe="assets/inline-react/src/frontend.tsx"
if [ -f "$fe" ]; then
  if grep -qE "^\s*import\s+React|from ['\"]react['\"]" "$fe"; then
    bad "inline-react: frontend.tsx 出现 import React（构建必失败）"
  else
    ok "inline-react: 无 import React"
  fi
  grep -q "HostSharedDeps" "$fe" && ok "inline-react: 通过 HostSharedDeps 取宿主 React" || bad "inline-react: 未使用 HostSharedDeps"
  grep -q "component:" "$fe" && ok "inline-react: 注册了 component" || bad "inline-react: 未注册 component"
else
  bad "inline-react: 缺少 src/frontend.tsx"
fi

# ── 3c. sandbox-view：view 文件存在且引了桥接脚本 ─────────────────────────
head_ "3c. sandbox-view 模板：view / 桥接 / 打包脚本"

sv="assets/sandbox-view"
for f in storage/teacher.html storage/student.html; do
  if [ -f "$sv/$f" ] && grep -q "/plugin-sandbox/view-bridge.js" "$sv/$f"; then
    ok "sandbox-view: $f 存在且引入桥接脚本"
  else
    bad "sandbox-view: $f 缺失或未引入 view-bridge.js"
  fi
done
grep -q '"view"' "$sv/plugin.contract.json" 2>/dev/null || grep -q 'viewFiles' "$sv/plugin.contract.json" && ok "sandbox-view: 契约声明了 viewFiles" || bad "sandbox-view: 契约缺 viewFiles"
[ -f "$sv/scripts/pack.mjs" ] && ok "sandbox-view: 带 pack.mjs（补 storage/**）" || bad "sandbox-view: 缺 scripts/pack.mjs"

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

# ── 5b. 一键脚手架覆盖全部占位符 / view 冒烟存在 ──────────────────────────
head_ "5b. 一键脚手架、Grilling 向导、契约水合、源码同步、双平台探测/同步与 view 冒烟"

if [ -x scripts/new-plugin.sh ]; then
  ok "new-plugin.sh 存在且可执行"
else
  bad "new-plugin.sh 缺失或不可执行"
fi

if [ -x scripts/grill-requirements.sh ]; then
  ok "grill-requirements.sh 存在且可执行"
else
  bad "grill-requirements.sh 缺失或不可执行"
fi

if python3 -m py_compile scripts/grill-requirements.py >/dev/null 2>&1; then
  ok "grill-requirements.py 语法校验通过"
else
  bad "grill-requirements.py 语法错误"
fi

if bash scripts/grill-requirements.sh -h >/dev/null 2>&1; then
  ok "grill-requirements.sh 帮助信息可正常打印"
else
  bad "grill-requirements.sh 帮助信息退出码异常"
fi

if [ -x scripts/hydrate-contracts.sh ]; then
  ok "hydrate-contracts.sh 存在且可执行"
else
  bad "hydrate-contracts.sh 缺失或不可执行"
fi

if bash scripts/hydrate-contracts.sh --check >/dev/null 2>&1; then
  ok "hydrate-contracts.sh 契约校验通过（与平台源码一致）"
else
  # 退出码 2 = 找不到本地平台仓库（契约真源）；1 = 检出漂移。
  # 两者都只作预警、不阻塞：契约快照直连平台 docs/agent/contracts/，
  # 平台改一次契约不应卡住与契约无关的 PR——发布版 API 面由 CI 的
  # scaffold-diff / build-verify 两个阻塞 job 把关。
  # 漂移的真正处理：bash scripts/hydrate-contracts.sh（重新水合）。
  hydrate_rc=$?
  if [ "$hydrate_rc" -eq 2 ]; then
    warn "跳过契约校验：未找到本地平台仓库（设置 PLATFORM_REPO 或克隆平台源码后重跑）"
  else
    warn "平台契约有漂移（不影响发布）：运行 bash scripts/hydrate-contracts.sh 水合"
  fi
fi

if [ -x scripts/sync-platform-repo.sh ]; then
  ok "sync-platform-repo.sh 存在且可执行"
else
  bad "sync-platform-repo.sh 缺失或不可执行"
fi

if bash scripts/sync-platform-repo.sh -h >/dev/null 2>&1; then
  ok "sync-platform-repo.sh 帮助信息可正常打印"
else
  bad "sync-platform-repo.sh 帮助信息退出码异常"
fi

if [ -x scripts/platform-probe.sh ]; then
  ok "platform-probe.sh 存在且可执行"
else
  bad "platform-probe.sh 缺失或不可执行"
fi

if bash scripts/platform-probe.sh -h >/dev/null 2>&1; then
  ok "platform-probe.sh 帮助信息可正常打印"
else
  bad "platform-probe.sh 帮助信息退出码异常"
fi

if [ -x scripts/sync-mirror.sh ]; then
  ok "sync-mirror.sh 存在且可执行"
else
  bad "sync-mirror.sh 缺失或不可执行"
fi

if bash scripts/sync-mirror.sh -h >/dev/null 2>&1; then
  ok "sync-mirror.sh 帮助信息可正常打印"
else
  bad "sync-mirror.sh 帮助信息退出码异常"
fi

if python3 - <<'PY' >/dev/null 2>&1
import json, pathlib, sys
p = pathlib.Path("references/repo-mirrors.json")
data = json.loads(p.read_text(encoding="utf-8"))
assert data.get("policy", {}).get("preferred") == "github"
assert data.get("policy", {}).get("fallback") == "gitee"
repos = data.get("repos")
assert isinstance(repos, dict) and repos
for gh, entry in repos.items():
    assert "/" in gh, gh
    assert (entry or {}).get("gitee"), gh
    assert (entry or {}).get("defaultBranch"), gh
PY
then
  ok "repo-mirrors.json 结构合法（policy + repos 映射齐全）"
else
  bad "repo-mirrors.json 缺失或结构非法（需 policy.preferred/fallback 与每个仓库的 gitee/defaultBranch）"
fi

missing_keys=""
for p in $used; do
  key="${p#\{\{}"; key="${key%\}\}}"
  grep -qE "\"$key\"|'$key'" scripts/new-plugin.sh 2>/dev/null || missing_keys="$missing_keys $key"
done
if [ -z "$missing_keys" ]; then
  ok "new-plugin.sh 替换全部占位符"
else
  bad "new-plugin.sh 未覆盖占位符 →$missing_keys"
fi

if grep -q "OpenLearnPluginBridge" assets/test-harness/view-smoke.test.ts 2>/dev/null; then
  ok "view-smoke.test.ts 使用真实的 OpenLearnPluginBridge 契约"
else
  bad "view-smoke.test.ts 缺失或未引用 OpenLearnPluginBridge"
fi

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

# ── 可复用 CI workflow（Issue #2）─────────────────────────────────────────
# 插件仓靠 `uses: aymwoo/openlearn-skills/.github/workflows/plugin-l0.yml@<ref>` 接入，
# 所以该文件必须存在且带 workflow_call 触发器；否则插件仓一接入就报「找不到 workflow」。
#
# 注意路径：ROOT 是**技能子目录**（openlearn-next-plugin-dev/），而 .github/ 与 CHANGELOG.md
# 在**仓库根** —— 这里显式算出 REPO_ROOT，避免在子目录里找不到文件而误报。
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
if [ -f "$REPO_ROOT/.github/workflows/plugin-l0.yml" ]; then
  ok "可复用 workflow plugin-l0.yml 存在"
  if grep -qE '^\s*workflow_call:' "$REPO_ROOT/.github/workflows/plugin-l0.yml"; then
    ok "plugin-l0.yml 含 workflow_call 触发器"
  else
    bad "plugin-l0.yml 缺少 workflow_call 触发器（插件仓无法 uses: 复用）"
  fi
else
  bad "缺少 .github/workflows/plugin-l0.yml（插件仓无法复用护栏 CI）"
fi

# v2 浮动 tag：插件仓用 @v2 固定护栏版本；tag 落后于最新版本只会让插件仓拿到旧规则，
# 所以这里给提醒（不阻断 —— tag 由维护者在发版后移动）。
LATEST_VER="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$REPO_ROOT/CHANGELOG.md" 2>/dev/null | head -1 | sed 's/^## \[//; s/\]$//')"
if git rev-parse -q --verify "refs/tags/v2^{commit}" >/dev/null 2>&1; then
  V2_VER="$(git show "v2:openlearn-next-plugin-dev/SKILL.md" 2>/dev/null | grep -m1 -oE '^version: .*' | sed 's/version: //')"
  if [ "$V2_VER" = "$LATEST_VER" ]; then
    ok "v2 浮动 tag 指向最新版本（$V2_VER）"
  else
    warn "v2 浮动 tag 指向 ${V2_VER:-未知}，而 CHANGELOG 最新版本是 ${LATEST_VER:-未知} —— 插件仓用 @v2 会拿到旧规则。发版后请移动：git tag -f v2 <新版本提交> && git push origin v2 --force"
  fi
else
  warn "没有 v2 浮动 tag —— 插件仓只能用 @main（无法固定护栏版本）。创建：git tag -a v2 -m '...' <最新版本提交> && git push origin v2"
fi

# ── 汇总 ──────────────────────────────────────────────────────────────────
printf '\n\033[1m结果\033[0m：通过 %d，失败 %d，跳过 %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
