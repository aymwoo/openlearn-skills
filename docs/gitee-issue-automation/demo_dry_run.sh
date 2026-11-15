#!/usr/bin/env bash
# End-to-end executable dry-run & idempotency demo using a local mock Gitee API server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMP_DIR="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 1. Create a temporary sample git repository for Skill B dry-run analysis.
SAMPLE_REPO="$TMP_DIR/sample-repo"
mkdir -p "$SAMPLE_REPO/tests"
git -C "$SAMPLE_REPO" init -q -b main
git -C "$SAMPLE_REPO" config user.email "demo@example.com"
git -C "$SAMPLE_REPO" config user.name "Demo"
cat > "$SAMPLE_REPO/calculator.py" <<'EOF'
def add(a: int, b: int) -> int:
    return a - b
EOF
cat > "$SAMPLE_REPO/tests/test_calculator.py" <<'EOF'
import unittest
from calculator import add

class CalcTest(unittest.TestCase):
    def test_add(self):
        self.assertEqual(add(1, 2), 3)
EOF
git -C "$SAMPLE_REPO" add -A
git -C "$SAMPLE_REPO" commit -q -m "initial"

# 2. Start a lightweight local mock Gitee OpenAPI v5 server on an ephemeral port.
PORT_FILE="$TMP_DIR/server.port"
python3 - "$PORT_FILE" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

port_file = sys.argv[1]
ISSUES = [
    {
        "number": 10,
        "title": "Already assigned issue",
        "body": "skip me",
        "state": "open",
        "assignee": {"login": "alice"},
        "labels": [],
    },
    {
        "number": 11,
        "title": "Fix add bug in calculator.py",
        "body": "calculator.py subtracts instead of adding",
        "state": "open",
        "assignee": None,
        "labels": [{"name": "bug"}],
    },
]
COMMENTS = {11: []}
PULLS = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _send(self, code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/v5/user":
            return self._send(200, {"login": "demo-bot"})
        if path == "/api/v5/repos/demo-org/demo-repo":
            return self._send(200, {"default_branch": "main"})
        if path == "/api/v5/repos/demo-org/demo-repo/issues":
            return self._send(200, ISSUES)
        if path == "/api/v5/repos/demo-org/demo-repo/issues/11":
            return self._send(200, ISSUES[1])
        if path == "/api/v5/repos/demo-org/demo-repo/issues/11/comments":
            return self._send(200, COMMENTS[11])
        if path == "/api/v5/repos/demo-org/demo-repo/issues/11/pull_requests":
            return self._send(200, [])
        if path == "/api/v5/repos/demo-org/demo-repo/pulls":
            return self._send(200, PULLS)
        return self._send(404, {"message": f"Not found: {path}"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        path = urlparse(self.path).path
        if path == "/api/v5/repos/demo-org/demo-repo/issues/11/comments":
            COMMENTS[11].append({"user": {"login": "demo-bot"}, "body": payload.get("body", "")})
            return self._send(201, {"id": len(COMMENTS[11])})
        return self._send(404, {"message": f"Not found: {path}"})

    def do_PATCH(self):
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        path = urlparse(self.path).path
        if path == "/api/v5/repos/demo-org/demo-repo/issues/11":
            if "assignee" in payload:
                ISSUES[1]["assignee"] = {"login": payload["assignee"]}
            if "labels" in payload:
                ISSUES[1]["labels"] = [{"name": x} for x in payload["labels"].split(",") if x]
            return self._send(200, ISSUES[1])
        return self._send(404, {"message": f"Not found: {path}"})

srv = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as fh:
    fh.write(str(srv.server_port))
srv.serve_forever()
PY
SERVER_PID=$!

for _ in $(seq 1 30); do
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.1
done
PORT="$(cat "$PORT_FILE")"

export GITEE_API_BASE="http://127.0.0.1:${PORT}/api/v5"
export GITEE_TOKEN="demo-secret-token-never-logged"
export GITEE_ISSUE_STATE_PATH="$TMP_DIR/state/gitee_issue_state.json"
export GITEE_REPO_DIR="$SAMPLE_REPO"

echo "=== 1. Skill A --dry-run (no remote/local writes) ==="
python3 "$REPO_ROOT/gitee-issue-claim/scripts/claim_issue.py" \
  --owner demo-org --repo demo-repo --dry-run

echo ""
echo "=== 2. Skill A live claim against mock server ==="
CLAIMED="$(python3 "$REPO_ROOT/gitee-issue-claim/scripts/claim_issue.py" --owner demo-org --repo demo-repo)"
echo "Claimed issue_number: ${CLAIMED}"

echo ""
echo "=== 3. Simulate state file deletion and re-run Skill A (bot-processing idempotency) ==="
rm -f "$GITEE_ISSUE_STATE_PATH"
python3 "$REPO_ROOT/gitee-issue-claim/scripts/claim_issue.py" \
  --owner demo-org --repo demo-repo --dry-run

echo ""
echo "=== 4. Skill B --dry-run on claimed issue #${CLAIMED} ==="
python3 "$REPO_ROOT/gitee-implement-issue/scripts/implement_issue.py" \
  --owner demo-org --repo demo-repo --issue-number "$CLAIMED" --dry-run
