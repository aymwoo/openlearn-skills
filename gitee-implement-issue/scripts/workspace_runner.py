"""Git workspace operations, verification detection, and branch cleanup."""

from __future__ import annotations

import json
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path

from gitee_issue_shared_loader import load_shared_module

_shared = load_shared_module()
redact_text = _shared.redact_text


class WorkspaceError(RuntimeError):
    """Raised when git workspace operations or preconditions fail."""


@dataclass(frozen=True)
class VerifyResult:
    """Result of running project lint/test verification commands."""

    passed: bool
    commands: list[str]
    summary: str


def _run_git(
    repo_dir: Path,
    args: list[str],
    *,
    check: bool = True,
    secrets: tuple[str, ...] = (),
) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=str(repo_dir),
        capture_output=True,
        text=True,
        check=False,
    )
    if check and proc.returncode != 0:
        msg = redact_text(
            f"git {' '.join(args)} failed (code {proc.returncode}): {proc.stderr.strip() or proc.stdout.strip()}",
            secrets,
        )
        raise WorkspaceError(msg)
    return proc


def ensure_clean_worktree(repo_dir: Path) -> None:
    """Abort if the local git worktree has uncommitted changes."""
    proc = _run_git(repo_dir, ["status", "--porcelain"])
    if proc.stdout.strip():
        raise WorkspaceError(
            "Local git worktree is not clean; commit or stash changes before running Skill B."
        )


def get_current_branch(repo_dir: Path) -> str:
    """Return the currently checked out branch name."""
    proc = _run_git(repo_dir, ["rev-parse", "--abbrev-ref", "HEAD"])
    branch = proc.stdout.strip()
    if not branch:
        raise WorkspaceError("Unable to determine current git branch")
    return branch


def list_remotes(repo_dir: Path) -> dict[str, str]:
    """Return a mapping of remote name -> fetch URL."""
    proc = _run_git(repo_dir, ["remote", "-v"], check=False)
    remotes: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] not in remotes:
            remotes[parts[0]] = parts[1]
    return remotes


def resolve_git_remote(
    repo_dir: Path,
    *,
    owner: str = "",
    repo: str = "",
    explicit: str = "",
) -> str:
    """Pick the remote that points at the target Gitee repository.

    Priority: explicit override > remote whose URL matches ``<owner>/<repo>``
    > ``origin`` > the first configured remote. Repositories often carry an
    ``origin`` pointing at a different host (e.g. a GitHub mirror) plus a
    ``gitee`` remote, so guessing ``origin`` blindly pushes to the wrong place.
    """
    if explicit.strip():
        return explicit.strip()

    remotes = list_remotes(repo_dir)
    if owner and repo:
        needle = f"{owner}/{repo}".lower()
        for name, url in remotes.items():
            normalized = url.lower().rstrip("/")
            if normalized.endswith(".git"):
                normalized = normalized[: -len(".git")]
            if needle in normalized:
                return name

    if "origin" in remotes:
        return "origin"
    return next(iter(remotes), "origin")


def has_remote(repo_dir: Path, remote: str = "origin") -> bool:
    """Return True if the given remote is configured."""
    return remote in list_remotes(repo_dir)


def has_origin_remote(repo_dir: Path) -> bool:
    """Return True if an `origin` remote is configured."""
    return has_remote(repo_dir, "origin")


def prepare_branch(
    repo_dir: Path,
    *,
    base_branch: str,
    branch_name: str,
    remote: str = "origin",
    secrets: tuple[str, ...] = (),
) -> None:
    """Sync base branch if the remote exists and checkout the target fix branch."""
    if has_remote(repo_dir, remote):
        _run_git(repo_dir, ["fetch", remote], check=False, secrets=secrets)
        remote_branch = _run_git(
            repo_dir,
            ["ls-remote", "--heads", remote, branch_name],
            check=False,
            secrets=secrets,
        )
        if remote_branch.stdout.strip():
            _run_git(
                repo_dir,
                ["checkout", "-B", branch_name, f"{remote}/{branch_name}"],
                secrets=secrets,
            )
            return
        # Fallback if remote branch creation used API or local repo is decoupled.
        base_ref = f"{remote}/{base_branch}"
        has_remote_base = (
            _run_git(repo_dir, ["rev-parse", "--verify", base_ref], check=False).returncode == 0
        )
        start_point = base_ref if has_remote_base else base_branch
        _run_git(repo_dir, ["checkout", "-B", branch_name, start_point], secrets=secrets)
    else:
        _run_git(repo_dir, ["checkout", "-B", branch_name, base_branch], secrets=secrets)


def get_changed_files(repo_dir: Path) -> list[str]:
    """Return relative paths of modified, added, deleted, or untracked files."""
    proc = _run_git(repo_dir, ["status", "--porcelain", "-uall"])
    files: list[str] = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        path_part = line[3:].strip()
        if " -> " in path_part:
            path_part = path_part.split(" -> ", 1)[1].strip()
        if path_part and path_part not in files:
            files.append(path_part)
    return files


def commit_and_push(
    repo_dir: Path,
    *,
    branch_name: str,
    commit_message: str,
    remote: str = "origin",
    secrets: tuple[str, ...] = (),
) -> None:
    """Stage changes, commit, and push the branch to the resolved remote."""
    _run_git(repo_dir, ["add", "-A"], secrets=secrets)
    _run_git(repo_dir, ["commit", "-m", commit_message], secrets=secrets)
    if has_remote(repo_dir, remote):
        _run_git(repo_dir, ["push", "-u", remote, branch_name], secrets=secrets)


