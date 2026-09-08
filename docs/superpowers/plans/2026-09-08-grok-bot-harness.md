# Grok Bot Harness Ref Implementation Plan

> **For agentic workers:** After plan save, emit workflow outcomes `subagent-driven` or `inline` per human choice; do not hard-code the next skill. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Supersuit runnable on Grok Bot desktop agents by shipping a harness ref that binds spawn / workspace / bootstrap to existing capability tokens (`session-inject`, `native-worktree`, `subagents`) plus a Platform Adaptation pointer — no new harness-named capability.

**Architecture:** Skills keep naming actions. This cut adds `skills/using-superpowers/references/grok-bot-tools.md` (action → Grok Bot primitive), one Platform Adaptation bullet, and `docs/workflow-config.md` token-meaning / advertise-example updates. Bundled `native-worktree.yaml` + `scripts/ensure-worktree` already implement the handshake; do not hardcode `CloudAgent` into that script. Detect stays conservative: no product-name env (`GROK`, `GROK_BOT`, `XAI`). Advertise via `SUPERPOWERS_CAPABILITIES` / `--capabilities`.

**Tech Stack:** Markdown harness ref + docs; Bash tests matching `tests/antigravity/test-antigravity-tools.sh` and `tests/workflow/`; existing Python `detect_capabilities`.

**Spec:** `docs/superpowers/specs/2026-09-08-grok-bot-harness-design.md`

## Global Constraints

- **No new capability noun** named after this harness (no `grok-bot` token; overlays already reject `when.harness`).
- **Do not rewrite Superpowers skill bodies** except one Platform Adaptation pointer line in `skills/using-superpowers/SKILL.md`.
- **Never infer tokens or spawn/pack from product/tier words** (“Grok”, “Grok Bot”, “Medium”, “cloud”, “quick”, “light”, “small”).
- **Do not hardcode `CloudAgent` into `scripts/ensure-worktree`** — it stays host-agnostic; the harness ref names CloudAgent as this host’s workspace primitive.
- **Do not advertise `exec-hook` or `native-canvas`** for this host in this cut.
- **Out of scope:** PROFILE/SEED, marketplace version bump, GREEN/RED eval fixtures, rewriting brainstorming/SDD/worktrees/finishing skill bodies, extracting a supersuit-superpowers pack, live “Let's make a react todo list” transcript (acceptance test is a later eval cut).
- **Craft/AR residuals:** Task-nest fact is `task_tool && skills_loadable`; Task present without `subagents` → CloudAgent fan-or-stop (never nest into unloadable children); no product-name inference.
- **Zero third-party runtime dependencies.**
- **Base branch:** feature branch off `dev`; PR targets `dev`.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `docs/superpowers/plans/2026-09-08-grok-bot-harness.md` | This plan |
| `skills/using-superpowers/references/grok-bot-tools.md` | Action → Grok Bot primitive; capabilities / workspace / spawn / finishing / profile / SessionStart |
| `skills/using-superpowers/SKILL.md` | One Platform Adaptation bullet only |
| `docs/workflow-config.md` | Link design spec; tighten `subagents` row; optional CloudAgent-workspace advertise example |
| `tests/grok-bot/test-grok-bot-tools.sh` | Ref exists, required sections/tools, Platform Adaptation pointer, no product-name detect |
| `tests/workflow/test-native-worktree.sh` | Combined `session-inject,native-worktree` still remaps handshake; `ensure-worktree` has no `CloudAgent` |
| `tests/workflow/test-resolve-workflow.sh` | `detect_capabilities` ignores `GROK` / `GROK_BOT` / `XAI` |
| `.github/workflows/plugin-tests.yml` | Run the new grok-bot mapping test in CI |

No resolver, overlay YAML, or `detect_capabilities` source change unless a real SessionStart-like hook-presence env of the same class as `CURSOR_PLUGIN_ROOT` is found. None is known; leave detect unchanged.

---

### Task 1: Failing tests (ref, pointer, detect, handshake remap)

**Files:**
- Create: `tests/grok-bot/test-grok-bot-tools.sh`
- Modify: `tests/workflow/test-native-worktree.sh` (append combined-capabilities + no-CloudAgent-in-script cases)
- Modify: `tests/workflow/test-resolve-workflow.sh` (extend detect-capabilities assertions)
- Modify: `.github/workflows/plugin-tests.yml`

**Interfaces:**
- Consumes: existing `detect_capabilities(environ) -> list[str]`; `scripts/resolve-workflow --capabilities`; `scripts/ensure-worktree`
- Produces: failing tests that name the files/behaviors Task 2–4 must create

