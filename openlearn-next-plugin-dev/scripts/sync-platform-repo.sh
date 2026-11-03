#!/usr/bin/env bash
# sync-platform-repo.sh —— OpenLearnV2 平台源码管理与更新检查
#
# 用途：
#   1. 初次运行检测：检查本地是否存在平台仓库（默认 ~/Develop/openlearnv2），
#      若未下载，引导用户选择是否在空闲/后台下载，或继续以快照模式运行；
#   2. 更新检测：轻量比对本地 HEAD 与远端 origin/main，若有更新提示拉取并联动 facts-check.sh；
#   3. 空闲/后台下载：支持 --bg / --idle 异步浅克隆，不阻断当前插件开发心流。
#
# 用法：
#   bash scripts/sync-platform-repo.sh check [--json]
#   bash scripts/sync-platform-repo.sh clone [--bg|--idle] [--depth 1] [--target PATH]
#   bash scripts/sync-platform-repo.sh update [--no-facts]
#   bash scripts/sync-platform-repo.sh status
#   bash scripts/sync-platform-repo.sh skip
#
# 退出码：
#   0 = 状态正常 / 已是最新 / 后台任务已就绪
#   1 = 需要关注（仓库缺失或有更新）
#   2 = 参数或执行环境错误
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_REPO="https://github.com/aymwoo/OpenLearn-Next-V2.git"
DEFAULT_MIRROR="https://gitee.com/aymwoo/openlearn-next.git"
DEFAULT_TARGET="$HOME/Develop/openlearnv2"
CONFIG_FILE="${OPENLEARN_CONFIG:-$HOME/.config/openlearn/platform-repo.json}"
PID_FILE="${TMPDIR:-/tmp}/openlearnv2-clone.pid"
LOG_FILE="${TMPDIR:-/tmp}/openlearnv2-clone.log"

# 彩色输出助手
ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$1"; }
info() { printf '  \033[36mℹ\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ── 配置持久化辅助函数 ────────────────────────────────────────────────────────
get_configured_path() {
  python3 -c "
import json, os, sys
cfg_path = os.path.expanduser('$CONFIG_FILE')
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
        val = cfg.get('platformPath', '')
        if val:
            print(val)
            sys.exit(0)
    except Exception:
        pass
print('')
" 2>/dev/null || echo ""
}

get_preference() {
  python3 -c "
import json, os, sys
cfg_path = os.path.expanduser('$CONFIG_FILE')
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
        val = cfg.get('downloadPreference', '')
        if val:
            print(val)
            sys.exit(0)
    except Exception:
        pass
print('')
" 2>/dev/null || echo ""
}

save_config_kv() {
  local key="$1"
  local val="$2"
  python3 -c "
import json, os, sys
cfg_path = os.path.expanduser('$CONFIG_FILE')
os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
cfg = {}
if os.path.exists(cfg_path):
    try:
        with open(cfg_path, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}
cfg['$key'] = '$val'
with open(cfg_path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
}

# ── 路径解析 ──────────────────────────────────────────────────────────────────
resolve_target() {
  if [[ -n "${OVERRIDE_TARGET:-}" ]]; then
    echo "$OVERRIDE_TARGET"
  elif [[ -n "${PLATFORM_REPO:-}" ]]; then
    echo "$PLATFORM_REPO"
  else
    local cfg_target
    cfg_target="$(get_configured_path)"
    if [[ -n "$cfg_target" && -d "$cfg_target" ]]; then
      echo "$cfg_target"
    elif [[ -d "$DEFAULT_TARGET" ]]; then
      echo "$DEFAULT_TARGET"
    elif [[ -n "$cfg_target" ]]; then
      echo "$cfg_target"
    else
      echo "$DEFAULT_TARGET"
    fi
  fi
}

resolve_repo() {
  echo "${OVERRIDE_REPO:-$DEFAULT_REPO}"
}

resolve_mirror_for() {
  local target="$1"
  if [[ -n "${OVERRIDE_MIRROR:-}" ]]; then
    echo "$OVERRIDE_MIRROR"
    return 0
  fi
  local configured
  configured="$(git -C "$target" remote get-url gitee 2>/dev/null || true)"
  if [[ -n "$configured" ]]; then
    echo "$configured"
  else
    echo "$DEFAULT_MIRROR"
  fi
}

ensure_gitee_remote() {
  local target="$1" mirror="$2"
  [[ -n "$mirror" ]] || return 0
  if [[ -z "$(git -C "$target" remote get-url gitee 2>/dev/null || true)" ]]; then
    git -C "$target" remote add gitee "$mirror" 2>/dev/null || true
  fi
}

# 统一远端约定：origin = GitHub 主仓，gitee = Gitee 镜像。
# 若仓库是从 Gitee 镜像克隆的，先把 origin 改名为 gitee，再补上 GitHub origin。
configure_remotes() {
  local target="$1" origin_url="$2" mirror="$3"
  local current_origin
  current_origin="$(git -C "$target" remote get-url origin 2>/dev/null || true)"

  if [[ -n "$mirror" && "$current_origin" == "$mirror" ]]; then
    git -C "$target" remote rename origin gitee 2>/dev/null || true
    current_origin=""
  fi

  if [[ -n "$origin_url" ]]; then
    if [[ -z "$current_origin" ]]; then
      git -C "$target" remote add origin "$origin_url" 2>/dev/null || true
    elif [[ "$current_origin" != "$origin_url" ]]; then
      git -C "$target" remote set-url origin "$origin_url" 2>/dev/null || true
    fi
  fi

  ensure_gitee_remote "$target" "$mirror"
}

remote_head() {
  local url="$1" branch="${2:-main}"
  [[ -n "$url" ]] || return 0
  python3 - "$url" "$branch" <<'PY' 2>/dev/null || true
import subprocess, sys

url, branch = sys.argv[1], sys.argv[2]
try:
    res = subprocess.run(
        ["git", "ls-remote", "--heads", url, f"refs/heads/{branch}"],
        capture_output=True, text=True, timeout=6, check=True,
        env={**__import__("os").environ, "GIT_TERMINAL_PROMPT": "0"},
    )
    for line in res.stdout.strip().splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == f"refs/heads/{branch}":
            print(parts[0])
            break
except Exception:
    pass
PY
}

# ── 检查后台克隆状态 ─────────────────────────────────────────────────────────
check_bg_clone() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || echo "")"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "RUNNING:$pid"
      return 0
    else
      # 进程已结束，清理 pid 文件
      rm -f "$PID_FILE" 2>/dev/null || true
      echo "FINISHED"
      return 0
    fi
  fi
  echo "NONE"
  return 0
}

