"""Lightweight JSON state machine with atomic writes and file locking."""

from __future__ import annotations

import fcntl
import json
import os
import tempfile
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Iterator


class IssueState(str, Enum):
    """Lifecycle states for automated Gitee issue processing."""

    NEW = "new"
    CLAIMED = "claimed"
    WORKING = "working"
    PR_OPEN = "pr_open"
    SKIPPED = "skipped"
    FAILED = "failed"


TERMINAL_STATES = frozenset({IssueState.PR_OPEN, IssueState.SKIPPED})

ALLOWED_TRANSITIONS: dict[IssueState, frozenset[IssueState]] = {
    IssueState.NEW: frozenset({IssueState.CLAIMED, IssueState.SKIPPED}),
    IssueState.CLAIMED: frozenset({IssueState.WORKING, IssueState.FAILED, IssueState.SKIPPED}),
    IssueState.WORKING: frozenset({IssueState.PR_OPEN, IssueState.FAILED}),
    IssueState.FAILED: frozenset({IssueState.SKIPPED}),
    IssueState.PR_OPEN: frozenset(),
    IssueState.SKIPPED: frozenset(),
}


class StateTransitionError(ValueError):
    """Raised when an invalid state transition is attempted."""


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _normalize_number(issue_number: str | int) -> str:
    cleaned = str(issue_number).strip().lstrip("#")
    if not cleaned:
        raise ValueError("issue_number cannot be empty")
    return cleaned


def _issue_key(owner: str, repo: str, issue_number: str | int) -> str:
    return f"{owner}/{repo}#{_normalize_number(issue_number)}"


