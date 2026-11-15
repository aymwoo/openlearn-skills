#!/usr/bin/env python3
"""Skill A: Poll Gitee open issues, filter candidates, and claim at most 1 issue."""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

# Locate shared module in repo root or adjacent installation directory.
_THIS_DIR = Path(__file__).resolve().parent
_CANDIDATE_ROOTS = [_THIS_DIR.parent.parent, _THIS_DIR.parent]
for _root in _CANDIDATE_ROOTS:
    if (_root / "gitee-issue-shared").is_dir() and str(_root) not in sys.path:
        sys.path.insert(0, str(_root))
        break

import importlib  # noqa: E402

_shared = importlib.import_module("gitee-issue-shared")
GiteeApiError = _shared.GiteeApiError
GiteeClient = _shared.GiteeClient
GiteeRestClient = _shared.GiteeRestClient
IssueState = _shared.IssueState
StateStore = _shared.StateStore
evaluate_issue_eligibility = _shared.evaluate_issue_eligibility
extract_label_names = _shared.extract_label_names
load_config = _shared.load_config
normalize_issue_number = _shared.normalize_issue_number
redact_text = _shared.redact_text
setup_logger = _shared.setup_logger


@dataclass(frozen=True)
class CandidateEvaluation:
    """Audit record for each issue inspected during a poll cycle."""

    issue_number: str
    title: str
    eligible: bool
    action: str
    reasons: list[str]


@dataclass(frozen=True)
class ClaimResult:
    """Outcome of a single Skill A run."""

    owner: str
    repo: str
    dry_run: bool
    claimed_issue_number: str | None
    evaluations: list[CandidateEvaluation]


def _resolve_bot_username(client: GiteeClient, configured_username: str) -> str:
    if configured_username:
        return configured_username
    user = client.get_current_user()
    login = str(user.get("login") or user.get("username") or "").strip()
    if not login:
        raise GiteeApiError("Unable to resolve authenticated Gitee username for assignee")
    return login


def _build_claim_comment(issue_number: str, bot_username: str, processing_label: str) -> str:
    return (
        f"🤖 自动化助手（`@{bot_username}`）已认领 Issue #{issue_number}，"
        f"已添加 `{processing_label}` 标签并准备进入草稿 PR 实现流程。\n\n"
        "- 当前定位：AI 起草 PR，人工审核后合并（不会自动合并）。\n"
        "- 如需人工接管，请移除该标签或重新分配负责人。"
    )


