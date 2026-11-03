#!/usr/bin/env bash
# platform-probe.sh —— GitHub / Gitee 连通性与权限探测
#
# 策略：GitHub 优先；只有 references/repo-mirrors.json 登记了 Gitee 镜像的仓库才允许回退。
# 探测两类能力，分开报告，避免把「能 fetch」误当成「能提 issue / 能 push」：
#   - git   ：git ls-remote 能否连通（fetch / push 的网络前提）
#   - cli   ：gh / gitee 是否已登录且对该仓库有 push 权限（issue / PR / merge 的前提）
#
# 用法：
#   bash scripts/platform-probe.sh [--repo owner/repo] [--local PATH] [--json] [--timeout 8]
#
# 退出码：
#   0 = 至少一个平台可用
#   1 = 两个平台都不可用
#   2 = 参数或环境错误
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAPPING_FILE="$SKILL_DIR/references/repo-mirrors.json"
DEFAULT_REPO="aymwoo/OpenLearn-Next-V2"
TIMEOUT="${PLATFORM_PROBE_TIMEOUT:-8}"

REPO=""
LOCAL=""
JSON=0

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$1"; }
info() { printf '  \033[36mℹ\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

usage() {
  local exit_code="${1:-2}"
  cat <<'EOF'
GitHub / Gitee 连通性与权限探测（GitHub 优先，Gitee 按镜像表回退）

用法：
  bash scripts/platform-probe.sh [--repo owner/repo] [--local PATH] [--json] [--timeout 8]

选项：
  --repo owner/repo   目标 GitHub 仓库；省略时从 --local 的 remote 推断
  --local PATH        本地仓库路径；省略时使用当前目录（若在 git 仓库内）
  --json              输出机读 JSON
  --timeout N         git/HTTP 探测超时秒数（默认 8，也可用 PLATFORM_PROBE_TIMEOUT）
  -h, --help          显示本帮助

输出字段（JSON）：
  github.git / github.cli / github.push    GitHub 的 git 连通、CLI 登录、push 权限
  gitee.git  / gitee.cli  / gitee.push     Gitee 的对应能力（无镜像时均为 false）
  preferred.fetch / preferred.issuePr / preferred.push
  fallback                                 回退平台；无镜像时为 none
EOF
  exit "$exit_code"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="${2:-}"; shift 2 ;;
    --local)   LOCAL="${2:-}"; shift 2 ;;
    --json)    JSON=1; shift ;;
    --timeout) TIMEOUT="${2:-8}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "未知参数：$1" >&2; usage 2 ;;
  esac
done

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]]; then
  echo "无效的 --timeout：$TIMEOUT" >&2
  exit 2
fi

# ── 本地仓库与 remote 解析 ────────────────────────────────────────────────────
if [[ -z "$LOCAL" ]] && git rev-parse --show-toplevel >/dev/null 2>&1; then
  LOCAL="$(git rev-parse --show-toplevel)"
fi
if [[ -n "$LOCAL" && -d "$LOCAL" ]]; then
  LOCAL="$(cd "$LOCAL" && pwd)"
fi
if [[ -n "$LOCAL" && ! -d "$LOCAL/.git" && ! -f "$LOCAL/.git" ]]; then
  # worktree 的 .git 是文件；两者都不存在则不是仓库
  LOCAL=""
fi

remote_url() {
  [[ -n "$LOCAL" ]] || return 1
  git -C "$LOCAL" remote get-url "$1" 2>/dev/null || true
}

find_remote_by_host() {
  local host="$1" r u
  [[ -n "$LOCAL" ]] || return 1
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    u="$(remote_url "$r")"
    case "$u" in
      *"$host"*) echo "$r"; return 0 ;;
    esac
  done < <(git -C "$LOCAL" remote 2>/dev/null)
  return 1
}

parse_repo_from_url() {
  local url="$1"
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
    git@github.com:*)        echo "${url#git@github.com:}" ;;
    https://github.com/*)    echo "${url#https://github.com/}" ;;
    ssh://git@github.com/*)  echo "${url#ssh://git@github.com/}" ;;
    git@gitee.com:*)         echo "${url#git@gitee.com:}" ;;
    https://gitee.com/*)     echo "${url#https://gitee.com/}" ;;
    ssh://git@gitee.com/*)   echo "${url#ssh://git@gitee.com/}" ;;
    *) echo "" ;;
  esac
}