@dataclass
class IssueRecord:
    """Persisted state record for a single Gitee issue."""

    owner: str
    repo: str
    issue_number: str
    state: IssueState = IssueState.NEW
    title: str = ""
    created_at: str = field(default_factory=_utc_now)
    updated_at: str = field(default_factory=_utc_now)
    claimed_at: str = ""
    branch: str = ""
    pr_url: str = ""
    pr_number: int | None = None
    reason: str = ""
    history: list[dict[str, str]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["state"] = self.state.value
        return data

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "IssueRecord":
        return cls(
            owner=str(data["owner"]),
            repo=str(data["repo"]),
            issue_number=_normalize_number(data["issue_number"]),
            state=IssueState(data["state"]),
            title=str(data.get("title", "")),
            created_at=str(data.get("created_at", _utc_now())),
            updated_at=str(data.get("updated_at", _utc_now())),
            claimed_at=str(data.get("claimed_at", "")),
            branch=str(data.get("branch", "")),
            pr_url=str(data.get("pr_url", "")),
            pr_number=data.get("pr_number"),
            reason=str(data.get("reason", "")),
            history=list(data.get("history", [])),
        )


class StateStore:
    """Thread/process-safe JSON state store for issue processing."""

    SCHEMA_VERSION = 1

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self._lock_path = self.path.with_name(f"{self.path.name}.lock")

    @contextmanager
    def _locked(self) -> Iterator[None]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self._lock_path, "a+", encoding="utf-8") as lock_file:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def _load_unlocked(self) -> dict[str, Any]:
        if not self.path.exists():
            return {"version": self.SCHEMA_VERSION, "issues": {}}
        raw = self.path.read_text(encoding="utf-8").strip()
        if not raw:
            return {"version": self.SCHEMA_VERSION, "issues": {}}
        data = json.loads(raw)
        if not isinstance(data, dict) or "issues" not in data:
            raise ValueError(f"Corrupted state file structure: {self.path}")
        return data

    def _save_unlocked(self, data: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(
            prefix=".state_", suffix=".tmp", dir=str(self.path.parent)
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
                json.dump(data, tmp_file, ensure_ascii=False, indent=2, sort_keys=True)
                tmp_file.write("\n")
                tmp_file.flush()
                os.fsync(tmp_file.fileno())
            os.replace(tmp_name, self.path)
        except BaseException:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
            raise

    def get_record(self, owner: str, repo: str, issue_number: str | int) -> IssueRecord | None:
        """Read a single issue record if present."""
        key = _issue_key(owner, repo, issue_number)
        with self._locked():
            data = self._load_unlocked()
            raw_record = data["issues"].get(key)
            return IssueRecord.from_dict(raw_record) if raw_record else None

    def list_records(self, owner: str | None = None, repo: str | None = None) -> list[IssueRecord]:
        """List all persisted records, optionally filtered by owner and repo."""
        with self._locked():
            data = self._load_unlocked()
            records = [IssueRecord.from_dict(v) for v in data["issues"].values()]
        if owner is not None:
            records = [r for r in records if r.owner == owner]
        if repo is not None:
            records = [r for r in records if r.repo == repo]
        return records

    def ensure_new(
        self, owner: str, repo: str, issue_number: str | int, *, title: str = ""
    ) -> IssueRecord:
        """Ensure an issue exists in the store (initializes as NEW if absent)."""
        clean_num = _normalize_number(issue_number)
        key = _issue_key(owner, repo, clean_num)
        with self._locked():
            data = self._load_unlocked()
            existing = data["issues"].get(key)
            if existing is not None:
                record = IssueRecord.from_dict(existing)
                if title and not record.title:
                    record.title = title
                    record.updated_at = _utc_now()
                    data["issues"][key] = record.to_dict()
                    self._save_unlocked(data)
                return record
            now = _utc_now()
            record = IssueRecord(
                owner=owner,
                repo=repo,
                issue_number=clean_num,
                state=IssueState.NEW,
                title=title,
                created_at=now,
                updated_at=now,
            )
            data["issues"][key] = record.to_dict()
            self._save_unlocked(data)
            return record

    def transition(
        self,
        owner: str,
        repo: str,
        issue_number: str | int,
        to_state: IssueState,
        *,
        reason: str = "",
        title: str = "",
        branch: str | None = None,
        pr_url: str | None = None,
        pr_number: int | None = None,
    ) -> IssueRecord:
        """Transition an issue to `to_state`, validating against ALLOWED_TRANSITIONS."""
        clean_num = _normalize_number(issue_number)
        key = _issue_key(owner, repo, clean_num)
        with self._locked():
            data = self._load_unlocked()
            raw_record = data["issues"].get(key)
            now = _utc_now()
            if raw_record is None:
                record = IssueRecord(
                    owner=owner,
                    repo=repo,
                    issue_number=clean_num,
                    state=IssueState.NEW,
                    title=title,
                    created_at=now,
                    updated_at=now,
                )
            else:
                record = IssueRecord.from_dict(raw_record)

            if record.state == to_state:
                return record

            allowed = ALLOWED_TRANSITIONS[record.state]
            if to_state not in allowed:
                raise StateTransitionError(
                    f"Illegal transition for {key}: {record.state.value} -> {to_state.value}"
                )

            record.history.append(
                {
                    "from": record.state.value,
                    "to": to_state.value,
                    "at": now,
                    "reason": reason,
                }
            )
            record.state = to_state
            record.updated_at = now
            if reason:
                record.reason = reason
            if title:
                record.title = title
            if to_state == IssueState.CLAIMED and not record.claimed_at:
                record.claimed_at = now
            if branch is not None:
                record.branch = branch
            if pr_url is not None:
                record.pr_url = pr_url
            if pr_number is not None:
                record.pr_number = pr_number

            data["issues"][key] = record.to_dict()
            self._save_unlocked(data)
            return record

    def pick_earliest_claimed(self, owner: str, repo: str) -> IssueRecord | None:
        """Return the earliest issue in CLAIMED state for the given repository."""
        records = [
            r
            for r in self.list_records(owner=owner, repo=repo)
            if r.state == IssueState.CLAIMED
        ]
        if not records:
            return None
        records.sort(
            key=lambda r: (
                r.claimed_at or r.created_at,
                int(r.issue_number) if r.issue_number.isdigit() else 0,
                r.issue_number,
            )
        )
        return records[0]
