#!/usr/bin/env bash
# diff-official-scaffold.sh —— 本 skill 模板 vs 官方 CLI 脚手架 的语义差异检查
#
# 背景：v1.x 的模板曾长期落后于官方脚手架（缺 manifest.main、沿用已废弃的 React 前端范式），
#       而人工 review 看不出「官方新增了字段」。本脚本把两边抽成「契约指纹」逐项对比，
#       **只要官方有、我们没有，就判失败**，强制在升级平台版本时同步模板。
#
# 用法：
#   bash scripts/diff-official-scaffold.sh [skill-root] [official-templates-dir]
#   PLATFORM_REPO=/path/to/openlearnv2 bash scripts/diff-official-scaffold.sh
#   OFFICIAL_SCAFFOLD_DIR=/path/to/plugin-sdk/scaffold/templates bash scripts/diff-official-scaffold.sh
#
# 第二个参数可以直接是官方模板目录（npm 安装的 @openlearn/plugin-sdk/scaffold/templates），
# 也可以是平台仓库根目录（会取其 packages/plugin-sdk/scaffold/templates）。
#
# 退出码：0 = 无「官方有我们缺」项；1 = 有漂移需处理；2 = 环境不满足（已跳过）

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PLATFORM="${PLATFORM_REPO:-$HOME/Develop/openlearnv2}"

# 解析官方模板目录
OFFICIAL=""
if [ -n "${OFFICIAL_SCAFFOLD_DIR:-}" ] && [ -d "${OFFICIAL_SCAFFOLD_DIR}" ]; then
  OFFICIAL="$OFFICIAL_SCAFFOLD_DIR"
elif [ "${2:-}" != "" ] && [ -d "${2}/server-only" ]; then
  OFFICIAL="$2"
elif [ "${2:-}" != "" ] && [ -d "${2}/packages/plugin-sdk/scaffold/templates" ]; then
  OFFICIAL="$2/packages/plugin-sdk/scaffold/templates"
elif [ -d "$ROOT/node_modules/@openlearn/plugin-sdk/scaffold/templates" ]; then
  OFFICIAL="$ROOT/node_modules/@openlearn/plugin-sdk/scaffold/templates"
elif [ -d "$PLATFORM/packages/plugin-sdk/scaffold/templates" ]; then
  OFFICIAL="$PLATFORM/packages/plugin-sdk/scaffold/templates"
fi

HELPER="$ROOT/scripts/scaffold-fingerprint.py"

cd "$ROOT" || exit 1

if [ ! -d "$OFFICIAL" ]; then
  printf '\033[33m⚠ 跳过\033[0m 未找到官方脚手架：%s\n' "$OFFICIAL"
  printf '  设置 PLATFORM_REPO 或传第二个参数指向本地平台仓库。\n'
  exit 2
fi

printf '\033[1m官方脚手架\033[0m %s\n' "$OFFICIAL"
printf '\033[1m本 skill 模板\033[0m %s/assets\n\n' "$ROOT"

DRIFT=0

for tpl in server-only full-stack frontend-only; do
  off_dir="$OFFICIAL/$tpl"
  our_dir="$ROOT/assets/$tpl"
  [ -d "$off_dir" ] || { printf '\033[31m✘ %s: 官方模板缺失 %s\033[0m\n' "$tpl" "$off_dir"; DRIFT=1; continue; }
  [ -d "$our_dir" ] || { printf '\033[31m✘ %s: 本 skill 模板缺失 %s\033[0m\n' "$tpl" "$our_dir"; DRIFT=1; continue; }

  off_json=$(python3 "$HELPER" "$off_dir" "$tpl") || { printf '✘ %s: 官方模板指纹提取失败\n' "$tpl"; DRIFT=1; continue; }
  our_json=$(python3 "$HELPER" "$our_dir" "$tpl") || { printf '✘ %s: 本 skill 模板指纹提取失败\n' "$tpl"; DRIFT=1; continue; }

  printf '\033[1m%s\033[0m\n' "$tpl"
  python3 - "$off_json" "$our_json" "${DIFF_ADVISORY:-0}" <<'PY'
import json, os, re, sys
off = json.loads(sys.argv[1])
our = json.loads(sys.argv[2])
advisory = sys.argv[3] == "1"
drift = 0

def line(status, label, detail):
    global drift
    if advisory and status == "warn":
        status = "info"
    mark = {"ok": "\033[32m✔\033[0m", "warn": "\033[31m✘\033[0m", "info": "\033[90m·\033[0m"}[status]
    if status == "warn":
        drift += 1
    print(f"  {mark} {label}: {detail}")

# 1) manifest 字段
missing = sorted(set(off["manifest_keys"]) - set(our["manifest_keys"]))
extra = sorted(set(our["manifest_keys"]) - set(off["manifest_keys"]))
if missing:
    line("warn", "manifest 字段", f"官方有、我们缺 → {', '.join(missing)}")
