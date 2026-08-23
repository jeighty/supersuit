# Skill Outcome Catalog Implementation Plan

> **For agentic workers:** After plan save, emit workflow outcomes `subagent-driven` or `inline` per human choice; do not hard-code the next skill. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Catalog opted-in foreign and bundled skills by reading `metadata.supersuit.outcomes` from `SKILL.md` frontmatter, attach compact `path` / `outcomes` on resolved registry entries, and leave SessionStart as bootstrap + `WORKFLOW_MAP` only.

**Architecture:** Extend `scripts/lib/workflow_resolve.py` so `resolve_workflow` walks a fixed, ordered list of skill roots, parses only the first YAML frontmatter block, and records first-seen logical ids that carry a valid opt-in marker. Overlay merge / `when` / `run` stay unchanged. After capability filtering, attach skill-frontmatter `outcomes` (and `path` for identity entries) using the winning overlay `SKILL.md`. Invalid markers warn on stderr and skip that file; they never raise `WorkflowResolveError`.

**Tech Stack:** Python 3 stdlib (existing `workflow_yaml.load_yaml`), bash tests matching `tests/workflow/test-resolve-workflow.sh` and `tests/hooks/test-session-start.sh`. Zero new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-23-skill-outcome-catalog-design.md`

## Global Constraints

- Opt-in only via `metadata.supersuit.outcomes` (non-empty list of non-empty strings) in `SKILL.md` YAML frontmatter. No `to` / `transitions` / graph in frontmatter is interpreted.
- Catalog, do not inject: SessionStart still injects only `using-superpowers` + `WORKFLOW_MAP`. No foreign `SKILL.md` bodies. At most compact `outcomes` on registry entries already in the map JSON.
- Do not create or scan `.supersuit/skills` unless that path is on `SUPERSUIT_SKILL_PATH`.
- Do not scan project-root `skills/` unless listed on `SUPERSUIT_SKILL_PATH`. Do not walk plugin caches or `node_modules`.
- Invalid / malformed `metadata.supersuit.outcomes` on a candidate `SKILL.md`: warn + skip that file. Do not raise global `WorkflowResolveError`. Missing `metadata.supersuit` is a silent skip. Do not implement strict mode.
- Discovery order: plugin `skills/`, then `SUPERSUIT_SKILL_PATH` (split with `os.pathsep`), then project `.agents/skills`, `.claude/skills`, `.opencode/skills`, then user `~/.agents/skills`, `~/.claude/skills`, `~/.config/opencode/skills`. First-seen logical id wins.
- Logical id = frontmatter `name` if present and non-empty, else parent directory name. Harness invocation stays the directory name.
- Overlay `{ skill: other-name }` with no `path`: attach outcomes from the aliased skill when that skill is cataloged with a valid marker; else omit. If both `skill` and `path` are set, `path` wins for which `SKILL.md` is read. `run` / `exec` entries do not get skill-frontmatter outcomes.
- Unmapped `(from, on)` stays `wait`. Overlay still owns transitions. Cataloged ids join `known_ids`.
- Expand `~` against `user_home` (the `--user-home` / `HOME` resolve argument, so tests stay isolated). Relative `SUPERSUIT_SKILL_PATH` entries resolve from `project_root`. Follow skill-dir symlinks; skip non-regular `SKILL.md` (`lstat` + `stat.S_ISREG`, same as `scripts/lib/migrate_to_supersuit.py`).
- Do not bump marketplace / plugin version. Do not add evals or live harness sessions. Do not change `workflows/default.yaml` to add `run` keys or markers (bundled markers are a later PR).
- Feature branch PRs target `dev`, not `main`.

## File Structure

| Path | Responsibility |
|------|----------------|
| `scripts/lib/workflow_resolve.py` | Frontmatter extract, marker parse, root walk, catalog dict, attach `path`/`outcomes` during resolve. Keep `discover_known_skills` for bundled directory names (with or without a marker). |
| `tests/workflow/test-resolve-workflow.sh` | Marker present/absent; first-seen wins; `SUPERSUIT_SKILL_PATH`; skip project `skills/` and `.supersuit/skills` unless listed; invalid marker warns and skips; `{ skill: other-name }` attaches or omits; overlay `path` wins; `run` does not get frontmatter outcomes; cataloged id is a valid `to`. |
| `tests/hooks/test-session-start.sh` | Fixture skill with a distinctive body is cataloged in the map JSON and that body is absent from SessionStart context. |
| `docs/workflow-config.md` | Discovery table, author opt-in snippet, and a glossary cross-link: skill frontmatter `outcomes` vs `skills.<id>.run.outcomes`. |
| `docs/superpowers/specs/2026-08-23-skill-outcome-catalog-design.md` | Binding spec. Do not rewrite it. |

Do **not** add a `.supersuit/skills` tree, a `--skill-path` CLI flag (env var is enough for v1), a strict-mode flag, or markers on bundled `skills/*/SKILL.md`.

### Resolver integration (so later tasks share one shape)

`resolve_workflow` already: load bundled + overlays → `validate_workflow(..., bundled_skills=discover_known_skills(...))` → `apply_capabilities` (which inserts `{}` for every bundled id).

After this plan:

1. `catalog = discover_skill_catalog(plugin_root, project_root, user_home, environ)`.
2. `validate_workflow(..., bundled_skills=bundled, extra_known_ids=set(catalog))` so an overlay may `to:` a cataloged id without a stub `skills:` entry.
3. `apply_capabilities` also inserts `{}` for cataloged ids that have no overlay entry (`extra_known_ids` argument).
4. `attach_catalog_outcomes(resolved["skills"], catalog, project_root)` mutates entries in place.

`--bundled-only` still skips user/project **overlays**. It does **not** skip skill-root discovery (catalog is not an overlay). Tests isolate roots via `--project-root` / `--user-home` / `SUPERSUIT_SKILL_PATH`.

---

### Task 1: Frontmatter + marker helpers

**Files:**
- Modify: `scripts/lib/workflow_resolve.py` (new helpers after `discover_known_skills`)
- Test: `tests/workflow/test-resolve-workflow.sh` (new Python block)

**Interfaces:**
- Consumes: `workflow_yaml.load_yaml`, `YAMLError`
- Produces:
  - `extract_skill_frontmatter(text: str) -> dict[str, Any] | None`
  - `classify_skill_marker(frontmatter: dict[str, Any] | None) -> tuple[str, list[str] | None]`
    - `("absent", None)` — no `metadata.supersuit`
    - `("invalid", None)` — `metadata.supersuit` present but not a mapping, or `outcomes` missing / wrong type / empty / empty strings
    - `("ok", outcomes)` — de-duplicated non-empty strings, first-seen order
  - `skill_logical_id(frontmatter: dict[str, Any] | None, skill_dir: Path) -> str`

- [ ] **Step 1: Write the failing helper tests**

Append to `tests/workflow/test-resolve-workflow.sh` before the `FAILURES` summary:

```bash
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
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: `FAIL` / `ImportError` for the new names (helpers not defined). Existing tests still pass.

- [ ] **Step 3: Implement the helpers**

Add to `scripts/lib/workflow_resolve.py` (stdlib `re` / `stat` already needed later; import `stat` now):

```python
def extract_skill_frontmatter(text: str) -> dict[str, Any] | None:
    """Return the first YAML frontmatter mapping (first --- ... ---), or None."""
    if text.startswith("\ufeff"):
        text = text[1:]
    if not text.startswith("---"):
        return None
    rest = text[3:]
    if rest.startswith("\r\n"):
        rest = rest[2:]
    elif rest.startswith("\n"):
        rest = rest[1:]
    else:
        return None
    closer = rest.find("\n---")
    if closer < 0:
        return None
    try:
        doc = load_yaml(rest[:closer])
    except YAMLError:
        return None
    return doc if isinstance(doc, dict) else None


def classify_skill_marker(
    frontmatter: dict[str, Any] | None,
) -> tuple[str, list[str] | None]:
    """Classify metadata.supersuit.outcomes: absent, invalid, or ok."""
    if not isinstance(frontmatter, dict):
        return "absent", None
    metadata = frontmatter.get("metadata")
    if not isinstance(metadata, dict) or "supersuit" not in metadata:
        return "absent", None
    supersuit = metadata.get("supersuit")
    if not isinstance(supersuit, dict):
        return "invalid", None
    if "outcomes" not in supersuit:
        return "invalid", None
    raw = supersuit.get("outcomes")
    if not isinstance(raw, list) or not raw:
        return "invalid", None
    outcomes: list[str] = []
    for item in raw:
        if not isinstance(item, str) or not item.strip():
            return "invalid", None
        if item not in outcomes:
            outcomes.append(item)
    if not outcomes:
        return "invalid", None
    return "ok", outcomes


def skill_logical_id(
    frontmatter: dict[str, Any] | None, skill_dir: Path
) -> str:
    name = frontmatter.get("name") if isinstance(frontmatter, dict) else None
    if isinstance(name, str) and name.strip():
        return name.strip()
    return skill_dir.name
```

`to` / `transitions` in the body or unused frontmatter keys are ignored (not parsed as a graph).

- [ ] **Step 4: Re-run the test**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: `All workflow tests passed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workflow_resolve.py tests/workflow/test-resolve-workflow.sh
git commit -m "feat(workflow): parse skill frontmatter outcome markers"
```

---

### Task 2: Ordered discovery + first-seen catalog

**Files:**
- Modify: `scripts/lib/workflow_resolve.py`
- Test: `tests/workflow/test-resolve-workflow.sh`

**Interfaces:**
- Consumes: Task 1 helpers; `user_home` for `~`; `os.pathsep` for `SUPERSUIT_SKILL_PATH`
- Produces:
  - `is_regular_skill_md(path: Path) -> bool` — `stat.S_ISREG(path.lstat().st_mode)`
  - `resolve_scan_root(raw: str, *, project_root: Path, user_home: Path) -> Path | None`
  - `catalog_scan_roots(*, plugin_root, project_root, user_home, environ) -> list[Path]`
  - `iter_skill_md_files(root: Path) -> list[Path]`
  - `discover_skill_catalog(*, plugin_root: Path, project_root: Path, user_home: Path, environ: dict[str, str] | None = None) -> dict[str, dict[str, Any]]`
    - values: `{"path": "<abs skill dir>", "outcomes": [str, ...]}`
    - first-seen logical id wins
    - invalid marker: `print(..., file=sys.stderr)` and skip
    - never raises `WorkflowResolveError`

Root order (directory must exist):

1. `plugin_root / "skills"`
2. each `SUPERSUIT_SKILL_PATH` entry (`environ.get("SUPERSUIT_SKILL_PATH")`, split `os.pathsep`, skip blanks)
3. `project_root / ".agents/skills"`, `.claude/skills`, `.opencode/skills`
4. `user_home / ".agents/skills"`, `.claude/skills`, `.config/opencode/skills`

Do **not** append `project_root / "skills"` or `project_root / ".supersuit/skills"` or `user_home / ".supersuit/skills"`.

`iter_skill_md_files`: if `root/SKILL.md` is a regular file, yield only that file (single-skill root). Else iterate children (sorted by name). `child.is_dir()` follows a skill-dir symlink. Require `is_regular_skill_md(child / "SKILL.md")`. Do not recurse.

- [ ] **Step 1: Write the failing catalog tests**

```bash
echo "=== skill catalog discovery order ==="
if python3 - "$REPO_ROOT" "$TEST_ROOT" <<'PY'
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts" / "lib"))
from workflow_resolve import discover_skill_catalog, WorkflowResolveError

repo = Path(sys.argv[1])
base = Path(sys.argv[2]) / "catalog-disc"
plugin = base / "plugin"
project = base / "proj"
home = base / "home"
pack_a = base / "pack-a"
pack_b = base / "pack-b"
proj_skills = project / "skills" / "shadowed"
dot_supersuit = project / ".supersuit" / "skills" / "leaked"

def write_skill(root: Path, dirname: str, name: str, outcomes, body="BODY"):
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
print("ok")
PY
then
  pass "skill catalog discovery order"
else
  fail "skill catalog discovery order"
fi
```

- [ ] **Step 2: Run and confirm RED**

Run: `/bin/bash tests/workflow/test-resolve-workflow.sh`

Expected: fail with `discover_skill_catalog` missing.

- [ ] **Step 3: Implement discovery**

```python
def is_regular_skill_md(path: Path) -> bool:
    try:
        return stat.S_ISREG(path.lstat().st_mode)
    except OSError:
        return False


def resolve_scan_root(
    raw: str, *, project_root: Path, user_home: Path
) -> Path | None:
    text = raw.strip()
    if not text:
        return None
    if text == "~" or text.startswith("~/") or text.startswith("~\\"):
        rest = text[2:] if text != "~" else ""
        expanded = user_home.joinpath(rest) if rest else user_home
    else:
        expanded = Path(text)
        if not expanded.is_absolute():
            expanded = project_root / expanded
    return expanded


def catalog_scan_roots(
    *,
    plugin_root: Path,
    project_root: Path,
    user_home: Path,
    environ: dict[str, str] | None = None,
) -> list[Path]:
    env = environ if environ is not None else os.environ
    roots: list[Path] = [plugin_root / "skills"]
    for part in env.get("SUPERSUIT_SKILL_PATH", "").split(os.pathsep):
        resolved = resolve_scan_root(
            part, project_root=project_root, user_home=user_home
        )
        if resolved is not None:
            roots.append(resolved)
    for rel in (".agents/skills", ".claude/skills", ".opencode/skills"):
        roots.append(project_root / rel)
    for rel in (".agents/skills", ".claude/skills", ".config/opencode/skills"):
        roots.append(user_home / rel)
    return [path for path in roots if path.is_dir()]


def iter_skill_md_files(root: Path) -> list[Path]:
    own = root / "SKILL.md"
    if is_regular_skill_md(own):
        return [own]
    found: list[Path] = []
    try:
        children = sorted(root.iterdir(), key=lambda item: item.name)
    except OSError:
        return []
    for child in children:
        try:
            if not child.is_dir():
                continue
        except OSError:
            continue
        skill_md = child / "SKILL.md"
        if is_regular_skill_md(skill_md):
            found.append(skill_md)
    return found


def discover_skill_catalog(
    *,
    plugin_root: Path,
    project_root: Path,
    user_home: Path,
    environ: dict[str, str] | None = None,
) -> dict[str, dict[str, Any]]:
    catalog: dict[str, dict[str, Any]] = {}
    for root in catalog_scan_roots(
        plugin_root=plugin_root,
        project_root=project_root,
        user_home=user_home,
        environ=environ,
    ):
        for skill_md in iter_skill_md_files(root):
            try:
                text = skill_md.read_text(encoding="utf-8")
            except OSError as exc:
                print(
                    f"warning: skipping unreadable SKILL.md {skill_md}: {exc}",
                    file=sys.stderr,
                )
                continue
            frontmatter = extract_skill_frontmatter(text)
            status, outcomes = classify_skill_marker(frontmatter)
            if status == "absent":
                continue
            if status != "ok" or outcomes is None:
                print(
                    "warning: skipping SKILL.md with invalid "
                    f"metadata.supersuit.outcomes: {skill_md}",
                    file=sys.stderr,
                )
                continue
            logical_id = skill_logical_id(frontmatter, skill_md.parent)
            if logical_id in catalog:
                continue
            catalog[logical_id] = {
                "path": str(skill_md.parent.resolve()),
                "outcomes": list(outcomes),
            }
    return catalog
```

- [ ] **Step 4: Re-run**

Expected: `All workflow tests passed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workflow_resolve.py tests/workflow/test-resolve-workflow.sh
git commit -m "feat(workflow): discover opted-in skills on catalog roots"
```

---

### Task 3: Wire catalog into resolve (identity entries + known_ids)

**Files:**
- Modify: `scripts/lib/workflow_resolve.py` (`validate_workflow`, `apply_capabilities`, `resolve_workflow`)
- Test: `tests/workflow/test-resolve-workflow.sh`

**Interfaces:**
- Consumes: `discover_skill_catalog`
- Produces: resolved `skills.<id>` for cataloged identity entries is `{"path": "<abs>", "outcomes": [...]}`. Cataloged ids are valid `to` targets. Skills without the marker do not appear unless they are already bundled directory names or overlay ids. `resolve_workflow` gains `environ: dict[str, str] | None = None` (CLI continues to use `os.environ`).

```python
def validate_workflow(..., extra_known_ids: set[str] | None = None) -> list[str]:
    known_ids = bundled_skills | set(skills.keys()) | set(extra_known_ids or ())

def apply_capabilities(..., extra_known_ids: set[str] | None = None) -> dict[str, Any]:
    for skill_id in set(bundled_skills) | set(extra_known_ids or ()):
        if skill_id not in skills_out:
            skills_out[skill_id] = {}
    # known_ids for leftover transition check includes extra_known_ids

def attach_catalog_outcomes(
    skills: dict[str, Any],
    catalog: dict[str, dict[str, Any]],
    *,
    project_root: Path,
) -> None:
    """See Task 4 for overlay rules. Task 3 only needs identity / empty."""
```

For Task 3, `attach_catalog_outcomes` may implement only the identity/empty branch plus adding catalog-only keys. Task 4 fills the overlay table.

`main()` / `run_workflow_action` / `run_workflow_exec` call `resolve_workflow` without passing `environ` so the process environment is used.

- [ ] **Step 1: Write failing resolve tests**

```bash
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
# bundled skills without a marker stay identity
assert d["skills"]["brainstorming"]=={} or "run" not in d["skills"]["brainstorming"]
'; then
  pass "resolve catalogs opted-in skills"
else
  fail "resolve catalogs opted-in skills"
fi
```

- [ ] **Step 2: Run RED**

Expected: resolve error `transition to unknown logical id: 'my-review'` and/or missing `my-review` in `skills`.

- [ ] **Step 3: Wire resolve**

In `validate_workflow`, add `extra_known_ids: set[str] | None = None` and union it into `known_ids`.

In `apply_capabilities`, add the same argument; insert `{}` for those ids; include them in the leftover `known_ids` check.

In `resolve_workflow`, accept `environ=None`, build the catalog, pass `extra_known_ids=set(catalog)`, then:

```python
resolved = apply_capabilities(...)
attach_catalog_outcomes(resolved["skills"], catalog, project_root=project_root)
return resolved
```

Identity branch of `attach_catalog_outcomes`:

```python
for skill_id, info in catalog.items():
    if skill_id not in skills:
        skills[skill_id] = {}
for skill_id, entry in list(skills.items()):
    if not isinstance(entry, dict):
        continue
    if "run" in entry:
        continue
    if "path" in entry or "skill" in entry:
        continue  # Task 4
    info = catalog.get(skill_id)
    if info is None:
        continue
    entry["path"] = info["path"]
    entry["outcomes"] = list(info["outcomes"])
```

- [ ] **Step 4: Re-run**

Expected: new test passes; existing resolve tests still see bundled skills as `{}` (no bundled markers).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workflow_resolve.py tests/workflow/test-resolve-workflow.sh
git commit -m "feat(workflow): attach cataloged skill path and outcomes"
```

---

### Task 4: Overlay attachment + invalid marker does not fail resolve

**Files:**
- Modify: `scripts/lib/workflow_resolve.py` (`attach_catalog_outcomes` + path re-read)
- Test: `tests/workflow/test-resolve-workflow.sh`

**Interfaces:**
- Consumes: Task 1–3
- Produces: overlay table from the spec

| Winning entry | SKILL.md | If missing / not cataloged / invalid marker |
|---------------|----------|---------------------------------------------|
| `path` set (path wins if `skill` also set) | that directory’s `SKILL.md` | omit `outcomes` |
| `{ skill: other-name }` and no `path` | catalog of `other-name` | omit `outcomes` |
| `run` / `exec` | none | do not attach skill-frontmatter `outcomes` |
| identity / empty | first-seen catalog for this id | omit `outcomes`; do not add a catalog-only entry without a valid marker |

Helper for path re-read (do not use a shadowed catalog hit for the overlay id):

```python
def outcomes_from_skill_dir(skill_dir: Path) -> list[str] | None:
    skill_md = skill_dir / "SKILL.md"
    if not is_regular_skill_md(skill_md):
        return None
    try:
        frontmatter = extract_skill_frontmatter(skill_md.read_text(encoding="utf-8"))
    except OSError:
        return None
    status, outcomes = classify_skill_marker(frontmatter)
    if status == "invalid":
        print(
            "warning: skipping SKILL.md with invalid "
            f"metadata.supersuit.outcomes: {skill_md}",
            file=sys.stderr,
        )
        return None
    if status != "ok":
        return None
    return list(outcomes)
```

- [ ] **Step 1: Write failing tests**

```bash
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
# Reuse $PROJ/scripts/ensure-fixture.sh from earlier in this file; recreate if needed.
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
```

- [ ] **Step 2: Run RED**

Expected: alias test fails (`outcomes` missing on `review`); invalid-marker test may already pass if Task 2 warns; path-win still has first-seen outcomes.

- [ ] **Step 3: Finish `attach_catalog_outcomes`**

```python
def attach_catalog_outcomes(
    skills: dict[str, Any],
    catalog: dict[str, dict[str, Any]],
    *,
    project_root: Path,
) -> None:
    for skill_id, info in catalog.items():
        if skill_id not in skills:
            skills[skill_id] = {}
    for skill_id, entry in list(skills.items()):
        if not isinstance(entry, dict):
            continue
        if "run" in entry:
            continue
        if "path" in entry:
            path_value = entry.get("path")
            if isinstance(path_value, str) and path_value.strip():
                outcomes = outcomes_from_skill_dir(
                    _resolve_skill_path(path_value, project_root)
                )
                if outcomes:
                    entry["outcomes"] = outcomes
            continue
        if "skill" in entry:
            alias = entry.get("skill")
            info = catalog.get(alias) if isinstance(alias, str) else None
            if info:
                entry["outcomes"] = list(info["outcomes"])
            continue
        info = catalog.get(skill_id)
        if info:
            entry["path"] = info["path"]
            entry["outcomes"] = list(info["outcomes"])
```

- [ ] **Step 4: Re-run**

Expected: all four new tests pass; no `WorkflowResolveError` from the empty-outcomes fixture.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workflow_resolve.py tests/workflow/test-resolve-workflow.sh
git commit -m "feat(workflow): attach overlay catalog outcomes without failing resolve"
```

---

### Task 5: SessionStart does not inject a foreign skill body

**Files:**
- Test: `tests/hooks/test-session-start.sh`
- Production: no hook change unless a test proves leakage (spec: keep `hooks/session-start` as using-superpowers + `WORKFLOW_MAP` only)

**Interfaces:**
- Consumes: Task 3 resolve output (compact `outcomes` in JSON is allowed)
- Produces: assertion that a distinctive foreign body string is absent from injected context

- [ ] **Step 1: Write the failing (or characterizing) fixture**

After the existing workflow-map injection tests in `tests/hooks/test-session-start.sh`:

```bash
echo "SessionStart does not inject cataloged foreign skill bodies"

foreign_proj="$TEST_ROOT/foreign-catalog-proj"
foreign_pack="$TEST_ROOT/foreign-catalog-pack/unique-review"
mkdir -p "$foreign_proj" "$foreign_pack"
cat > "$foreign_pack/SKILL.md" <<'EOF'
---
name: unique-review
metadata:
  supersuit:
    outcomes:
      - approved
---
UNIQUE_FOREIGN_SKILL_BODY_TOKEN
EOF
foreign_home="$(make_home foreign-catalog)"
assert_command_output \
    "SessionStart catalog JSON has outcomes but not the foreign SKILL.md body" \
    "cursor" \
    "WORKFLOW_MAP"$'\037'"unique-review"$'\037'"\"outcomes\": [\"approved\"]" \
    "UNIQUE_FOREIGN_SKILL_BODY_TOKEN" \
    "$foreign_home" \
    CURSOR_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    SUPERSUIT_SKILL_PATH="$(dirname "$foreign_pack")" \
    bash -c "cd \"$foreign_proj\" && bash \"$HOOK_UNDER_TEST\""
```

`assert_command_output` already runs `env -i PATH=... HOME="$home" "$@"`. The hook uses `PWD` as `--project-root` and `HOME` as `--user-home`. `SUPERSUIT_SKILL_PATH` must be in that `env -i` invocation — pass it as an env assignment before `bash` like the other tests.

If `assert_command_output` cannot `cd`, use the same `cd "$foreign_proj" && env -i ...` pattern as the invalid-overlay test, and assert with a small node snippet: context contains `WORKFLOW_MAP` and `unique-review` / `approved`, and does not contain `UNIQUE_FOREIGN_SKILL_BODY_TOKEN`.

- [ ] **Step 2: Run**

Run: `/bin/bash tests/hooks/test-session-start.sh`

Expected: if resolve is wired, this should **pass** without hook edits (catalog JSON only). If it fails because `assert_command_output` does not `cd` into `foreign_proj`, fix the test harness invocation, not the hook. Do not add a second catalog block or `cat` a foreign `SKILL.md` in `hooks/session-start`.

- [ ] **Step 3: Commit**

```bash
git add tests/hooks/test-session-start.sh
git commit -m "test(hooks): SessionStart omits cataloged foreign skill bodies"
```

---

### Task 6: Docs — workflow-config + author note

**Files:**
- Modify: `docs/workflow-config.md`
- Do **not** edit `skills/writing-skills/SKILL.md` (skill-prose changes need evals; this PR is resolver + docs).

**Interfaces:**
- Consumes: spec glossary
- Produces: a short section authors can follow

- [ ] **Step 1: Add the spec link under Design specs**

In the existing list at the top of `docs/workflow-config.md`, add:

```markdown
- [Skill outcome catalog](superpowers/specs/2026-08-23-skill-outcome-catalog-design.md)
```

- [ ] **Step 2: Add a section before Validation** (after the “clear a user override” example)

```markdown
## Skill outcome catalog

Standalone skills (a pack on `SUPERSUIT_SKILL_PATH`, or a skill already in a
harness table dir) can **opt in** so the resolver lists them and copies the
labels they emit. This is **not** `skills.<id>.run.outcomes` (exit-code →
label for a deterministic action). Do not mix the two.

### Author opt-in

In `SKILL.md` frontmatter only:

```yaml
---
name: my-review
description: Use when a human asks for a structured review.
metadata:
  supersuit:
    outcomes:
      - approved
      - changes-requested
      - skip
---
```

Rules:

- `metadata.supersuit` must be a mapping. `outcomes` must be a non-empty list
  of non-empty strings. Duplicates collapse, first-seen order kept.
- Do not put `to`, `transitions`, or a graph in frontmatter. The overlay owns
  `(from, on, to)`. Unmapped outcomes stay `wait`.
- Keep frontmatter `name` equal to the skill directory name. The catalog key
  is `name` (else the directory); the harness Skill tool still uses the
  directory name.
- A missing `metadata.supersuit` is an ordinary skill (not cataloged). An
  invalid marker is warned and skipped; resolve continues.

### Where skills are found

Scan order, first-seen logical id wins. A root is `<root>/<id>/SKILL.md`, or
a path that itself contains `SKILL.md`.

1. This plugin’s `skills/`
2. `SUPERSUIT_SKILL_PATH` — platform pathsep (`:` on Unix, `;` on Windows;
   Python `os.pathsep`). `~` expands; relative entries are from the project
   root. Preferred way to add a checkout of `jamesthomasonjr/skills` or
   another pack.
3. Project: `.agents/skills`, `.claude/skills`, `.opencode/skills`
4. User: `~/.agents/skills`, `~/.claude/skills`, `~/.config/opencode/skills`

Not scanned unless listed on `SUPERSUIT_SKILL_PATH`: project-root `skills/`,
`.supersuit/skills`, plugin caches, `node_modules`. Do not invent a
`.supersuit/skills` install home.

Resolved identity entries gain compact `path` + `outcomes`. Overlay
`{ skill: other-name }` copies that other skill’s cataloged outcomes when
present. `run` / `exec` entries keep only `run.outcomes`. SessionStart still
injects `using-superpowers` and `WORKFLOW_MAP` only — not foreign skill
bodies.
```

- [ ] **Step 3: Cross-link from Deterministic run / exec actions**

After the `outcomes:` mapping in that section, add one sentence:

```markdown
`run.outcomes` maps process exit codes to labels. It is not the skill
frontmatter list under `metadata.supersuit.outcomes` (see
[Skill outcome catalog](#skill-outcome-catalog)).
```

- [ ] **Step 4: Commit**

```bash
git add docs/workflow-config.md
git commit -m "docs: skill outcome catalog author and discovery notes"
```

---

## Self-review

**1. Spec coverage**

| Spec requirement | Task |
|------------------|------|
| Opt-in `metadata.supersuit.outcomes` | 1 |
| Frontmatter only; no body parse; no `to` graph | 1 |
| Logical id = `name` else directory | 1, 2 |
| Discovery order + `os.pathsep` + `~` / relative | 2 |
| Do not scan `.supersuit/skills` or project `skills/` unless env-listed | 2, 3 |
| Follow skill-dir symlinks; skip non-regular `SKILL.md` | 2 |
| First-seen wins | 2 |
| Catalog attach `path` + `outcomes` on identity | 3 |
| Cataloged ids join `known_ids` | 3 |
| Invalid marker warn + skip; no `WorkflowResolveError` | 2, 4 |
| `{ skill: other-name }` attach / omit | 4 |
| `path` wins for which `SKILL.md` is read | 4 |
| `run`/`exec` get no frontmatter outcomes | 4 |
| Unmapped stays `wait`; overlay owns transitions | unchanged; 3 uses existing validate |
| SessionStart no foreign body | 5 |
| Docs + glossary cross-link | 6 |
| No default.yaml `run` keys; no version bump; no evals | constraints |
| No strict mode | constraints |

**2. Placeholder scan:** none. Helper names are locked here so tasks agree; they are not in the spec and may be renamed if a test still covers the behavior.

**3. Type consistency:** `discover_skill_catalog` → `dict[str, dict[str, Any]]` with `path: str` and `outcomes: list[str]`. `classify_skill_marker` → `("absent"|"invalid"|"ok", list[str]|None)`. `extra_known_ids: set[str] | None` on both `validate_workflow` and `apply_capabilities`.
