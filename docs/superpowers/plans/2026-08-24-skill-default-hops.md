# Skill-Default Hops Implementation Plan

> **For agentic workers:** After plan save, emit workflow outcomes `subagent-driven` or `inline` per human choice; do not hard-code the next skill. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Superpowers pipeline hops from `workflows/default.yaml` onto cataloged `SKILL.md` `metadata.supersuit.next`, merge ungated overlay transitions per `(from, on)` only, delete `entries`, and emit a thin skills registry.

**Architecture:** Keep catalog discovery as it is (`discover_skill_catalog`, first-seen logical id, warn+skip invalid `outcomes`). After a file catalogs, parse optional `metadata.supersuit.next` with `parse_skill_next`. `resolve_workflow` starts from an in-memory `{version: 1}` (never reads `default.yaml`), merges overlay **skills** first, materializes ungated hops from each winning `SKILL.md`, then merges overlay **transitions** per `(from, on)` (gated still append). `apply_capabilities` no longer seeds identity stubs. SessionStart stays `using-superpowers` + `WORKFLOW_MAP` only; hops appear as ordinary `transitions`.

**Tech Stack:** Python 3 stdlib (existing `workflow_yaml` + `workflow_resolve.py`), bash tests matching `tests/workflow/test-resolve-workflow.sh` and `tests/hooks/test-session-start.sh`. Zero new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-23-skill-default-hops-design.md`

## Global Constraints

- Binding spec is the hops design on current `dev` (squash-merged PR #26, including thin-registry + replace-one-hop). Follow it exactly.
- `next` is optional and additive. `outcomes` remains the catalog marker. `next` without valid `outcomes` cannot catalog.
- Extra `next` keys: warn + skip that hop. Do not raise `WorkflowResolveError` for extra keys. Missing `next` keys stay `wait`.
- `next` present but not a mapping: warn, ignore `next`, still catalog if `outcomes` ok.
- Unknown `to` (not `null` / `wait` / known logical id) is a resolve error, same as overlay transitions. Known ids = cataloged ids ∪ overlay/registry ids ∪ `discover_known_skills` directory names (even when absent from resolved `skills`).
- Ungated overlay transitions replace per `(from, on)` only. Do not replace-by-`from`. Overlay `to` replaces that one hop: `null` = continue session, `wait` = ask human. Do not collapse those.
- Gated (`when:`) overlay transitions stay appended. Most-specific satisfied `when` still wins. `native-worktree` still inserts `ensure-worktree`.
- Delete `workflows/default.yaml`. Bundled YAML base is in-memory `{version: 1}`. Do not read `default.yaml`. Do not keep a fallback copy. Do not re-seed identity stubs.
- Delete `entries` from schema, merge, validate, emitted JSON, docs, and tests. No shim. Overlay `entries:` is an unknown top-level key (ignored, no warning).
- Thin registry: resolved `skills` only from catalog attach (valid `outcomes`) or overlay remap. Non-cataloged bundled skills (TDD, etc.) must not be required in `skills` JSON.
- Add `outcomes` + `next` frontmatter ONLY to `brainstorming`, `writing-plans`, `subagent-driven-development`, `executing-plans` per the spec migration table (include both brainstorming `null` hops). Do not rewrite Red Flags / human-partner prose.
- Keep `workflows/overlays/native-worktree.yaml` and `native-canvas.yaml`.
- SessionStart still `using-superpowers` + `WORKFLOW_MAP` only. No foreign bodies. No `next` map in the payload.
- Do not bump marketplace / plugin versions. Do not extract `supersuit-superpowers`. Do not add `disable-model-invocation`.
- Feature branch PRs target `dev`, not `main`. Draft for human review.

## File Structure

| Path | Responsibility |
|------|----------------|
| `scripts/lib/workflow_resolve.py` | `parse_skill_next`; store `next` on catalog records; `winning_skill_next` / `materialize_skill_hops`; empty bundled base; per-`(from, on)` ungated merge; drop `entries`; stop stub-seeding in `apply_capabilities`. |
| `skills/{brainstorming,writing-plans,subagent-driven-development,executing-plans}/SKILL.md` | Frontmatter `metadata.supersuit.outcomes` + `next` only. Bodies unchanged. |
| `workflows/default.yaml` | Delete the file. |
| `tests/workflow/test-resolve-workflow.sh` | Helper, merge, resolve, thin-registry, and spec success-criteria cases. Rewrite `default.yaml` / replace-by-`from` / `entries` assertions. |
| `tests/workflow/test-native-worktree.sh`, `test-visual-surface.sh`, `test-exec-hook.sh` | Stop reading `default.yaml`. Keep capability-overlay behavior. |
| `tests/hooks/test-session-start.sh` | Leftover `default.yaml` is not a resolve input. Total bundled failure uses a broken **overlay**, not `default.yaml`. |
| `docs/workflow-config.md` | Layer list, merge rules, delete “list all outcomes for `from`”, author note `to` only inside `next`. |
| `docs/superpowers/specs/2026-08-23-skill-outcome-catalog-design.md` | Decision #2 + author/`to` sentences only. Cross-link hops spec. |
| `docs/superpowers/specs/2026-08-16-configurable-workflow-graph-design.md` | Cross-link hops spec. Do not rewrite the historical design. |

Do **not** add `outcomes` to other bundled skills. Do **not** add `skills.test-driven-development: {}` anywhere. Do **not** put a `next` object on resolved JSON.

### Resolver integration (so later tasks share one shape)

`resolve_workflow` today: `load_workflow_mapping(plugin_root/workflows/default.yaml)` → merge bundled/user/project overlays (skills **and** transitions together; ungated replace-by-`from`) → `discover_skill_catalog` → `validate_workflow(..., bundled_skills, extra_known_ids=set(catalog))` → `apply_capabilities` (inserts `{}` for every bundled + cataloged id) → `attach_catalog_outcomes`.

After this plan:

1. `catalog = discover_skill_catalog(...)` first. Each catalog record is `{path, outcomes, next}` where `next` is the filtered hop map from `parse_skill_next` (extra keys already warned+dropped).
2. `merged = {"version": 1}`. Do **not** call `load_workflow_mapping` on `workflows/default.yaml`.
3. Load overlay docs in order: `bundled_overlay_paths` (name-sorted), then user, then project (skip user/project when `bundled_only`).
4. For each overlay doc, `merge_workflows(merged, overlay_without_transitions)` — registry only (`skills` + `version`). `entries` is ignored.
5. `materialize_skill_hops(merged, catalog, project_root=project_root)` — ungated hops; implicit `from` is the logical id being resolved (overlay key when remapped).
6. For each overlay doc, `merge_workflows(merged, overlay_transitions_only)` — ungated replace per `(from, on)`; gated append.
7. `validate_workflow(..., bundled_skills=discover_known_skills(plugin_root), extra_known_ids=set(catalog))`. Unknown `to` is a resolve error. No `entries` field.
8. `apply_capabilities` filters `when:` and does **not** insert identity stubs.
9. `attach_catalog_outcomes` still inserts cataloged ids (thin registry via catalog attach) and compact `path` / `outcomes`. It must **not** copy `next` onto the JSON.

`--bundled-only` still skips user/project overlays only. Catalog discovery is unchanged.

CLI `main` emits `{version, capabilities, skills, transitions}` — no `entries`.

### Current helpers to keep (do not rename on a hunch)

- `classify_skill_marker(frontmatter) -> tuple[str, list[str] | None]` — unchanged. `next` without `outcomes` stays `invalid`.
- `discover_skill_catalog` — same roots / first-seen / warn+skip. Extend the stored record with `next`.
- `discover_known_skills(plugin_root)` — bundled directory names; still the known-id set for non-cataloged skills.
- `attach_catalog_outcomes` — same winning-`SKILL.md` table as hops (`path` wins; `{skill: other}` uses alias; `run`/`exec` none).
- `lookup_transition_to(resolved, from_id, on) -> tuple[bool, Any]` — `False` means wait. Missing hop ≠ `to: null`.
- `bundled_overlay_paths`, `overlay_workflow_path`, `merge_capability_sets`, `_pick_most_specific`.

---

### Task 1: `parse_skill_next` helper

**Files:**
- Modify: `scripts/lib/workflow_resolve.py` (new helper after `classify_skill_marker`)
- Test: `tests/workflow/test-resolve-workflow.sh` (new Python block before the `FAILURES` summary)

**Interfaces:**
- Consumes: `classify_skill_marker`, `extract_skill_frontmatter`
- Produces:
  - `parse_skill_next(frontmatter: dict[str, Any] | None, outcomes: list[str], *, source: str | Path | None = None) -> dict[str, Any]`
    - `next` absent → `{}`
    - `next` not a mapping → print `warning: ignoring metadata.supersuit.next (not a mapping): {source}` on stderr (omit the colon+source when `source` is `None`); return `{}`
    - key not in `outcomes` → print `warning: skipping next hop {key!r} (not in outcomes): {source}`; skip that key
    - key in `outcomes` → keep the value as-is (`None`, `"wait"`, string id, or any other YAML value so later validate can resolve-error unknowns)
    - other `metadata.supersuit` keys besides `outcomes` / `next` are ignored
    - top-level frontmatter `to` / `transitions` are not hops
    - YAML mapping last-key-wins already happens in the frontmatter loader

- [ ] **Step 1: Write the failing helper tests**

Append to `tests/workflow/test-resolve-workflow.sh` before the `FAILURES` summary:

```bash
echo "=== parse_skill_next helpers ==="
if python3 - "$REPO_ROOT" <<'PY'
import io
import sys
from contextlib import redirect_stderr
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import extract_skill_frontmatter, parse_skill_next