mapping_lookup() {
  local repo="$1"
  [[ -f "$MAPPING_FILE" ]] || { echo ""; return 0; }
  python3 - "$MAPPING_FILE" "$repo" <<'PY' 2>/dev/null || true
import json, os, sys
path, repo = sys.argv[1], sys.argv[2]
try:
    with open(os.path.expanduser(path), encoding="utf-8") as f:
        data = json.load(f)
    entry = (data.get("repos") or {}).get(repo) or {}
    print(entry.get("gitee") or "")
except Exception:
    print("")
PY
}

GITHUB_REMOTE="$(find_remote_by_host github.com || true)"
GITEE_REMOTE="$(find_remote_by_host gitee.com || true)"

if [[ -z "$REPO" && -n "$GITHUB_REMOTE" ]]; then
  REPO="$(parse_repo_from_url "$(remote_url "$GITHUB_REMOTE")")"
fi
if [[ -z "$REPO" && -n "$GITEE_REMOTE" ]]; then
  local_repo="$(parse_repo_from_url "$(remote_url "$GITEE_REMOTE")")"
  # Gitee 端仓库名不一定与 GitHub 相同，按镜像表反查
  if [[ -f "$MAPPING_FILE" ]]; then
    REPO="$(python3 - "$MAPPING_FILE" "$local_repo" <<'PY' 2>/dev/null || true
import json, os, sys
path, gitee = sys.argv[1], sys.argv[2]
try:
    with open(os.path.expanduser(path), encoding="utf-8") as f:
        data = json.load(f)
    for gh, entry in (data.get("repos") or {}).items():
        if (entry or {}).get("gitee") == gitee:
            print(gh)
            break
except Exception:
    pass
PY
)"
  fi
fi
[[ -n "$REPO" ]] || REPO="$DEFAULT_REPO"

MIRROR=""
if [[ -n "$GITEE_REMOTE" ]]; then
  MIRROR="$(parse_repo_from_url "$(remote_url "$GITEE_REMOTE")")"
fi
if [[ -z "$MIRROR" ]]; then
  MIRROR="$(mapping_lookup "$REPO")"
fi

GITHUB_URL=""
[[ -n "$GITHUB_REMOTE" ]] && GITHUB_URL="$(remote_url "$GITHUB_REMOTE")"
[[ -n "$GITHUB_URL" ]] || GITHUB_URL="https://github.com/$REPO.git"

GITEE_URL=""
[[ -n "$GITEE_REMOTE" ]] && GITEE_URL="$(remote_url "$GITEE_REMOTE")"
if [[ -z "$GITEE_URL" && -n "$MIRROR" ]]; then
  GITEE_URL="https://gitee.com/$MIRROR.git"
fi

# ── 探测 ──────────────────────────────────────────────────────────────────────
probe_git() {
  local url="$1"
  GIT_TERMINAL_PROMPT=0 \
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
    timeout "$TIMEOUT" git ls-remote --heads "$url" >/dev/null 2>&1
}

probe_http() {
  local url="$1" code
  command -v curl >/dev/null 2>&1 || return 1
  code="$(curl -sS -m "$TIMEOUT" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
  [[ "$code" =~ ^[1-5][0-9][0-9]$ ]]
}

probe_gh() {
  command -v gh >/dev/null 2>&1 || return 1
  local out
  out="$(timeout $((TIMEOUT + 4)) gh api "repos/$REPO" --jq '.permissions.push // false' 2>/dev/null || true)"
  [[ "$out" == "true" ]]
}

probe_gitee() {
  command -v gitee >/dev/null 2>&1 || return 1
  [[ -n "$MIRROR" ]] || return 1
  local out
  out="$(timeout $((TIMEOUT + 4)) gitee api "/repos/$MIRROR" 2>/dev/null || true)"
  [[ -n "$out" ]] || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    p = d.get("permission") or {}
    print("true" if p.get("push") else "false")
except Exception:
    print("false")
' 2>/dev/null | grep -qx true
}

GH_GIT=0; probe_git "$GITHUB_URL" && GH_GIT=1
GH_HTTP=0; probe_http "https://github.com/$REPO" && GH_HTTP=1
GH_CLI=0; probe_gh && GH_CLI=1

GT_GIT=0
GT_HTTP=0
GT_CLI=0
if [[ -n "$MIRROR" ]]; then
  probe_git "$GITEE_URL" && GT_GIT=1
  probe_http "https://gitee.com/$MIRROR" && GT_HTTP=1
  probe_gitee && GT_CLI=1
