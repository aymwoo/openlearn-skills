#!/usr/bin/env bash
# new-plugin.sh —— 从模板生成插件目录（复制 + 替换占位符，不执行 npm install / build）
#
# 用法：
#   bash scripts/new-plugin.sh <template> <target-dir> [options]
#
# template：server-only | full-stack | frontend-only | sandbox-view | inline-react
#
# options：
#   --id <pluginId>        插件全局 ID（默认 @local/<目录名>）
#   --name <pluginName>    显示名称（默认目录名）
#   --prefix <prefix>      命令前缀 / tab id 前缀（默认由目录名派生）
#   --description <text>   描述
#   --author <text>        作者（默认 git config user.name）
#   --force                目标目录非空时覆盖（默认拒绝）
#   -h, --help             显示帮助
#
# 示例：
#   bash scripts/new-plugin.sh sandbox-view ~/Develop/openlearn-plugins/my-board \
#     --id @openlearn-community/my-board --name "我的看板"
#
# 生成后按 SKILL.md 第四步自检：先铺 test-harness，跑 L0，再写业务逻辑。
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
META="$SKILL_DIR/references/.cache-meta.json"
TEMPLATES="server-only full-stack frontend-only sandbox-view inline-react"

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }
die() { printf '\033[31m✘\033[0m %s\n' "$1" >&2; exit 1; }

if [[ $# -lt 2 ]]; then usage; exit 2; fi
TPL="$1"; TARGET="$2"; shift 2

ID=""; NAME=""; PREFIX=""; DESC=""; AUTHOR=""; FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id|--name|--prefix|--description|--author)
      [[ $# -ge 2 ]] || die "$1 缺少参数值"
      case "$1" in
        --id) ID="$2" ;;
        --name) NAME="$2" ;;
        --prefix) PREFIX="$2" ;;
        --description) DESC="$2" ;;
        --author) AUTHOR="$2" ;;
      esac
      shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1（见 --help）" ;;
  esac
done

case " $TEMPLATES " in
  *" $TPL "*) ;;
  *) die "未知模板：$TPL（可选：$TEMPLATES）" ;;
esac
[[ -d "$ASSETS/$TPL" && -f "$ASSETS/$TPL/src/index.ts" ]] || die "模板不完整：assets/$TPL"

if [[ -e "$TARGET" ]]; then
  [[ -d "$TARGET" ]] || die "目标已存在且不是目录：$TARGET"
  if [[ -n "$(ls -A "$TARGET" 2>/dev/null)" && "$FORCE" -ne 1 ]]; then
    die "目标目录非空：$TARGET（确认覆盖请加 --force）"
  fi
else
  mkdir -p "$TARGET" || die "无法创建目录：$TARGET"
fi

BASE="$(basename "$TARGET")"
SLUG="$(printf '%s' "$BASE" | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/[^a-z0-9._-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^[-._]*//' -e 's/[-._]*$//')"
[[ -n "$SLUG" ]] || SLUG="plugin"

ID="${ID:-@local/$SLUG}"
[[ "$ID" =~ ^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$ ]] \
  || die "pluginId 不合法：$ID（示例：@openlearn-community/my-plugin）"

