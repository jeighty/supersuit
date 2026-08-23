#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FAILURES=0
TEST_ROOT="$(mktemp -d)"
TEST_HOME="$TEST_ROOT/home"
mkdir -p "$TEST_HOME"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

echo "=== workflow YAML loader ==="
if LOADER_OUT="$(python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_yaml import load_yaml
text = """
version: 1
skills:
  brainstorming: {}
  writing-plans:
    skill: my-writing-plans
transitions:
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-architectural
    to: writing-plans
entries:
  creative-work: brainstorming
"""
doc = load_yaml(text)
assert doc["version"] == 1
assert doc["skills"]["brainstorming"] == {}
assert doc["skills"]["writing-plans"]["skill"] == "my-writing-plans"
assert doc["transitions"][0]["to"] is None
assert doc["entries"]["creative-work"] == "brainstorming"
print("ok")
PY
)"; then
  pass "load_yaml parses subset"
else
  fail "load_yaml parses subset"
  echo "$LOADER_OUT" | sed 's/^/    /'
fi

echo "=== merge skills replace-by-id ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import merge_workflows

base = {"version": 1, "skills": {"brainstorming": {"path": "/old"}}, "entries": {}, "transitions": []}
user = {"skills": {"brainstorming": {"skill": "alias-a"}}}
project = {"skills": {"brainstorming": {"path": "/proj"}}}
m1 = merge_workflows(base, user)
assert m1["skills"]["brainstorming"] == {"skill": "alias-a"}
m2 = merge_workflows(m1, project)
assert m2["skills"]["brainstorming"] == {"path": "/proj"}
m3 = merge_workflows(m2, {"skills": {"brainstorming": {}}})
assert m3["skills"]["brainstorming"] == {}
print("ok")
PY
then
  pass "skills replace-by-id"
else
  fail "skills replace-by-id"
fi

echo "=== merge transitions replace-by-from ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import merge_workflows

base = {
  "version": 1,
  "skills": {},
  "entries": {},
  "transitions": [
    {"from": "brainstorming", "on": "approved-architectural", "to": "writing-plans"},
    {"from": "brainstorming", "on": "approved-bounded", "to": None},
    {"from": "writing-plans", "on": "inline", "to": "executing-plans"},
  ],
}
overlay = {
  "transitions": [
    {"from": "brainstorming", "on": "approved-architectural", "to": "wait"},
    {"from": "brainstorming", "on": "approved-bounded", "to": None},
    {"from": "brainstorming", "on": "approved-spike", "to": None},
  ]
}
m = merge_workflows(base, overlay)
bs = [t for t in m["transitions"] if t["from"] == "brainstorming"]
assert len(bs) == 3
assert any(t["on"] == "approved-architectural" and t["to"] == "wait" for t in bs)
assert any(t["from"] == "writing-plans" for t in m["transitions"])
print("ok")
PY
then
  pass "transitions replace-by-from"
else
  fail "transitions replace-by-from"
fi

echo "=== default.yaml encodes core handoffs ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_yaml import load_yaml
doc = load_yaml((Path(sys.argv[1]) / "workflows" / "default.yaml").read_text())
pairs = {(t["from"], t["on"], t["to"]) for t in doc["transitions"]}
assert ("brainstorming", "approved-architectural", "writing-plans") in pairs
assert ("brainstorming", "approved-bounded", None) in pairs
assert ("brainstorming", "approved-spike", None) in pairs
assert ("writing-plans", "subagent-driven", "subagent-driven-development") in pairs
assert ("writing-plans", "inline", "executing-plans") in pairs
assert ("subagent-driven-development", "complete", "finishing-a-development-branch") in pairs
assert ("executing-plans", "complete", "finishing-a-development-branch") in pairs
print("ok")
PY
then
  pass "default handoffs"
else
  fail "default handoffs"
fi

echo "=== merge rejects transition missing from ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import WorkflowResolveError, merge_workflows

base = {"version": 1, "skills": {}, "entries": {}, "transitions": []}
overlay = {"transitions": [{"on": "approved-architectural", "to": "writing-plans"}]}
try:
    merge_workflows(base, overlay)
    raise SystemExit("expected WorkflowResolveError")
except WorkflowResolveError:
    pass
print("ok")
PY
then
  pass "merge rejects transition missing from"
else
  fail "merge rejects transition missing from"
fi

echo "=== CLI resolves bundled defaults ==="
if OUT="$(cd "$REPO_ROOT" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$REPO_ROOT" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["version"]==1; assert any(t["from"]=="brainstorming" and t["on"]=="approved-architectural" and t["to"]=="writing-plans" for t in d["transitions"])'; then
  pass "CLI resolves bundled defaults"
else
  fail "CLI resolves bundled defaults"
fi

echo "=== CLI project overlay wait ==="
PROJ="$TEST_ROOT/proj"
mkdir -p "$PROJ/.superpowers"
cat > "$PROJ/.superpowers/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
if OUT="$(cd "$PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]; assert t["to"]=="wait"'; then
  pass "CLI project overlay wait"
else
  fail "CLI project overlay wait"
fi

echo "=== CLI invalid config exits 1 ==="
mkdir -p "$PROJ/.superpowers"
echo 'version: "nope"' > "$PROJ/.superpowers/workflow.yaml"
if "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" >/dev/null 2>"$TEST_ROOT/err.txt"; then
  fail "invalid config should exit 1"
else
  pass "invalid config exits 1"
fi

echo "=== merge rejects null skills ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import WorkflowResolveError, merge_workflows

base = {"version": 1, "skills": {}, "entries": {}, "transitions": []}
try:
    merge_workflows(base, {"skills": None})
    raise SystemExit("expected WorkflowResolveError for null skills")
except WorkflowResolveError as exc:
    assert "skills must be a mapping" in str(exc)
try:
    merge_workflows(base, {"entries": ["not", "a", "map"]})
    raise SystemExit("expected WorkflowResolveError for list entries")
except WorkflowResolveError as exc:
    assert "entries must be a mapping" in str(exc)
print("ok")
PY
then
  pass "merge rejects null skills"
else
  fail "merge rejects null skills"
fi

echo "=== CLI rejects non-mapping overlay ==="
mkdir -p "$PROJ/.superpowers"
printf '%s\n' '- just-a-list' > "$PROJ/.superpowers/workflow.yaml"
if "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" >/dev/null 2>"$TEST_ROOT/err-nonmap.txt"; then
  fail "non-mapping overlay should exit 1"
