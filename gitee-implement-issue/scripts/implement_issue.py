#!/usr/bin/env python3
"""Skill B: Implement a claimed Gitee issue on a branch, verify, and open a PR."""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable

from coding_agent import (
    AgentRunResult,
    build_coding_prompt,
    build_dry_run_plan,
    invoke_coding_agent,
)
from gitee_issue_shared_loader import load_shared_module
from workspace_runner import (
    WorkspaceError,
    cleanup_branch_on_failure,
    commit_and_push,
    detect_verify_commands,
    ensure_clean_worktree,
    get_changed_files,
    get_current_branch,
    prepare_branch,
    run_verification,
)

_shared = load_shared_module()
Config = _shared.Config
GiteeClient = _shared.GiteeClient
GiteeRestClient = _shared.GiteeRestClient
IssueState = _shared.IssueState
StateStore = _shared.StateStore
build_branch_name = _shared.build_branch_name
has_linked_open_pr = _shared.has_linked_open_pr
load_config = _shared.load_config
normalize_issue_number = _shared.normalize_issue_number
redact_text = _shared.redact_text
setup_logger = _shared.setup_logger

AgentRunner = Callable[..., AgentRunResult]


@dataclass(frozen=True)
class ImplementResult:
    """Outcome of a single Skill B execution."""

    owner: str
    repo: str
    issue_number: str | None
    status: str  # pr_open | dry_run | failed | noop | aborted
    branch: str = ""
    pr_url: str = ""
    pr_number: int | None = None
    changed_files: list[str] | None = None
    reason: str = ""
    dry_run_plan: dict[str, Any] | None = None


def _resolve_base_branch(
    client: GiteeClient, owner: str, repo: str, cfg: Config
) -> str:
    if cfg.base_branch:
        return cfg.base_branch
    try:
        repo_info = client.get_repo(owner, repo)
        default_branch = str(repo_info.get("default_branch") or "").strip()
        if default_branch:
            return default_branch
    except Exception:
        pass
    return get_current_branch(cfg.repo_dir)


def _transition_to_working(
    state_store: StateStore,
    owner: str,
    repo: str,
    issue_number: str,
    *,
    title: str,
    branch_name: str,
) -> None:
    record = state_store.get_record(owner, repo, issue_number)
    if record is None:
        state_store.ensure_new(owner, repo, issue_number, title=title)
        record = state_store.transition(
            owner,
            repo,
            issue_number,
            IssueState.CLAIMED,
            title=title,
            reason="Adopted directly by Skill B",
        )
    elif record.state == IssueState.NEW:
        record = state_store.transition(
            owner,
            repo,
            issue_number,
            IssueState.CLAIMED,
            title=title,
            reason="Adopted directly by Skill B",
        )

    if record.state == IssueState.CLAIMED:
        state_store.transition(
            owner,
            repo,
            issue_number,
            IssueState.WORKING,
            title=title,
            branch=branch_name,
            reason=f"Created branch {branch_name}",
        )


