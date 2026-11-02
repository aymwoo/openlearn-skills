#!/usr/bin/env bash
# grill-requirements.sh —— OpenLearnV2 插件需求梳理 Grilling 决策向导
#
# 用途：
#   提供逐个问题的单步交互式问答（像 /grill-me 一样），每个问题附带推荐选项与架构说明，
#   根据前序选项动态分支，遇违规架构即时摩擦拦截，梳理完成后自动生成 plugin.contract.json。
#
# 用法：
#   bash scripts/grill-requirements.sh
#   bash scripts/grill-requirements.sh --output /path/to/plugin.contract.json
#   bash scripts/grill-requirements.sh --dump-questions
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/grill-requirements.py" "$@"