outcomes = ["approved-architectural", "approved-bounded", "approved-spike"]

fm = extract_skill_frontmatter(
    "---\nmetadata:\n  supersuit:\n    outcomes:\n"
    "      - approved-architectural\n      - approved-bounded\n"
    "      - approved-spike\n    next:\n"
    "      approved-architectural: writing-plans\n"
    "      approved-bounded: null\n      approved-spike: null\n"
    "      typo-outcome: writing-plans\n    extra: 1\n"
    "to: should-not-count\ntransitions:\n  - from: other\n---\n"
)
err = io.StringIO()
with redirect_stderr(err):
    hops = parse_skill_next(fm, outcomes, source="fixture.md")
assert hops == {
    "approved-architectural": "writing-plans",
    "approved-bounded": None,
    "approved-spike": None,
}
assert "typo-outcome" not in hops
assert "skipping next hop 'typo-outcome' (not in outcomes)" in err.getvalue()
assert "fixture.md" in err.getvalue()

fm_bad = extract_skill_frontmatter(
    "---\nmetadata:\n  supersuit:\n    outcomes:\n      - done\n    next: yes\n---\n"
)
err = io.StringIO()
with redirect_stderr(err):
    hops = parse_skill_next(fm_bad, ["done"], source="bad.md")
assert hops == {}
assert "ignoring metadata.supersuit.next (not a mapping)" in err.getvalue()