- [ ] **Step 1: Write the harness-ref mapping test**

Create `tests/grok-bot/test-grok-bot-tools.sh`:

```bash
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

# Handshake stays host-agnostic
if grep -F 'CloudAgent' "$ENSURE"; then
  fail "ensure-worktree must not hardcode CloudAgent"
fi

# workflow-config links the design spec and tightens subagents
grep -q '2026-09-08-grok-bot-harness-design.md' "$DOCS" \
  || fail "workflow-config.md does not link the Grok Bot design spec"
grep -q 'task_tool && skills_loadable' "$DOCS" \
  || fail "workflow-config.md subagents row missing Task-nest fact"

echo "PASS: Grok Bot harness ref, pointer, detect, and docs contracts"
```

chmod +x that file.

- [ ] **Step 2: Extend native-worktree tests for the CloudAgent-workspace pair**

Append to `tests/workflow/test-native-worktree.sh` **before** the `FAILURES` summary (before `if [[ "$FAILURES" -gt 0 ]]`):

```bash
echo "=== session-inject,native-worktree remaps worktree handshake ==="
if OUT="$(cd "$REPO_ROOT" && env -u SUPERPOWERS_CAPABILITIES -u CURSOR_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u COPILOT_CLI \
  "${RESOLVE[@]}" --project-root "$REPO_ROOT" --user-home "$TEST_HOME" \
  --capabilities session-inject,native-worktree --bundled-only)"; then
  write_json "$OUT"
  if python3 - "$JSON_FILE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert "session-inject" in d["capabilities"]
assert "native-worktree" in d["capabilities"]
assert "subagents" not in d["capabilities"]
assert "run" in d["skills"]["ensure-worktree"]
assert d["skills"]["ensure-worktree"]["run"]["argv"][0].endswith("ensure-worktree")
assert "run" in d["skills"]["using-git-worktrees"]
assert d["skills"]["using-git-worktrees"]["run"]["argv"][0].endswith("ensure-worktree")
arch = [x for x in d["transitions"] if x["from"] == "brainstorming" and x["on"] == "approved-architectural"][0]
assert arch["to"] == "ensure-worktree", arch
PY
  then
    pass "session-inject,native-worktree remaps worktree handshake"
  else
    fail "session-inject,native-worktree remaps worktree handshake"
  fi
else
  fail "session-inject,native-worktree remaps worktree handshake"
fi

echo "=== ensure-worktree source is host-agnostic (no CloudAgent) ==="
if grep -F 'CloudAgent' "$REPO_ROOT/scripts/ensure-worktree"; then
  fail "ensure-worktree source hardcodes CloudAgent"
else
  pass "ensure-worktree source has no CloudAgent"
fi
```

- [ ] **Step 3: Extend detect tests — product-name env is not a capability**

In `tests/workflow/test-resolve-workflow.sh`, inside the existing `detect-capabilities claims session-inject only from hook env` Python block (after the `COPILOT_CLI` assertion), add:

```python
assert detect_capabilities({"GROK": "1"}) == []
assert detect_capabilities({"GROK_BOT": "1"}) == []
assert detect_capabilities({"XAI": "1"}) == []
assert detect_capabilities({"GROK": "1", "GROK_BOT": "yes", "XAI": "true"}) == []
src = Path(sys.argv[1], "scripts", "lib", "workflow_resolve.py").read_text()
for token in ("GROK", "GROK_BOT", "XAI"):
    assert token not in src, token
```

- [ ] **Step 4: Wire the mapping test into CI**

In `.github/workflows/plugin-tests.yml`, after the native-worktree line, add:

```yaml
          /bin/bash tests/grok-bot/test-grok-bot-tools.sh
```

- [ ] **Step 5: Run tests — expect failure**

Run:

```bash
bash tests/grok-bot/test-grok-bot-tools.sh
```

Expected: FAIL `harness ref missing at .../grok-bot-tools.md`

Run:

```bash
bash tests/workflow/test-native-worktree.sh
```

Expected: PASS on existing cases; the new combined-capabilities case should PASS already (resolver already remaps). The no-CloudAgent case should PASS (script is already host-agnostic). If either fails, stop — the handshake is not the shipped contract.

Run:

```bash
bash tests/workflow/test-resolve-workflow.sh
```

Expected: PASS on the new GROK/GROK_BOT/XAI assertions (detect is already product-name-free). If they fail, stop and do not add product-name probes.

- [ ] **Step 6: Commit the failing mapping test + passing detect/handshake extensions**

