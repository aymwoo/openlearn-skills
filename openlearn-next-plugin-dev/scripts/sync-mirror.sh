#!/usr/bin/env bash
# sync-mirror.sh —— GitHub / Gitee 双远端同步
#
# 约定：
#   origin / github  = GitHub（主）
#   gitee            = Gitee（镜像；仅 references/repo-mirrors.json 登记过的仓库）
#
# 策略：
#   push       GitHub 优先；成功后再推 Gitee 做镜像。GitHub 不可达/无权限时只推 Gitee，
#              并明确提示「GitHub 待同步」。
#   fetch      GitHub 优先；不可达时从 Gitee fetch。
#   sync-main  在一个平台合并 PR 后，把该平台 main 快进到另一个平台；绝不 force-push。
#
# 用法：
#   bash scripts/sync-mirror.sh status [--repo owner/repo] [--local PATH] [--json]
#   bash scripts/sync-mirror.sh fetch  [--repo owner/repo] [--local PATH]
#   bash scripts/sync-mirror.sh push <branch> [--repo owner/repo] [--local PATH]
#   bash scripts/sync-mirror.sh sync-main --from github|gitee [--repo owner/repo] [--local PATH]
#
# 退出码：
#   0 = 成功 / 已同步
#   1 = 需要人工处理（分叉、目标不可达等）
#   2 = 参数或环境错误 / 两个平台都失败
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/platform-probe.sh"
TIMEOUT="${PLATFORM_PROBE_TIMEOUT:-8}"

