"""Constrained coding agent invocation and read-only dry-run planning."""

from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from gitee_issue_shared_loader import load_shared_module

_shared = load_shared_module()
redact_text = _shared.redact_text

_IGNORED_DIRS = frozenset(
    {".git", "node_modules", "dist", "build", "__pycache__", ".venv", "venv", "state"}
)


@dataclass(frozen=True)
class AgentRunResult:
    """Outcome of invoking the coding agent."""

    success: bool
    cannot_implement_reason: str
    output: str


@dataclass(frozen=True)
class DryRunPlan:
    """Read-only implementation preview produced in --dry-run mode."""

    candidate_files: list[str]
    plan_summary: str
    prompt_preview: str


def build_coding_prompt(
    *,
    owner: str,
    repo: str,
    issue_number: str,
    issue: dict[str, Any],
    comments: list[dict[str, Any]],
    max_changed_files: int,
) -> str:
    """Build the constrained prompt enforcing limited related-file changes."""
    title = str(issue.get("title", "")).strip()
    body = str(issue.get("body") or "").strip() or "(No description provided)"
    comment_lines: list[str] = []
    for c in comments[-10:]:
        user = c.get("user") or {}
        author = user.get("login") or user.get("name") or "unknown"
        text = str(c.get("body") or "").strip()
        if text:
            comment_lines.append(f"- @{author}: {text}")
    comments_block = "\n".join(comment_lines) if comment_lines else "(No comments)"

    return (
        f"你正在为 Gitee 仓库 `{owner}/{repo}` 的 Issue #{issue_number} 起草代码修复。\n\n"
        f"## Issue 标题\n{title}\n\n"
        f"## Issue 描述\n{body}\n\n"
        f"## 最近评论\n{comments_block}\n\n"
        "## 硬性约束（必须严格遵守）\n"
        f"1. **有限文件范围**：只修改与该 Issue 直接相关的有限文件（硬上限最多 {max_changed_files} 个文件），禁止无关重构、格式化无关文件或大面积改动。\n"
        "2. **禁止强行实现**：如果无法理解 Issue 诉求、缺少复现/上下文、或需要超出范围的架构改造，请不要修改任何文件，直接输出一行：`CANNOT_IMPLEMENT: <具体原因>`。\n"
        "3. **仅改动工作区**：不要执行 `git push`、不要创建 PR、更严禁调用或执行任何合并 PR（`merge_pull`）操作。\n"
        "4. **可验证**：如修改涉及已有测试或需要补充针对性用例，请确保改动后现有 lint/test 能够通过。\n"
    )


def _scan_candidate_files(
    repo_dir: Path, issue: dict[str, Any], comments: list[dict[str, Any]], *, limit: int = 8
) -> list[str]:
    """Heuristically identify repository files mentioned in or matching the issue."""
    if not repo_dir.is_dir():
        return []

    text_parts = [str(issue.get("title", "")), str(issue.get("body") or "")]
    text_parts.extend(str(c.get("body") or "") for c in comments)
    combined = "\n".join(text_parts)
    combined_lower = combined.lower()

    all_files: list[str] = []
    for root, dirs, files in os.walk(repo_dir):
        dirs[:] = sorted(d for d in dirs if d not in _IGNORED_DIRS and not d.startswith("."))
        for fname in sorted(files):
            rel = str((Path(root) / fname).relative_to(repo_dir))
            all_files.append(rel)
            if len(all_files) >= 500:
                break
        if len(all_files) >= 500:
            break

    direct_hits: list[str] = []
    keyword_hits: list[str] = []
    tokens = {
        tok
        for tok in re.findall(r"[a-z0-9_]{3,}", combined_lower)
        if tok not in {"issue", "error", "fix", "bug", "the", "and", "for", "with"}
    }

    for rel in all_files:
        rel_lower = rel.lower()
        stem_lower = Path(rel).stem.lower()
        if rel_lower in combined_lower or (len(stem_lower) >= 4 and stem_lower in combined_lower):
            direct_hits.append(rel)
        elif any(tok in rel_lower for tok in tokens):
            keyword_hits.append(rel)

    ordered = direct_hits + [f for f in keyword_hits if f not in direct_hits]
    if ordered:
        return ordered[:limit]
    return all_files[: min(limit, 5)]


def build_dry_run_plan(
    *,
    repo_dir: Path,
    owner: str,
    repo: str,
    issue_number: str,
    issue: dict[str, Any],
    comments: list[dict[str, Any]],
    branch_name: str,
    verify_commands: list[str],
    max_changed_files: int,
) -> DryRunPlan:
    """Produce a zero-side-effect preview of what Skill B would modify and verify."""
    candidates = _scan_candidate_files(repo_dir, issue, comments)
    prompt = build_coding_prompt(
        owner=owner,
        repo=repo,
        issue_number=issue_number,
        issue=issue,
        comments=comments,
        max_changed_files=max_changed_files,
    )
    target_desc = ", ".join(candidates[:3]) if candidates else "(unable to match local files automatically)"
    verify_desc = ", ".join(verify_commands) if verify_commands else "(no lint/test command detected)"
    plan_summary = (
        f"如果真实执行，将基于目标分支创建 `{branch_name}`，"
        f"在最多 {max_changed_files} 个直接相关文件范围内定位并修改（候选文件：{target_desc}），"
        f"随后运行校验命令（{verify_desc}），通过后提交包含 `closes #{issue_number}` 的草稿 PR（人工合并）。"
    )
    return DryRunPlan(
        candidate_files=candidates,
        plan_summary=plan_summary,
        prompt_preview=prompt,
    )


def invoke_coding_agent(
    *,
    repo_dir: Path,
    prompt: str,
    agent_cmd: str,
    max_turns: int,
    timeout_sec: int,
    secrets: tuple[str, ...] = (),
) -> AgentRunResult:
    """Run the configured coding agent CLI with max-turns and timeout guardrails."""
    parts = shlex.split(agent_cmd)
    if not parts:
        return AgentRunResult(
            success=False,
            cannot_implement_reason="GITEE_CODING_AGENT_CMD is empty",
            output="",
        )

    executable = parts[0]
    if shutil.which(executable) is None:
        return AgentRunResult(
            success=False,
            cannot_implement_reason=f"Coding agent executable not found: {executable}",
            output="",
        )

    if "{prompt}" in agent_cmd:
        cmd_args = [
            prompt if arg == "{prompt}" else arg.replace("{max_turns}", str(max_turns))
            for arg in parts
        ]
    else:
        cmd_args = [*parts, "-p", prompt, "--max-turns", str(max_turns)]

    try:
        proc = subprocess.run(
            cmd_args,
            cwd=str(repo_dir),
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return AgentRunResult(
            success=False,
            cannot_implement_reason=f"Coding agent timed out after {timeout_sec}s",
            output="",
        )

    combined = redact_text((proc.stdout + "\n" + proc.stderr).strip(), secrets)
    match = re.search(r"CANNOT_IMPLEMENT:\s*(.+)", combined)
    if match:
        return AgentRunResult(
            success=False,
            cannot_implement_reason=match.group(1).strip(),
            output=combined,
        )

    if proc.returncode != 0:
        snippet = combined[-800:] if len(combined) > 800 else combined
        return AgentRunResult(
            success=False,
            cannot_implement_reason=f"Coding agent exited with code {proc.returncode}: {snippet}",
            output=combined,
        )

    return AgentRunResult(success=True, cannot_implement_reason="", output=combined)