fm_none = extract_skill_frontmatter(
    "---\nmetadata:\n  supersuit:\n    outcomes:\n      - done\n---\n"
)
assert parse_skill_next(fm_none, ["done"]) == {}
print("ok")
PY
then
  pass "parse_skill_next helpers"
else
  fail "parse_skill_next helpers"
fi
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: `FAIL` / `ImportError` for `parse_skill_next`. Existing tests still pass.

- [ ] **Step 3: Implement the helper**

Add `parse_skill_next` in `scripts/lib/workflow_resolve.py` immediately after `classify_skill_marker`. Do not raise `WorkflowResolveError`. Read `frontmatter["metadata"]["supersuit"]["next"]` only when `supersuit` is a mapping.

```python
def parse_skill_next(
    frontmatter: dict[str, Any] | None,
    outcomes: list[str],
    *,
    source: str | Path | None = None,
) -> dict[str, Any]:
    if not isinstance(frontmatter, dict):
        return {}
    metadata = frontmatter.get("metadata")
    if not isinstance(metadata, dict):
        return {}
    supersuit = metadata.get("supersuit")
    if not isinstance(supersuit, dict) or "next" not in supersuit:
        return {}
    raw = supersuit.get("next")
    label = f": {source}" if source is not None else ""
    if not isinstance(raw, dict):
        print(
            f"warning: ignoring metadata.supersuit.next (not a mapping){label}",
            file=sys.stderr,
        )
        return {}
    allowed = set(outcomes)
    hops: dict[str, Any] = {}
    for key, value in raw.items():
        if key not in allowed:
            print(
                f"warning: skipping next hop {key!r} (not in outcomes){label}",
                file=sys.stderr,
            )
            continue
        hops[key] = value
    return hops
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: `parse_skill_next helpers` PASS. Existing tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/workflow/test-resolve-workflow.sh scripts/lib/workflow_resolve.py
git commit -m "feat(workflow): parse optional SKILL.md next hops"
```

---

### Task 2: Ungated merge per `(from, on)`; drop `entries`

**Files:**
- Modify: `scripts/lib/workflow_resolve.py` (`merge_workflows`, `apply_capabilities`, `main`)
- Modify: `tests/workflow/test-resolve-workflow.sh` (existing merge / entries blocks)

**Interfaces:**
- Consumes: `_entry_has_when`
- Produces: `merge_workflows` no longer copies or validates `entries`. Ungated overlay transitions replace only matching `(from, on)` (keep sibling hops and any already-merged gated rows for that `from`). Gated overlay transitions still append. CLI JSON has no `entries` key. `apply_capabilities` return dict has no `entries` key.

- [ ] **Step 1: Rewrite the failing merge tests**

Replace the block titled `=== merge transitions replace-by-from ===` with:

```bash
echo "=== merge transitions replace per (from, on) ==="
if python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import merge_workflows

base = {
  "version": 1,
  "skills": {},
  "transitions": [
    {"from": "brainstorming", "on": "approved-architectural", "to": "writing-plans"},
    {"from": "brainstorming", "on": "approved-bounded", "to": None},
    {"from": "brainstorming", "on": "approved-spike", "to": None},
    {"from": "writing-plans", "on": "inline", "to": "executing-plans"},
  ],
}
overlay = {
  "transitions": [
    {"from": "brainstorming", "on": "approved-architectural", "to": "wait"},
  ]
}
m = merge_workflows(base, overlay)
bs = [t for t in m["transitions"] if t["from"] == "brainstorming"]
assert len(bs) == 3, bs
assert any(t["on"] == "approved-architectural" and t["to"] == "wait" for t in bs)
assert any(t["on"] == "approved-bounded" and t["to"] is None for t in bs)
assert any(t["on"] == "approved-spike" and t["to"] is None for t in bs)
assert any(t["from"] == "writing-plans" for t in m["transitions"])
assert "entries" not in m
print("ok")
PY
then
  pass "transitions replace per (from, on)"
else
  fail "transitions replace per (from, on)"
fi
```

In `=== merge rejects null skills ===`, delete the `entries` list overlay case. Replace it with:

```python
ignored = merge_workflows(base, {"entries": {"creative-work": "brainstorming"}})
assert "entries" not in ignored
ignored_list = merge_workflows(base, {"entries": ["not", "a", "map"]})
assert "entries" not in ignored_list
```

