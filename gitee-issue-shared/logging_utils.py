"""Structured logging utilities with mandatory token redaction."""

from __future__ import annotations

import logging
import re
import sys
from typing import Iterable

_REDACTION = "***REDACTED***"
_TOKEN_PATTERNS = (
    re.compile(r"(access_token=)[^&\s\"']+", re.IGNORECASE),
    re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE),
    re.compile(r"(token\s+)[A-Za-z0-9._\-]+", re.IGNORECASE),
    re.compile(r"(https?://[^/\s:@]+:)[^@\s/]+(@)", re.IGNORECASE),
)


def redact_text(text: str, secrets: Iterable[str] = ()) -> str:
    """Scrub known secret tokens and common credential patterns from text."""
    if not text:
        return text
    result = text
    for secret in secrets:
        if secret:
            result = result.replace(secret, _REDACTION)
    for pattern in _TOKEN_PATTERNS:
        if pattern.groups == 2:
            result = pattern.sub(rf"\1{_REDACTION}\2", result)
        else:
            result = pattern.sub(rf"\1{_REDACTION}", result)
    return result


class TokenRedactingFilter(logging.Filter):
    """Logging filter that strips tokens from log records before emission."""

    def __init__(self, secrets: Iterable[str] = ()) -> None:
        super().__init__()
        self._secrets = tuple(s for s in secrets if s)

    def filter(self, record: logging.LogRecord) -> bool:
        rendered = record.getMessage()
        scrubbed = redact_text(rendered, self._secrets)
        if scrubbed != rendered:
            record.msg = scrubbed
            record.args = ()
        if record.exc_info and record.exc_info[1] is not None:
            exc = record.exc_info[1]
            # Scrub exception string representation without losing type info.
            scrubbed_exc = redact_text(str(exc), self._secrets)
            if scrubbed_exc != str(exc):
                record.msg = f"{record.msg} ({scrubbed_exc})"
                record.exc_info = None
                record.exc_text = None
        return True


def setup_logger(
    name: str,
    *,
    secrets: Iterable[str] = (),
    level: int = logging.INFO,
) -> logging.Logger:
    """Create or reconfigure a stderr logger with token redaction enabled."""
    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.propagate = False
    logger.handlers.clear()

    handler = logging.StreamHandler(sys.stderr)
    handler.setLevel(level)
    handler.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    )
    handler.addFilter(TokenRedactingFilter(secrets))
    logger.addHandler(handler)
    return logger
