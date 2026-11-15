"""Helper to locate gitee-issue-shared from scripts inside Skill B."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path
from types import ModuleType


def load_shared_module() -> ModuleType:
    """Ensure `gitee-issue-shared` is importable and return it."""
    here = Path(__file__).resolve().parent
    for root in (here.parent.parent, here.parent):
        if (root / "gitee-issue-shared").is_dir() and str(root) not in sys.path:
            sys.path.insert(0, str(root))
            break
    return importlib.import_module("gitee-issue-shared")
