#!/usr/bin/env bash
# platform-drift-check.sh —— 平台行为漂移检测（维护本 skill 用）
#
# 检测「文档看不出来、但一错就整套方案跑偏」的平台事实是否变化：
#   槽位数量 / view 槽位 / 安装器解压前缀 / CLI 打包内容 /
#   README 是否重新公开白名单变量 / 白名单通配符 / 白板卡片是否支持 view / 平台版本
#
# 期望值来源：references/.cache-meta.json 的 watchlist 字段（单一真源）
# 说明文档：references/platform-change-watchlist.md
#
# 用法：
#   bash scripts/platform-drift-check.sh                # 只检测，drift 时退出码 1
#   bash scripts/platform-drift-check.sh --write        # 检测 + 重生成 slot-registry.json
#   PLATFORM_REPO=/path/to/openlearnv2 bash scripts/platform-drift-check.sh
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${PLATFORM_REPO:-$HOME/Develop/openlearnv2}"
TOOLKIT="$SKILL_DIR/assets/test-harness/slot-registry.json"
META="$SKILL_DIR/references/.cache-meta.json"
WRITE=0
[[ "${1:-}" == "--write" ]] && WRITE=1

PASS=0; FAIL=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✖\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
head_(){ printf '\n\033[1m%s\033[0m\n' "$1"; }

[[ -d "$PLATFORM" ]] || { echo "找不到平台仓库：$PLATFORM（用 PLATFORM_REPO=... 指定）"; exit 2; }
[[ -f "$META" ]] || { echo "找不到 $META"; exit 2; }

meta() { python3 -c "import json,sys;d=json.load(open('$META'));print(json.dumps(d['watchlist'].get('$1')))"; }

printf '\033[1m平台\033[0m %s\n' "$PLATFORM"
printf '\033[1m基线\033[0m %s\n' "$(cd "$PLATFORM" && git rev-parse --short HEAD)"

# ── 1. 平台版本 ────────────────────────────────────────────────────────────
head_ "1. 平台版本"
ACTUAL_VER=$(python3 -c "import json;print(json.load(open('$PLATFORM/package.json'))['version'])")
EXP_VER=$(python3 -c "import json;print(json.load(open('$META')).get('platformVersion',''))")
if [[ "$ACTUAL_VER" == "$EXP_VER" ]]; then ok "platformVersion = $ACTUAL_VER"
else bad "platformVersion 漂移：期望 $EXP_VER，实际 $ACTUAL_VER → 更新 SKILL.md 头部与 .cache-meta.json"; fi

# ── 2. 槽位数量 + view 槽位 ────────────────────────────────────────────────
head_ "2. 扩展槽位（ExtensionSlot 联合类型）"
read -r ACTUAL_SLOTS ACTUAL_VIEW < <(python3 - "$PLATFORM" <<'PY'
import re, json, sys
root = sys.argv[1]
lines = open(f'{root}/src/plugin-host/types.ts', encoding='utf-8').read().splitlines()
try:
    s = next(i for i, l in enumerate(lines) if l.startswith('export type ExtensionSlot'))
    e = next(i for i, l in enumerate(lines) if l.startswith('export type AnchorSlot'))
except StopIteration:
    print('0 '); raise SystemExit
seg = '\n'.join(lines[s:e])
slots = []
for m in re.finditer(r"'\s*([a-zA-Z0-9_.:-]+)\s*'", seg):
    if m.group(1) not in slots:
        slots.append(m.group(1))
schema = open(f'{root}/packages/core/esm-loader/manifest-schema.ts', encoding='utf-8').read()
# 先收集命名 schema（teacher.panel 这类 view 定义在命名 schema 里）
named = {}
for m in re.finditer(r'const\s+(\w+Schema)\s*=\s*z\s*\.\s*object\(\{([\s\S]*?)\n\}\)', schema):
    named[m.group(1)] = m.group(2)
keys = [(m.start(), m.group(1)) for m in re.finditer(r"^    '([a-zA-Z0-9_.:]+)':\s*z", schema, re.M)]
view_slots = []
for i, (pos, key) in enumerate(keys):
    end = keys[i + 1][0] if i + 1 < len(keys) else pos + 2500
    block = schema[pos:end]
    has = 'view: z.string' in block
    if not has:
        for name in re.findall(r'z\s*\.\s*array\s*\(\s*(\w+Schema)\s*\)', block):
            has = has or 'view: z.string' in named.get(name, '')
    if has:
        view_slots.append(key)
print(len(slots), ','.join(view_slots))
PY
)
EXP_SLOTS=$(python3 -c "import json;print(json.load(open('$META'))['watchlist']['slotCount'])")
EXP_VIEW=$(python3 -c "import json;print(','.join(json.load(open('$META'))['watchlist']['viewSlots']))")
if [[ "$ACTUAL_SLOTS" == "$EXP_SLOTS" ]]; then ok "槽位数量 = $ACTUAL_SLOTS"
else bad "槽位数量漂移：期望 $EXP_SLOTS，实际 $ACTUAL_SLOTS → 更新 slot-registry.json 与 ui-channel-decision.md"; fi
if python3 -c "import sys;a=sorted('$ACTUAL_VIEW'.split(','));b=sorted('$EXP_VIEW'.split(','));sys.exit(0 if a==b else 1)"; then
  ok "view 槽位 = $ACTUAL_VIEW"