```bash
git add tests/grok-bot/test-grok-bot-tools.sh tests/workflow/test-native-worktree.sh tests/workflow/test-resolve-workflow.sh .github/workflows/plugin-tests.yml
git commit -m "test: Grok Bot harness ref contracts and product-name detect"
```

---

### Task 2: Harness ref `grok-bot-tools.md`

**Files:**
- Create: `skills/using-superpowers/references/grok-bot-tools.md`

**Interfaces:**
- Consumes: spec “Bootstrap ref outline”, RED cases, capability table, spawn-seat facts; known primitives `Task`, `CloudAgent`, `Shell`, `Read`
- Produces: locked-path ref covering Capabilities / Action map / Workspace / Spawn / Finishing / Profile / SessionStart

- [ ] **Step 1: Confirm no SessionStart-like hook env on this host**

Search `scripts/lib/workflow_resolve.py` `detect_capabilities` and this repo for a Grok Bot hook-presence env of the same class as `CURSOR_PLUGIN_ROOT` / `CLAUDE_PLUGIN_ROOT` / `COPILOT_CLI`. Do **not** treat `GROK`, `GROK_BOT`, or `XAI` as that class.

If none exists: leave `detect_capabilities` unchanged. Document advertise-via-env (`SUPERPOWERS_CAPABILITIES` / `--capabilities`) as the path in the Capabilities section.

- [ ] **Step 2: Write the harness ref**

Create `skills/using-superpowers/references/grok-bot-tools.md` with exactly these `##` headings (tests grep them): `Capabilities`, `Action map`, `Workspace`, `Spawn`, `Finishing`, `Profile`, `SessionStart`.

Required content (do not invent a `grok-bot` capability; do not invent tool names beyond the known set; tell the agent to trust the live tool list):

```markdown
# Grok Bot Tool Mapping

Skills speak in actions ("dispatch a subagent", "read a file", "ensure a worktree").
On Grok Bot desktop agents these resolve to the primitives below. Trust the
**live tool list** over this table — including this file — when they disagree.
Do not invent a capability token named after this harness.

## Capabilities

Advertise existing overlay tokens. Never infer tokens from product or tier
words ("Grok", "Grok Bot", "Medium", "cloud", "quick", "light", "small").

| Token | Meaning on this host | How it becomes active |
|-------|----------------------|------------------------|
| `session-inject` | Host injects `using-superpowers` + `WORKFLOW_MAP` every session. | Advertise. Conservative detect only from SessionStart-like hook-presence env (`CURSOR_PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`, `COPILOT_CLI`). This host has no such env yet — do not detect from `GROK` / `GROK_BOT` / `XAI`. |
| `native-worktree` | Host owns workspace creation. On this host that primitive is a CloudAgent branch / PR, with `ensure-worktree` / `using-git-worktrees` remapped to the handshake. | Advertise explicitly. CloudAgent **tip** access without the handshake is not this token. |
| `subagents` | Task-nest fact is true: `task_tool && skills_loadable`. | Advertise only after that probe. A `Task` tool whose children cannot load skills is **not** this token. |
| `exec-hook` / `native-canvas` | Unchanged. Do not advertise for this host in this cut. | Do not infer from any product name. |

Preferred advertise (typical CloudAgent-workspace profile):

```bash
export SUPERPOWERS_CAPABILITIES=session-inject,native-worktree
# add ,subagents only when the Task-nest fact is true

./scripts/resolve-workflow --plugin-root "$PWD" --project-root "$PWD" \
  --user-home "$HOME" --capabilities session-inject,native-worktree --pretty