fi

PREFERRED_FETCH="none"
if [[ "$GH_GIT" == 1 ]]; then
  PREFERRED_FETCH="github"
elif [[ "$GT_GIT" == 1 ]]; then
  PREFERRED_FETCH="gitee"
fi

PREFERRED_ISSUE="none"
if [[ "$GH_CLI" == 1 ]]; then
  PREFERRED_ISSUE="github"
elif [[ "$GT_CLI" == 1 ]]; then
  PREFERRED_ISSUE="gitee"
fi

PREFERRED_PUSH="none"
if [[ "$GH_GIT" == 1 && "$GH_CLI" == 1 ]]; then
  PREFERRED_PUSH="github"
elif [[ "$GT_GIT" == 1 && "$GT_CLI" == 1 ]]; then
  PREFERRED_PUSH="gitee"
fi

FALLBACK="none"
if [[ -n "$MIRROR" ]]; then
  FALLBACK="gitee"
fi

if [[ "$JSON" == 1 ]]; then
  export REPO LOCAL MIRROR GITHUB_URL GITEE_URL
  export GH_GIT GH_HTTP GH_CLI GT_GIT GT_HTTP GT_CLI
  export PREFERRED_FETCH PREFERRED_ISSUE PREFERRED_PUSH FALLBACK
  python3 - <<'PY'
import json, os

def b(name):
    return os.environ.get(name) == "1"

print(json.dumps({
    "repo": os.environ.get("REPO", ""),
    "local": os.environ.get("LOCAL", ""),
    "mirror": os.environ.get("MIRROR", ""),
    "github": {
        "url": os.environ.get("GITHUB_URL", ""),
        "git": b("GH_GIT"),
        "http": b("GH_HTTP"),
        "cli": b("GH_CLI"),
        "push": b("GH_CLI"),
    },
    "gitee": {
        "url": os.environ.get("GITEE_URL", ""),
        "git": b("GT_GIT"),
        "http": b("GT_HTTP"),
        "cli": b("GT_CLI"),
        "push": b("GT_CLI"),
    },
    "preferred": {
        "fetch": os.environ.get("PREFERRED_FETCH", "none"),
        "issuePr": os.environ.get("PREFERRED_ISSUE", "none"),
        "push": os.environ.get("PREFERRED_PUSH", "none"),
    },
    "fallback": os.environ.get("FALLBACK", "none"),
    "policy": "github-first; gitee-only-if-mirror-registered",
}, ensure_ascii=False, indent=2))
PY
else
  head_ "【平台连通性】$REPO"
  [[ -n "$LOCAL" ]] && info "本地仓库：$LOCAL"

  if [[ "$GH_GIT" == 1 ]]; then ok "GitHub  git 可达（$GITHUB_URL）"; else bad "GitHub  git 不可达（$GITHUB_URL）"; fi
  if [[ "$GH_CLI" == 1 ]]; then ok "GitHub  CLI 已登录且有 push 权限（gh）"; else warn "GitHub  CLI 不可用 / 无 push 权限（issue、PR、merge 不可用）"; fi

  if [[ -n "$MIRROR" ]]; then
    if [[ "$GT_GIT" == 1 ]]; then ok "Gitee   git 可达（$GITEE_URL）"; else bad "Gitee   git 不可达（$GITEE_URL）"; fi
    if [[ "$GT_CLI" == 1 ]]; then ok "Gitee   CLI 已登录且有 push 权限（gitee）"; else warn "Gitee   CLI 不可用 / 无 push 权限（issue、PR、merge 不可用）"; fi
  else
    warn "未登记 Gitee 镜像：本仓库不回退 Gitee（见 references/repo-mirrors.json）"
  fi

  printf '\n'
  info "首选 fetch：$PREFERRED_FETCH"
  info "首选 issue/PR：$PREFERRED_ISSUE"
  info "首选 push：$PREFERRED_PUSH"
  if [[ "$FALLBACK" == "gitee" ]]; then
    info "回退平台：Gitee（仅当 GitHub 对应能力不可用时）"
  fi
fi

if [[ "$GH_GIT" == 1 || "$GT_GIT" == 1 || "$GH_CLI" == 1 || "$GT_CLI" == 1 ]]; then
  exit 0
fi
exit 1