else
  if grep -qi 'must be a mapping' "$TEST_ROOT/err-nonmap.txt"; then
    pass "CLI rejects non-mapping overlay"
  else
    fail "CLI rejects non-mapping overlay"
    sed 's/^/    /' "$TEST_ROOT/err-nonmap.txt"
  fi
fi

echo "=== CLI bundled-only ignores invalid overlay ==="
if OUT="$(cd "$PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" --bundled-only)" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["version"]==1; assert any(t["from"]=="brainstorming" and t["on"]=="approved-architectural" and t["to"]=="writing-plans" for t in d["transitions"])'; then
  pass "CLI bundled-only resolves defaults despite invalid overlay"
else
  fail "CLI bundled-only resolves defaults despite invalid overlay"
fi

echo "=== validate rejects transition missing to ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import validate_workflow

errors = validate_workflow(
    {
        "version": 1,
        "skills": {"brainstorming": {}, "writing-plans": {}},
        "entries": {},
        "transitions": [
            {"from": "brainstorming", "on": "approved-architectural"},
        ],
    },
    project_root=Path("."),
    bundled_skills={"brainstorming", "writing-plans"},
)
assert any("missing to" in e for e in errors), errors
print("ok")
PY
then
  pass "validate rejects transition missing to"
else
  fail "validate rejects transition missing to"
fi

echo "=== resolve wraps overlay OSError ==="
if python3 - "$REPO_ROOT" "$TEST_ROOT" <<'PY'
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import WorkflowResolveError, resolve_workflow

repo = Path(sys.argv[1])
home = Path(sys.argv[2]) / "oserror-home"
proj = Path(sys.argv[2]) / "oserror-proj"
home.mkdir(parents=True)
proj.mkdir(parents=True)
(user_dir := home / ".superpowers").mkdir()
user_path = user_dir / "workflow.yaml"
user_path.write_text("version: 1\n", encoding="utf-8")

real_read_text = Path.read_text

def flaky_read_text(self, *args, **kwargs):
    if self == user_path:
        raise PermissionError("simulated unreadable overlay")
    return real_read_text(self, *args, **kwargs)

with patch.object(Path, "read_text", flaky_read_text):
    try:
        resolve_workflow(plugin_root=repo, project_root=proj, user_home=home)
        raise SystemExit("expected WorkflowResolveError")
    except WorkflowResolveError as exc:
        assert "failed to read user workflow" in str(exc), exc
print("ok")
PY
then
  pass "resolve wraps overlay OSError"
else
  fail "resolve wraps overlay OSError"
fi

echo "=== CLI unreadable overlay exits cleanly ==="
mkdir -p "$PROJ/.superpowers"
echo 'version: 1' > "$PROJ/.superpowers/workflow.yaml"
chmod 000 "$PROJ/.superpowers/workflow.yaml"
set +e
"$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" >/dev/null 2>"$TEST_ROOT/err-unreadable.txt"
cli_status=$?
set -e
chmod 644 "$PROJ/.superpowers/workflow.yaml" || true
if grep -qi 'Traceback' "$TEST_ROOT/err-unreadable.txt"; then
  fail "unreadable overlay should not traceback"
  sed 's/^/    /' "$TEST_ROOT/err-unreadable.txt"
elif [[ "$cli_status" -ne 0 ]] && grep -qi 'failed to read project workflow' "$TEST_ROOT/err-unreadable.txt"; then
  pass "CLI unreadable overlay exits cleanly"
elif [[ "$cli_status" -eq 0 ]]; then
  pass "CLI unreadable overlay exits cleanly (overlay readable under this environment)"
else
  fail "CLI unreadable overlay exits cleanly"
  sed 's/^/    /' "$TEST_ROOT/err-unreadable.txt"
fi

echo "=== YAML nested mapping under sequence item ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_yaml import load_yaml
doc = load_yaml("""
transitions:
  - from: brainstorming
    on: approved-architectural
    to: ensure-worktree
    when:
      capabilities:
        - exec-hook
""")
t = doc["transitions"][0]
assert t["when"]["capabilities"] == ["exec-hook"]
print("ok")
PY
then
  pass "YAML nested mapping under sequence item"
else
  fail "YAML nested mapping under sequence item"
fi

echo "=== validate accepts run entry ==="
mkdir -p "$PROJ/scripts"
cat > "$PROJ/scripts/ensure-fixture.sh" <<'EOF'
#!/usr/bin/env bash
exit "${FIXTURE_EXIT:-0}"
EOF
chmod +x "$PROJ/scripts/ensure-fixture.sh"
cat > "$PROJ/.superpowers/workflow.yaml" <<'EOF'
version: 1
skills:
  ensure-fixture:
    run:
      argv:
        - scripts/ensure-fixture.sh
      allow:
        - project
      outcomes:
        0: complete
        nonzero: failed
transitions:
  - from: brainstorming
    on: approved-architectural
    to: ensure-fixture
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
  - from: ensure-fixture
    on: complete
    to: writing-plans
  - from: ensure-fixture
    on: failed
    to: wait
EOF
if OUT="$(cd "$PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); e=d["skills"]["ensure-fixture"]; assert "run" in e; assert e["run"]["argv"][0]=="scripts/ensure-fixture.sh"; assert e["run"]["outcomes"]["0"]=="complete"'; then
  pass "validate accepts run entry"
else
  fail "validate accepts run entry"
fi

echo "=== exec alias normalizes to run ==="
cat > "$PROJ/.superpowers/workflow.yaml" <<'EOF'
version: 1
skills:
  ensure-fixture:
    exec:
      argv:
        - scripts/ensure-fixture.sh
      allow:
        - project
EOF
if OUT="$(cd "$PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); e=d["skills"]["ensure-fixture"]; assert "run" in e and "exec" not in e'; then
  pass "exec alias normalizes to run"
else
  fail "exec alias normalizes to run"
fi

echo "=== reject run+path combination ==="
cat > "$PROJ/.superpowers/workflow.yaml" <<'EOF'
version: 1
skills:
  ensure-fixture:
    path: ./nope
    run:
      argv:
        - scripts/ensure-fixture.sh
