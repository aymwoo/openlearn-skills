#!/usr/bin/env bash
# hydrate-contracts.sh —— 从 OpenLearnV2 平台源码同步与水合契约元数据
#
# 用途：
#   从本地平台仓库（$PLATFORM/docs/agent/contracts/）读取最新机器可读契约，
#   水合至 assets/test-harness/contracts/ 与 slot-registry.json，
#   确保 L0 静态检查（static-check.mjs）、L1 契约测试（contract.test.ts）
#   与 Grilling 需求向导（grill-requirements.py）始终对齐平台真源。
#
# 用法：
#   bash scripts/hydrate-contracts.sh              # 检查并同步水合
#   bash scripts/hydrate-contracts.sh --check      # 仅检查是否发生漂移（退出码 0=一致, 1=漂移）
#   PLATFORM_REPO=/path/to/openlearnv2 bash scripts/hydrate-contracts.sh
#
# 退出码：
#   0 = 成功 / 一致
#   1 = 漂移（在 --check 模式下）或部分失败
#   2 = 缺少平台仓库或参数错误
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM="${PLATFORM_REPO:-$HOME/Develop/openlearnv2}"
TARGET_DIR="$SKILL_DIR/assets/test-harness/contracts"
LEGACY_SLOT_REGISTRY="$SKILL_DIR/assets/test-harness/slot-registry.json"

CHECK_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; }
info() { printf '  \033[36mℹ\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

SRC_DIR="$PLATFORM/docs/agent/contracts"
if [[ ! -d "$SRC_DIR" ]]; then
  bad "找不到平台契约目录：$SRC_DIR"
  printf '  请确认平台源码已下载并包含 docs/agent/contracts/ 目录。\n'
  exit 2
fi

head_ "【OpenLearnV2 平台契约水合与对齐】"
info "平台契约源: $SRC_DIR"
info "目标快照目录: $TARGET_DIR"

mkdir -p "$TARGET_DIR"

python3 - "$SRC_DIR" "$TARGET_DIR" "$LEGACY_SLOT_REGISTRY" "$CHECK_ONLY" <<'PY'
import json, os, sys

src_dir, target_dir, legacy_slots_path, check_only_str = sys.argv[1:5]
check_only = (check_only_str == "1")

required_files = [
    "capabilities.json",
    "slots.json",
    "forbidden-tables.json",
    "bridge-ops.json"
]

has_drift = False

for fname in required_files:
    src_file = os.path.join(src_dir, fname)
    target_file = os.path.join(target_dir, fname)

    if not os.path.exists(src_file):
        print(f"  \033[33m⚠\033[0m 平台源码缺文件: {fname}")
        continue

    with open(src_file, "r", encoding="utf-8") as f:
        src_data = json.load(f)

    target_data = None
    if os.path.exists(target_file):
        try:
            with open(target_file, "r", encoding="utf-8") as f:
                target_data = json.load(f)
        except Exception:
            target_data = None

    if src_data != target_data:
        has_drift = True
        if check_only:
            print(f"  \033[31m✘\033[0m {fname} 存在漂移")
        else:
            with open(target_file, "w", encoding="utf-8") as f:
                json.dump(src_data, f, ensure_ascii=False, indent=2)
            print(f"  \033[32m✔\033[0m 已水合同步: {fname}")
    else:
        print(f"  \033[32m✔\033[0m {fname} 保持最新")

# 同步旧版 slot-registry.json 保持向后兼容
slots_src = os.path.join(src_dir, "slots.json")
if os.path.exists(slots_src):
    with open(slots_src, "r", encoding="utf-8") as f:
        slots_data = json.load(f)
    ext_slots = slots_data.get("extension_slots", [])
    legacy_format = {
        "_comment": "由 scripts/hydrate-contracts.sh 自动同步自平台 docs/agent/contracts/slots.json",
        "count": len(ext_slots),
        "slots": sorted(ext_slots)
    }
    old_legacy = None
    if os.path.exists(legacy_slots_path):
        try:
            with open(legacy_slots_path, "r", encoding="utf-8") as f:
                old_legacy = json.load(f)
        except Exception:
            old_legacy = None

    if not old_legacy or old_legacy.get("slots") != legacy_format.get("slots"):
        has_drift = True
        if check_only:
            print("  \033[31m✘\033[0m slot-registry.json 存在漂移")
        else:
            with open(legacy_slots_path, "w", encoding="utf-8") as f:
                json.dump(legacy_format, f, ensure_ascii=False, indent=2)
            print("  \033[32m✔\033[0m 已同步更新旧版 slot-registry.json")
    else:
        print("  \033[32m✔\033[0m slot-registry.json 保持最新")

if check_only:
    if has_drift:
        print("\n检出契约漂移：请运行 bash scripts/hydrate-contracts.sh 完成同步。")
        sys.exit(1)
    else:
        print("\n契约全部一致，无漂移。")
        sys.exit(0)
else:
    print("\n水合完成！本地测试护栏与 Grilling 向导现已直连平台最新真源。")
    sys.exit(0)
PY