Change every `merge_workflows` fixture that still sets `"entries": {}` so it omits `entries` (skills-replace, missing-`from`, gated-append, validate missing-`to`). Keep the YAML loader test that parses an `entries` key — that tests `load_yaml`, not the schema.

- [ ] **Step 2: Run the test and confirm the new replace case fails**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: `transitions replace per (from, on)` FAIL — overlay still drops `approved-bounded` / `approved-spike` because of replace-by-`from`. Gated-append test still passes.

- [ ] **Step 3: Implement the merge + emit change**

In `merge_workflows`:

1. Remove `"entries"` from the result dict and delete the `if "entries" in overlay:` block. Do not warn.
2. Replace the ungated filter:

```python
        overlay_keys = {
            (transition["from"], transition["on"])
            for transition in ungated
            if isinstance(transition.get("on"), str) and transition["on"].strip()
        }
        result["transitions"] = [
            transition
            for transition in result["transitions"]
            if _entry_has_when(transition)
            or (transition.get("from"), transition.get("on")) not in overlay_keys
        ]
        result["transitions"].extend(ungated)
        result["transitions"].extend(gated)
```

Ungated overlay rows that lack `on` still raise via the existing `from` check; add the same `on` check if a row has `from` but no `on` (raise `WorkflowResolveError` with `missing valid on`) so `(from, None)` cannot wipe siblings.

3. `apply_capabilities`: drop `"entries": dict(doc.get("entries") or {})` from the return dict.
4. `main`: drop `"entries": resolved["entries"]` from `output`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: new merge tests PASS. CLI still emits bundled hops (default.yaml still loaded until Task 3). If any CLI assertion requires `"entries"` in JSON, delete that assertion.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workflow_resolve.py tests/workflow/test-resolve-workflow.sh
git commit -m "feat(workflow): merge ungated hops per from+on and drop entries"
```

---

### Task 3: Empty bundled base, materialize hops, thin registry, migrate four skills

**Files:**
- Modify: `scripts/lib/workflow_resolve.py` (`discover_skill_catalog`, new hop helpers, `resolve_workflow`, `apply_capabilities`, `attach_catalog_outcomes`)
- Modify: `skills/brainstorming/SKILL.md`, `skills/writing-plans/SKILL.md`, `skills/subagent-driven-development/SKILL.md`, `skills/executing-plans/SKILL.md` (frontmatter only)
- Delete: `workflows/default.yaml`
- Modify: `tests/workflow/test-resolve-workflow.sh`, `tests/workflow/test-native-worktree.sh`, `tests/workflow/test-visual-surface.sh`, `tests/workflow/test-exec-hook.sh`

**Interfaces:**
- Consumes: `parse_skill_next`, `classify_skill_marker`, `discover_skill_catalog`, `discover_known_skills`, `merge_workflows`, `attach_catalog_outcomes`
- Produces:
  - `discover_skill_catalog` record: `{"path": str, "outcomes": list[str], "next": dict[str, Any]}`
  - `next_from_skill_dir(skill_dir: Path) -> dict[str, Any] | None` — `None` if the file is not cataloged (`absent` or `invalid`; `invalid` still warns via the existing outcomes warning). `{}` if cataloged with no usable `next`.
  - `winning_skill_next(skill_id: str, entry: dict[str, Any], catalog: dict[str, dict[str, Any]], *, project_root: Path) -> dict[str, Any] | None` — `None` means contribute no hops (`run`/`exec`). Same winner table as attach.
  - `materialize_skill_hops(merged: dict[str, Any], catalog: dict[str, dict[str, Any]], *, project_root: Path) -> None` — mutates `merged["transitions"]` by appending ungated `{from, on, to}` for every cataloged or remapped logical id.
  - `resolve_workflow` never reads `workflows/default.yaml`.
  - `apply_capabilities` does **not** loop `bundled_skills | extra_known_ids` to insert `{}`.

Winning `SKILL.md` (copy from the spec; implicit `from` is always `skill_id`):

| Winning overlay entry | Whose `next` materializes |
|-----------------------|---------------------------|
| `path` is set | `next_from_skill_dir` of that path |
| `{ skill: other-name }` and no `path` | `catalog[alias]["next"]` when aliased skill is cataloged; else no hops |
| `run` / `exec` | None |
| Identity / empty / missing entry | `catalog[skill_id]["next"]` when cataloged |

Iterate `set(catalog) | set(merged.get("skills") or {})` so remapped-only ids still get hops and cataloged identity ids get hops before attach.

- [ ] **Step 1: Write failing resolve tests that do not depend on default.yaml**

Replace `=== default.yaml encodes core handoffs ===` with a resolve assertion (real plugin root + isolated home):

```bash
echo "=== bundled hops come from cataloged SKILL.md next ==="
if OUT="$("$REPO_ROOT/scripts/resolve-workflow" --plugin-root "$REPO_ROOT" --project-root "$TEST_ROOT/empty-proj" --user-home "$TEST_HOME" --bundled-only)" &&
  echo "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