# ── 子命令：check ─────────────────────────────────────────────────────────────
cmd_check() {
  local json_mode=0
  local target
  target="$(resolve_target)"
  local repo
  repo="$(resolve_repo)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)   json_mode=1; shift ;;
      --target) OVERRIDE_TARGET="$2"; target="$2"; shift 2 ;;
      --repo)   OVERRIDE_REPO="$2"; repo="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local bg_state
  bg_state="$(check_bg_clone)"

  # 1. 后台克隆进行中
  if [[ "$bg_state" == RUNNING:* ]]; then
    local bg_pid="${bg_state#RUNNING:}"
    if [[ $json_mode -eq 1 ]]; then
      python3 -c "
import json
print(json.dumps({
    'status': 'cloning',
    'bgPid': int('$bg_pid'),
    'target': '$target',
    'logFile': '$LOG_FILE',
    'message': '后台克隆任务正在执行中，当前处于快照降级模式'
}, ensure_ascii=False, indent=2))"
    else
      head_ "【OpenLearnV2 平台源码状态】"
      info "后台克隆任务正在执行中（PID: $bg_pid）"
      info "目标路径: $target"
      info "日志文件: $LOG_FILE"
      info "当前会话已自动降级为「快照模式」（依赖 references/ 快照与 npm latest），无需等待下载完成。"
    fi
    return 0
  fi

  # 2. 本地不存在平台仓库
  if [[ ! -d "$target" || ! -d "$target/.git" ]]; then
    local pref
    pref="$(get_preference)"
    if [[ $json_mode -eq 1 ]]; then
      python3 -c "