NAME="${NAME:-$BASE}"
if [[ ${#NAME} -gt 80 ]] || printf '%s' "$NAME" | grep -q '["\\<>{}]'; then
  die "显示名称不能包含引号、反斜杠、尖括号或花括号（且不超过 80 字）"
fi

DESC="${DESC:-TODO：描述这个插件做什么}"
if [[ ${#DESC} -gt 200 ]] || printf '%s' "$DESC" | grep -q '["\\<>{}]' \
  || case "$DESC" in *$'\n'*) true ;; *) false ;; esac; then
  die "描述不能包含引号、反斜杠、尖括号、花括号或换行（且不超过 200 字）"
fi

if [[ -z "$AUTHOR" ]]; then
  AUTHOR="$(git config user.name 2>/dev/null || true)"
  AUTHOR="${AUTHOR:-unknown}"
fi
if [[ ${#AUTHOR} -gt 80 ]] || printf '%s' "$AUTHOR" | grep -q '["\\<>{}]'; then
  die "作者名不能包含引号、反斜杠、尖括号或花括号（且不超过 80 字）"
fi

if [[ -z "$PREFIX" ]]; then
  PREFIX="$(printf '%s' "${SLUG##*/}" | tr -cd 'a-z0-9' | cut -c1-16)"
  [[ "$PREFIX" =~ ^[a-z] ]] || PREFIX="p$PREFIX"
fi
[[ "$PREFIX" =~ ^[a-z][a-z0-9]{0,15}$ ]] \
  || die "命令前缀不合法：$PREFIX（小写字母开头，仅 a-z0-9，最长 16）"

SDK_VERSION="3.7.4"
if [[ -f "$META" ]]; then
  SDK_VERSION="$(python3 -c "import json;print(json.load(open('$META')).get('sdkVersion') or '3.7.4')" 2>/dev/null || echo 3.7.4)"
fi

cp -r "$ASSETS/$TPL/." "$TARGET/" || die "复制模板失败"

NEW_PLUGIN_TARGET="$TARGET" \
NEW_PLUGIN_NAME="$SLUG" \
NEW_PLUGIN_ID="$ID" \
NEW_PLUGIN_DISPLAY_NAME="$NAME" \
NEW_PLUGIN_DESCRIPTION="$DESC" \
NEW_PLUGIN_AUTHOR="$AUTHOR" \
NEW_PLUGIN_SDK_VERSION="$SDK_VERSION" \
NEW_PLUGIN_PREFIX="$PREFIX" \
python3 - <<'PY' || exit 1
import os, pathlib, re, sys

target = pathlib.Path(os.environ['NEW_PLUGIN_TARGET'])
prefix = os.environ['NEW_PLUGIN_PREFIX']
name = os.environ['NEW_PLUGIN_DISPLAY_NAME']
vals = {
    'name': os.environ['NEW_PLUGIN_NAME'],
    'pluginId': os.environ['NEW_PLUGIN_ID'],
    'pluginName': name,
    'description': os.environ['NEW_PLUGIN_DESCRIPTION'],
    'author': os.environ['NEW_PLUGIN_AUTHOR'],
    'sdkVersion': os.environ['NEW_PLUGIN_SDK_VERSION'],
    'commandPrefix': prefix,
    'toolId': f'{prefix}-tool',
    'toolName': name,
    'tabId': f'{prefix}-tab',
}
exts = {'.ts', '.tsx', '.json', '.html', '.mjs', '.md', '.css'}
files = [p for p in target.rglob('*') if p.is_file() and p.suffix in exts]
for p in files:
    text = p.read_text(encoding='utf-8')
    new = text
    for key, value in vals.items():
        new = new.replace('{{' + key + '}}', value)
    if new != text:
        p.write_text(new, encoding='utf-8')

leftovers = []
for p in files:
    for marker in re.findall(r'\{\{[a-zA-Z]+\}\}', p.read_text(encoding='utf-8')):
        leftovers.append(f'{p.relative_to(target)}: {marker}')
if leftovers:
    print('\n'.join(f'  · {line}' for line in leftovers), file=sys.stderr)
    sys.exit(1)
PY

printf '\033[32m✔\033[0m 已生成 %s（模板 %s）\n' "$TARGET" "$TPL"
printf '  pluginId      %s\n' "$ID"
printf '  commandPrefix %s\n' "$PREFIX"
[[ "$TPL" == "sandbox-view" ]] && printf '  view 文件     storage/*.html（安装器只解压 storage/**）\n'
printf '\n下一步：\n'
printf '  cd %s\n' "$TARGET"
printf '  cp -r %s/assets/test-harness ./test-harness\n' "$SKILL_DIR"
printf '  npm i\n'
if [[ "$TPL" == "sandbox-view" ]]; then
  printf '  npm run pack                              # build + 补 storage/**\n'
else
  printf '  npm run build\n'
fi
printf '  node test-harness/static-check.mjs .      # L0：先让它 0 error\n'
