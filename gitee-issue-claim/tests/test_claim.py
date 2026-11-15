"""Unit tests for Skill A (gitee-issue-claim), state machine, filters, and redaction."""

from __future__ import annotations

import importlib
import io
import logging
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
CLAIM_SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
for _p in (REPO_ROOT, CLAIM_SCRIPTS):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

_shared = importlib.import_module("gitee-issue-shared")
GiteeClient = _shared.GiteeClient
IssueState = _shared.IssueState
StateStore = _shared.StateStore
StateTransitionError = _shared.StateTransitionError
setup_logger = _shared.setup_logger

import claim_issue  # noqa: E402


class FakeGiteeClient(GiteeClient):
    """In-memory mock Gitee client for deterministic Skill A tests."""

    def __init__(
        self,
        *,
        issues: list[dict[str, Any]],
        open_pulls: list[dict[str, Any]] | None = None,
        issue_pulls_map: dict[str, list[dict[str, Any]]] | None = None,
        bot_login: str = "openlearn-bot",
    ) -> None:
        self.issues = issues
        self.open_pulls = open_pulls or []
        self.issue_pulls_map = issue_pulls_map or {}
        self.bot_login = bot_login
        self.comments: list[tuple[str, str]] = []
        self.updates: list[dict[str, Any]] = []
        self.writes_count = 0

    def get_current_user(self) -> dict[str, Any]:
        return {"login": self.bot_login}

    def get_repo(self, owner: str, repo: str) -> dict[str, Any]:
        return {"default_branch": "main"}

    def list_repo_issues(
        self, owner: str, repo: str, *, state: str = "open", page: int = 1, per_page: int = 50
    ) -> list[dict[str, Any]]:
        return [i for i in self.issues if i.get("state", "open") == state]

    def get_repo_issue_detail(self, owner: str, repo: str, number: str | int) -> dict[str, Any]:
        for issue in self.issues:
            if str(issue["number"]) == str(number):
                return issue
        raise KeyError(number)

    def list_issue_comments(
        self, owner: str, repo: str, number: str | int, *, page: int = 1, per_page: int = 50
    ) -> list[dict[str, Any]]:
        return []

    def update_issue(
        self,
        owner: str,
        repo: str,
        number: str | int,
        *,
        assignee: str | None = None,
        labels: list[str] | None = None,
        state: str | None = None,
    ) -> dict[str, Any]:
        self.writes_count += 1
        self.updates.append(
            {"number": str(number), "assignee": assignee, "labels": labels, "state": state}
        )
        for issue in self.issues:
            if str(issue["number"]) == str(number):
                if assignee is not None:
                    issue["assignee"] = {"login": assignee}
                if labels is not None:
                    issue["labels"] = [{"name": lbl} for lbl in labels]
                return issue
        raise KeyError(number)

    def comment_issue(
        self, owner: str, repo: str, number: str | int, body: str
    ) -> dict[str, Any]:
        self.writes_count += 1
        self.comments.append((str(number), body))
        return {"id": len(self.comments), "body": body}

    def list_repo_pulls(
        self, owner: str, repo: str, *, state: str = "open", page: int = 1, per_page: int = 50
    ) -> list[dict[str, Any]]:
        return self.open_pulls

    def list_issue_pulls(
        self, owner: str, repo: str, number: str | int
    ) -> list[dict[str, Any]]:
        return self.issue_pulls_map.get(str(number), [])

    def create_branch(
        self, owner: str, repo: str, *, refs: str, branch_name: str
    ) -> dict[str, Any]:
        raise AssertionError("Skill A must never create branches")

    def delete_branch(self, owner: str, repo: str, branch_name: str) -> None:
        raise AssertionError("Skill A must never delete branches")

    def create_pull(
        self, owner: str, repo: str, *, title: str, head: str, base: str, body: str
    ) -> dict[str, Any]:
        raise AssertionError("Skill A must never create PRs")