import json
print(json.dumps({
    'status': 'missing',
    'target': '$target',
    'repo': '$repo',
    'preference': '$pref',
    'promptRequired': True,
    'options': [
        {'id': 1, 'label': '空闲/后台下载（推荐）', 'action': 'clone --bg'},
        {'id': 2, 'label': '立即前台浅克隆', 'action': 'clone --depth 1'},
        {'id': 3, 'label': '指定已有路径', 'action': 'config'},
        {'id': 4, 'label': '暂不下载（快照模式）', 'action': 'skip'}
    ]
}, ensure_ascii=False, indent=2))"
    else
      head_ "【OpenLearnV2 平台源码检查】"
      warn "未检测到本地平台源码仓库：$target"
      printf '\n'
      printf '  💡 OpenLearnV2 插件开发遵循「平台一手源优先，源码是最终真理」。\n'
      printf '     本地拥有源码可用于运行契约校验（facts-check.sh）与真实行为探活。\n'
      printf '\n'
      printf '  请选择您的处置方式：\n'
      printf '  [1] (推荐) 空闲/后台下载：在后台异步浅克隆，当前会话以快照模式继续\n'
      printf '      → 命令：bash scripts/sync-platform-repo.sh clone --bg\n'
      printf '  [2] 立即前台浅克隆：快速下载当前主干（体积约几 MB，耗时数秒）\n'
      printf '      → 命令：bash scripts/sync-platform-repo.sh clone --depth 1\n'
      printf '  [3] 指定已有源码路径：若已在其他目录存在仓库，配置环境变量或路径\n'
      printf '      → 命令：export PLATFORM_REPO=/path/to/openlearnv2\n'
      printf '  [4] 暂不下载：仅依赖 references/ 快照与 npm latest 规则开发（跳过源码校验）\n'
      printf '      → 命令：bash scripts/sync-platform-repo.sh skip\n'
    fi
    return 1
  fi

  # 3. 本地仓库已存在，进行版本与远端更新检查
  local local_head
  local_head="$(git -C "$target" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  local local_full
  local_full="$(git -C "$target" rev-parse HEAD 2>/dev/null || echo "")"
  local current_branch
  current_branch="$(git -C "$target" branch --show-current 2>/dev/null || echo "detached")"

  # 查询远端 main 最新 commit（GitHub 优先，Gitee 镜像回退）
  local mirror remote_main remote_source
  mirror="$(resolve_mirror_for "$target")"
  remote_main="$(remote_head "$repo" main)"
  remote_source=""
  if [[ -n "$remote_main" ]]; then
    remote_source="github"
  elif [[ -n "$mirror" ]]; then
    remote_main="$(remote_head "$mirror" main)"
    [[ -n "$remote_main" ]] && remote_source="gitee"
  fi
  [[ -z "$remote_source" ]] && remote_source="none"

  local is_dirty=0
  if [[ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]]; then
    is_dirty=1
  fi

  local status="up_to_date"
  local remote_short=""
  if [[ -n "$remote_main" ]]; then
    remote_short="${remote_main:0:7}"
    if [[ "$local_full" != "$remote_main" ]]; then
      # 检查本地是否已经包含远端 commit（避免分支切换误判）
      local has_commit
      has_commit="$(git -C "$target" branch --contains "$remote_main" 2>/dev/null || echo "")"
      if [[ -z "$has_commit" ]]; then
        status="behind"
      fi
    fi
  else
    status="local_only"
  fi

  if [[ $json_mode -eq 1 ]]; then
    python3 -c "
import json
print(json.dumps({
    'status': '$status',
    'target': '$target',
    'branch': '$current_branch',
    'localHead': '$local_head',
    'remoteHead': '$remote_short',
    'remoteSource': '$remote_source',
    'mirror': '$mirror',
    'isDirty': bool($is_dirty),
    'promptRequired': ('$status' == 'behind'),
    'updateCommand': 'bash scripts/sync-platform-repo.sh update'
}, ensure_ascii=False, indent=2))"
  else
    head_ "【OpenLearnV2 平台源码状态】"
    ok "本地平台仓库: $target"
    info "当前分支/提交: $current_branch ($local_head)"
    if [[ $is_dirty -eq 1 ]]; then
      warn "工作区有未提交的改动"
    fi

    if [[ "$status" == "up_to_date" ]]; then
      ok "平台源码已是最新（对齐 $remote_source 的 main: $remote_short）"
      return 0
    elif [[ "$status" == "behind" ]]; then
      warn "检测到平台源码有更新！"
      printf '     本地提交: %s  →  远端最新: %s（来源: %s）\n' "$local_head" "$remote_short" "$remote_source"
      printf '     建议更新：bash scripts/sync-platform-repo.sh update\n'
      printf '     （拉取最新代码并联动 facts-check.sh 复核契约锚点）\n'
      return 1
    else
      info "网络检查超时或离线，沿用本地源码快照"
      return 0
    fi
  fi
}