def _fail_and_cleanup(
    *,
    client: GiteeClient,
    state_store: StateStore,
    cfg: Config,
    owner: str,
    repo: str,
    issue_number: str,
    title: str,
    base_branch: str,
    branch_name: str,
    remote_branch_created: bool,
    reason: str,
    logger: logging.Logger,
) -> ImplementResult:
    safe_reason = redact_text(reason, (cfg.gitee_token,))
    logger.warning(
        "Issue %s/%s#%s failed: %s", owner, repo, issue_number, safe_reason
    )

    comment_body = (
        f"⚠️ 自动化助手未能完成 Issue #{issue_number} 的 PR 起草，未创建任何 PR。\n\n"
        f"- **失败原因**：{safe_reason}\n"
        "- **已执行清理**：临时分支已回滚/清理，等待人工进一步确认或处理。"
    )
    try:
        client.comment_issue(owner, repo, issue_number, comment_body)
    except Exception as exc:
        logger.error(
            "Failed to comment failure reason on #%s: %s",
            issue_number,
            redact_text(str(exc), (cfg.gitee_token,)),
        )

    if base_branch and branch_name:
        cleanup_branch_on_failure(
            cfg.repo_dir,
            base_branch=base_branch,
            branch_name=branch_name,
            secrets=(cfg.gitee_token,),
        )
    if remote_branch_created and branch_name:
        try:
            client.delete_branch(owner, repo, branch_name)
        except Exception as exc:
            logger.warning(
                "Could not delete remote branch %s: %s",
                branch_name,
                redact_text(str(exc), (cfg.gitee_token,)),
            )

    record = state_store.get_record(owner, repo, issue_number)
    if record is None:
        state_store.ensure_new(owner, repo, issue_number, title=title)
        state_store.transition(
            owner, repo, issue_number, IssueState.CLAIMED, title=title
        )
    current = state_store.get_record(owner, repo, issue_number)
    if current and current.state in (IssueState.CLAIMED, IssueState.WORKING):
        state_store.transition(
            owner,
            repo,
            issue_number,
            IssueState.FAILED,
            title=title,
            branch=branch_name,
            reason=safe_reason,
        )
    current = state_store.get_record(owner, repo, issue_number)
    if current and current.state == IssueState.FAILED:
        state_store.transition(
            owner,
            repo,
            issue_number,
            IssueState.SKIPPED,
            title=title,
            branch=branch_name,
            reason=safe_reason,
        )

    return ImplementResult(
        owner=owner,
        repo=repo,
        issue_number=issue_number,
        status="failed",
        branch=branch_name,
        reason=safe_reason,
    )