```

Active set is detect ∪ `SUPERPOWERS_CAPABILITIES` ∪ `--capabilities` (first-seen).
Forward the resolved map’s `capabilities` into `run-workflow-action --id`.

## Action map

| Skill action | Grok Bot primitive |
|--------------|--------------------|
| Read a file | `Read` on the box (no local repo clone) |
| Write / edit a file | `Write` / `Read`+`Write` on the box if present in the live list; never clone the repo onto the box to edit |
| Run a shell command | `Shell` on the box |
| Dispatch a subagent (Task-nest fact true) | `Task` (executor) — one nested child per seat |
| Dispatch a subagent (Task present, `subagents` **not** advertised) | `CloudAgent` fan — one CloudAgent per seat — or stop. Never nest into unloadable `Task` children. Never one CloudAgent reviewing every seat inline. |
| Dispatch a subagent (no `Task`, no CloudAgent launch) | Stop. Name the missing primitive. Do not review inline. |
| Ensure isolated workspace | Host CloudAgent branch / PR. When `native-worktree` is advertised, run `ensure-worktree` (handshake). Never `git worktree add`. |
| Finish / push / open PR | CloudAgent PR path (see Finishing). Not a local worktree merge menu. |

## Workspace

Repo work on this host is a **CloudAgent branch / PR**, not a box checkout.

- When `native-worktree` is advertised, `using-git-worktrees` and `ensure-worktree` are `run` actions (`scripts/ensure-worktree`). Do not load the worktree skill and do not invent `git worktree` steps.
- The handshake reports isolation if present, otherwise reports host-owned workspace, always `complete` unless the process errors. It never runs `git worktree add`.
- Box clone is forbidden. Do not clone the repo onto the box to get a worktree.
- Do not advertise `native-worktree` from CloudAgent **tip** access alone.

## Spawn

Task-nest fact = `task_tool && skills_loadable`. Nest only when that fact is true
**and** `subagents` is advertised.

| Fact | Rule |
|------|------|
| Task-nest fact true | Nest with `Task`. One fresh child per seat. Do not prefer CloudAgent “because it runs in parallel.” |
| `Task` exists but skills unloadable / `subagents` not advertised | CloudAgent fan (one agent per seat) or stop. Never nest into unloadable children. |
| No CloudAgent launch either | Stop. Name the missing primitive. Do not review inline. |
| One agent per seat | Never one CloudAgent doing every seat in one window. |
| Partial return | A subset of dumps from **one** spawn call is a whole-call stop. Do not merge seats that did return. Do not re-announce a thinner pack. |
| Pack | Caller-named `full` / `core` (default `full`). Do not infer `core` from “Medium”, “quick”, “light”, “small”, or a missing `Task` tool. |

Probe loadability (`plugin-catalog` contains the family, or a child can `Read` the slot `SKILL.md`) before advertising `subagents`. SDD and `dispatching-parallel-agents` use this same binding; do not rewrite those skill bodies.

## Finishing

Map “push / open PR / finish the branch” to the host’s **CloudAgent PR path**.
Do not drive `finishing-a-development-branch` as a local worktree merge menu
(`git worktree remove`, merge-into-main on the box). The skill body stays
Superpowers; this host’s primitive is CloudAgent branch / PR.

## Profile

Superpowers **xor** Supersuit. Enable one plugin identity. This fork’s plugin
id is `supersuit`; skills are `supersuit:<skill>`. Config dirs are
`.supersuit/` / `~/.supersuit/` (`.superpowers/` is a one-release read fallback).
Enabling both in one agent profile is RED.

## SessionStart

Inject `using-superpowers` + `WORKFLOW_MAP` **every session**. No per-session
opt-in. A skill directory on disk is not bootstrap. Advertise `session-inject`
via env / CLI (this host has no hook-presence detect env yet).

Acceptance test (later eval cut, not this PR): a clean session whose user
message is exactly `Let's make a react todo list` must auto-trigger
`brainstorming` before any code.
```

Include the nested bash fence inside Capabilities as in the spec. Keep “Never infer” / “Do not infer” wording so tests pass.

- [ ] **Step 3: Re-run the mapping test — still fail on the SKILL.md pointer and workflow-config until Tasks 3–4**

Run: `bash tests/grok-bot/test-grok-bot-tools.sh`

Expected: FAIL on Platform Adaptation pointer and/or workflow-config until those land. Harness-ref heading/tool assertions should now pass.

- [ ] **Step 4: Commit the harness ref**

```bash
git add skills/using-superpowers/references/grok-bot-tools.md
git commit -m "feat: Grok Bot harness ref (action map + capability tokens)"
```

---

### Task 3: Platform Adaptation pointer

**Files:**
- Modify: `skills/using-superpowers/SKILL.md` (Platform Adaptation list only)

**Interfaces:**
- Consumes: existing pointer list (Codex, Pi, Antigravity, Hermes Agent)
- Produces: one additional bullet, no behavior-shaping prose

- [ ] **Step 1: Add the pointer**

Under `## Platform Adaptation`, after the Hermes Agent bullet, add:

```markdown
- Grok Bot: `references/grok-bot-tools.md`
```

Do not add spawn/workspace/bootstrap prose to `SKILL.md`. Pointer list only.

- [ ] **Step 2: Confirm no other skill-body edits**

```bash
git diff --stat -- skills/
```

Expected: only `skills/using-superpowers/SKILL.md` (one bullet) and the new `references/grok-bot-tools.md`. No edits to brainstorming, SDD, worktrees, finishing, dispatching-parallel-agents.

- [ ] **Step 3: Commit**

```bash
git add skills/using-superpowers/SKILL.md
git commit -m "feat: Platform Adaptation pointer for Grok Bot"
```