# ── 子命令：clone ─────────────────────────────────────────────────────────────
cmd_clone() {
  local is_bg=0
  local depth=1
  local full=0
  local target
  target="$(resolve_target)"
  local repo
  repo="$(resolve_repo)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bg|--idle) is_bg=1; shift ;;
      --full)      full=1; shift ;;
      --depth)     depth="${2:-1}"; shift 2 ;;
      --target)    OVERRIDE_TARGET="$2"; target="$2"; shift 2 ;;
      --repo)      OVERRIDE_REPO="$2"; repo="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # 如果目标已存在
  if [[ -d "$target/.git" ]]; then
    ok "平台仓库已存在于：$target"
    configure_remotes "$target" "$repo" "$(resolve_mirror_for "$target")"
    save_config_kv "platformPath" "$target"
    return 0
  fi

  # 检查是否已在后台克隆
  local bg_state
  bg_state="$(check_bg_clone)"
  if [[ "$bg_state" == RUNNING:* ]]; then
    warn "克隆任务已在后台运行中（PID: ${bg_state#RUNNING:}）"
    info "查看日志: tail -f $LOG_FILE"
    return 0
  fi

  mkdir -p "$(dirname "$target")"

  local mirror clone_repo
  mirror="$(resolve_mirror_for "$target")"
  clone_repo="$repo"
  if [[ -z "$(remote_head "$repo" main)" ]]; then
    if [[ -n "$mirror" && -n "$(remote_head "$mirror" main)" ]]; then
      warn "GitHub 不可达，改用 Gitee 镜像克隆：$mirror"
      clone_repo="$mirror"
    fi
  fi

  local clone_args=()
  if [[ $full -eq 0 ]]; then
    clone_args+=(--depth "$depth")
  fi
  clone_args+=("$clone_repo" "$target")

  if [[ $is_bg -eq 1 ]]; then
    # 后台模式：由内部 worker 完成克隆，并在克隆后统一配置 origin/gitee 远端
    head_ "【启动后台空闲下载】"
    local worker_args=(__clone-worker --target "$target" --clone-url "$clone_repo"
      --origin-url "$repo" --mirror-url "$mirror" --depth "$depth")
    [[ $full -eq 1 ]] && worker_args+=(--full)
    nohup bash "$SCRIPT_DIR/sync-platform-repo.sh" "${worker_args[@]}" > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    save_config_kv "platformPath" "$target"
    save_config_kv "downloadPreference" "background"

    ok "已在后台启动平台仓库下载任务（PID: $pid）"
    info "克隆地址: $clone_repo"
    info "目标路径: $target"
    info "日志输出: $LOG_FILE"
    info "当前开发可立即继续！会话将以『快照模式』运行，不受下载影响。"
    info "可随时运行 bash scripts/sync-platform-repo.sh status 查看进度。"
    return 0
  else
    # 前台同步模式
    head_ "【开始下载平台仓库】"
    info "执行命令: git clone ${clone_args[*]}"
    if git clone "${clone_args[@]}"; then
      configure_remotes "$target" "$repo" "$mirror"
      save_config_kv "platformPath" "$target"
      save_config_kv "downloadPreference" "completed"
      ok "平台仓库下载成功: $target"
      info "远端约定: origin = GitHub 主仓, gitee = Gitee 镜像"
      return 0
    else
      bad "克隆失败，请检查网络连接或权限"
      return 2
    fi
  fi
}

# ── 内部子命令：后台克隆 worker ──────────────────────────────────────────────
cmd_clone_worker() {
  local target="" clone_url="" origin_url="" mirror="" depth=1 full=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)     target="$2"; shift 2 ;;
      --clone-url)  clone_url="$2"; shift 2 ;;
      --origin-url) origin_url="$2"; shift 2 ;;
      --mirror-url) mirror="$2"; shift 2 ;;
      --depth)      depth="$2"; shift 2 ;;
      --full)       full=1; shift ;;
      *) shift ;;
    esac
  done

  if [[ -z "$target" || -z "$clone_url" ]]; then
    echo "clone worker: 缺少 --target 或 --clone-url" >&2
    return 2
  fi

  local clone_args=()
  if [[ $full -eq 0 ]]; then
    clone_args+=(--depth "$depth")
  fi
  clone_args+=("$clone_url" "$target")

  if git clone "${clone_args[@]}"; then
    configure_remotes "$target" "$origin_url" "$mirror"
    echo "REMOTES_CONFIGURED: origin=${origin_url:-未设置}, gitee=${mirror:-未设置}"
    return 0
  fi
  echo "CLONE_FAILED" >&2
  return 2
}

