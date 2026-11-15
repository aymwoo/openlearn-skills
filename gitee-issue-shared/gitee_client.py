"""Gitee API v5 client aligned with Gitee MCP Server tool semantics.

Safety invariant: this module intentionally does NOT implement `merge_pull` or
any PR-merging endpoint. PRs must always be reviewed and merged by a human.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from abc import ABC, abstractmethod
from typing import Any

from .logging_utils import redact_text


class GiteeApiError(RuntimeError):
    """Raised when a Gitee API call fails."""

    def __init__(self, message: str, *, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


class GiteeClient(ABC):
    """Abstract interface matching Gitee MCP Server tools (without merge_pull)."""

    @abstractmethod
    def get_current_user(self) -> dict[str, Any]:
        """Return the authenticated bot user profile."""

    @abstractmethod
    def get_repo(self, owner: str, repo: str) -> dict[str, Any]:
        """Return repository metadata (including default_branch)."""

    @abstractmethod
    def list_repo_issues(
        self,
        owner: str,
        repo: str,
        *,
        state: str = "open",
        page: int = 1,
        per_page: int = 50,
    ) -> list[dict[str, Any]]:
        """List repository issues (MCP: list_repo_issues)."""

    @abstractmethod
    def get_repo_issue_detail(
        self, owner: str, repo: str, number: str | int
    ) -> dict[str, Any]:
        """Fetch a single issue detail (MCP: get_repo_issue_detail)."""

    @abstractmethod
    def list_issue_comments(
        self,
        owner: str,
        repo: str,
        number: str | int,
        *,
        page: int = 1,
        per_page: int = 50,
    ) -> list[dict[str, Any]]:
        """List comments on an issue (MCP: list_issue_comments)."""

    @abstractmethod
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
        """Update issue assignee, labels, or state (MCP: update_issue)."""

    @abstractmethod
    def comment_issue(
        self, owner: str, repo: str, number: str | int, body: str
    ) -> dict[str, Any]:
        """Post a comment on an issue (MCP: comment_issue)."""

    @abstractmethod
    def list_repo_pulls(
        self,
        owner: str,
        repo: str,
        *,
        state: str = "open",
        page: int = 1,
        per_page: int = 50,
    ) -> list[dict[str, Any]]:
        """List repository pull requests."""

    @abstractmethod
    def list_issue_pulls(
        self, owner: str, repo: str, number: str | int
    ) -> list[dict[str, Any]]:
        """List pull requests linked to a specific issue if supported."""

    @abstractmethod
    def create_branch(
        self, owner: str, repo: str, *, refs: str, branch_name: str
    ) -> dict[str, Any]:
        """Create a branch in the remote repository (MCP: create_branch)."""

    @abstractmethod
    def delete_branch(self, owner: str, repo: str, branch_name: str) -> None:
        """Delete a temporary remote branch during failure rollback."""

    @abstractmethod
    def create_pull(
        self,
        owner: str,
        repo: str,
        *,
        title: str,
        head: str,
        base: str,
        body: str,
    ) -> dict[str, Any]:
        """Create a pull request (MCP: create_pull). Never merges."""


class GiteeRestClient(GiteeClient):
    """Zero-dependency Python stdlib HTTP client for Gitee REST API v5."""

    def __init__(
        self,
        *,
        token: str,
        api_base: str = "https://gitee.com/api/v5",
        timeout_sec: int = 30,
    ) -> None:
        self._token = token.strip()
        self._api_base = api_base.rstrip("/")
        self._timeout_sec = timeout_sec

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        payload: dict[str, Any] | None = None,
    ) -> Any:
        url = f"{self._api_base}{path}"
        if params:
            filtered = {k: v for k, v in params.items() if v is not None}
            if filtered:
                url = f"{url}?{urllib.parse.urlencode(filtered)}"

        headers = {
            "Accept": "application/json",
            "User-Agent": "openlearn-gitee-issue-automation/1.0",
        }
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"

        data: bytes | None = None
        if payload is not None:
            headers["Content-Type"] = "application/json; charset=utf-8"
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self._timeout_sec) as resp:
                raw = resp.read().decode("utf-8", errors="replace").strip()
                if not raw:
                    return None
                return json.loads(raw)
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace").strip()
            safe_msg = redact_text(
                f"Gitee API {method} {path} failed ({exc.code}): {err_body}",
                (self._token,),
            )
            raise GiteeApiError(safe_msg, status_code=exc.code) from exc
        except urllib.error.URLError as exc:
            safe_msg = redact_text(
                f"Gitee API {method} {path} network error: {exc.reason}",
                (self._token,),
            )
            raise GiteeApiError(safe_msg) from exc

    def get_current_user(self) -> dict[str, Any]:
        result = self._request("GET", "/user")
        if not isinstance(result, dict):
            raise GiteeApiError("Unexpected response from /user")
        return result

    def get_repo(self, owner: str, repo: str) -> dict[str, Any]:
        result = self._request(
            "GET",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}",
        )
        if not isinstance(result, dict):
            raise GiteeApiError("Unexpected response from get_repo")
        return result

    def list_repo_issues(
        self,
        owner: str,
        repo: str,
        *,
        state: str = "open",
        page: int = 1,
        per_page: int = 50,
    ) -> list[dict[str, Any]]:
        result = self._request(
            "GET",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/issues",
            params={
                "state": state,
                "page": page,
                "per_page": per_page,
                "sort": "created",
                "direction": "asc",
            },
        )
        return result if isinstance(result, list) else []

    def get_repo_issue_detail(
        self, owner: str, repo: str, number: str | int
    ) -> dict[str, Any]:
        clean = str(number).lstrip("#")
        result = self._request(
            "GET",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/issues/{urllib.parse.quote(clean)}",
        )
        if not isinstance(result, dict):
            raise GiteeApiError(f"Unexpected response from get_repo_issue_detail #{clean}")
        return result

    def list_issue_comments(
        self,
        owner: str,
        repo: str,
        number: str | int,
        *,
        page: int = 1,
        per_page: int = 50,
    ) -> list[dict[str, Any]]:
        clean = str(number).lstrip("#")
        result = self._request(
            "GET",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/issues/{urllib.parse.quote(clean)}/comments",
            params={"page": page, "per_page": per_page},
        )
        return result if isinstance(result, list) else []

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
        clean = str(number).lstrip("#")
        payload: dict[str, Any] = {"repo": repo}
        if assignee is not None:
            payload["assignee"] = assignee
        if labels is not None:
            payload["labels"] = ",".join(labels)
        if state is not None:
            payload["state"] = state
        result = self._request(
            "PATCH",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/issues/{urllib.parse.quote(clean)}",
            payload=payload,
        )
        if not isinstance(result, dict):
            raise GiteeApiError(f"Unexpected response from update_issue #{clean}")
        return result

    def comment_issue(
        self, owner: str, repo: str, number: str | int, body: str
    ) -> dict[str, Any]:
        clean = str(number).lstrip("#")
        result = self._request(
            "POST",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/issues/{urllib.parse.quote(clean)}/comments",
            payload={"body": body},
        )
        if not isinstance(result, dict):
            raise GiteeApiError(f"Unexpected response from comment_issue #{clean}")
        return result

    def list_repo_pulls(
        self,
        owner: str,
        repo: str,
        *,
        state: str = "open",
        page: int = 1,
        per_page: int = 50,
    ) -> list[dict[str, Any]]:
        result = self._request(
            "GET",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/pulls",
            params={"state": state, "page": page, "per_page": per_page},
        )
        return result if isinstance(result, list) else []

    def list_issue_pulls(
        self, owner: str, repo: str, number: str | int
    ) -> list[dict[str, Any]]:
        clean = str(number).lstrip("#")
        try:
            result = self._request(
                "GET",
                f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/issues/{urllib.parse.quote(clean)}/pull_requests",
            )
            return result if isinstance(result, list) else []
        except GiteeApiError as exc:
            if exc.status_code in (404, 405):
                return []
            raise

    def create_branch(
        self, owner: str, repo: str, *, refs: str, branch_name: str
    ) -> dict[str, Any]:
        result = self._request(
            "POST",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/branches",
            payload={"refs": refs, "branch_name": branch_name},
        )
        return result if isinstance(result, dict) else {"name": branch_name, "refs": refs}

    def delete_branch(self, owner: str, repo: str, branch_name: str) -> None:
        encoded = urllib.parse.quote(branch_name, safe="")
        self._request(
            "DELETE",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/branches/{encoded}",
        )

    def create_pull(
        self,
        owner: str,
        repo: str,
        *,
        title: str,
        head: str,
        base: str,
        body: str,
    ) -> dict[str, Any]:
        result = self._request(
            "POST",
            f"/repos/{urllib.parse.quote(owner)}/{urllib.parse.quote(repo)}/pulls",
            payload={
                "title": title,
                "head": head,
                "base": base,
                "body": body,
            },
        )
        if not isinstance(result, dict):
            raise GiteeApiError("Unexpected response from create_pull")
        return result