EOF
if "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" >/dev/null 2>"$TEST_ROOT/err-run-path.txt"; then
  fail "reject run+path combination"
else
  if grep -qi 'cannot combine' "$TEST_ROOT/err-run-path.txt"; then
    pass "reject run+path combination"
  else
    fail "reject run+path combination"
    sed 's/^/    /' "$TEST_ROOT/err-run-path.txt"
  fi
fi

echo "=== reject escaped run program ==="
cat > "$PROJ/.superpowers/workflow.yaml" <<'EOF'
version: 1
skills:
  bad-run:
    run:
      argv:
        - /bin/true
      allow:
        - project
EOF
if "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" >/dev/null 2>"$TEST_ROOT/err-escape.txt"; then
  fail "reject escaped run program"
else
  if grep -qi 'not found under allow roots\|run program' "$TEST_ROOT/err-escape.txt"; then
    pass "reject escaped run program"
  else
    fail "reject escaped run program"
    sed 's/^/    /' "$TEST_ROOT/err-escape.txt"
  fi
fi

echo "=== default.yaml has no run actions ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_yaml import load_yaml
doc = load_yaml((Path(sys.argv[1]) / "workflows" / "default.yaml").read_text())
for skill_id, entry in (doc.get("skills") or {}).items():
    assert isinstance(entry, dict)
    assert "run" not in entry and "exec" not in entry, skill_id
print("ok")
PY
then
  pass "default.yaml has no run actions"
else
  fail "default.yaml has no run actions"
fi

echo "=== run-workflow-action complete/failed ==="
cat > "$PROJ/.superpowers/workflow.yaml" <<'EOF'
version: 1
skills:
  ensure-fixture:
    run:
      argv:
        - scripts/ensure-fixture.sh
      allow:
        - project
EOF
if OUT="$(cd "$PROJ" && FIXTURE_EXIT=0 "$REPO_ROOT/scripts/run-workflow-action" --id ensure-fixture --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["outcome"]=="complete"; assert d["exit_code"]==0'; then
  pass "run-workflow-action complete"
else
  fail "run-workflow-action complete"
fi
set +e
OUT="$(cd "$PROJ" && FIXTURE_EXIT=1 "$REPO_ROOT/scripts/run-workflow-action" --id ensure-fixture --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" 2>/dev/null)"
status=$?
set -e
if [[ "$status" -ne 0 ]] && echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["outcome"]=="failed"; assert d["exit_code"]==1'; then
  pass "run-workflow-action failed"
else
  fail "run-workflow-action failed"
  echo "$OUT" | sed 's/^/    /'
fi

echo "=== run-workflow-action rejects skill id ==="
if "$REPO_ROOT/scripts/run-workflow-action" --id brainstorming --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" >/dev/null 2>"$TEST_ROOT/err-not-run.txt"; then
  fail "run-workflow-action rejects skill id"
else
  if grep -qi 'not a run' "$TEST_ROOT/err-not-run.txt"; then
    pass "run-workflow-action rejects skill id"
  else
    fail "run-workflow-action rejects skill id"
    sed 's/^/    /' "$TEST_ROOT/err-not-run.txt"
  fi
fi

echo "=== run-workflow-action keeps JSON clean with noisy child ==="
cat > "$PROJ/scripts/noisy-fixture.sh" <<'EOF'
#!/usr/bin/env bash
echo "progress: starting"
echo "warning: chatter" >&2
exit 0
EOF
chmod +x "$PROJ/scripts/noisy-fixture.sh"
cat > "$PROJ/.superpowers/workflow.yaml" <<'EOF'
version: 1
skills:
  noisy-fixture:
    run:
      argv:
        - scripts/noisy-fixture.sh
      allow:
        - project
EOF
set +e
OUT="$(cd "$PROJ" && "$REPO_ROOT/scripts/run-workflow-action" --id noisy-fixture --plugin-root "$REPO_ROOT" --project-root "$PROJ" --user-home "$TEST_HOME" 2>"$TEST_ROOT/noisy-stderr.txt")"
status=$?
set -e
if [[ "$status" -eq 0 ]] &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["outcome"]=="complete"; assert d["exit_code"]==0' &&
  grep -q 'progress: starting' "$TEST_ROOT/noisy-stderr.txt" &&
  grep -q 'warning: chatter' "$TEST_ROOT/noisy-stderr.txt"; then
  pass "run-workflow-action keeps JSON clean with noisy child"
else
  fail "run-workflow-action keeps JSON clean with noisy child"
  echo "$OUT" | sed 's/^/    stdout: /'
  sed 's/^/    stderr: /' "$TEST_ROOT/noisy-stderr.txt"
fi

echo "=== CLI project .supersuit overlay wait ==="
CANON="$TEST_ROOT/canon-proj"
mkdir -p "$CANON/.supersuit"
cat > "$CANON/.supersuit/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
if OUT="$(cd "$CANON" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$CANON" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]; assert t["to"]=="wait"'; then
  pass "CLI project .supersuit overlay wait"
else
  fail "CLI project .supersuit overlay wait"
fi

echo "=== CLI prefers .supersuit over .superpowers ==="
BOTH="$TEST_ROOT/both-proj"
mkdir -p "$BOTH/.supersuit" "$BOTH/.superpowers"
cat > "$BOTH/.superpowers/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: writing-plans
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
cat > "$BOTH/.supersuit/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
if OUT="$(cd "$BOTH" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$BOTH" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]; assert t["to"]=="wait"'; then
  pass "CLI prefers .supersuit over .superpowers"
else
  fail "CLI prefers .supersuit over .superpowers"
fi

echo "=== CLI prefers user ~/.supersuit over ~/.superpowers ==="
USER_BOTH="$TEST_ROOT/user-both-home"
mkdir -p "$USER_BOTH/.supersuit" "$USER_BOTH/.superpowers"
cat > "$USER_BOTH/.superpowers/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: writing-plans
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
cat > "$USER_BOTH/.supersuit/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
EMPTY_PROJ="$TEST_ROOT/empty-for-user"
mkdir -p "$EMPTY_PROJ"
if OUT="$(cd "$EMPTY_PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$EMPTY_PROJ" --user-home "$USER_BOTH")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]; assert t["to"]=="wait"'; then
  pass "CLI prefers user ~/.supersuit over ~/.superpowers"
else
  fail "CLI prefers user ~/.supersuit over ~/.superpowers"