# ── 子命令：update ────────────────────────────────────────────────────────────
cmd_update() {
  local target
  target="$(resolve_target)"
  local run_facts=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-facts) run_facts=0; shift ;;
      --target)   OVERRIDE_TARGET="$2"; target="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ ! -d "$target/.git" ]]; then
    bad "找不到本地平台仓库：$target"
    info "请先执行 clone：bash scripts/sync-platform-repo.sh clone --bg"
    return 2
  fi

  head_ "【更新平台仓库源码】"
  info "仓库路径: $target"

  # 检查工作区干净度
  if [[ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]]; then
    warn "检测到工作区存在未提交的修改，为防止覆盖工作，跳过自动合并！"
    info "建议先在 $target 中提交或执行 git stash，然后再行更新。"
    return 1
  fi

  local current_branch
  current_branch="$(git -C "$target" branch --show-current 2>/dev/null || echo "")"
  local old_head
  old_head="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"

  # 统一远端约定，并探测 GitHub 可达性；不可达时才回退 Gitee 镜像
  local repo mirror
  repo="$(resolve_repo)"
  mirror="$(resolve_mirror_for "$target")"
  configure_remotes "$target" "$repo" "$mirror"

  if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
    info "当前位于主干分支 ($current_branch)，执行 fast-forward pull..."
    if [[ -n "$(remote_head "$repo" "$current_branch")" ]]; then
      if git -C "$target" pull --ff-only origin "$current_branch"; then
        local new_head
        new_head="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
        ok "平台主干已更新（来源: GitHub）: $old_head → $new_head"
      else
        bad "GitHub pull 失败，可能存在分支冲突，请手动检查 $target"
        return 1
      fi
    elif [[ -n "$mirror" && -n "$(remote_head "$mirror" "$current_branch")" ]]; then
      warn "GitHub 不可达，回退 Gitee 镜像拉取..."
      if git -C "$target" pull --ff-only gitee "$current_branch"; then
        local new_head
        new_head="$(git -C "$target" rev-parse --short HEAD 2>/dev/null)"
        ok "平台主干已更新（来源: Gitee 镜像）: $old_head → $new_head"
      else
        bad "Gitee pull 失败，可能存在分支冲突，请手动检查 $target"
        return 1
      fi
    else
      bad "GitHub 与 Gitee 均不可达，无法更新"
      info "可先运行 bash scripts/platform-probe.sh 诊断网络与鉴权"
      return 1
    fi
  else
    info "当前位于开发分支 ($current_branch)，安全拉取远端 main 引用..."
    if [[ -n "$(remote_head "$repo" main)" ]]; then
      if git -C "$target" fetch origin main:main 2>/dev/null || git -C "$target" fetch origin main; then
        local remote_main_short
        remote_main_short="$(git -C "$target" rev-parse --short origin/main 2>/dev/null || echo "")"
        ok "已安全同步远端 origin/main ($remote_main_short)，保持当前分支 ($current_branch) 不受影响"
      else
        bad "fetch 失败，请检查网络连接"
        return 1
      fi
    elif [[ -n "$mirror" && -n "$(remote_head "$mirror" main)" ]]; then
      warn "GitHub 不可达，改从 Gitee 镜像同步 main 引用..."
      if git -C "$target" fetch gitee main:refs/remotes/gitee/main; then
        local mirror_main_short
        mirror_main_short="$(git -C "$target" rev-parse --short gitee/main 2>/dev/null || echo "")"
        ok "已同步 gitee/main ($mirror_main_short)，保持当前分支 ($current_branch) 不受影响"
        info "注意：Gitee 镜像可能滞后于 GitHub，未改动 origin/main"
      else
        bad "Gitee fetch 失败，请检查网络连接"
        return 1
      fi
    else
      bad "GitHub 与 Gitee 均不可达，无法同步 main 引用"
      return 1
    fi
  fi

  if [[ -f "$SCRIPT_DIR/hydrate-contracts.sh" ]]; then
    head_ "【联动水合平台契约元数据】"
    PLATFORM_REPO="$target" bash "$SCRIPT_DIR/hydrate-contracts.sh" || true
  fi

  if [[ $run_facts -eq 1 && -f "$SCRIPT_DIR/facts-check.sh" ]]; then
    head_ "【联动运行集成事实校验】"
    PLATFORM_REPO="$target" bash "$SCRIPT_DIR/facts-check.sh" || true
  fi
  return 0
}

