"""Unit tests for Skill B (gitee-implement-issue) and safety guardrails."""

from __future__ import annotations

import importlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
IMPL_SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
for _p in (REPO_ROOT, IMPL_SCRIPTS):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

_shared = importlib.import_module("gitee-issue-shared")
Config = _shared.Config
GiteeClient = _shared.GiteeClient
GiteeRestClient = _shared.GiteeRestClient
IssueState = _shared.IssueState
StateStore = _shared.StateStore
build_branch_name = _shared.build_branch_name

from coding_agent import AgentRunResult  # noqa: E402
import implement_issue  # noqa: E402
import workspace_runner  # noqa: E402


class FakeImplGiteeClient(GiteeClient):
    """In-memory mock Gitee client for Skill B lifecycle tests."""

    def __init__(self, issues: dict[str, dict[str, Any]]) -> None:
        self.issues = issues
        self.comments: list[tuple[str, str]] = []
        self.created_branches: list[tuple[str, str]] = []
        self.deleted_branches: list[str] = []
        self.created_pulls: list[dict[str, Any]] = []
        self.open_pulls: list[dict[str, Any]] = []

    def get_current_user(self) -> dict[str, Any]:
        return {"login": "openlearn-bot"}

    def get_repo(self, owner: str, repo: str) -> dict[str, Any]:
        return {"default_branch": "main"}

    def list_repo_issues(
        self, owner: str, repo: str, *, state: str = "open", page: int = 1, per_page: int = 50
    ) -> list[dict[str, Any]]:
        return list(self.issues.values())

    def get_repo_issue_detail(self, owner: str, repo: str, number: str | int) -> dict[str, Any]:
        return self.issues[str(number)]

    def list_issue_comments(
        self, owner: str, repo: str, number: str | int, *, page: int = 1, per_page: int = 50
    ) -> list[dict[str, Any]]:
        return [{"user": {"login": "maintainer"}, "body": "Please fix calc.py"}]

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
        return self.issues[str(number)]

    def comment_issue(
        self, owner: str, repo: str, number: str | int, body: str
    ) -> dict[str, Any]:
        self.comments.append((str(number), body))
        return {"id": len(self.comments), "body": body}

    def list_repo_pulls(
        self, owner: str, repo: str, *, state: str = "open", page: int = 1, per_page: int = 50
    ) -> list[dict[str, Any]]:
        return self.open_pulls

    def list_issue_pulls(
        self, owner: str, repo: str, number: str | int
    ) -> list[dict[str, Any]]:
        return []

    def create_branch(
        self, owner: str, repo: str, *, refs: str, branch_name: str
    ) -> dict[str, Any]:
        self.created_branches.append((refs, branch_name))
        return {"name": branch_name, "refs": refs}

    def delete_branch(self, owner: str, repo: str, branch_name: str) -> None:
        self.deleted_branches.append(branch_name)

    def create_pull(
        self, owner: str, repo: str, *, title: str, head: str, base: str, body: str
    ) -> dict[str, Any]:
        pr = {
            "number": len(self.created_pulls) + 101,
            "title": title,
            "head": head,
            "base": base,
            "body": body,
            "html_url": f"https://gitee.com/{owner}/{repo}/pulls/{len(self.created_pulls) + 101}",
        }
        self.created_pulls.append(pr)
        return pr