fi

echo "=== CLI still reads user ~/.superpowers fallback ==="
USER_LEGACY="$TEST_ROOT/user-legacy-home"
mkdir -p "$USER_LEGACY/.superpowers"
cat > "$USER_LEGACY/.superpowers/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
if OUT="$(cd "$EMPTY_PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$EMPTY_PROJ" --user-home "$USER_LEGACY")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]; assert t["to"]=="wait"'; then
  pass "CLI still reads user ~/.superpowers fallback"
else
  fail "CLI still reads user ~/.superpowers fallback"
fi

echo "=== default.yaml has no capability gates ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_yaml import load_yaml
doc = load_yaml((Path(sys.argv[1]) / "workflows" / "default.yaml").read_text())
for skill_id, entry in (doc.get("skills") or {}).items():
    assert isinstance(entry, dict)
    assert "when" not in entry, skill_id
for transition in doc.get("transitions") or []:
    assert "when" not in transition, transition
print("ok")
PY
then
  pass "default.yaml has no capability gates"
else
  fail "default.yaml has no capability gates"
fi

echo "=== gated overlay transitions append without replace-by-from ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import merge_workflows

base = {
  "version": 1,
  "skills": {},
  "entries": {},
  "transitions": [
    {"from": "brainstorming", "on": "approved-architectural", "to": "writing-plans"},
    {"from": "brainstorming", "on": "approved-bounded", "to": None},
  ],
}
overlay = {
  "transitions": [
    {
      "from": "brainstorming",
      "on": "approved-architectural",
      "to": "ensure-fixture",
      "when": {"capabilities": ["exec-hook"]},
    }
  ]
}
merged = merge_workflows(base, overlay)
froms = [t for t in merged["transitions"] if t["from"] == "brainstorming"]
assert len(froms) == 3, froms
assert any(t.get("when") for t in froms)
assert any(t["on"] == "approved-bounded" for t in froms)
assert any(
    t["on"] == "approved-architectural" and t["to"] == "writing-plans" and "when" not in t
    for t in froms
)
print("ok")
PY
then
  pass "gated overlay transitions append without replace-by-from"
else
  fail "gated overlay transitions append without replace-by-from"
fi

echo "=== capability match / miss / missing-capability-probe ==="
CAP_PROJ="$TEST_ROOT/cap-proj"
mkdir -p "$CAP_PROJ/scripts" "$CAP_PROJ/.supersuit"
cat > "$CAP_PROJ/scripts/ensure-fixture.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$CAP_PROJ/scripts/ensure-fixture.sh"
cat > "$CAP_PROJ/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  ensure-fixture:
    run:
      argv:
        - scripts/ensure-fixture.sh
      allow:
        - project
    when:
      capabilities:
        - exec-hook
transitions:
  - from: brainstorming
    on: approved-architectural
    to: ensure-fixture
    when:
      capabilities:
        - exec-hook
EOF

if OUT="$(cd "$CAP_PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$CAP_PROJ" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("capabilities") == []
t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]
assert t["to"]=="writing-plans"
assert "when" not in t
assert "ensure-fixture" not in d["skills"] or "run" not in d["skills"].get("ensure-fixture", {})
'; then
  pass "capability miss keeps baseline edge"
else
  fail "capability miss keeps baseline edge"
fi

if OUT="$(cd "$CAP_PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$CAP_PROJ" --user-home "$TEST_HOME" --capabilities exec-hook)" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert "exec-hook" in d["capabilities"]
t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]
assert t["to"]=="ensure-fixture"
assert "when" not in t
assert "run" in d["skills"]["ensure-fixture"]
assert "when" not in d["skills"]["ensure-fixture"]
'; then
  pass "capability match selects gated edge"
else
  fail "capability match selects gated edge"
fi

if OUT="$(cd "$CAP_PROJ" && env -u SUPERPOWERS_CAPABILITIES -u CURSOR_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u COPILOT_CLI "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$CAP_PROJ" --user-home "$TEST_HOME" --detect-capabilities)" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("capabilities") == []
for cap in ("native-worktree", "subagents", "exec-hook", "native-canvas", "session-inject"):
    assert cap not in d.get("capabilities", [])
t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]
assert t["to"]=="writing-plans"
'; then
  pass "missing-capability-probe keeps baseline"
else
  fail "missing-capability-probe keeps baseline"
fi

echo "=== detect-capabilities claims session-inject only from hook env ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import detect_capabilities

assert detect_capabilities({}) == []
assert detect_capabilities({"CURSOR_PLUGIN_ROOT": "/tmp"}) == ["session-inject"]
assert detect_capabilities({"CLAUDE_PLUGIN_ROOT": "/tmp"}) == ["session-inject"]
assert detect_capabilities({"COPILOT_CLI": "1"}) == ["session-inject"]
claimed = detect_capabilities({"CURSOR_PLUGIN_ROOT": "/tmp", "TERM": "xterm"})
assert claimed == ["session-inject"]
assert "native-canvas" not in claimed
assert "native-worktree" not in claimed
assert "subagents" not in claimed
assert "exec-hook" not in claimed
print("ok")
PY
then
  pass "detect-capabilities claims session-inject only from hook env"
else
  fail "detect-capabilities claims session-inject only from hook env"
fi

if OUT="$(cd "$CAP_PROJ" && CURSOR_PLUGIN_ROOT=/tmp "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$CAP_PROJ" --user-home "$TEST_HOME" --detect-capabilities --bundled-only)" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["capabilities"]==["session-inject"]'; then
  pass "CLI --detect-capabilities adds session-inject"
else
  fail "CLI --detect-capabilities adds session-inject"
fi

echo "=== SUPERPOWERS_CAPABILITIES env selects gated edge ==="
if OUT="$(cd "$CAP_PROJ" && SUPERPOWERS_CAPABILITIES=exec-hook "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$CAP_PROJ" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]; assert t["to"]=="ensure-fixture"'; then
  pass "SUPERPOWERS_CAPABILITIES env selects gated edge"
else
  fail "SUPERPOWERS_CAPABILITIES env selects gated edge"
fi

echo "=== gated skill keeps lower-layer remap when capability misses ==="
SKILL_PROJ="$TEST_ROOT/gated-skill-proj"
mkdir -p "$SKILL_PROJ/.supersuit" "$TEST_ROOT/gated-skill-home/.supersuit"
cat > "$TEST_ROOT/gated-skill-home/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  brainstorming:
    skill: my-brainstorm