class TestClaimSkill(unittest.TestCase):
    def test_filter_rules_and_max_one_claim(self) -> None:
        issues = [
            {
                "number": 1,
                "title": "Already assigned",
                "state": "open",
                "assignee": {"login": "alice"},
                "labels": [],
            },
            {
                "number": 2,
                "title": "Already labeled",
                "state": "open",
                "assignee": None,
                "labels": [{"name": "bot-processing"}],
            },
            {
                "number": 3,
                "title": "Has open PR",
                "state": "open",
                "assignee": None,
                "labels": [],
            },
            {
                "number": 4,
                "title": "First eligible issue",
                "state": "open",
                "assignee": None,
                "labels": [{"name": "bug"}],
            },
            {
                "number": 5,
                "title": "Second eligible issue",
                "state": "open",
                "assignee": None,
                "labels": [],
            },
        ]
        open_pulls = [
            {"number": 99, "state": "open", "title": "WIP", "body": "fixes #3", "head": {"ref": "fix/other"}}
        ]
        client = FakeGiteeClient(issues=issues, open_pulls=open_pulls)

        with tempfile.TemporaryDirectory() as tmp:
            state_path = Path(tmp) / "state.json"
            store = StateStore(state_path)

            res = claim_issue.claim_next_issue(client, store, "aymwoo", "demo")

            self.assertEqual(res.claimed_issue_number, "4")
            self.assertEqual(len(client.comments), 1)
            self.assertEqual(client.comments[0][0], "4")
            self.assertEqual(len(client.updates), 1)
            self.assertEqual(client.updates[0]["assignee"], "openlearn-bot")
            self.assertEqual(client.updates[0]["labels"], ["bug", "bot-processing"])

            rec4 = store.get_record("aymwoo", "demo", 4)
            self.assertIsNotNone(rec4)
            self.assertEqual(rec4.state, IssueState.CLAIMED)
            self.assertIsNone(store.get_record("aymwoo", "demo", 5))

    def test_dry_run_performs_zero_writes(self) -> None:
        issues = [
            {"number": 10, "title": "Assigned", "state": "open", "assignee": {"login": "bob"}, "labels": []},
            {"number": 11, "title": "Eligible", "state": "open", "assignee": None, "labels": []},
        ]
        client = FakeGiteeClient(issues=issues)

        with tempfile.TemporaryDirectory() as tmp:
            state_path = Path(tmp) / "state.json"
            store = StateStore(state_path)
            res = claim_issue.claim_next_issue(client, store, "aymwoo", "demo", dry_run=True)

            self.assertTrue(res.dry_run)
            self.assertEqual(res.claimed_issue_number, "11")
            self.assertEqual(client.writes_count, 0)
            self.assertFalse(state_path.exists())
            self.assertEqual([e.action for e in res.evaluations], ["skip", "would_claim"])

    def test_idempotency_after_state_file_deleted(self) -> None:
        issues = [
            {"number": 21, "title": "Idempotent issue", "state": "open", "assignee": None, "labels": []}
        ]
        client = FakeGiteeClient(issues=issues)

        with tempfile.TemporaryDirectory() as tmp:
            state_path = Path(tmp) / "state.json"
            store = StateStore(state_path)

            first = claim_issue.claim_next_issue(client, store, "aymwoo", "demo")
            self.assertEqual(first.claimed_issue_number, "21")

            # Simulate state file loss.
            state_path.unlink()
            # Clear assignee to verify `bot-processing` label alone blocks re-claim.
            issues[0]["assignee"] = None

            second = claim_issue.claim_next_issue(client, store, "aymwoo", "demo")
            self.assertIsNone(second.claimed_issue_number)
            self.assertEqual(len(client.comments), 1)
            self.assertIn("bot-processing", second.evaluations[0].reasons[0])

    def test_state_machine_rejects_illegal_transition(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = StateStore(Path(tmp) / "state.json")
            store.ensure_new("o", "r", 7)
            store.transition("o", "r", 7, IssueState.CLAIMED)
            store.transition("o", "r", 7, IssueState.WORKING)
            store.transition("o", "r", 7, IssueState.PR_OPEN, pr_url="https://gitee.com/o/r/pulls/1")

            with self.assertRaises(StateTransitionError):
                store.transition("o", "r", 7, IssueState.WORKING)

    def test_token_redaction_in_logs(self) -> None:
        secret = "super-secret-gitee-token-12345"
        logger = setup_logger("test-redact", secrets=(secret,))
        stream = io.StringIO()
        handler = logging.StreamHandler(stream)
        for flt in logger.handlers[0].filters:
            handler.addFilter(flt)
        logger.handlers = [handler]

        logger.error("Auth failed with token %s and access_token=%s", secret, secret)
        output = stream.getvalue()
        self.assertNotIn(secret, output)
        self.assertIn("***REDACTED***", output)


if __name__ == "__main__":
    unittest.main()