def _init_temp_git_repo(repo_dir: Path) -> None:
    subprocess.run(["git", "init", "-b", "main"], cwd=repo_dir, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "bot@example.com"], cwd=repo_dir, check=True)
    subprocess.run(["git", "config", "user.name", "Bot"], cwd=repo_dir, check=True)

    (repo_dir / "calc.py").write_text("def add(a, b):\n    return a - b\n", encoding="utf-8")
    tests_dir = repo_dir / "tests"
    tests_dir.mkdir()
    (tests_dir / "test_calc.py").write_text(
        "import unittest\nfrom calc import add\n\nclass T(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(add(2, 3), 5)\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "add", "-A"], cwd=repo_dir, check=True)
    subprocess.run(["git", "commit", "-m", "init"], cwd=repo_dir, check=True, capture_output=True)


def _make_config(repo_dir: Path, state_path: Path, *, max_changed_files: int = 5) -> Config:
    return Config(
        gitee_token="dummy-token",
        api_base="https://gitee.com/api/v5",
        bot_username="openlearn-bot",
        state_path=state_path,
        repo_dir=repo_dir,
        base_branch="main",
        coding_agent_cmd="claude",
        agent_max_turns=25,
        agent_timeout_sec=1200,
        verify_cmd="python3 -m unittest discover -s tests",
        max_changed_files=max_changed_files,
        processing_label="bot-processing",
    )


class TestImplementSkill(unittest.TestCase):
    def test_no_merge_pull_capability_exposed(self) -> None:
        self.assertFalse(hasattr(GiteeClient, "merge_pull"))
        self.assertFalse(hasattr(GiteeRestClient, "merge_pull"))

    def test_branch_name_slug_and_length_limit(self) -> None:
        long_title = "Fix crash when parsing extraordinarily long configuration header names in parser"
        branch = build_branch_name(42, long_title, max_slug_len=30)
        self.assertTrue(branch.startswith("fix/issue-42-"))
        slug = branch[len("fix/issue-42-") :]
        self.assertLessEqual(len(slug), 30)
        self.assertFalse(slug.endswith("-"))

        zh_branch = build_branch_name(8, "修复中文标题解析异常")
        self.assertRegex(zh_branch, r"^fix/issue-8-task-[0-9a-f]{6}$")

    def test_dry_run_outputs_plan_without_writes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            repo_dir = tmp_path / "repo"
            repo_dir.mkdir()
            _init_temp_git_repo(repo_dir)
            cfg = _make_config(repo_dir, tmp_path / "state.json")
            store = StateStore(cfg.state_path)
            client = FakeImplGiteeClient(
                {"12": {"number": 12, "title": "Fix add in calc.py", "body": "calc.py returns wrong sum", "state": "open"}}
            )

            res = implement_issue.implement_issue(
                client, store, cfg, "aymwoo", "demo", issue_number=12, dry_run=True
            )

            self.assertEqual(res.status, "dry_run")
            self.assertIn("calc.py", res.dry_run_plan["candidate_files"])
            self.assertEqual(client.created_branches, [])
            self.assertEqual(client.created_pulls, [])
            self.assertEqual(client.comments, [])

    def test_auto_picks_earliest_claimed_and_opens_pr_with_closes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            repo_dir = tmp_path / "repo"
            repo_dir.mkdir()
            _init_temp_git_repo(repo_dir)
            cfg = _make_config(repo_dir, tmp_path / "state.json")
            store = StateStore(cfg.state_path)

            # Seed two claimed issues; #5 was claimed before #9.
            store.ensure_new("aymwoo", "demo", 5, title="Fix add in calc.py")
            store.transition("aymwoo", "demo", 5, IssueState.CLAIMED)
            store.ensure_new("aymwoo", "demo", 9, title="Other issue")
            store.transition("aymwoo", "demo", 9, IssueState.CLAIMED)

            client = FakeImplGiteeClient(
                {
                    "5": {"number": 5, "title": "Fix add in calc.py", "body": "Fix add", "state": "open"},
                    "9": {"number": 9, "title": "Other issue", "body": "Other", "state": "open"},
                }
            )

            def fake_agent(**kwargs: Any) -> AgentRunResult:
                (repo_dir / "calc.py").write_text(
                    "def add(a, b):\n    return a + b\n", encoding="utf-8"
                )
                return AgentRunResult(success=True, cannot_implement_reason="", output="fixed")

            res = implement_issue.implement_issue(
                client,
                store,
                cfg,
                "aymwoo",
                "demo",
                issue_number=None,  # omit to verify auto-pick earliest claimed
                agent_runner=fake_agent,
            )

            self.assertEqual(res.status, "pr_open")
            self.assertEqual(res.issue_number, "5")
            self.assertEqual(len(client.created_pulls), 1)
            self.assertIn("closes #5", client.created_pulls[0]["body"])
            self.assertEqual(len(client.comments), 1)
            self.assertIn("https://gitee.com/aymwoo/demo/pulls/101", client.comments[0][1])

            rec5 = store.get_record("aymwoo", "demo", 5)
            rec9 = store.get_record("aymwoo", "demo", 9)
            self.assertEqual(rec5.state, IssueState.PR_OPEN)
            self.assertEqual(rec9.state, IssueState.CLAIMED)

    def test_verification_failure_comments_cleans_branch_and_skips_pr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            repo_dir = tmp_path / "repo"
            repo_dir.mkdir()
            _init_temp_git_repo(repo_dir)
            cfg = _make_config(repo_dir, tmp_path / "state.json")
            store = StateStore(cfg.state_path)
            client = FakeImplGiteeClient(
                {"7": {"number": 7, "title": "Broken fix", "body": "Fix calc", "state": "open"}}
            )

            def bad_agent(**kwargs: Any) -> AgentRunResult:
                (repo_dir / "calc.py").write_text(
                    "def add(a, b):\n    return a * b\n", encoding="utf-8"
                )
                return AgentRunResult(success=True, cannot_implement_reason="", output="edited")

            res = implement_issue.implement_issue(
                client, store, cfg, "aymwoo", "demo", issue_number=7, agent_runner=bad_agent
            )

            self.assertEqual(res.status, "failed")
            self.assertEqual(client.created_pulls, [])
            self.assertEqual(len(client.comments), 1)
            self.assertIn("失败原因", client.comments[0][1])
            self.assertEqual(client.deleted_branches, ["fix/issue-7-broken-fix"])

            rec7 = store.get_record("aymwoo", "demo", 7)
            self.assertEqual(rec7.state, IssueState.SKIPPED)
            self.assertEqual(
                subprocess.run(
                    ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                    cwd=repo_dir,
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip(),
                "main",
            )

    def test_agent_cannot_implement_comments_and_skips_pr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            repo_dir = tmp_path / "repo"
            repo_dir.mkdir()
            _init_temp_git_repo(repo_dir)
            cfg = _make_config(repo_dir, tmp_path / "state.json")
            store = StateStore(cfg.state_path)
            client = FakeImplGiteeClient(
                {"15": {"number": 15, "title": "Vague request", "body": "Make it better", "state": "open"}}
            )

            def confused_agent(**kwargs: Any) -> AgentRunResult:
                return AgentRunResult(
                    success=False,
                    cannot_implement_reason="Issue lacks reproduction steps",
                    output="CANNOT_IMPLEMENT: Issue lacks reproduction steps",
                )

            res = implement_issue.implement_issue(
                client, store, cfg, "aymwoo", "demo", issue_number=15, agent_runner=confused_agent
            )

            self.assertEqual(res.status, "failed")
            self.assertEqual(client.created_pulls, [])
            self.assertIn("Issue lacks reproduction steps", client.comments[0][1])
            self.assertEqual(store.get_record("aymwoo", "demo", 15).state, IssueState.SKIPPED)

    def test_excess_changed_files_guardrail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            repo_dir = tmp_path / "repo"
            repo_dir.mkdir()
            _init_temp_git_repo(repo_dir)
            cfg = _make_config(repo_dir, tmp_path / "state.json", max_changed_files=2)
            store = StateStore(cfg.state_path)
            client = FakeImplGiteeClient(
                {"20": {"number": 20, "title": "Too broad", "body": "Refactor", "state": "open"}}
            )

            def noisy_agent(**kwargs: Any) -> AgentRunResult:
                for idx in range(4):
                    (repo_dir / f"extra_{idx}.txt").write_text("x", encoding="utf-8")
                return AgentRunResult(success=True, cannot_implement_reason="", output="done")

            res = implement_issue.implement_issue(
                client, store, cfg, "aymwoo", "demo", issue_number=20, agent_runner=noisy_agent
            )

            self.assertEqual(res.status, "failed")
            self.assertEqual(client.created_pulls, [])
            self.assertIn("GITEE_MAX_CHANGED_FILES=2", client.comments[0][1])


class RemoteAndPackageManagerTests(unittest.TestCase):
    """Guard rails for git remote resolution and JS package manager detection."""

    def _git_repo_with_remotes(self, remotes: dict[str, str]) -> Path:
        tmp = tempfile.mkdtemp()
        repo_dir = Path(tmp)
        subprocess.run(["git", "init", "-b", "main"], cwd=repo_dir, check=True, capture_output=True)
        for name, url in remotes.items():
            subprocess.run(
                ["git", "remote", "add", name, url],
                cwd=repo_dir,
                check=True,
                capture_output=True,
            )
        return repo_dir

    def test_resolve_git_remote_prefers_remote_matching_owner_repo(self) -> None:
        """A GitHub `origin` plus a `gitee` remote must resolve to `gitee`."""
        repo_dir = self._git_repo_with_remotes(
            {
                "origin": "git@github.com:aymwoo/OpenLearn-Next-V2.git",
                "gitee": "https://gitee.com/aymwoo/openlearn-next.git",
            }
        )
        remote = workspace_runner.resolve_git_remote(
            repo_dir, owner="aymwoo", repo="openlearn-next"
        )
        self.assertEqual(remote, "gitee")

    def test_resolve_git_remote_falls_back_to_origin(self) -> None:
        repo_dir = self._git_repo_with_remotes(
            {"origin": "https://gitee.com/other/project.git"}
        )
        remote = workspace_runner.resolve_git_remote(
            repo_dir, owner="aymwoo", repo="openlearn-next"
        )
        self.assertEqual(remote, "origin")

    def test_resolve_git_remote_honours_explicit_override(self) -> None:
        repo_dir = self._git_repo_with_remotes(
            {
                "origin": "https://gitee.com/aymwoo/openlearn-next.git",
                "upstream": "https://gitee.com/aymwoo/openlearn-next.git",
            }
        )
        remote = workspace_runner.resolve_git_remote(
            repo_dir, owner="aymwoo", repo="openlearn-next", explicit="upstream"
        )
        self.assertEqual(remote, "upstream")

    def _repo_with_package_json(self, extra_files: dict[str, str]) -> Path:
        tmp = tempfile.mkdtemp()
        repo_dir = Path(tmp)
        (repo_dir / "package.json").write_text(
            '{"scripts": {"lint": "tsc --noEmit", "test": "vitest run"}}',
            encoding="utf-8",
        )
        for name, content in extra_files.items():
            (repo_dir / name).write_text(content, encoding="utf-8")
        return repo_dir

    def test_detect_verify_commands_uses_pnpm_when_lockfile_present(self) -> None:
        repo_dir = self._repo_with_package_json({"pnpm-lock.yaml": "lockfileVersion: 9\n"})
        self.assertEqual(workspace_runner.detect_package_manager(repo_dir), "pnpm")
        self.assertEqual(
            workspace_runner.detect_verify_commands(repo_dir),
            ["pnpm run lint", "pnpm run test"],
        )

    def test_detect_verify_commands_uses_yarn_when_lockfile_present(self) -> None:
        repo_dir = self._repo_with_package_json({"yarn.lock": ""})
        self.assertEqual(
            workspace_runner.detect_verify_commands(repo_dir),
            ["yarn run lint", "yarn run test"],
        )

    def test_detect_verify_commands_defaults_to_npm(self) -> None:
        repo_dir = self._repo_with_package_json({})
        self.assertEqual(
            workspace_runner.detect_verify_commands(repo_dir),
            ["npm run lint", "npm test"],
        )

    def test_detect_verify_commands_honours_override(self) -> None:
        repo_dir = self._repo_with_package_json({"pnpm-lock.yaml": ""})
        self.assertEqual(
            workspace_runner.detect_verify_commands(repo_dir, override_cmd="pnpm run lint"),
            ["pnpm run lint"],
        )


if __name__ == "__main__":
    unittest.main()
