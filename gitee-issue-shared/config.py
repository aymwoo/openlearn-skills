"""Configuration loading and validation from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _parse_positive_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(f"Environment variable {name} must be an integer, got {raw!r}") from exc
    if value <= 0:
        raise ValueError(f"Environment variable {name} must be > 0, got {value}")
    return value


@dataclass(frozen=True)
class Config:
    """Runtime configuration for gitee-issue-claim and gitee-implement-issue."""

    gitee_token: str
    api_base: str
    bot_username: str
    state_path: Path
    repo_dir: Path
    base_branch: str
    coding_agent_cmd: str
    agent_max_turns: int
    agent_timeout_sec: int
    verify_cmd: str
    max_changed_files: int
    processing_label: str
    # Optional: pin the git remote used for fetch/push. Empty means auto-detect
    # (remote whose URL matches <owner>/<repo>, falling back to `origin`).
    git_remote: str = ""


def load_config(*, require_token: bool = True, repo_dir_override: str | None = None) -> Config:
    """Load configuration from environment variables with safe defaults."""
    token = os.environ.get("GITEE_TOKEN", "").strip()
    if require_token and not token:
        raise ValueError("GITEE_TOKEN environment variable is required")

    api_base = os.environ.get("GITEE_API_BASE", "https://gitee.com/api/v5").strip().rstrip("/")
    bot_username = os.environ.get("GITEE_BOT_USERNAME", "").strip()
    state_path = Path(
        os.environ.get("GITEE_ISSUE_STATE_PATH", "./state/gitee_issue_state.json").strip()
    )
    repo_dir = Path(
        (repo_dir_override or os.environ.get("GITEE_REPO_DIR", ".")).strip()
    ).resolve()
    base_branch = os.environ.get("GITEE_BASE_BRANCH", "").strip()
    git_remote = os.environ.get("GITEE_GIT_REMOTE", "").strip()
    coding_agent_cmd = os.environ.get("GITEE_CODING_AGENT_CMD", "claude").strip()
    agent_max_turns = _parse_positive_int("GITEE_AGENT_MAX_TURNS", 25)
    agent_timeout_sec = _parse_positive_int("GITEE_AGENT_TIMEOUT_SEC", 1200)
    verify_cmd = os.environ.get("GITEE_VERIFY_CMD", "").strip()
    max_changed_files = _parse_positive_int("GITEE_MAX_CHANGED_FILES", 5)
    processing_label = os.environ.get("GITEE_PROCESSING_LABEL", "bot-processing").strip()

    if not processing_label:
        raise ValueError("GITEE_PROCESSING_LABEL cannot be empty")

    return Config(
        gitee_token=token,
        api_base=api_base,
        bot_username=bot_username,
        state_path=state_path,
        repo_dir=repo_dir,
        base_branch=base_branch,
        git_remote=git_remote,
        coding_agent_cmd=coding_agent_cmd,
        agent_max_turns=agent_max_turns,
        agent_timeout_sec=agent_timeout_sec,
        verify_cmd=verify_cmd,
        max_changed_files=max_changed_files,
        processing_label=processing_label,
    )
