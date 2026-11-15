"""Shared core library for Gitee issue automation skills."""

from .config import Config, load_config
from .filters import (
    FilterDecision,
    build_branch_name,
    evaluate_issue_eligibility,
    extract_label_names,
    has_linked_open_pr,
    normalize_issue_number,
)
from .gitee_client import GiteeApiError, GiteeClient, GiteeRestClient
from .logging_utils import redact_text, setup_logger
from .state_machine import (
    ALLOWED_TRANSITIONS,
    IssueRecord,
    IssueState,
    StateStore,
    StateTransitionError,
)

__all__ = [
    "ALLOWED_TRANSITIONS",
    "Config",
    "FilterDecision",
    "GiteeApiError",
    "GiteeClient",
    "GiteeRestClient",
    "IssueRecord",
    "IssueState",
    "StateStore",
    "StateTransitionError",
    "build_branch_name",
    "evaluate_issue_eligibility",
    "extract_label_names",
    "has_linked_open_pr",
    "load_config",
    "normalize_issue_number",
    "redact_text",
    "setup_logger",
]