pairs={(t["from"], t["on"], t["to"]) for t in d["transitions"]}
assert ("brainstorming", "approved-architectural", "writing-plans") in pairs
assert ("brainstorming", "approved-bounded", None) in pairs
assert ("brainstorming", "approved-spike", None) in pairs
assert ("writing-plans", "subagent-driven", "subagent-driven-development") in pairs
assert ("writing-plans", "inline", "executing-plans") in pairs
assert ("subagent-driven-development", "complete", "finishing-a-development-branch") in pairs
assert ("executing-plans", "complete", "finishing-a-development-branch") in pairs
assert "entries" not in d
assert "test-driven-development" not in d["skills"]
assert "next" not in d["skills"].get("brainstorming", {})
'; then
  pass "bundled hops come from cataloged SKILL.md next"
else
  fail "bundled hops come from cataloged SKILL.md next"
fi
```

`mkdir -p "$TEST_ROOT/empty-proj"` before the CLI call.

Replace `=== default.yaml has no run actions ===` and `=== default.yaml has no capability gates ===` (and the same-named blocks in `test-native-worktree.sh`, `test-visual-surface.sh`, `test-exec-hook.sh`) with: assert `workflows/default.yaml` does not exist, and that bundled-only JSON has no `when` on emitted transitions / no `run` on cataloged identity skills.

Add this leftover-file test (temp plugin that copies resolver + real `skills/` + overlays, plus a poison `default.yaml`):

```bash
echo "=== leftover default.yaml is not read ==="
POISON="$TEST_ROOT/poison-plugin"
mkdir -p "$POISON"
cp -a "$REPO_ROOT/scripts" "$REPO_ROOT/skills" "$REPO_ROOT/workflows" "$POISON/"
printf '%s\n' 'version: "must-not-read"' > "$POISON/workflows/default.yaml"
if OUT="$("$POISON/scripts/resolve-workflow" --plugin-root "$POISON" --project-root "$TEST_ROOT/empty-proj" --user-home "$TEST_HOME" --bundled-only)" &&
  echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["version"]==1; assert any(t["from"]=="brainstorming" for t in d["transitions"])'; then
  pass "leftover default.yaml is not read"
else
  fail "leftover default.yaml is not read"
fi
```

- [ ] **Step 2: Run tests and confirm they fail for the right reason**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: `bundled hops come from cataloged SKILL.md next` FAIL — brainstorming is not cataloged yet (no marker) and/or hops still come from `default.yaml` stubs so `test-driven-development` is still in `skills`. `leftover default.yaml is not read` FAIL — resolve still loads the poison file (`unsupported version`).

- [ ] **Step 3: Implement resolve order, hop materialization, thin registry, and the four skill markers**

`discover_skill_catalog`: after a file is `ok`, set

```python
catalog[logical_id] = {
    "path": str(skill_md.parent.resolve()),
    "outcomes": list(outcomes),
    "next": parse_skill_next(frontmatter, outcomes, source=skill_md),
}
```

Add `next_from_skill_dir` next to `outcomes_from_skill_dir`. Reuse the same read/parse/warn path; if status is `ok`, return `parse_skill_next(frontmatter, outcomes, source=skill_md)`; if `invalid`, keep the existing outcomes warning and return `None`; if `absent`, return `None` with no warning.

Add `winning_skill_next` and `materialize_skill_hops`:

```python
def winning_skill_next(
    skill_id: str,
    entry: dict[str, Any],
    catalog: dict[str, dict[str, Any]],
    *,
    project_root: Path,
) -> dict[str, Any] | None:
    if "run" in entry:
        return None
    if "path" in entry:
        path_value = entry.get("path")
        if isinstance(path_value, str) and path_value.strip():
            hops = next_from_skill_dir(_resolve_skill_path(path_value, project_root))
            return hops
        return None
    if "skill" in entry:
        alias = entry.get("skill")
        info = catalog.get(alias) if isinstance(alias, str) else None
        return dict(info["next"]) if info else None
    info = catalog.get(skill_id)
    return dict(info["next"]) if info else None


def materialize_skill_hops(
    merged: dict[str, Any],
    catalog: dict[str, dict[str, Any]],
    *,
    project_root: Path,
) -> None:
    skills = merged.get("skills") or {}
    hops: list[dict[str, Any]] = []
    for skill_id in sorted(set(catalog) | set(skills)):
        entry = skills.get(skill_id) or {}
        if not isinstance(entry, dict):
            continue
        nxt = winning_skill_next(
            skill_id, entry, catalog, project_root=project_root
        )
        if not nxt:
            continue
        for on, to in nxt.items():
            hops.append({"from": skill_id, "on": on, "to": to})
    merged["transitions"] = hops + list(merged.get("transitions") or [])
```

Rewrite `resolve_workflow` to the nine-step order in **Resolver integration**. Two-pass overlay merge using the existing `merge_workflows` (it only applies keys that are present):

```python
    overlays: list[dict[str, Any]] = []
    for overlay_path in bundled_overlay_paths(plugin_root):
        overlays.append(
            load_workflow_mapping(
                overlay_path, label=f"bundled overlay {overlay_path.name}"
            )
        )
    if not bundled_only:
        # user then project, same overlay_workflow_path calls as today
        ...

    merged: dict[str, Any] = {"version": 1}
    for overlay in overlays:
        skills_layer = {k: v for k, v in overlay.items() if k != "transitions"}
        merged = merge_workflows(merged, skills_layer)
    materialize_skill_hops(merged, catalog, project_root=project_root)
    for overlay in overlays:
        trans_layer = {
            k: overlay[k] for k in ("version", "transitions") if k in overlay
        }
        merged = merge_workflows(merged, trans_layer)
