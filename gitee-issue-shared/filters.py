"""Issue filtering rules, linked-PR detection, and branch slug helpers."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from typing import Any

from .state_machine import IssueRecord, IssueState


@dataclass(frozen=True)
class FilterDecision:
    """Result of evaluating whether an issue is eligible for claiming."""

    eligible: bool
    reasons: tuple[str, ...]


def normalize_issue_number(number: str | int) -> str:
    """Normalize an issue number/ident (accepts int, numeric str, or Gitee ident)."""
    cleaned = str(number).strip().lstrip("#")
    if not cleaned:
        raise ValueError("Issue number cannot be empty")
    return cleaned


def extract_label_names(issue: dict[str, Any]) -> list[str]:
    """Extract normalized label names from a Gitee issue payload."""
    raw_labels = issue.get("labels") or []
    names: list[str] = []
    for item in raw_labels:
        if isinstance(item, dict):
            name = str(item.get("name", "")).strip()
        else:
            name = str(item).strip()
        if name and name not in names:
            names.append(name)
    return names


def _has_assignee(issue: dict[str, Any]) -> str:
    assignee = issue.get("assignee")
    if isinstance(assignee, dict):
        return str(assignee.get("login") or assignee.get("username") or assignee.get("name") or "").strip()
    if isinstance(assignee, str):
        return assignee.strip()
    return ""


def _pr_references_issue(pr: dict[str, Any], issue_number: str) -> bool:
    escaped = re.escape(issue_number)
    ref_pattern = re.compile(rf"(?<![A-Za-z0-9_])#{escaped}(?![A-Za-z0-9_])", re.IGNORECASE)
    branch_pattern = re.compile(rf"(?:^|/)issue-{escaped}(?:-|$)", re.IGNORECASE)

    head = pr.get("head")
    head_ref = ""
    if isinstance(head, dict):
        head_ref = str(head.get("ref") or head.get("label") or "")
    elif isinstance(head, str):
        head_ref = head

    if branch_pattern.search(head_ref):
        return True

    text = f"{pr.get('title', '')}\n{pr.get('body', '')}"
    return bool(ref_pattern.search(text))


def has_linked_open_pr(
    issue: dict[str, Any],
    *,
    open_pulls: list[dict[str, Any]] | None = None,
    issue_pulls: list[dict[str, Any]] | None = None,
) -> tuple[bool, str]:
    """Check whether the issue already has a linked open PR."""
    issue_num = normalize_issue_number(issue.get("number", ""))
    for pr in issue_pulls or []:
        if str(pr.get("state", "open")).lower() == "open":
            pr_num = pr.get("number", "?")
            return True, f"issue has linked open PR #{pr_num}"

    for pr in open_pulls or []:
        if str(pr.get("state", "")).lower() != "open":
            continue
        if _pr_references_issue(pr, issue_num):
            pr_num = pr.get("number", "?")
            return True, f"open PR #{pr_num} already references #{issue_num}"

    return False, ""


def evaluate_issue_eligibility(
    issue: dict[str, Any],
    *,
    processing_label: str = "bot-processing",
    open_pulls: list[dict[str, Any]] | None = None,
    issue_pulls: list[dict[str, Any]] | None = None,
    local_record: IssueRecord | None = None,
) -> FilterDecision:
    """Evaluate all Skill A claim rules and return detailed rejection reasons."""
    reasons: list[str] = []

    state = str(issue.get("state", "")).lower()
    if state != "open":
        reasons.append(f"state is {state!r}, expected 'open'")

    assignee = _has_assignee(issue)
    if assignee:
        reasons.append(f"already assigned to {assignee!r}")

    labels = extract_label_names(issue)
    if processing_label in labels:
        reasons.append(f"already has label {processing_label!r}")

    linked_pr, pr_reason = has_linked_open_pr(
        issue, open_pulls=open_pulls, issue_pulls=issue_pulls
    )
    if linked_pr:
        reasons.append(pr_reason)

    if local_record is not None and local_record.state != IssueState.NEW:
        reasons.append(f"local state is already {local_record.state.value!r}")

    if reasons:
        return FilterDecision(eligible=False, reasons=tuple(reasons))

    return FilterDecision(
        eligible=True,
        reasons=(
            f"state=open, assignee is empty, lacks {processing_label!r} label, and no linked open PR",
        ),
    )


def build_branch_name(
    issue_number: str | int, title: str, *, max_slug_len: int = 40
) -> str:
    """Build deterministic git branch name `fix/issue-{number}-{slug}`."""
    clean_num = normalize_issue_number(issue_number)
    ascii_tokens = re.findall(r"[a-z0-9]+", title.lower())
    raw_slug = "-".join(ascii_tokens)

    if not raw_slug:
        digest = hashlib.sha1(title.encode("utf-8", errors="replace")).hexdigest()[:6]
        slug = f"task-{digest}"
    else:
        slug = raw_slug[:max_slug_len].strip("-")
        if not slug:
            slug = "task"

    return f"fix/issue-{clean_num}-{slug}"