def claim_next_issue(
    client: GiteeClient,
    state_store: StateStore,
    owner: str,
    repo: str,
    *,
    dry_run: bool = False,
    bot_username: str = "",
    processing_label: str = "bot-processing",
    logger: logging.Logger | None = None,
) -> ClaimResult:
    """Poll open issues and claim at most 1 eligible issue.

    Idempotency order in live mode:
      1. Comment on the issue (`comment_issue`)
      2. Assign to self + preserve existing labels + add `bot-processing` (`update_issue`)
      3. Persist `claimed` state locally (`StateStore.transition`)
    """
    log = logger or logging.getLogger("gitee-issue-claim")
    issues = client.list_repo_issues(owner, repo, state="open")
    open_pulls = client.list_repo_pulls(owner, repo, state="open")

    evaluations: list[CandidateEvaluation] = []
    claimed_issue_number: str | None = None

    for issue in issues:
        issue_num = normalize_issue_number(issue.get("number", ""))
        title = str(issue.get("title", ""))
        local_record = state_store.get_record(owner, repo, issue_num)

        # Avoid extra API calls if basic metadata already disqualifies the issue.
        preliminary = evaluate_issue_eligibility(
            issue,
            processing_label=processing_label,
            open_pulls=open_pulls,
            local_record=local_record,
        )
        issue_pulls: list[dict[str, Any]] = []
        if preliminary.eligible:
            issue_pulls = client.list_issue_pulls(owner, repo, issue_num)
            decision = evaluate_issue_eligibility(
                issue,
                processing_label=processing_label,
                open_pulls=open_pulls,
                issue_pulls=issue_pulls,
                local_record=local_record,
            )
        else:
            decision = preliminary

        if not decision.eligible:
            log.info(
                "Skip %s/%s#%s (%s): %s",
                owner,
                repo,
                issue_num,
                title,
                "; ".join(decision.reasons),
            )
            evaluations.append(
                CandidateEvaluation(
                    issue_number=issue_num,
                    title=title,
                    eligible=False,
                    action="skip",
                    reasons=list(decision.reasons),
                )
            )
            continue

        if dry_run:
            log.info(
                "[DRY-RUN] Would claim %s/%s#%s (%s): %s",
                owner,
                repo,
                issue_num,
                title,
                "; ".join(decision.reasons),
            )
            evaluations.append(
                CandidateEvaluation(
                    issue_number=issue_num,
                    title=title,
                    eligible=True,
                    action="would_claim",
                    reasons=list(decision.reasons),
                )
            )
            if claimed_issue_number is None:
                claimed_issue_number = issue_num
            # In dry-run, stop after identifying the 1 issue that would be claimed
            # (or evaluate remaining? Showing only the first candidate respects max-1).
            break

        assignee = _resolve_bot_username(client, bot_username)
        existing_labels = extract_label_names(issue)
        updated_labels = list(existing_labels)
        if processing_label not in updated_labels:
            updated_labels.append(processing_label)

        # Idempotency critical section: mark remote issue FIRST before writing local state.
        comment_body = _build_claim_comment(issue_num, assignee, processing_label)
        client.comment_issue(owner, repo, issue_num, comment_body)
        client.update_issue(
            owner,
            repo,
            issue_num,
            assignee=assignee,
            labels=updated_labels,
        )

        state_store.ensure_new(owner, repo, issue_num, title=title)
        state_store.transition(
            owner,
            repo,
            issue_num,
            IssueState.CLAIMED,
            title=title,
            reason=f"Claimed by @{assignee} with label {processing_label}",
        )

        claimed_issue_number = issue_num
        log.info(
            "Claimed %s/%s#%s (%s) as @%s",
            owner,
            repo,
            issue_num,
            title,
            assignee,
        )
        evaluations.append(
            CandidateEvaluation(
                issue_number=issue_num,
                title=title,
                eligible=True,
                action="claimed",
                reasons=list(decision.reasons),
            )
        )
        # Concurrency gate: max 1 issue per run.
        break

    return ClaimResult(
        owner=owner,
        repo=repo,
        dry_run=dry_run,
        claimed_issue_number=claimed_issue_number,
        evaluations=evaluations,
    )


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Poll open Gitee issues, filter candidates, and claim at most 1 issue."
    )
    parser.add_argument("--owner", required=True, help="Gitee repository owner/namespace")
    parser.add_argument("--repo", required=True, help="Gitee repository name")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List eligible/skipped issues and reasons without any write operations",
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
        cfg = load_config(require_token=not args.dry_run)
    except ValueError as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2

    logger = setup_logger("gitee-issue-claim", secrets=(cfg.gitee_token,))
    client = GiteeRestClient(token=cfg.gitee_token, api_base=cfg.api_base)
    state_store = StateStore(cfg.state_path)

    try:
        result = claim_next_issue(
            client,
            state_store,
            args.owner,
            args.repo,
            dry_run=args.dry_run,
            bot_username=cfg.bot_username,
            processing_label=cfg.processing_label,
            logger=logger,
        )
    except Exception as exc:
        logger.error(
            "Failed to poll/claim issues: %s",
            redact_text(str(exc), (cfg.gitee_token,)),
        )
        return 1

    if args.json_output:
        payload = {
            "owner": result.owner,
            "repo": result.repo,
            "dry_run": result.dry_run,
            "claimed_issue_number": result.claimed_issue_number,
            "evaluations": [asdict(item) for item in result.evaluations],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif args.dry_run:
        if not result.evaluations:
            print("DRY-RUN: No open issues found.")
        else:
            for item in result.evaluations:
                tag = "CLAIM" if item.action == "would_claim" else "SKIP"
                print(f"[{tag}] #{item.issue_number} {item.title}: {'; '.join(item.reasons)}")
            if result.claimed_issue_number:
                print(f"DRY-RUN candidate issue_number: {result.claimed_issue_number}")
            else:
                print("DRY-RUN: No eligible issue to claim.")
    else:
        # Print claimed issue_number (or empty line) for downstream Layer 3 piping.
        print(result.claimed_issue_number or "")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