EOF
cat > "$SKILL_PROJ/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  brainstorming:
    skill: canvas-brainstorm
    when:
      capabilities:
        - native-canvas
EOF
if OUT="$(cd "$SKILL_PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$SKILL_PROJ" --user-home "$TEST_ROOT/gated-skill-home")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["skills"]["brainstorming"]["skill"]=="my-brainstorm"'; then
  pass "gated skill miss keeps lower-layer remap"
else
  fail "gated skill miss keeps lower-layer remap"
fi
if OUT="$(cd "$SKILL_PROJ" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$SKILL_PROJ" --user-home "$TEST_ROOT/gated-skill-home" --capabilities native-canvas)" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["skills"]["brainstorming"]["skill"]=="canvas-brainstorm"; assert "when" not in d["skills"]["brainstorming"]'; then
  pass "gated skill match replaces remap"
else
  fail "gated skill match replaces remap"
fi

echo "=== ambiguous equally-specific transitions fail ==="
# Use tokens that are not also gated in bundled overlays (native-worktree is).
AMBIG="$TEST_ROOT/ambig-proj"
mkdir -p "$AMBIG/.supersuit"
cat > "$AMBIG/.supersuit/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
    when:
      capabilities:
        - exec-hook
  - from: brainstorming
    on: approved-architectural
    to: writing-plans
    when:
      capabilities:
        - subagents
EOF
if "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$AMBIG" --user-home "$TEST_HOME" --capabilities exec-hook,subagents >/dev/null 2>"$TEST_ROOT/err-ambig.txt"; then
  fail "ambiguous equally-specific transitions fail"
else
  if grep -qi 'ambiguous' "$TEST_ROOT/err-ambig.txt"; then
    pass "ambiguous equally-specific transitions fail"
  else
    fail "ambiguous equally-specific transitions fail"
    sed 's/^/    /' "$TEST_ROOT/err-ambig.txt"
  fi
fi

echo "=== two-call: resolve detect then run-workflow-action --id ==="
TWO_CALL="$TEST_ROOT/two-call-proj"
mkdir -p "$TWO_CALL/scripts" "$TWO_CALL/.supersuit"
cat > "$TWO_CALL/scripts/gated-only.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TWO_CALL/scripts/fallback.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TWO_CALL/scripts/gated.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TWO_CALL/scripts/gated-only.sh" "$TWO_CALL/scripts/fallback.sh" "$TWO_CALL/scripts/gated.sh"
cat > "$TWO_CALL/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  gated-only-run:
    run:
      argv:
        - scripts/gated-only.sh
      allow:
        - project
    when:
      capabilities:
        - session-inject
  dual-run:
    run:
      argv:
        - scripts/gated.sh
      allow:
        - project
    when:
      capabilities:
        - session-inject
transitions:
  - from: brainstorming
    on: approved-architectural
    to: gated-only-run
    when:
      capabilities:
        - session-inject
  - from: gated-only-run
    on: complete
    to: writing-plans
    when:
      capabilities:
        - session-inject
  - from: dual-run
    on: complete
    to: writing-plans
    when:
      capabilities:
        - session-inject
EOF
TWO_CALL_HOME="$TEST_ROOT/two-call-home"
mkdir -p "$TWO_CALL_HOME/.supersuit"
cat > "$TWO_CALL_HOME/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  dual-run:
    run:
      argv:
        - scripts/fallback.sh
      allow:
        - project
EOF

if OUT="$(cd "$TWO_CALL" && env -u SUPERPOWERS_CAPABILITIES CURSOR_PLUGIN_ROOT="$REPO_ROOT" "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$TWO_CALL" --user-home "$TWO_CALL_HOME" --detect-capabilities)" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "session-inject" in d["capabilities"]; assert "run" in d["skills"]["gated-only-run"]; assert d["skills"]["dual-run"]["run"]["argv"][0].endswith("gated.sh")'; then
  pass "two-call resolve with detect publishes gated run ids"
else
  fail "two-call resolve with detect publishes gated run ids"
fi

if OUT="$(cd "$TWO_CALL" && env -u SUPERPOWERS_CAPABILITIES CURSOR_PLUGIN_ROOT="$REPO_ROOT" "$REPO_ROOT/scripts/run-workflow-action" --id gated-only-run --plugin-root "$REPO_ROOT" --project-root "$TWO_CALL" --user-home "$TWO_CALL_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["outcome"]=="complete"; assert d["argv"][0].endswith("gated-only.sh")'; then
  pass "two-call gated-only --id executes gated script"
else
  fail "two-call gated-only --id executes gated script"
  echo "$OUT" | sed 's/^/    /'
fi

if OUT="$(cd "$TWO_CALL" && env -u SUPERPOWERS_CAPABILITIES CURSOR_PLUGIN_ROOT="$REPO_ROOT" "$REPO_ROOT/scripts/run-workflow-action" --id dual-run --plugin-root "$REPO_ROOT" --project-root "$TWO_CALL" --user-home "$TWO_CALL_HOME")" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["outcome"]=="complete"; path=d["argv"][0]; assert path.endswith("gated.sh"), path; assert not path.endswith("fallback.sh")'; then
  pass "two-call gated-with-fallback --id executes gated script"
else
  fail "two-call gated-with-fallback --id executes gated script"
  echo "$OUT" | sed 's/^/    /'
fi

echo "=== reject ungated transition to gated-only skill ==="
GATED_ONLY_TO="$TEST_ROOT/gated-only-to-proj"
mkdir -p "$GATED_ONLY_TO/scripts" "$GATED_ONLY_TO/.supersuit"
cat > "$GATED_ONLY_TO/scripts/ensure-fixture.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$GATED_ONLY_TO/scripts/ensure-fixture.sh"
cat > "$GATED_ONLY_TO/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  ensure-fixture:
    run:
      argv:
        - scripts/ensure-fixture.sh
      allow:
        - project
    when:
      capabilities:
        - exec-hook
transitions:
  - from: brainstorming
    on: approved-architectural
    to: ensure-fixture
EOF
if "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$GATED_ONLY_TO" --user-home "$TEST_HOME" --capabilities exec-hook >/dev/null 2>"$TEST_ROOT/err-gated-to.txt"; then
  fail "reject ungated transition to gated-only skill"