```

Remove the stub-seed loop in `apply_capabilities`:

```python
    for skill_id in set(bundled_skills) | set(extra_known_ids or ()):
        if skill_id not in skills_out:
            skills_out[skill_id] = {}
```

Keep `bundled_skills` and `extra_known_ids` for `known_ids` / unknown-`to` checks.

`attach_catalog_outcomes` stays; do not write `entry["next"]`.

Frontmatter only (do not touch Red Flags / human-partner body copy):

`skills/brainstorming/SKILL.md`:

```yaml
metadata:
  supersuit:
    outcomes:
      - approved-architectural
      - approved-bounded
      - approved-spike
    next:
      approved-architectural: writing-plans
      approved-bounded: null
      approved-spike: null
```

`skills/writing-plans/SKILL.md`:

```yaml
metadata:
  supersuit:
    outcomes:
      - subagent-driven
      - inline
    next:
      subagent-driven: subagent-driven-development
      inline: executing-plans
```

`skills/subagent-driven-development/SKILL.md` and `skills/executing-plans/SKILL.md`:

```yaml
metadata:
  supersuit:
    outcomes:
      - complete
    next:
      complete: finishing-a-development-branch
```

`git rm workflows/default.yaml`.

- [ ] **Step 4: Run the workflow + capability suites**

Run:

```bash
/bin/bash tests/workflow/test-resolve-workflow.sh
/bin/bash tests/workflow/test-native-worktree.sh
/bin/bash tests/workflow/test-visual-surface.sh
/bin/bash tests/workflow/test-exec-hook.sh
```

Expected: bundled hops PASS from skill `next`. `native-worktree` advertised still resolves `brainstorming` / `approved-architectural` → `ensure-worktree`. TDD absent from `skills`. Poison `default.yaml` is ignored. No `entries` in CLI JSON.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workflow_resolve.py \
  skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md \
  skills/subagent-driven-development/SKILL.md skills/executing-plans/SKILL.md \
  tests/workflow/test-resolve-workflow.sh \
  tests/workflow/test-native-worktree.sh \
  tests/workflow/test-visual-surface.sh \
  tests/workflow/test-exec-hook.sh
git rm workflows/default.yaml
git commit -m "feat(workflow): materialize skill-default hops and drop default.yaml"
```

---

### Task 4: Spec success-criteria tests

**Files:**
- Test: `tests/workflow/test-resolve-workflow.sh`
- Modify: `scripts/lib/workflow_resolve.py` only if a test fails for a missing rule

**Interfaces:**
- Consumes: `resolve_workflow`, `lookup_transition_to`, `merge_workflows`, `materialize_skill_hops`
- Produces: coverage for every Success criteria / Tests-the-spec-requires bullet that Task 3 did not already lock.

- [ ] **Step 1: Write the failing cases** (isolated `--plugin-root` fixtures; do not edit bundled skills for these)

```bash
echo "=== extra next key warns and skips that hop ==="
# Foreign cataloged skill: outcomes [done, skip], next: {done: wait, typo: wait}
# Resolve continues. lookup (from=extra-next, on=typo) is missing (wait).
# stderr contains skipping next hop 'typo'

echo "=== missing next key stays wait ==="
# outcomes [done, other], next: {done: null}
# lookup_transition_to(..., "other") == (False, None)
# lookup for done is (True, None) — explicit null, not wait

echo "=== unknown next to is a resolve error ==="
# next: {done: not-a-skill} → CLI exit 1, stderr has "unknown logical id"

echo "=== next without outcomes does not catalog ==="
# metadata.supersuit.next only → warn invalid outcomes, id absent from skills, no hops

echo "=== overlay replace architectural with wait keeps skill nulls ==="
# project overlay: only brainstorming / approved-architectural / to: wait
# bounded + spike stay None (not missing, not wait)

echo "=== overlay to null stays continue-session ==="
# overlay approved-architectural to: null → to is None, not "wait"

echo "=== foreign cataloged next uses the same rules ==="
# SUPERSUIT_SKILL_PATH skill with valid next → hop materialized under that logical id

echo "=== remapped path next uses remapped from ==="
# overlay skills.brainstorming.path = custom SKILL.md whose next.approved-architectural = wait
# from is brainstorming (overlay key), not the directory name

echo "=== non-cataloged bundled skill is reachable by id ==="
# bundled-only: test-driven-development not in skills
# project overlay transition writing-plans / inline / to: test-driven-development succeeds
# second overlay remaps skills.test-driven-development.path to a fixture dir → key appears

echo "=== no duplicate ungated (from, on) before capability filter ==="
# After materialize + merge of native-worktree.yaml (do not apply_capabilities):
# exactly one ungated (brainstorming, approved-architectural)
# plus the gated native-worktree row. validate_workflow on that merged doc is empty.
```