else bad "view 槽位漂移：期望 [$EXP_VIEW]，实际 [$ACTUAL_VIEW] → 更新 slot-registry.json.viewSlots 与 §4.5.1"; fi

# ── 3. 安装器解压前缀 ──────────────────────────────────────────────────────
head_ "3. 安装器解压前缀（决定 view 路径写 storage/ 还是 views/）"
ACTUAL_PREFIX=$(grep -oE "startsWith\('[^']+/'\)" "$PLATFORM/packages/core/plugin-host/install.ts" | sed "s/startsWith('//; s/')\$//" | sort -u | tr '\n' ' ' | sed 's/ *$//')
EXP_PREFIX=$(python3 -c "import json;print(' '.join(json.load(open('$META'))['watchlist']['installExtractPrefixes']))")
if [[ "$ACTUAL_PREFIX" == "$EXP_PREFIX" ]]; then ok "解压前缀 = $ACTUAL_PREFIX"
else bad "解压前缀漂移：期望 [$EXP_PREFIX]，实际 [$ACTUAL_PREFIX] → ZIP 插件的 view 路径规则可能变化，更新 watchlist §2 与 L0 规则"; fi

# ── 4. CLI 打包内容 ────────────────────────────────────────────────────────
head_ "4. SDK CLI 打包文件"
ACTUAL_ZIP=$(grep -oE "zip\.file\('[^']+'" "$PLATFORM/packages/plugin-sdk/cli.mjs" | sed "s/zip\.file('//; s/'//" | grep -v '^signature.json$' | sort -u | tr '\n' ' ' | sed 's/ *$//')
SIGN_SUPPORTED=$(grep -c "zip\.file('signature.json'" "$PLATFORM/packages/plugin-sdk/cli.mjs" || true)
EXP_ZIP=$(python3 -c "import json;print(' '.join(json.load(open('$META'))['watchlist']['cliPackedFiles']))")
if python3 -c "import sys;a=sorted('$ACTUAL_ZIP'.split());b=sorted('$EXP_ZIP'.split());sys.exit(0 if a==b else 1)"; then
  ok "打包文件 = $ACTUAL_ZIP（sign 命令另写 signature.json，仅签名时）"
else
  if echo "$ACTUAL_ZIP" | grep -q "storage/"; then
    bad "CLI 已开始打包 storage/（$ACTUAL_ZIP）→ 可简化 sandbox-view 的 pack.mjs 要求，更新 watchlist §3 与模板 README"
  else
    bad "打包文件漂移：期望 [$EXP_ZIP]，实际 [$ACTUAL_ZIP] → 更新 watchlist §3"
  fi
fi

# ── 5. 白名单：README 曝光 + 通配符 ────────────────────────────────────────
head_ "5. OPENLEARN_TRUSTED_INLINE_PLUGINS（README 曝光 / 通配符）"
ACTUAL_README=$(grep -c "OPENLEARN_TRUSTED_INLINE_PLUGINS" "$PLATFORM/README.md" 2>/dev/null || true)
EXP_README=$(python3 -c "import json;print(json.load(open('$META'))['watchlist']['readmeMentionsTrustedInline'])")
if [[ "$ACTUAL_README" == "$EXP_README" ]]; then ok "README 提及次数 = $ACTUAL_README（PR #343 已移除）"
else bad "README 提及次数漂移：期望 $EXP_README，实际 $ACTUAL_README → 白名单叙事可能变化，复核 watchlist §1"; fi

if grep -q "endsWith('\*')" "$PLATFORM/packages/core/plugin-host/execution-policy.ts"; then
  ACTUAL_WILD=1
else
  ACTUAL_WILD=0