REPO=""
LOCAL=""
JSON=0
DRY_RUN=0

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$1"; }
info() { printf '  \033[36mℹ\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

usage() {
  local exit_code="${1:-2}"
  cat <<'EOF'
GitHub / Gitee 双远端同步（GitHub 优先，Gitee 按镜像表回退）

用法：
  bash scripts/sync-mirror.sh status [--repo owner/repo] [--local PATH] [--json]
  bash scripts/sync-mirror.sh fetch  [--repo owner/repo] [--local PATH]
  bash scripts/sync-mirror.sh push <branch> [--repo owner/repo] [--local PATH] [--dry-run]
  bash scripts/sync-mirror.sh sync-main --from github|gitee [--repo owner/repo] [--local PATH] [--dry-run]

子命令：
  status     只读检查两个平台的 main 是否一致
  fetch      GitHub 优先 fetch；不可达时从 Gitee fetch
  push       推分支：GitHub 优先，成功后镜像到 Gitee；GitHub 失败则只推 Gitee
  sync-main  合并 PR 后同步 main；--from 指定「在哪个平台合并的」

选项：
  --repo owner/repo   目标 GitHub 仓库；省略时从 --local 的 remote 推断
  --local PATH        本地仓库路径；省略时使用当前目录（若在 git 仓库内）
  --json              仅 status 支持，输出机读 JSON
  --dry-run           push / sync-main 只演练，不真正推送
  -h, --help          显示本帮助
EOF
  exit "$exit_code"
}

if [[ ! -x "$PROBE" && ! -f "$PROBE" ]]; then
  echo "缺少 $PROBE" >&2
  exit 2
fi

resolve_local() {
  if [[ -z "$LOCAL" ]] && git rev-parse --show-toplevel >/dev/null 2>&1; then
    LOCAL="$(git rev-parse --show-toplevel)"
  fi
  if [[ -n "$LOCAL" && -d "$LOCAL" ]]; then
    LOCAL="$(cd "$LOCAL" && pwd)"
  fi
  if [[ -z "$LOCAL" || ( ! -d "$LOCAL/.git" && ! -f "$LOCAL/.git" ) ]]; then
    echo "找不到本地 git 仓库；请用 --local 指定，或进入仓库目录后重试" >&2
    exit 2
  fi
}

probe_json() {
  local args=(--json --timeout "$TIMEOUT")
  [[ -n "$REPO" ]] && args+=(--repo "$REPO")
  [[ -n "$LOCAL" ]] && args+=(--local "$LOCAL")
  bash "$PROBE" "${args[@]}"
}

json_get() {
  local path="$1"
  printf '%s' "$PROBE_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d = d.get(k) if isinstance(d, dict) else None
if isinstance(d, bool):
    print("true" if d else "false")
elif d is None:
    print("")
else:
    print(d)
' "$path"
}

remote_url() {
  git -C "$LOCAL" remote get-url "$1" 2>/dev/null || true
}

remote_for_url() {
  local url="$1" r u
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    u="$(remote_url "$r")"
    [[ "$u" == "$url" ]] && { echo "$r"; return 0; }
  done < <(git -C "$LOCAL" remote 2>/dev/null)
  return 1
}

ensure_remote() {
  local name="$1" url="$2"
  [[ -n "$url" ]] || return 1
  if ! remote_url "$name" >/dev/null 2>&1 || [[ -z "$(remote_url "$name")" ]]; then
    git -C "$LOCAL" remote add "$name" "$url" 2>/dev/null || true
  fi
}

load_probe() {
  PROBE_JSON="$(probe_json)"
  [[ -n "$REPO" ]] || REPO="$(json_get repo)"
  GH_URL="$(json_get github.url)"
  GT_URL="$(json_get gitee.url)"
  MIRROR="$(json_get mirror)"
  GH_GIT="$(json_get github.git)"
  GH_PUSH="$(json_get github.push)"
  GT_GIT="$(json_get gitee.git)"
  GT_PUSH="$(json_get gitee.push)"

  GH_REMOTE="$(remote_for_url "$GH_URL" || true)"
  [[ -n "$GH_REMOTE" ]] || GH_REMOTE="origin"
  ensure_remote "$GH_REMOTE" "$GH_URL"

  GT_REMOTE=""
  if [[ -n "$GT_URL" ]]; then
    GT_REMOTE="$(remote_for_url "$GT_URL" || true)"
    [[ -n "$GT_REMOTE" ]] || GT_REMOTE="gitee"
    ensure_remote "$GT_REMOTE" "$GT_URL"
  fi
}

remote_main_sha() {
  local remote="$1"
  GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
    timeout "$TIMEOUT" git -C "$LOCAL" ls-remote --heads "$remote" refs/heads/main 2>/dev/null \
    | awk '{print $1}' | head -1
}

# 区分「网络/鉴权失败」（可回退 Gitee）与「远端拒绝」（不可回退，否则会把
# 非 fast-forward 的分支推到另一边造成分叉）。
classify_push_error() {
  local log="$1"
  if grep -qiE 'non-fast-forward|fetch first|\[rejected\]|protected branch|pre-receive hook declined|hook declined' "$log"; then
    echo "rejected"
  elif grep -qiE 'authentication failed|could not read Username|permission denied|access denied|403 forbidden|invalid username or password' "$log"; then
    echo "auth"
  else
    echo "network"
  fi
}

# ── status ────────────────────────────────────────────────────────────────────
cmd_status() {
  resolve_local
  load_probe

  local gh_sha gt_sha
  gh_sha="$(remote_main_sha "$GH_REMOTE")"
  gt_sha=""
  [[ -n "$GT_REMOTE" ]] && gt_sha="$(remote_main_sha "$GT_REMOTE")"

  if [[ "$JSON" == 1 ]]; then
    export REPO LOCAL GH_URL GT_URL GH_REMOTE GT_REMOTE GH_SHA="$gh_sha" GT_SHA="$gt_sha"
    python3 - <<'PY'
import json, os
print(json.dumps({
    "repo": os.environ.get("REPO", ""),
    "local": os.environ.get("LOCAL", ""),
    "github": {"remote": os.environ.get("GH_REMOTE", ""), "url": os.environ.get("GH_URL", ""), "main": os.environ.get("GH_SHA", "")},
    "gitee": {"remote": os.environ.get("GT_REMOTE", ""), "url": os.environ.get("GT_URL", ""), "main": os.environ.get("GT_SHA", "")},
    "inSync": bool(os.environ.get("GH_SHA")) and os.environ.get("GH_SHA") == os.environ.get("GT_SHA"),
}, ensure_ascii=False, indent=2))
PY
    return 0
  fi

  head_ "【双远端状态】${REPO:-$LOCAL}"
  if [[ -n "$gh_sha" ]]; then ok "GitHub $GH_REMOTE/main: ${gh_sha:0:7}"; else bad "GitHub main 不可达（$GH_URL）"; fi
  if [[ -n "$GT_REMOTE" ]]; then
    if [[ -n "$gt_sha" ]]; then ok "Gitee  $GT_REMOTE/main: ${gt_sha:0:7}"; else bad "Gitee main 不可达（$GT_URL）"; fi
  else
    warn "未登记 Gitee 镜像：只检查 GitHub"
  fi

  if [[ -n "$gh_sha" && -n "$gt_sha" ]]; then
    if [[ "$gh_sha" == "$gt_sha" ]]; then
      ok "两边 main 一致"
    else
      warn "两边 main 不一致（合并 PR 后请运行 sync-main）"
    fi
  fi
  return 0
}

# ── fetch ─────────────────────────────────────────────────────────────────────
cmd_fetch() {
  resolve_local
  load_probe

  head_ "【fetch】${REPO:-$LOCAL}"
  if [[ "$GH_GIT" == "true" ]]; then
    if git -C "$LOCAL" fetch "$GH_REMOTE" --prune; then
      ok "已从 GitHub fetch（$GH_REMOTE）"
      return 0
    fi
    warn "GitHub fetch 失败，尝试 Gitee"
  else
    warn "GitHub git 不可达，尝试 Gitee"
  fi

  if [[ -n "$GT_REMOTE" && "$GT_GIT" == "true" ]]; then
    if git -C "$LOCAL" fetch "$GT_REMOTE" --prune; then
      ok "已从 Gitee fetch（$GT_REMOTE）"
      warn "本次使用的是 Gitee 镜像；GitHub 恢复后请再 fetch 一次 origin"
      return 0
    fi
  fi

  bad "GitHub 与 Gitee 都 fetch 失败"
  return 2
}

# ── push ──────────────────────────────────────────────────────────────────────
cmd_push() {
  local branch="${1:-}"
  [[ -n "$branch" ]] || { echo "push 需要分支名" >&2; usage 2; }
  resolve_local
  load_probe

  local push_flags=()
  local suffix=""
  if [[ "$DRY_RUN" == 1 ]]; then
    push_flags+=(--dry-run)
    suffix="（dry-run）"
  fi

  head_ "【push】$branch$suffix"
  local github_ok=0 gitee_ok=0 github_err="" gitee_err=""
  local github_reason="" gitee_reason=""
  local gh_log gt_log
  gh_log="$(mktemp "${TMPDIR:-/tmp}/openlearn-gh-push.XXXXXX")"
  gt_log="$(mktemp "${TMPDIR:-/tmp}/openlearn-gt-push.XXXXXX")"

  if [[ "$GH_GIT" == "true" && "$GH_PUSH" == "true" ]]; then
    if git -C "$LOCAL" push "${push_flags[@]}" -u "$GH_REMOTE" "$branch" >"$gh_log" 2>&1; then
      github_ok=1
      ok "GitHub 推送成功（$GH_REMOTE）"
    else
      github_reason="$(classify_push_error "$gh_log")"
      github_err="git push $GH_REMOTE $branch 失败（$github_reason）"
      warn "GitHub 推送失败（$github_reason）"
      sed 's/^/      /' "$gh_log" | head -12
    fi
  else
    github_reason="unavailable"
    warn "GitHub git 不可达或无 push 权限，跳过"
  fi

  if [[ "$github_ok" == 1 ]]; then
    if [[ -n "$GT_REMOTE" && "$GT_GIT" == "true" && "$GT_PUSH" == "true" ]]; then
      if git -C "$LOCAL" push "${push_flags[@]}" "$GT_REMOTE" "$branch" >"$gt_log" 2>&1; then
        gitee_ok=1
        ok "Gitee 镜像推送成功（$GT_REMOTE）"
      else
        gitee_reason="$(classify_push_error "$gt_log")"
        gitee_err="git push $GT_REMOTE $branch 失败（$gitee_reason）"
        warn "Gitee 镜像推送失败；GitHub 已成功，稍后可重试"
        sed 's/^/      /' "$gt_log" | head -12
      fi
    elif [[ -n "$GT_REMOTE" ]]; then
      warn "Gitee 不可用，跳过镜像推送"
    fi
  elif [[ "$github_reason" == "rejected" ]]; then
    bad "GitHub 拒绝推送（非 fast-forward / 保护分支）；不自动回退 Gitee，避免把分叉带到另一边"
  else
    if [[ -n "$GT_REMOTE" && "$GT_GIT" == "true" && "$GT_PUSH" == "true" ]]; then
      if git -C "$LOCAL" push "${push_flags[@]}" -u "$GT_REMOTE" "$branch" >"$gt_log" 2>&1; then
        gitee_ok=1
        ok "Gitee 推送成功（$GT_REMOTE）"
        warn "GitHub 待同步：恢复后运行 bash scripts/sync-mirror.sh push $branch"
      else
        gitee_reason="$(classify_push_error "$gt_log")"
        gitee_err="git push $GT_REMOTE $branch 失败（$gitee_reason）"
        sed 's/^/      /' "$gt_log" | head -12
      fi
    fi
  fi

  printf '\n'
  if [[ "$github_ok" == 1 ]]; then info "GitHub：已同步"; else info "GitHub：未同步${github_err:+（$github_err）}"; fi
  if [[ -n "$GT_REMOTE" ]]; then
    if [[ "$gitee_ok" == 1 ]]; then info "Gitee：已同步"; else info "Gitee：未同步${gitee_err:+（$gitee_err）}"; fi
  else
    info "Gitee：无镜像"
  fi

  rm -f "$gh_log" "$gt_log" 2>/dev/null || true

  if [[ "$github_ok" == 1 || "$gitee_ok" == 1 ]]; then
    return 0
  fi
  [[ "$github_reason" == "rejected" ]] && return 1
  return 2
}

# ── sync-main ─────────────────────────────────────────────────────────────────
cmd_sync_main() {
  local from=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      --repo) REPO="${2:-}"; shift 2 ;;
      --local) LOCAL="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      *) echo "未知参数：$1" >&2; usage 2 ;;
    esac
  done
  [[ "$from" == "github" || "$from" == "gitee" ]] || { echo "sync-main 需要 --from github|gitee" >&2; usage 2; }

  resolve_local
  load_probe

  local src dst src_name dst_name
  if [[ "$from" == "github" ]]; then
    src="$GH_REMOTE"; dst="$GT_REMOTE"; src_name="GitHub"; dst_name="Gitee"
  else
    src="$GT_REMOTE"; dst="$GH_REMOTE"; src_name="Gitee"; dst_name="GitHub"
  fi
  if [[ -z "$src" || -z "$dst" ]]; then
    bad "缺少源或目标远端（源=$src_name:$src 目标=$dst_name:$dst）"
    return 1
  fi

  head_ "【sync-main】$src_name → $dst_name"

  if ! git -C "$LOCAL" fetch "$src" main; then
    bad "无法从 $src_name fetch main（$src）"
    return 1
  fi
  # 目标端也 fetch 一次，确保 merge-base 能判断是否 fast-forward；失败不阻断，
  # 后面直接 push 时由远端做 non-fast-forward 校验（绝不 force）。
  git -C "$LOCAL" fetch "$dst" main >/dev/null 2>&1 || true
  local src_sha tgt_sha
  src_sha="$(git -C "$LOCAL" rev-parse "$src/main" 2>/dev/null || true)"
  tgt_sha="$(remote_main_sha "$dst")"
  [[ -n "$src_sha" ]] || { bad "读不到 $src/main"; return 1; }

  if [[ -z "$tgt_sha" ]]; then
    info "$dst_name 尚无 main，直接推送"
  elif [[ "$src_sha" == "$tgt_sha" ]]; then
    ok "两边 main 已一致（${src_sha:0:7}），无需同步"
    return 0
  elif git -C "$LOCAL" merge-base --is-ancestor "$tgt_sha" "$src_sha" 2>/dev/null; then
    info "$dst_name 落后，执行 fast-forward 推送"
  elif git -C "$LOCAL" merge-base --is-ancestor "$src_sha" "$tgt_sha" 2>/dev/null; then
    warn "$dst_name 已领先 $src_name；本次无需同步（不要反向覆盖）"
    return 0
  else
    bad "两边 main 已分叉，不能自动同步"
    info "请先在本地合并两边 main，解决冲突后再运行 sync-main；绝不 force-push"
    return 1
  fi

  local push_flags=()
  [[ "$DRY_RUN" == 1 ]] && push_flags+=(--dry-run)
  if git -C "$LOCAL" push "${push_flags[@]}" "$dst" "$src_sha:main"; then
    ok "已推送 $src_name/main → $dst_name/main（${src_sha:0:7}）"
    [[ "$DRY_RUN" == 1 ]] || git -C "$LOCAL" fetch "$dst" main >/dev/null 2>&1 || true
    return 0
  fi

  bad "推送失败；目标可能不可达或非 fast-forward"
  return 1
}

# ── 入口 ──────────────────────────────────────────────────────────────────────
cmd="${1:-}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  status)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --local) LOCAL="${2:-}"; shift 2 ;;
        --json) JSON=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "未知参数：$1" >&2; usage 2 ;;
      esac
    done
    cmd_status
    ;;
  fetch)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --local) LOCAL="${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "未知参数：$1" >&2; usage 2 ;;
      esac
    done
    cmd_fetch
    ;;
  push)
    BRANCH="${1:-}"
    [[ $# -gt 0 ]] && shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --local) LOCAL="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "未知参数：$1" >&2; usage 2 ;;
      esac
    done
    cmd_push "$BRANCH"
    ;;
  sync-main)
    cmd_sync_main "$@"
    ;;
  -h|--help|"")
    usage 0
    ;;
  *)
    echo "未知命令：$cmd" >&2
    usage 2
    ;;
esac