Use `lookup_transition_to` for wait-vs-null. Use a copied plugin root + empty project/home so bundled hops are present when testing overlay replace.

For the duplicate test, load overlays in Python:

```python
from workflow_resolve import (
    bundled_overlay_paths,
    discover_skill_catalog,
    load_workflow_mapping,
    materialize_skill_hops,
    merge_workflows,
    resolve_workflow,
    validate_workflow,
    discover_known_skills,
)
plugin = Path(sys.argv[1])
catalog = discover_skill_catalog(
    plugin_root=plugin, project_root=plugin, user_home=Path(sys.argv[2]), environ={},
)
merged = {"version": 1}
overlays = [
    load_workflow_mapping(path, label=path.name)
    for path in bundled_overlay_paths(plugin)
]
for overlay in overlays:
    merged = merge_workflows(merged, {k: v for k, v in overlay.items() if k != "transitions"})
materialize_skill_hops(merged, catalog, project_root=plugin)
for overlay in overlays:
    merged = merge_workflows(
        merged, {k: overlay[k] for k in ("version", "transitions") if k in overlay}
    )
ungated = [
    (t["from"], t["on"])
    for t in merged["transitions"]
    if not t.get("when")
]
assert len(ungated) == len(set(ungated)), ungated
errors = validate_workflow(
    merged,
    project_root=plugin,
    bundled_skills=set(discover_known_skills(plugin)),
    plugin_root=plugin,
    extra_known_ids=set(catalog),
)
assert errors == []
```

- [ ] **Step 2: Run and confirm new cases fail until resolve implements them**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: each new named case FAIL for the missing rule (or PASS if Task 3 already implemented it — that is acceptable; do not weaken the assertion).

- [ ] **Step 3: Fill any gaps in `workflow_resolve.py`**

Typical gaps: remapped `from` using the overlay key; `next` not-a-mapping still catalogs; unknown `to` going through `validate_workflow` unchanged (`to not in (None, "wait") and to not in known_ids`). Do not special-case foreign vs bundled.

- [ ] **Step 4: Re-run until green**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: All workflow tests passed.

- [ ] **Step 5: Commit**

```bash
git add tests/workflow/test-resolve-workflow.sh scripts/lib/workflow_resolve.py
git commit -m "test(workflow): lock skill-default hop success criteria"
```

---

### Task 5: SessionStart fixture — no default.yaml fallback

**Files:**
- Modify: `tests/hooks/test-session-start.sh`

**Interfaces:**
- Consumes: `hooks/session-start` (unchanged payload: bootstrap + `WORKFLOW_MAP` only)
- Produces: total bundled failure still warns `no WORKFLOW_MAP available`. A leftover `workflows/default.yaml` must not be the knob that creates that failure.

- [ ] **Step 1: Write the failing fixture change**

In the “SessionStart total resolve failure warning” block, stop writing `workflows/default.yaml`. Instead:

```bash
mkdir -p "$broken_plugin/workflows/overlays"
printf '%s\n' 'version: "broken-bundled"' > "$broken_plugin/workflows/overlays/z-broken.yaml"
```

Keep copying `hooks/session-start`, `scripts/resolve-workflow`, `scripts/lib/*.py`, and the stub `using-superpowers` SKILL.md. Expected stderr/context strings stay the same (`workflow resolve failed (including bundled defaults); no WORKFLOW_MAP available`).

Add a sibling case: same broken plugin **plus** a valid empty overlay set, but with poison `workflows/default.yaml` (`version: "must-not-read"`) and the four cataloged skills copied from the repo. SessionStart must inject `WORKFLOW_MAP` (resolve succeeds). That proves there is no `default.yaml` fallback and leftover file is ignored.

- [ ] **Step 2: Run and confirm the old default.yaml-only fixture would no longer fail resolve**

Run: `/bin/bash tests/hooks/test-session-start.sh`

Expected: after the fixture change, total-failure still triggers via the broken overlay. If you leave only poison `default.yaml` and no broken overlay, resolve succeeds (new leftover case).

- [ ] **Step 3: No production hook change unless a string drifts**

`hooks/session-start` already retries `--bundled-only` then warns. Do not add a `default.yaml` read. Do not inject a `next` map.

- [ ] **Step 4: Re-run SessionStart tests**

Run: `/bin/bash tests/hooks/test-session-start.sh`

Expected: catalog body still absent; `WORKFLOW_MAP` still has transitions; no foreign bodies.

- [ ] **Step 5: Commit**

```bash
git add tests/hooks/test-session-start.sh
git commit -m "test(hooks): SessionStart bundled failure does not use default.yaml"
```

---

### Task 6: Docs