---

### Task 4: workflow-config.md spec link + `subagents` meaning

**Files:**
- Modify: `docs/workflow-config.md`

**Interfaces:**
- Consumes: spec capability table + advertise example
- Produces: Design specs list entry; tightened `subagents` row; optional CloudAgent-workspace advertise example (no product-name detect)

- [ ] **Step 1: Add the design spec to the Design specs list**

After the Skill-default hops bullet (~line 15), add:

```markdown
- [Grok Bot harness](superpowers/specs/2026-09-08-grok-bot-harness-design.md)
```

- [ ] **Step 2: Tighten the `subagents` row**

Replace the capability-table row:

```markdown
| `subagents` | Host supports subagent dispatch. | No. Advertise explicitly. |
```

with:

```markdown
| `subagents` | Task-nest fact is true: nested Task / subagent tool **and** the child can load that slot’s `SKILL.md` (`task_tool && skills_loadable`). A Task tool whose children cannot load skills is **not** this token. | No. Advertise only after that probe. |
```

- [ ] **Step 3: Add a short advertise example (no product-name detect)**

After the existing `SUPERPOWERS_CAPABILITIES` / `--capabilities` examples in **How capabilities are detected** (or immediately after **Advertising `native-worktree`**’s env example), add a short block. Do not add product-name detect. Example:

```markdown
Typical Grok Bot CloudAgent-workspace advertise (tokens, not a product-name
detect): `session-inject,native-worktree`. Add `subagents` only when children
can load slot skills.

```bash
export SUPERPOWERS_CAPABILITIES=session-inject,native-worktree
```
```

Do not add a `GROK_*` detect paragraph.

- [ ] **Step 4: Run tests**

```bash
bash tests/grok-bot/test-grok-bot-tools.sh
bash tests/workflow/test-native-worktree.sh
bash tests/workflow/test-resolve-workflow.sh
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/workflow-config.md
git commit -m "docs: Grok Bot spec link and precise subagents token"
```

---

### Task 5: Confirm bundled handshake; no detect change

**Files:**
- Read-only confirm: `workflows/overlays/native-worktree.yaml`, `scripts/ensure-worktree`
- No modify unless a test in Task 1 proved a regression

**Interfaces:**
- Overlay already gates `ensure-worktree` / `using-git-worktrees` on `native-worktree`
- Script never runs `git worktree add`; never names `CloudAgent`

- [ ] **Step 1: Confirm overlay + script**

```bash
grep -n 'native-worktree' workflows/overlays/native-worktree.yaml
grep -E 'git worktree add|CloudAgent' scripts/ensure-worktree || true
```

Expected: overlay gated on `native-worktree`; neither `git worktree add` nor `CloudAgent` in `scripts/ensure-worktree`.

- [ ] **Step 2: Confirm detect unchanged**

```bash
git diff origin/dev -- scripts/lib/workflow_resolve.py
```

Expected: empty (no product-name detect; no invented hook env).

If a real SessionStart-like env of the `CURSOR_PLUGIN_ROOT` class is discovered on this host, add it to `detect_capabilities` **and** the detect test — never `GROK` / `GROK_BOT` / `XAI`. None is known; skip.

---

### Task 6: Full relevant suite + residuals

- [ ] **Step 1: Run the relevant suite**

```bash
bash tests/grok-bot/test-grok-bot-tools.sh
bash tests/workflow/test-native-worktree.sh
bash tests/workflow/test-resolve-workflow.sh
bash tests/hooks/test-session-start.sh
bash tests/workflow/test-skill-handoff-lint.sh
```

Expected: all PASS.

- [ ] **Step 2: Record residuals in the PR**

Residuals (do not ship in this PR): PROFILE/SEED, marketplace version bump, GREEN/RED eval fixtures (stations.dev #475 live score), live harness acceptance transcript, `exec-hook`/`native-canvas` for this host, any future hook-presence env once Grok Bot actually exposes one.

---

## Self-review

1. **Spec coverage:** Later implementation items 1–4 are tasked (ref + pointer; advertise/docs; handshake confirm; skill bodies intact). Items 5–6 (acceptance transcript, Skill Evaluator fixtures) are explicit residuals.
2. **RED cases:** Infer-from-product-name (detect tests + ref prose); nest-into-unloadable (Spawn section); claim `native-worktree` with only tip (Workspace section); Superpowers+Supersuit same profile (Profile).
3. **No placeholders.** Tool names are the known live set (`Task`, `CloudAgent`, `Shell`, `Read`) plus “trust the live list.”
4. **No `grok-bot` capability.** Handshake remains host-agnostic.