elif extra:
    line("info", "manifest 字段", f"与官方一致（我们额外: {', '.join(extra) or '无'}）")
else:
    line("ok", "manifest 字段", f"与官方一致（{len(off['manifest_keys'])} 个）")

# 2) 关键字段值
#    main 必须完全一致；engines.openlearn 允许**更严格**（官方模板写死 >=0.2.5，
#    我们按「实际用到的 API 的最低宿主版本」填，更高才是正确做法），但不能更低。
def minver(v):
    if not v:
        return None
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", str(v))
    return tuple(int(x) for x in m.groups()) if m else None

o_main, u_main = off["manifest_values"].get("main"), our["manifest_values"].get("main")
if o_main != u_main:
    line("warn", "main", f"官方={o_main} 我们={u_main}")
else:
    line("ok", "main", str(o_main))

o_eng, u_eng = off["manifest_values"].get("engines.openlearn"), our["manifest_values"].get("engines.openlearn")
ov, uv = minver(o_eng), minver(u_eng)
if ov and uv and uv > ov:
    line("info", "engines.openlearn", f"官方={o_eng} 我们={u_eng}（我们更严格：按实际用到的 API 填，不是官方的一律 >=0.2.5）")
elif o_eng != u_eng:
    line("warn", "engines.openlearn", f"官方={o_eng} 我们={u_eng}")
else:
    line("ok", "engines.openlearn", str(o_eng))

# 3) commandType ↔ ActionDescriptor 配对
#    注：commandType 的**具体命名**由插件作者自定（官方用 {{pluginId}}.x，我们用 {{commandPrefix}}.x），
#    两者都被宿主命名空间化，因此只比**数量**与**配对完整性**，不比对字面值。
off_h = set(off["command_types"]["handlers"])
off_a = set(off["command_types"]["actions"])
our_h = set(our["command_types"]["handlers"])
our_a = set(our["command_types"]["actions"])
if len(our_h) < len(off_h):
    line("warn", "command handler", f"官方 {len(off_h)} 个，我们只有 {len(our_h)} 个 → 缺 {sorted(off_h - our_h)}")
elif our_h - our_a:
    line("warn", "ActionDescriptor", f"我们有 handler 但缺描述符 → {sorted(our_h - our_a)}")
elif our_h != off_h:
    line("info", "command 配对", f"{len(our_h)} 个 commandType 均有描述符（命名与官方不同，属预期）")
else:
    line("ok", "command 配对", f"{len(our_a)} 个 commandType 均有描述符")

# 4) 前端 React/DOM
if off["frontend_react"]:
    line("info", "前端 React", "官方模板也依赖 React（平台已勘误：远程插件不可用）")
elif our["frontend_react"]:
    line("warn", "前端 React", "官方已不用 React，我们仍依赖 React/DOM")
else:
    line("ok", "前端 React", "无 React/DOM 依赖（符合 v0.7 沙箱桥接范式）")

# 5) default export 契约
if off["default_export"] and our["default_export"] != off["default_export"]:
    line("warn", "default export", f"官方={off['default_export']} 我们={our['default_export']}")
elif our["default_export"]:
    line("ok", "default export", "activate / deactivate 齐全")
else:
    line("info", "default export", "（该模板无前端产物）")

# 6) SDK 版本写法
if off["sdk_dep"] != our["sdk_dep"]:
    line("info", "SDK 依赖", f"官方={off['sdk_dep']} 我们={our['sdk_dep']}（我们用占位符，不写死）")
else:
    line("ok", "SDK 依赖", our["sdk_dep"])

# 7) 官方占位符
#    占位符只是 CLI 的命名约定，不是能力契约（如 {{componentName}} 只在官方 React 模板里用得上，
#    我们的桥接模板没有组件名）——因此只提示不判失败。
known = {"author", "description", "name", "pluginId", "pluginName", "sdkVersion"}
off_ph = set(off["placeholders"]) - known
if off_ph:
    line("info", "占位符", f"官方独有占位符（多为组件名，桥接模板不适用）→ {sorted(off_ph)}")
else:
    line("ok", "占位符", "官方占位符已全覆盖")

sys.exit(1 if drift else 0)
PY
  if [ $? -ne 0 ]; then DRIFT=1; fi
done

echo
if [ "$DRIFT" -ne 0 ]; then
  printf '\033[31m✘ 检出漂移\033[0m —— 官方脚手架有本 skill 尚未跟进的内容，请按上方提示更新 assets/ 模板。\n'
  exit 1
fi
if [ "${DIFF_ADVISORY:-0}" = "1" ]; then
  printf '\033[33m⚠ 预警模式\033[0m —— 差异仅提示，不阻塞 CI。\n'
else
  printf '\033[32m✔ 三套模板与官方脚手架契约一致\033[0m\n'
fi
exit 0