**Files:**
- Modify: `docs/workflow-config.md`
- Modify: `docs/superpowers/specs/2026-08-23-skill-outcome-catalog-design.md` (Decision #2 + `to` sentences + cross-link only)
- Modify: `docs/superpowers/specs/2026-08-16-configurable-workflow-graph-design.md` (cross-link only)

**Interfaces:**
- Consumes: hops spec Design decisions 5, 6, 7, 14 and Merge rules
- Produces: docs that match the resolver. No marketplace version bump.

- [ ] **Step 1: Edit `docs/workflow-config.md`**

1. Add the hops spec to the Design specs list.
2. Layer list item 1 becomes: **Bundled defaults** — cataloged `metadata.supersuit.next` hops (in-memory `{version: 1}`; there is no `workflows/default.yaml`).
3. Merge rules: delete the `entries` bullet. Change transitions to: ungated replace per `(from, on)`; gated append.
4. Replace the “stop the architectural chain” example with the spec’s one-hop overlay (`to: wait` only). Delete the sentence “you must list **all** outcomes for `brainstorming` you want to keep”.
5. Author opt-in: change “Do not put `to`, `transitions`, or a graph in frontmatter” to: `to` is allowed **only** as a `next` value. No `transitions:` list on the skill. No graph of other skills’ edges. Unmapped outcomes stay `wait`.
6. Show an optional `next` map on the opt-in snippet. State that SessionStart does not include a `next` object — hops are ordinary `transitions`.
7. Replace remaining “`workflows/default.yaml` stays ungated / has no `run`” sentences with: capability overlays stay in `workflows/overlays/*.yaml`; cataloged identity skills have no `run`.

- [ ] **Step 2: Revise catalog spec Decision #2**

In `docs/superpowers/specs/2026-08-23-skill-outcome-catalog-design.md`:

- Decision #2 becomes: `to` is allowed **only** inside `metadata.supersuit.next` values. No `transitions:` list on the skill. No graph of other skills’ edges. (Hops spec Decision #5.)
- Safety goal / glossary / author sentences that say “no `to` in frontmatter” get the same narrowing.
- Success criterion “No new transitions unless an overlay added them” becomes: overlays and skill-default `next` may add transitions; unmapped outcomes stay `wait`.
- Drop “`workflows/default.yaml` stays ungated and free of `run` keys” from catalog success criteria (file is gone).
- Cross-link: `[Skill-default hops](2026-08-23-skill-default-hops-design.md)`.

Do not rewrite the rest of the catalog spec.

- [ ] **Step 3: Cross-link the graph design**

At the top of `docs/superpowers/specs/2026-08-16-configurable-workflow-graph-design.md`, add one line: Superpowers hops now live on cataloged `SKILL.md` `next` — see `2026-08-23-skill-default-hops-design.md`. Leave the historical `default.yaml` / `entries` text as history.

- [ ] **Step 4: Grep for leftover live-field docs**

```bash
rg -n "workflows/default.yaml|list all outcomes|entries:" docs/workflow-config.md docs/superpowers/specs/2026-08-23-skill-outcome-catalog-design.md
```

Expected: no live instructions that `default.yaml` is the bundled graph or that `entries` is a schema field. Historical graph-design mentions may remain.

- [ ] **Step 5: Commit**

```bash
git add docs/workflow-config.md \
  docs/superpowers/specs/2026-08-23-skill-outcome-catalog-design.md \
  docs/superpowers/specs/2026-08-16-configurable-workflow-graph-design.md
git commit -m "docs: skill-default hops layer list and per-from-on merge"
```

---

## Self-review

**1. Spec coverage**

| Spec requirement | Task |
|------------------|------|
| Parse `next` from winning SKILL.md; implicit `from` = logical id being resolved | 1, 3, 4 |
| Extra key warn+skip; missing key wait; `next` not a mapping warn+ignore | 1, 4 |
| `next` without valid `outcomes` cannot catalog | 4 |
| Unknown `to` resolve error (same as overlays) | 4 |
| Known ids include `discover_known_skills` even when absent from `skills` | 3, 4 |
| Ungated overlay merge per `(from, on)` only; replace-one-hop `wait`/`null` stay distinct | 2, 4 |
| Gated append; native-worktree still wins | 3 (existing native-worktree suite) |
| Delete `default.yaml`; in-memory `{version: 1}`; do not read / re-seed | 3, 5 |
| Delete `entries` (no shim) | 2, 3 |
| Thin registry; TDD valid `to`, absent, identity, overlay remap | 3, 4 |
| Migration table on four skills only; both brainstorming nulls | 3 |
| Keep capability overlay YAML files | 3 (do not delete) |
| Docs layer list, merge rules, delete “list all outcomes”, catalog Decision #2, cross-links | 6 |
| SessionStart bootstrap + WORKFLOW_MAP only; no `next` in payload | 3, 5 |
| Foreign cataloged `next` same rules; `--bundled-only` = empty YAML + catalog hops + bundled overlays | 3, 4 |
| No duplicate ungated `(from, on)` before capability filter | 4 |
| No version bump; no extract; no disable-model-invocation | constraints |

**2. Placeholder scan:** no TBD / “tests for the above” / “similar to Task N”.

**3. Type consistency:** `parse_skill_next` → `dict[str, Any]`; catalog record `next` is that dict; `winning_skill_next` returns `dict[str, Any] | None`; `materialize_skill_hops` mutates `merged["transitions"]`; `lookup_transition_to` remains `(found, to)` with `found is False` = wait.

---

## Execution Handoff

This plan is written to be executed in the same PR that adds it (inline), targeting `dev`.