else
  if grep -qi 'same capability set' "$TEST_ROOT/err-gated-to.txt"; then
    pass "reject ungated transition to gated-only skill"
  else
    fail "reject ungated transition to gated-only skill"
    sed 's/^/    /' "$TEST_ROOT/err-gated-to.txt"
  fi
fi

echo "=== reject invalid when clause ==="
BAD_WHEN="$TEST_ROOT/bad-when-proj"
mkdir -p "$BAD_WHEN/.supersuit"
cat > "$BAD_WHEN/.supersuit/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
    when:
      harness: cursor
EOF
if "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$BAD_WHEN" --user-home "$TEST_HOME" >/dev/null 2>"$TEST_ROOT/err-when.txt"; then
  fail "reject invalid when clause"
else
  if grep -qi 'when' "$TEST_ROOT/err-when.txt"; then
    pass "reject invalid when clause"
  else
    fail "reject invalid when clause"
    sed 's/^/    /' "$TEST_ROOT/err-when.txt"
  fi
fi

echo "=== skill frontmatter marker helpers ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import (
    classify_skill_marker,
    extract_skill_frontmatter,
    skill_logical_id,
)

text = """---
name: my-review
description: Use when a human asks for a structured review.
metadata:
  supersuit:
    outcomes:
      - approved
      - changes-requested
      - approved
      - skip
---

# Body that must not be parsed
to: writing-plans
"""
fm = extract_skill_frontmatter(text)
assert fm["name"] == "my-review"
assert "Body" not in str(fm)
status, outcomes = classify_skill_marker(fm)
assert status == "ok"
assert outcomes == ["approved", "changes-requested", "skip"]
assert skill_logical_id(fm, Path("/tmp/review-changes")) == "my-review"

plain = extract_skill_frontmatter("---\nname: plain\n---\n")
assert classify_skill_marker(plain) == ("absent", None)
assert skill_logical_id(plain, Path("/tmp/plain")) == "plain"
assert skill_logical_id({"name": "  "}, Path("/tmp/dir-id")) == "dir-id"

empty_list = extract_skill_frontmatter(
    "---\nmetadata:\n  supersuit:\n    outcomes: []\n---\n"
)
assert classify_skill_marker(empty_list)[0] == "invalid"

not_map = extract_skill_frontmatter("---\nmetadata:\n  supersuit: yes\n---\n")
assert classify_skill_marker(not_map)[0] == "invalid"

missing_outcomes = extract_skill_frontmatter(
    "---\nmetadata:\n  supersuit:\n    extra: 1\n---\n"
)
assert classify_skill_marker(missing_outcomes)[0] == "invalid"

blank = extract_skill_frontmatter(
    "---\nmetadata:\n  supersuit:\n    outcomes:\n      - ok\n      - ''\n---\n"
)
assert classify_skill_marker(blank)[0] == "invalid"
print("ok")
PY
then
  pass "skill frontmatter marker helpers"
else
  fail "skill frontmatter marker helpers"
fi

echo "=== frontmatter block scalars keep valid outcomes ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import classify_skill_marker, extract_skill_frontmatter

literal = """---
name: block-review
description: |
  Use when a human asks for a structured review
  that spans more than one line.
metadata:
  supersuit:
    outcomes:
      - approved
      - skip
---
FOREIGN_BODY
"""
fm = extract_skill_frontmatter(literal)
assert fm is not None, "literal block description must parse"
assert fm["name"] == "block-review"
assert "structured review" in fm["description"]
status, outcomes = classify_skill_marker(fm)
assert status == "ok", status
assert outcomes == ["approved", "skip"]

folded = """---
name: folded-review
description: >-
  Use when a human asks for a structured review
  that spans more than one line.
metadata:
  supersuit:
    outcomes:
      - approved
---
FOREIGN_BODY
"""
fm = extract_skill_frontmatter(folded)
assert fm is not None, "folded description must parse"
assert fm["name"] == "folded-review"
status, outcomes = classify_skill_marker(fm)
assert status == "ok", status
assert outcomes == ["approved"]
print("ok")
PY
then
  pass "frontmatter block scalars keep valid outcomes"
else
  fail "frontmatter block scalars keep valid outcomes"
fi

echo "=== unreadable frontmatter with supersuit pocket warns ==="
if python3 - "$REPO_ROOT" "$TEST_ROOT" <<'PY'
import io
import sys
from contextlib import redirect_stderr
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import discover_skill_catalog

base = Path(sys.argv[2]) / "frontmatter-parse"
plugin = base / "plugin"
project = base / "proj"
home = base / "home"
pack = base / "pack"
(plugin / "skills").mkdir(parents=True)
project.mkdir(parents=True)
home.mkdir(parents=True)

broken = pack / "broken-tab"
broken.mkdir(parents=True)
(broken / "SKILL.md").write_text(
    "---\nname: broken-tab\ndescription: x\nmetadata:\n\tsupersuit:\n"
    "    outcomes:\n      - approved\n---\nbody\n",
    encoding="utf-8",
)
plain_broken = pack / "plain-broken"
plain_broken.mkdir(parents=True)
(plain_broken / "SKILL.md").write_text(
    "---\nname: plain-broken\ndescription: \"unclosed\n---\nbody\n",
    encoding="utf-8",
)

err = io.StringIO()
with redirect_stderr(err):
    catalog = discover_skill_catalog(
        plugin_root=plugin,
        project_root=project,
        user_home=home,
        environ={"SUPERSUIT_SKILL_PATH": str(pack)},
    )
stderr = err.getvalue()
assert "broken-tab" not in catalog
assert "plain-broken" not in catalog
assert "invalid metadata.supersuit.outcomes" in stderr
assert "broken-tab" in stderr
assert "plain-broken" not in stderr
print("ok")
PY
then
  pass "unreadable frontmatter with supersuit pocket warns"
else
  fail "unreadable frontmatter with supersuit pocket warns"
fi

echo "=== skill catalog discovery order ==="
if python3 - "$REPO_ROOT" "$TEST_ROOT" <<'PY'
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import discover_skill_catalog

base = Path(sys.argv[2]) / "catalog-disc"
plugin = base / "plugin"
project = base / "proj"
home = base / "home"
pack_a = base / "pack-a"
pack_b = base / "pack-b"
proj_skills = project / "skills" / "shadowed"
dot_supersuit = project / ".supersuit" / "skills" / "leaked"

