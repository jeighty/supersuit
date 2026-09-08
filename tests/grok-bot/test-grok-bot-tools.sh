#!/usr/bin/env bash
# Grok Bot harness ref: action map + Platform Adaptation pointer.
# CI-safe: does not require a Grok Bot session. Mirrors tests/antigravity/test-antigravity-tools.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MAPPING="$REPO_ROOT/skills/using-superpowers/references/grok-bot-tools.md"
SKILL="$REPO_ROOT/skills/using-superpowers/SKILL.md"
DETECT="$REPO_ROOT/scripts/lib/workflow_resolve.py"
ENSURE="$REPO_ROOT/scripts/ensure-worktree"
DOCS="$REPO_ROOT/docs/workflow-config.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "test-grok-bot-tools: checking Grok Bot harness ref"

[ -f "$MAPPING" ] || fail "harness ref missing at $MAPPING"

# Required outline sections from the design spec
for heading in '## Capabilities' '## Action map' '## Workspace' '## Spawn' '## Finishing' '## Profile' '## SessionStart'; do
  grep -q "^${heading}$" "$MAPPING" \
    || fail "harness ref missing heading: $heading"
done

# Known Grok Bot primitives (trust live tool lists over invented names)
for tool in '`Task`' '`CloudAgent`' '`Shell`' '`Read`'; do
  grep -q "$tool" "$MAPPING" \
    || fail "harness ref does not name the '$tool' primitive"
done

# Spawn / workspace contracts
grep -q 'task_tool && skills_loadable' "$MAPPING" \
  || fail "harness ref missing Task-nest fact"
grep -q 'ensure-worktree' "$MAPPING" \
  || fail "harness ref missing ensure-worktree handshake"
grep -q 'git worktree add' "$MAPPING" \
  || fail "harness ref must forbid git worktree add"
grep -q 'session-inject' "$MAPPING" \
  || fail "harness ref missing session-inject advertise"
grep -q 'native-worktree' "$MAPPING" \
  || fail "harness ref missing native-worktree"
grep -q 'subagents' "$MAPPING" \
  || fail "harness ref missing subagents meaning"
grep -q 'plugin id `supersuit`' "$MAPPING" \
  || fail "harness ref missing plugin id supersuit"
grep -q 'WORKFLOW_MAP' "$MAPPING" \
  || fail "harness ref missing WORKFLOW_MAP inject"

# RED: never infer tokens from product/tier words
grep -qE 'Do not infer|never infer|Never infer' "$MAPPING" \
  || fail "harness ref must forbid product/tier inference"

# Platform Adaptation pointer list only
grep -q 'Grok Bot: `references/grok-bot-tools.md`' "$SKILL" \
  || fail "SKILL.md Platform Adaptation does not list Grok Bot pointer"

# Detect must not grow product-name probes
if grep -E '\b(GROK|GROK_BOT|XAI)\b' "$DETECT"; then
  fail "detect_capabilities source contains product-name tokens GROK/GROK_BOT/XAI"
fi

# Handshake stays host-agnostic; the ref names CloudAgent as this host's workspace
if grep -F 'CloudAgent' "$ENSURE"; then
  fail "ensure-worktree must not hardcode CloudAgent"
fi
grep -q 'host-owned CloudAgent workspace' "$MAPPING" \
  || fail "harness ref must treat handshake complete as host-owned CloudAgent workspace"
grep -q 'Do not invent `git worktree add` after the `native-worktree` remap' "$MAPPING" \
  || fail "harness ref must forbid inventing git worktree add after native-worktree remap"

# Pack / cloud-seat are review-family only — not a general SDD pack menu
grep -q 'review-family only' "$MAPPING" \
  || fail "Pack row must be scoped to review-family only"
grep -q 'When running the review family' "$MAPPING" \
  || fail "cloud-seat must be scoped to the review family"
grep -qE 'thinner set / thinner review pack|thinner review pack' "$MAPPING" \
  || fail "partial-return must not name a general SDD pack menu"
if grep -qE '\| Pack \| Caller-named' "$MAPPING"; then
  fail "Pack row is unscoped (SDD would hunt a pack menu)"
fi

# workflow-config links the design spec and tightens subagents
grep -q '2026-09-08-grok-bot-harness-design.md' "$DOCS" \
  || fail "workflow-config.md does not link the Grok Bot design spec"
grep -q 'task_tool && skills_loadable' "$DOCS" \
  || fail "workflow-config.md subagents row missing Task-nest fact"

echo "PASS: Grok Bot harness ref, pointer, detect, and docs contracts"