def implement_issue(
    client: GiteeClient,
    state_store: StateStore,
    cfg: Config,
    owner: str,
    repo: str,
    *,
    issue_number: str | int | None = None,
    dry_run: bool = False,
    agent_runner: AgentRunner = invoke_coding_agent,
    logger: logging.Logger | None = None,
) -> ImplementResult:
    """Execute Skill B workflow for a single issue (max 1 per run)."""
    log = logger or logging.getLogger("gitee-implement-issue")

    if issue_number is None or str(issue_number).strip() == "":
        earliest = state_store.pick_earliest_claimed(owner, repo)
        if earliest is None:
            log.info("No issue in 'claimed' state for %s/%s; nothing to do.", owner, repo)
            return ImplementResult(
                owner=owner,
                repo=repo,
                issue_number=None,
                status="noop",
                reason="No claimed issue found in state store",
            )
        resolved_num = earliest.issue_number
    else:
        resolved_num = normalize_issue_number(issue_number)

    existing_record = state_store.get_record(owner, repo, resolved_num)
    if existing_record and existing_record.state in (IssueState.PR_OPEN, IssueState.SKIPPED):
        reason = f"Local state is already terminal ({existing_record.state.value})"
        log.info("Aborting %s/%s#%s: %s", owner, repo, resolved_num, reason)
        return ImplementResult(
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            status="aborted",
            reason=reason,
        )

    issue = client.get_repo_issue_detail(owner, repo, resolved_num)
    title = str(issue.get("title", "")).strip()
    issue_state = str(issue.get("state", "")).lower()
    if issue_state != "open":
        reason = f"Remote issue state is {issue_state!r}, expected 'open'"
        log.info("Aborting %s/%s#%s: %s", owner, repo, resolved_num, reason)
        return ImplementResult(
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            status="aborted",
            reason=reason,
        )

    comments = client.list_issue_comments(owner, repo, resolved_num)
    open_pulls = client.list_repo_pulls(owner, repo, state="open")
    issue_pulls = client.list_issue_pulls(owner, repo, resolved_num)
    linked, pr_reason = has_linked_open_pr(
        issue, open_pulls=open_pulls, issue_pulls=issue_pulls
    )
    if linked:
        log.info("Aborting %s/%s#%s: %s", owner, repo, resolved_num, pr_reason)
        return ImplementResult(
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            status="aborted",
            reason=pr_reason,
        )

    branch_name = build_branch_name(resolved_num, title)

    if dry_run:
        verify_cmds = detect_verify_commands(cfg.repo_dir, override_cmd=cfg.verify_cmd)
        plan = build_dry_run_plan(
            repo_dir=cfg.repo_dir,
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            issue=issue,
            comments=comments,
            branch_name=branch_name,
            verify_commands=verify_cmds,
            max_changed_files=cfg.max_changed_files,
        )
        log.info("[DRY-RUN] %s/%s#%s: %s", owner, repo, resolved_num, plan.plan_summary)
        return ImplementResult(
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            status="dry_run",
            branch=branch_name,
            reason=plan.plan_summary,
            dry_run_plan=asdict(plan),
        )

    base_branch = ""
    remote_branch_created = False
    try:
        ensure_clean_worktree(cfg.repo_dir)
        base_branch = _resolve_base_branch(client, owner, repo, cfg)

        client.create_branch(owner, repo, refs=base_branch, branch_name=branch_name)
        remote_branch_created = True
        prepare_branch(
            cfg.repo_dir,
            base_branch=base_branch,
            branch_name=branch_name,
            secrets=(cfg.gitee_token,),
        )
        _transition_to_working(
            state_store,
            owner,
            repo,
            resolved_num,
            title=title,
            branch_name=branch_name,
        )
    except Exception as exc:
        return _fail_and_cleanup(
            client=client,
            state_store=state_store,
            cfg=cfg,
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            title=title,
            base_branch=base_branch,
            branch_name=branch_name,
            remote_branch_created=remote_branch_created,
            reason=f"Failed to prepare branch: {exc}",
            logger=log,
        )

    prompt = build_coding_prompt(
        owner=owner,
        repo=repo,
        issue_number=resolved_num,
        issue=issue,
        comments=comments,
        max_changed_files=cfg.max_changed_files,
    )
    agent_res = agent_runner(
        repo_dir=cfg.repo_dir,
        prompt=prompt,
        agent_cmd=cfg.coding_agent_cmd,
        max_turns=cfg.agent_max_turns,
        timeout_sec=cfg.agent_timeout_sec,
        secrets=(cfg.gitee_token,),
    )
    if not agent_res.success:
        return _fail_and_cleanup(
            client=client,
            state_store=state_store,
            cfg=cfg,
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            title=title,
            base_branch=base_branch,
            branch_name=branch_name,
            remote_branch_created=remote_branch_created,
            reason=agent_res.cannot_implement_reason or "Coding agent failed",
            logger=log,
        )

    changed_files = get_changed_files(cfg.repo_dir)
    if not changed_files:
        return _fail_and_cleanup(
            client=client,
            state_store=state_store,
            cfg=cfg,
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            title=title,
            base_branch=base_branch,
            branch_name=branch_name,
            remote_branch_created=remote_branch_created,
            reason="Coding agent produced no file changes in workspace.",
            logger=log,
        )

    if len(changed_files) > cfg.max_changed_files:
        return _fail_and_cleanup(
            client=client,
            state_store=state_store,
            cfg=cfg,
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            title=title,
            base_branch=base_branch,
            branch_name=branch_name,
            remote_branch_created=remote_branch_created,
            reason=(
                f"Modified {len(changed_files)} files ({', '.join(changed_files[:8])}), "
                f"exceeding limited-file guardrail GITEE_MAX_CHANGED_FILES={cfg.max_changed_files}."
            ),
            logger=log,
        )

    verify_res = run_verification(
        cfg.repo_dir,
        override_cmd=cfg.verify_cmd,
        secrets=(cfg.gitee_token,),
    )
    if not verify_res.passed:
        return _fail_and_cleanup(
            client=client,
            state_store=state_store,
            cfg=cfg,
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            title=title,
            base_branch=base_branch,
            branch_name=branch_name,
            remote_branch_created=remote_branch_created,
            reason=verify_res.summary,
            logger=log,
        )

    try:
        commit_and_push(
            cfg.repo_dir,
            branch_name=branch_name,
            commit_message=f"fix: resolve #{resolved_num} - {title[:60]}",
            secrets=(cfg.gitee_token,),
        )
        pr_body = (
            f"## 变更说明\n\n"
            f"针对 Issue #{resolved_num}（{title}）起草修复 PR。\n\n"
            f"- **修改文件**：{', '.join(f'`{f}`' for f in changed_files)}\n"
            f"- **校验结果**：{verify_res.summary}\n"
            "- **合并方式**：等待人工审核后手动合并（禁止自动合并）。\n\n"
            f"closes #{resolved_num}\n"
        )
        pr = client.create_pull(
            owner,
            repo,
            title=f"fix: #{resolved_num} {title[:70]}",
            head=branch_name,
            base=base_branch,
            body=pr_body,
        )
        pr_url = str(pr.get("html_url") or pr.get("url") or "")
        pr_number = pr.get("number")

        client.comment_issue(
            owner,
            repo,
            resolved_num,
            (
                f"✅ 已为 Issue #{resolved_num} 创建草稿修复 PR：{pr_url or f'PR #{pr_number}'}\n\n"
                f"- 分支：`{branch_name}` → `{base_branch}`\n"
                f"- 涉及文件：{', '.join(f'`{f}`' for f in changed_files)}\n"
                f"- 校验状态：{verify_res.summary}\n"
                "- 请人工审核变更后决定是否合并。"
            ),
        )
        state_store.transition(
            owner,
            repo,
            resolved_num,
            IssueState.PR_OPEN,
            title=title,
            branch=branch_name,
            pr_url=pr_url,
            pr_number=int(pr_number) if pr_number is not None else None,
            reason="PR opened successfully; awaiting human review",
        )
    except Exception as exc:
        return _fail_and_cleanup(
            client=client,
            state_store=state_store,
            cfg=cfg,
            owner=owner,
            repo=repo,
            issue_number=resolved_num,
            title=title,
            base_branch=base_branch,
            branch_name=branch_name,
            remote_branch_created=remote_branch_created,
            reason=f"Failed while committing/opening PR: {exc}",
            logger=log,
        )

    return ImplementResult(
        owner=owner,
        repo=repo,
        issue_number=resolved_num,
        status="pr_open",
        branch=branch_name,
        pr_url=pr_url,
        pr_number=int(pr_number) if pr_number is not None else None,
        changed_files=changed_files,
        reason="PR opened; awaiting human review",
    )


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Implement a claimed Gitee issue on a new branch, verify, and open a PR."
    )
    parser.add_argument("--owner", required=True, help="Gitee repository owner/namespace")
    parser.add_argument("--repo", required=True, help="Gitee repository name")
    parser.add_argument(
        "--issue-number",
        default=None,
        help="Target issue number; if omitted, picks the earliest 'claimed' issue from state",
    )
    parser.add_argument(
        "--repo-dir",
        default=None,
        help="Path to local cloned git repository (overrides GITEE_REPO_DIR)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview target files and change plan without creating branch or PR",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output structured JSON result to stdout",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    try:
        cfg = load_config(
            require_token=not args.dry_run,
            repo_dir_override=args.repo_dir,
        )
    except ValueError as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2

    logger = setup_logger("gitee-implement-issue", secrets=(cfg.gitee_token,))
    client = GiteeRestClient(token=cfg.gitee_token, api_base=cfg.api_base)
    state_store = StateStore(cfg.state_path)

    try:
        result = implement_issue(
            client,
            state_store,
            cfg,
            args.owner,
            args.repo,
            issue_number=args.issue_number,
            dry_run=args.dry_run,
            logger=logger,
        )
    except (WorkspaceError, Exception) as exc:
        logger.error(
            "Unexpected error implementing issue: %s",
            redact_text(str(exc), (cfg.gitee_token,)),
        )
        return 1

    if args.json_output:
        print(json.dumps(asdict(result), ensure_ascii=False, indent=2))
    elif result.status == "dry_run" and result.dry_run_plan:
        print(f"[DRY-RUN] #{result.issue_number} -> branch {result.branch}")
        print(f"Candidate files: {', '.join(result.dry_run_plan['candidate_files']) or '(none)'}")
        print(f"Plan: {result.dry_run_plan['plan_summary']}")
    elif result.status == "pr_open":
        print(f"PR opened for #{result.issue_number}: {result.pr_url or result.branch}")
    else:
        print(f"[{result.status.upper()}] #{result.issue_number or '-'}: {result.reason}")

    return 1 if result.status == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