def cleanup_branch_on_failure(
    repo_dir: Path,
    *,
    base_branch: str,
    branch_name: str,
    secrets: tuple[str, ...] = (),
) -> None:
    """Discard working changes, switch back to base_branch, and delete local branch."""
    _run_git(repo_dir, ["reset", "--hard"], check=False, secrets=secrets)
    _run_git(repo_dir, ["clean", "-fd"], check=False, secrets=secrets)
    _run_git(repo_dir, ["checkout", base_branch], check=False, secrets=secrets)
    if branch_name and branch_name != base_branch:
        _run_git(repo_dir, ["branch", "-D", branch_name], check=False, secrets=secrets)


def detect_package_manager(repo_dir: Path) -> str:
    """Detect the JavaScript package manager used by the repository.

    Lockfiles are authoritative; ``packageManager`` in package.json is used as a
    fallback before defaulting to npm. Hardcoding npm breaks pnpm/yarn/bun
    workspaces, where ``npm test`` either fails outright or resolves a different
    dependency tree than the project expects.
    """
    lockfiles = (
        ("pnpm-lock.yaml", "pnpm"),
        ("yarn.lock", "yarn"),
        ("bun.lockb", "bun"),
        ("bun.lock", "bun"),
    )
    for filename, manager in lockfiles:
        if (repo_dir / filename).is_file():
            return manager

    pkg_json = repo_dir / "package.json"
    if pkg_json.is_file():
        try:
            pkg = json.loads(pkg_json.read_text(encoding="utf-8"))
            declared = str(pkg.get("packageManager") or "").strip().lower()
            for manager in ("pnpm", "yarn", "bun", "npm"):
                if declared.startswith(manager):
                    return manager
        except (OSError, json.JSONDecodeError):
            pass
    return "npm"


def _script_command(manager: str, script: str) -> str:
    """Build the run command for a package.json script under a given manager."""
    if manager == "npm":
        # `npm test` is the canonical shorthand; other scripts need `npm run`.
        return "npm test" if script == "test" else f"npm run {script}"
    return f"{manager} run {script}"


def detect_verify_commands(repo_dir: Path, override_cmd: str = "") -> list[str]:
    """Detect existing lint/test commands in priority order."""
    if override_cmd.strip():
        return [override_cmd.strip()]

    commands: list[str] = []

    pkg_json = repo_dir / "package.json"
    if pkg_json.is_file():
        try:
            pkg = json.loads(pkg_json.read_text(encoding="utf-8"))
            scripts = pkg.get("scripts") or {}
            if isinstance(scripts, dict):
                manager = detect_package_manager(repo_dir)
                lint_cmd = str(scripts.get("lint", "")).strip()
                test_cmd = str(scripts.get("test", "")).strip()
                if lint_cmd:
                    commands.append(_script_command(manager, "lint"))
                if test_cmd and "no test specified" not in test_cmd.lower():
                    commands.append(_script_command(manager, "test"))
        except (OSError, json.JSONDecodeError):
            pass

    if (repo_dir / "ruff.toml").is_file() or (repo_dir / ".ruff.toml").is_file():
        commands.append("ruff check .")

    has_pytest = (
        (repo_dir / "pytest.ini").is_file()
        or (repo_dir / "conftest.py").is_file()
        or (
            (repo_dir / "pyproject.toml").is_file()
            and "pytest" in (repo_dir / "pyproject.toml").read_text(encoding="utf-8", errors="ignore")
        )
    )
    if has_pytest:
        commands.append("pytest")
    elif (repo_dir / "tests").is_dir() and any((repo_dir / "tests").glob("test_*.py")):
        commands.append("python3 -m unittest discover -s tests")

    if (repo_dir / "go.mod").is_file():
        commands.append("go test ./...")

    if (repo_dir / "Cargo.toml").is_file():
        commands.append("cargo test")

    return commands


def run_verification(
    repo_dir: Path,
    *,
    override_cmd: str = "",
    timeout_sec: int = 300,
    secrets: tuple[str, ...] = (),
) -> VerifyResult:
    """Run detected lint/test commands; fail fast on first non-zero exit."""
    commands = detect_verify_commands(repo_dir, override_cmd=override_cmd)
    if not commands:
        return VerifyResult(
            passed=True,
            commands=[],
            summary="No existing lint/test command detected in repository; skipped verification.",
        )

    outputs: list[str] = []
    for cmd in commands:
        # Use shell=True only for user-configured GITEE_VERIFY_CMD; detected commands are fixed strings.
        use_shell = bool(override_cmd.strip())
        run_arg: str | list[str] = cmd if use_shell else shlex.split(cmd)
        try:
            proc = subprocess.run(
                run_arg,
                cwd=str(repo_dir),
                shell=use_shell,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                check=False,
            )
        except FileNotFoundError:
            return VerifyResult(
                passed=False,
                commands=commands,
                summary=f"Verification command not found: {cmd}",
            )
        except subprocess.TimeoutExpired:
            return VerifyResult(
                passed=False,
                commands=commands,
                summary=f"Verification command timed out after {timeout_sec}s: {cmd}",
            )

        combined = redact_text(
            (proc.stdout + "\n" + proc.stderr).strip(), secrets
        )
        if proc.returncode != 0:
            snippet = combined[-1200:] if len(combined) > 1200 else combined
            return VerifyResult(
                passed=False,
                commands=commands,
                summary=f"Verification failed for `{cmd}` (exit {proc.returncode}):\n{snippet}",
            )
        outputs.append(f"`{cmd}` passed")

    return VerifyResult(
        passed=True,
        commands=commands,
        summary="; ".join(outputs),
    )