def write_skill(root, dirname, name, outcomes, body="BODY"):
    skill_dir = root / dirname
    skill_dir.mkdir(parents=True, exist_ok=True)
    lines = ["---", f"name: {name}", "metadata:", "  supersuit:", "    outcomes:"]
    for item in outcomes:
        lines.append(f"      - {item}")
    lines.extend(["---", "", body, ""])
    (skill_dir / "SKILL.md").write_text("\n".join(lines), encoding="utf-8")
    return skill_dir

(plugin / "skills").mkdir(parents=True)
write_skill(plugin / "skills", "bundled-marked", "bundled-marked", ["done"])
write_skill(pack_a, "review-changes", "my-review", ["approved", "skip"], body="FOREIGN_BODY_PACK_A")
write_skill(pack_b, "review-changes", "my-review", ["later"], body="FOREIGN_BODY_PACK_B")
write_skill(project / ".agents" / "skills", "agents-skill", "agents-skill", ["from-agents"])
write_skill(project / ".opencode" / "skills", "oc-skill", "oc-skill", ["from-oc"])
write_skill(home / ".agents" / "skills", "user-agents", "user-agents", ["from-user"])
write_skill(proj_skills.parent, "shadowed", "shadowed", ["from-project-skills"])
write_skill(dot_supersuit.parent, "leaked", "leaked", ["from-dot-supersuit"])
plain = project / ".claude" / "skills" / "plain"
plain.mkdir(parents=True)
(plain / "SKILL.md").write_text("---\nname: plain\n---\n# no marker\n", encoding="utf-8")

catalog = discover_skill_catalog(
    plugin_root=plugin,
    project_root=project,
    user_home=home,
    environ={
        "SUPERSUIT_SKILL_PATH": os.pathsep.join([str(pack_a), str(pack_b)]),
    },
)
assert "bundled-marked" in catalog
assert catalog["my-review"]["outcomes"] == ["approved", "skip"]
assert Path(catalog["my-review"]["path"]) == pack_a / "review-changes"
assert "agents-skill" in catalog
assert "oc-skill" in catalog
assert "user-agents" in catalog
assert "plain" not in catalog
assert "shadowed" not in catalog
assert "leaked" not in catalog

listed = discover_skill_catalog(
    plugin_root=plugin,
    project_root=project,
    user_home=home,
    environ={"SUPERSUIT_SKILL_PATH": str(project / "skills")},
)
assert listed["shadowed"]["outcomes"] == ["from-project-skills"]

single = base / "single-skill"
single.mkdir(parents=True)
(single / "SKILL.md").write_text(
    "---\nname: solo\nmetadata:\n  supersuit:\n    outcomes:\n      - only\n---\n",
    encoding="utf-8",
)
solo = discover_skill_catalog(
    plugin_root=plugin,
    project_root=project,
    user_home=home,
    environ={"SUPERSUIT_SKILL_PATH": str(single)},
)
assert solo["solo"]["outcomes"] == ["only"]
assert Path(solo["solo"]["path"]) == single.resolve()
print("ok")
PY
then
  pass "skill catalog discovery order"
else
  fail "skill catalog discovery order"
fi

echo "=== resolve catalogs opted-in skills ==="
CAT_PROJ="$TEST_ROOT/resolve-cat-proj"
CAT_HOME="$TEST_ROOT/resolve-cat-home"
CAT_PACK="$TEST_ROOT/resolve-cat-pack"
mkdir -p "$CAT_PROJ" "$CAT_HOME" "$CAT_PACK/my-review" \
  "$CAT_PROJ/skills/ignored" "$CAT_PROJ/.supersuit/skills/leaked" \
  "$CAT_PROJ/.agents/skills/from-agents"
cat > "$CAT_PACK/my-review/SKILL.md" <<'EOF'
---
name: my-review
metadata:
  supersuit:
    outcomes:
      - approved
      - changes-requested
---
FOREIGN_BODY_MUST_NOT_LEAK
EOF
cat > "$CAT_PROJ/.agents/skills/from-agents/SKILL.md" <<'EOF'
---
name: from-agents
metadata:
  supersuit:
    outcomes:
      - done
---
agents body
EOF
cat > "$CAT_PROJ/skills/ignored/SKILL.md" <<'EOF'
---
name: ignored
metadata:
  supersuit:
    outcomes:
      - nope
---
project-root skills body
EOF
cat > "$CAT_PROJ/.supersuit/skills/leaked/SKILL.md" <<'EOF'
---
name: leaked
metadata:
  supersuit:
    outcomes:
      - nope
---
dot supersuit skills body
EOF
mkdir -p "$CAT_PROJ/.supersuit"
cat > "$CAT_PROJ/.supersuit/workflow.yaml" <<'EOF'
version: 1
transitions:
  - from: brainstorming
    on: approved-architectural
    to: my-review
  - from: brainstorming
    on: approved-bounded
    to: null
  - from: brainstorming
    on: approved-spike
    to: null
EOF
if OUT="$(cd "$CAT_PROJ" && SUPERSUIT_SKILL_PATH="$CAT_PACK" \
  "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" \
  --project-root "$CAT_PROJ" --user-home "$CAT_HOME")" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
e=d["skills"]["my-review"]
assert e["outcomes"]==["approved","changes-requested"]
assert e["path"].endswith("my-review")
assert "ignored" not in d["skills"]
assert "leaked" not in d["skills"]
assert d["skills"]["from-agents"]["outcomes"]==["done"]
t=[x for x in d["transitions"] if x["from"]=="brainstorming" and x["on"]=="approved-architectural"][0]
assert t["to"]=="my-review"
assert "run" not in d["skills"]["brainstorming"]
'; then
  pass "resolve catalogs opted-in skills"
else
  fail "resolve catalogs opted-in skills"
fi

echo "=== resolve catalogs skill with multiline description ==="
ML_PROJ="$TEST_ROOT/multiline-proj"
ML_HOME="$TEST_ROOT/multiline-home"
ML_PACK="$TEST_ROOT/multiline-pack"
mkdir -p "$ML_PROJ" "$ML_HOME" "$ML_PACK/block-review"
cat > "$ML_PACK/block-review/SKILL.md" <<'EOF'
---
name: block-review
description: |
  Use when a human asks for a structured review
  that spans more than one line.