# ── 子命令：status ────────────────────────────────────────────────────────────
cmd_status() {
  local target
  target="$(resolve_target)"
  head_ "【OpenLearnV2 平台仓库与同步任务概况】"

  local bg_state
  bg_state="$(check_bg_clone)"
  if [[ "$bg_state" == RUNNING:* ]]; then
    info "后台克隆任务: 进行中 (PID: ${bg_state#RUNNING:})"
    info "日志尾部 (最新 5 行)："
    tail -n 5 "$LOG_FILE" 2>/dev/null | sed 's/^/    /' || true
  elif [[ -f "$LOG_FILE" ]]; then
    info "最近克隆日志: $LOG_FILE"
  fi

  if [[ -d "$target/.git" ]]; then
    ok "本地仓库路径: $target"
    local branch
    branch="$(git -C "$target" branch --show-current 2>/dev/null || echo "detached")"
    local head
    head="$(git -C "$target" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
    info "当前提交: $branch ($head)"
    local origin_url gitee_url
    origin_url="$(git -C "$target" remote get-url origin 2>/dev/null || echo "未配置")"
    gitee_url="$(git -C "$target" remote get-url gitee 2>/dev/null || echo "未配置")"
    info "远端 origin: $origin_url"
    info "远端 gitee : $gitee_url"
  else
    warn "本地尚未克隆仓库（目标路径: $target）"
  fi

  local pref
  pref="$(get_preference)"
  if [[ -n "$pref" ]]; then
    info "已记录用户偏好: $pref"
  fi
  return 0
}

# ── 子命令：skip ─────────────────────────────────────────────────────────────
cmd_skip() {
  save_config_kv "downloadPreference" "skip"
  ok "已记录偏好：暂不下载平台源码（使用 references/ 快照模式）"
  info "后续随时可通过 bash scripts/sync-platform-repo.sh clone --bg 开启下载"
  return 0
}

# ── 入口分发 ──────────────────────────────────────────────────────────────────
usage() {
  local exit_code="${1:-2}"
  cat <<'EOF'
OpenLearnV2 平台源码管理与更新检查工具

远端约定：
  origin = GitHub 主仓 (aymwoo/OpenLearn-Next-V2)
  gitee  = Gitee 镜像 (aymwoo/openlearn-next)
  GitHub 可达时始终优先 GitHub；仅在网络/鉴权失败时回退 Gitee。

用法：
  bash scripts/sync-platform-repo.sh check [--json]
      检查本地仓库是否存在、是否需要更新提示、后台任务状态
  bash scripts/sync-platform-repo.sh clone [--bg|--idle] [--depth 1] [--target PATH]
      克隆平台源码；加 --bg 或 --idle 在后台空闲异步执行
      GitHub 不可达时自动改用 Gitee 镜像克隆
  bash scripts/sync-platform-repo.sh update [--no-facts]
      安全更新本地平台源码并联动运行 facts-check.sh
      GitHub 不可达时回退 Gitee 镜像
  bash scripts/sync-platform-repo.sh status
      查看本地仓库状态、远端配置及后台任务执行进度
  bash scripts/sync-platform-repo.sh skip
      跳过下载提示并保持快照模式
EOF
  exit "$exit_code"
}

case "${1:-}" in
  check)  shift; cmd_check "$@" ;;
  clone)  shift; cmd_clone "$@" ;;
  update) shift; cmd_update "$@" ;;
  status) shift; cmd_status "$@" ;;
  skip)   shift; cmd_skip "$@" ;;
  __clone-worker) shift; cmd_clone_worker "$@" ;;
  -h|--help) usage 0 ;;
  "") usage 2 ;;
  *) echo "未知命令：$1"; usage 2 ;;
esac