fi
EXP_WILD=$(python3 -c "import json;print(int(json.load(open('$META'))['watchlist']['allowlistWildcard']))")
if [[ "$ACTUAL_WILD" == "$EXP_WILD" ]]; then ok "通配符支持 = $([[ $ACTUAL_WILD == 1 ]] && echo yes || echo no)"
else bad "通配符支持漂移：期望 $EXP_WILD，实际 $ACTUAL_WILD → 更新 watchlist §1 与 ui-channel-decision.md §3"; fi

# ── 6. 白板卡片是否支持 view ───────────────────────────────────────────────
head_ "6. 白板画布卡片渲染能力"
if grep -qE "ext\.view|hasView" "$PLATFORM/src/features/whiteboard/widgets/PluginCardRenderer.tsx" 2>/dev/null; then
  ACTUAL_WB=1
else
  ACTUAL_WB=0
fi
EXP_WB=$(python3 -c "import json;print(int(json.load(open('$META'))['watchlist']['whiteboardCardSupportsView']))")
if [[ "$ACTUAL_WB" == "$EXP_WB" ]]; then ok "PluginCardRenderer 支持 view = $([[ $ACTUAL_WB == 1 ]] && echo yes || echo no)"
else bad "白板卡片支持 view 的结论已失效 → 更新 watchlist §5、ui-channel-decision §5（白板可能不再强制 inline）"; fi

# ── 7. 可选：重生成 slot-registry.json ────────────────────────────────────
if [[ "$WRITE" == "1" ]]; then
  head_ "7. 重生成 slot-registry.json"
  python3 - "$PLATFORM" "$TOOLKIT" <<'PY'
import re, json, sys
root, out = sys.argv[1], sys.argv[2]
lines = open(f'{root}/src/plugin-host/types.ts', encoding='utf-8').read().splitlines()
s = next(i for i, l in enumerate(lines) if l.startswith('export type ExtensionSlot'))
e = next(i for i, l in enumerate(lines) if l.startswith('export type AnchorSlot'))
slots = []
for m in re.finditer(r"'\s*([a-zA-Z0-9_.:-]+)\s*'", '\n'.join(lines[s:e])):
    if m.group(1) not in slots:
        slots.append(m.group(1))
schema = open(f'{root}/packages/core/esm-loader/manifest-schema.ts', encoding='utf-8').read()
named = {}
for m in re.finditer(r'const\s+(\w+Schema)\s*=\s*z\s*\.\s*object\(\{([\s\S]*?)\n\}\)', schema):
    named[m.group(1)] = m.group(2)
keys = [(m.start(), m.group(1)) for m in re.finditer(r"^    '([a-zA-Z0-9_.:]+)':\s*z", schema, re.M)]
view_slots = []
for i, (pos, key) in enumerate(keys):
    end = keys[i + 1][0] if i + 1 < len(keys) else pos + 2500
    block = schema[pos:end]
    has = 'view: z.string' in block
    if not has:
        for name in re.findall(r'z\s*\.\s*array\s*\(\s*(\w+Schema)\s*\)', block):
            has = has or 'view: z.string' in named.get(name, '')
    if has:
        view_slots.append(key)
old = json.load(open(out, encoding='utf-8')) if __import__('os').path.exists(out) else {}
groups = old.get('groups', {})
data = {
    'source': 'src/plugin-host/types.ts (export type ExtensionSlot)',
    'platformVersion': json.load(open(f'{root}/package.json'))['version'],
    'platformCommit': __import__('subprocess').check_output(['git', '-C', root, 'rev-parse', '--short', 'HEAD'], text=True).strip(),
    'anchorPattern': 'anchor:{区域}:{锚点id}',
    'note': '槽位是封闭集合；未列出的名字宿主没有消费方，声明了也不会渲染。anchor:* 为动态模式。',
    'count': len(slots),
    'slots': slots,
    'groups': groups,
    'viewSlots': view_slots,
    'viewNote': 'view 字段由 manifest-schema 显式声明；student.classroom.overlay 等走 passthrough，可能透传但不保证。',
}
open(out, 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print(f'已写入 {out}：{len(slots)} 个槽位，{len(view_slots)} 个 view 槽位')
PY
  ok "slot-registry.json 已按当前平台源码重生成"
else
  head_ "7. 重生成 slot-registry.json"
  printf '  \033[33m—\033[0m 未指定 --write，跳过重生成\n'
fi

printf '\n\033[1m结果\033[0m：通过 %d，漂移 %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '漂移不等于 bug：先读 references/platform-change-watchlist.md 对应条目，确认是「行为变了」还是「文档补上了」。\n'
  exit 1
fi
printf '无需改动；若远端文档版本有更新，记得到 references/.cache-meta.json 更新 docSiteVersion。\n'