metadata:
  supersuit:
    outcomes:
      - approved
      - changes-requested
---
MULTILINE_FOREIGN_BODY
EOF
if OUT="$(cd "$ML_PROJ" && SUPERSUIT_SKILL_PATH="$ML_PACK" \
  "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" \
  --project-root "$ML_PROJ" --user-home "$ML_HOME")" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
e=d["skills"]["block-review"]
assert e["outcomes"]==["approved","changes-requested"]
assert e["path"].endswith("block-review")
'; then
  pass "resolve catalogs skill with multiline description"
else
  fail "resolve catalogs skill with multiline description"
fi

echo "=== invalid marker warns and resolve continues ==="
BAD="$TEST_ROOT/invalid-marker-proj"
BAD_HOME="$TEST_ROOT/invalid-marker-home"
mkdir -p "$BAD/.claude/skills/broken" "$BAD_HOME"
cat > "$BAD/.claude/skills/broken/SKILL.md" <<'EOF'
---
name: broken
metadata:
  supersuit:
    outcomes: []
---
broken body
EOF
set +e
OUT="$(cd "$BAD" && "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" \
  --project-root "$BAD" --user-home "$BAD_HOME" 2>"$TEST_ROOT/invalid-marker.err")"
status=$?
set -e
if [[ "$status" -eq 0 ]] &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["version"]==1; assert "broken" not in d["skills"]' &&
  grep -qi 'invalid metadata.supersuit.outcomes' "$TEST_ROOT/invalid-marker.err"; then
  pass "invalid marker warns and resolve continues"
else
  fail "invalid marker warns and resolve continues"
  echo "$OUT" | sed 's/^/    /'
  sed 's/^/    /' "$TEST_ROOT/invalid-marker.err"
fi

echo "=== overlay skill alias attaches cataloged outcomes ==="
ALIAS_PROJ="$TEST_ROOT/alias-proj"
ALIAS_HOME="$TEST_ROOT/alias-home"
ALIAS_PACK="$TEST_ROOT/alias-pack"
mkdir -p "$ALIAS_PROJ/.supersuit" "$ALIAS_HOME" \
  "$ALIAS_PACK/other-name" "$ALIAS_PACK/bare-alias"
cat > "$ALIAS_PACK/other-name/SKILL.md" <<'EOF'
---
name: other-name
metadata:
  supersuit:
    outcomes:
      - approved
      - skip
---
aliased body
EOF
cat > "$ALIAS_PACK/bare-alias/SKILL.md" <<'EOF'
---
name: bare-alias
---
no marker
EOF
cat > "$ALIAS_PROJ/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  review:
    skill: other-name
  missing-alias:
    skill: not-cataloged
  bare:
    skill: bare-alias
EOF
if OUT="$(cd "$ALIAS_PROJ" && SUPERSUIT_SKILL_PATH="$ALIAS_PACK" \
  "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" \
  --project-root "$ALIAS_PROJ" --user-home "$ALIAS_HOME")" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["skills"]["review"]["skill"]=="other-name"
assert d["skills"]["review"]["outcomes"]==["approved","skip"]
assert "outcomes" not in d["skills"]["missing-alias"]
assert "outcomes" not in d["skills"]["bare"]
'; then
  pass "overlay skill alias attaches cataloged outcomes"
else
  fail "overlay skill alias attaches cataloged outcomes"
fi

echo "=== overlay path wins for outcomes SKILL.md ==="
PATH_PROJ="$TEST_ROOT/path-win-proj"
PATH_HOME="$TEST_ROOT/path-win-home"
PATH_PACK="$TEST_ROOT/path-win-pack"
PATH_CUSTOM="$TEST_ROOT/path-win-custom/custom-review"
mkdir -p "$PATH_PROJ/.supersuit" "$PATH_HOME" "$PATH_PACK/my-review" "$PATH_CUSTOM"
cat > "$PATH_PACK/my-review/SKILL.md" <<'EOF'
---
name: my-review
metadata:
  supersuit:
    outcomes:
      - first-seen
---
pack body
EOF
cat > "$PATH_CUSTOM/SKILL.md" <<'EOF'
---
name: my-review
metadata:
  supersuit:
    outcomes:
      - from-path
---
custom body
EOF
cat > "$PATH_PROJ/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  my-review:
    path: ../path-win-custom/custom-review
EOF
if OUT="$(cd "$PATH_PROJ" && SUPERSUIT_SKILL_PATH="$PATH_PACK" \
  "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" \
  --project-root "$PATH_PROJ" --user-home "$PATH_HOME")" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["skills"]["my-review"]["outcomes"]==["from-path"]
assert "first-seen" not in d["skills"]["my-review"]["outcomes"]
'; then
  pass "overlay path wins for outcomes SKILL.md"
else
  fail "overlay path wins for outcomes SKILL.md"
fi

echo "=== run entries do not get skill-frontmatter outcomes ==="
mkdir -p "$PROJ/scripts" "$PROJ/.supersuit"
cat > "$PROJ/scripts/ensure-fixture.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$PROJ/scripts/ensure-fixture.sh"
mkdir -p "$TEST_ROOT/run-pack/ensure-fixture"
cat > "$TEST_ROOT/run-pack/ensure-fixture/SKILL.md" <<'EOF'
---
name: ensure-fixture
metadata:
  supersuit:
    outcomes:
      - approved
---
should not attach
EOF
cat > "$PROJ/.supersuit/workflow.yaml" <<'EOF'
version: 1
skills:
  ensure-fixture:
    run:
      argv:
        - scripts/ensure-fixture.sh
      allow:
        - project
EOF
if OUT="$(cd "$PROJ" && SUPERSUIT_SKILL_PATH="$TEST_ROOT/run-pack" \
  "$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" \
  --project-root "$PROJ" --user-home "$TEST_HOME")" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
e=d["skills"]["ensure-fixture"]
assert "run" in e
assert e.get("outcomes") != ["approved"]
assert e["run"]["outcomes"]["0"]=="complete"
'; then
  pass "run entries do not get skill-frontmatter outcomes"
else
  fail "run entries do not get skill-frontmatter outcomes"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "FAILED: $FAILURES"
  exit 1
fi
echo "All workflow tests passed"
exit 0
