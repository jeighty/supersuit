# Skill Outcome Catalog — Design Spec

**Status:** Approved design (2026-08-23). JT directed the revisions in this file. Implementation waits on this spec.
**Product:** Supersuit (`jeighty/supersuit`).
**Depends on:** Configurable workflow graph; capability overlays. Does not depend on #21 or PR #23 merging.
**Does not implement:** Per-skill default workflow JSON; merging many full graphs; a `.supersuit/skills` install home; injecting foreign SKILL.md bodies into SessionStart.

A draft pull request for this spec is process (review and landing), not a contradiction of the approved-design status.

## Problem

Standalone skills (a public repo such as `jamesthomasonjr/skills`, a private pack, a plugin that installs extra skills) should be able to emit Supersuit-style outcomes and show up in the resolved map without packaging a workflow overlay.

Today the resolver only lists bundled skill *directory names*. It never reads `SKILL.md`. Unmapped `(from, on)` is already `wait`. There is no catalog of what outcomes a foreign skill declares, and no discovery of skills the harness already loaded outside this plugin.

Shipping a default `workflow.yaml` per skill is the wrong fix: ungated overlays replace every edge for that `from`, so many “default graphs” last-writer-win.

## Goals

| Priority | Goal |
|----------|------|
| Primary | A skill opts in by listing outcomes in frontmatter. The resolver catalogs those skills. |
| Discovery | Find opted-in `SKILL.md` files on `SUPERSUIT_SKILL_PATH` plus a small table of dirs harnesses already use. |
| Safety | Catalog, not inject. No extra skill prose in SessionStart. `to` is allowed only inside `metadata.supersuit.next`. |
| Callable | Skills stay where the harness already loads them. Do not invent `.supersuit/skills`. |

## Non-goals

- Per-skill default workflow JSON or soft `approved: writing-plans` defaults on the skill.
- Walking plugin caches, `node_modules`, or inferring capabilities from product names / skill paths.
- A “list loaded skills” RPC. Almost no Shape A host exposes one; in-process hosts pass paths instead.
- Making `.supersuit/skills` a harness skill root.
- Changing bundled capability overlay YAML shape or adding `run` keys on cataloged identity skills. Superpowers hops live on `SKILL.md` `next` — see [skill-default hops](2026-08-23-skill-default-hops-design.md).
- Rewriting skill bodies or Red Flags tables.
- Auto-wiring discovered skills into the Superpowers pipeline.

## Glossary

These two `outcomes` fields are different. Do not mix them.

| Term | Where | Meaning |
|------|--------|---------|
| Skill frontmatter `outcomes` | `SKILL.md` YAML: `metadata.supersuit.outcomes` | Completion **labels the skill emits** when it finishes (for example `approved`, `changes-requested`). The catalog copies this list onto the resolved registry entry. Optional `next` may name `to` for edges **from this skill only** — see [skill-default hops](2026-08-23-skill-default-hops-design.md). |
| `skills.<id>.run.outcomes` | Overlay / registry `run` / `exec` block | **Exit-code → label** for a deterministic action. Keys are exit codes (`0`, other integers) or `nonzero`. Defaults: `0 → complete`, `nonzero → failed`. See [workflow-config.md](../../workflow-config.md) (Deterministic run / exec actions) and [run/exec design](2026-08-17-workflow-run-actions-design.md). |

A `run` / `exec` registry entry has no `SKILL.md`. Do not attach skill-frontmatter `outcomes` to it. Its labels come only from `run.outcomes`.

## Design decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Opt-in marker is YAML frontmatter `metadata.supersuit.outcomes` (non-empty list of non-empty strings). | Extra keys at the top level can collide with harness frontmatter. `metadata` is the reserved pocket. No marker → not a catalog skill. |
| 2 | `to` is allowed **only** inside `metadata.supersuit.next` values. No `transitions:` list on the skill. No graph of other skills’ edges. | Narrowed by [skill-default hops](2026-08-23-skill-default-hops-design.md) Decision #5. Per-`(from, on)` merge removed the replace-by-`from` reason for a total forbid. |
| 3 | Logical id is frontmatter `name` if present, else the parent directory name. Do not invent a new id scheme. Harness Skill-tool invocation uses the directory name. Authors SHOULD keep `name` equal to the directory name. | Matches how harnesses label the skill. If `name` and the directory diverge, overlays can target the logical id while the Skill tool only finds the directory. |
| 4 | Unmapped `(from, on)` stays `wait`. | Already the rule; catalog does not invent edges. |
| 5 | Discovery is path-based. First-seen logical id wins. User/project workflow remaps still override registry entries. | No harness API required for the first cut. |
| 6 | Do not create or scan `.supersuit/skills`. | Harnesses do not load that directory. A second tree is copy/symlink overhead and skills the Skill tool cannot see. `.supersuit/` stays config + scratch. |
| 7 | SessionStart does not inject discovered SKILL.md bodies. At most, compact `outcomes: [...]` on registry entries already in `WORKFLOW_MAP` JSON. | Context stays the bootstrap + map. Harnesses often strip frontmatter before the model sees a skill anyway. |
| 8 | Only read the YAML frontmatter block (first `---` … `---` ). Do not parse the skill body. | Cheap, no prompt-sized I/O. |
| 9 | A malformed or invalid `metadata.supersuit.outcomes` on a candidate `SKILL.md` must **not** raise a global `WorkflowResolveError`. Default v1: **warn and skip that file** (do not catalog it; continue resolve). Missing `metadata.supersuit` is a silent skip. A later optional strict mode MAY fail closed; v1 default is skip. | One broken third-party skill in a user dir must not brick SessionStart for every project. Fail-closed is reserved for an opt-in strict mode. |

## Marker

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

`metadata.supersuit` must be a mapping. `outcomes` must be a list of non-empty strings. Duplicates in one list are collapsed, first-seen order kept.

This list is **skill frontmatter `outcomes`** (labels the skill emits). It is not `skills.<id>.run.outcomes` (see [Glossary](#glossary)).

### Invalid marker (Decision #9)

A file is a **candidate** when discovery selected it as a `SKILL.md` under a scanned root.

| Frontmatter | Default v1 |
|-------------|------------|
| No `metadata.supersuit` | Silent skip. Ordinary skill. Not cataloged. |
| `metadata.supersuit` present but `outcomes` missing, wrong type, empty list, empty strings, or `supersuit` is not a mapping | **Warn** (stderr is fine) **and skip that file**. Do not catalog it. Do **not** raise `WorkflowResolveError`. Continue resolve. |
| Valid non-empty `outcomes` list | Catalog it. |

Optional later: a strict mode MAY treat an invalid marker as a resolve error (fail closed). Default v1 does not enable that. Implementers must not make global fail-closed the v1 default.

Bundled Superpowers pipeline skills now carry the same marker plus optional `next` — see [skill-default hops](2026-08-23-skill-default-hops-design.md). Other bundled skills stay description-triggered and are not required in resolved `skills`.

## Identity (logical id vs invocation)

Do not invent a new id scheme.

| Role | Value |
|------|--------|
| **Logical id** (catalog key, overlay `from` / `to`, registry key) | Frontmatter `name` if present and non-empty, else the parent directory name. |
| **Harness Skill-tool invocation** | The **directory name** (for example `supersuit:review-changes` when the folder is `review-changes`). |

Authors **SHOULD** keep frontmatter `name` equal to the parent directory name.

If they diverge, an overlay can target `my-review` in transitions while the Skill tool only finds `review-changes`. The catalog will not rewrite either name to paper over that. Authors who need both must keep them aligned, or remap with an overlay `path` / `skill` entry they understand.

## Discovery order

A **root** is a directory that contains skill folders (`<root>/<id>/SKILL.md`). A path that itself is a skill directory (`<path>/SKILL.md`) is also a root of one.

Scan in this order. First-seen logical id wins; later hits are ignored (not an error). Each table path is used only if it is a directory.

1. **This plugin’s `skills/`** — `plugin_root/skills/*/SKILL.md` (today’s `discover_known_skills`, plus frontmatter when present).
2. **`SUPERSUIT_SKILL_PATH`** — host-supplied extra roots. This is the **preferred** way to add a pack (a checkout of `jamesthomasonjr/skills`, a CI fixture, Shape B plugin dirs). Empty or unset is fine.
3. **Project table:**
   - `<project_root>/.agents/skills`
   - `<project_root>/.claude/skills`
   - `<project_root>/.opencode/skills` — OpenCode project skills; this repo already tests that path (`tests/opencode/`).
4. **User table:**
   - `~/.agents/skills` — Codex / Copilot CLI / Gemini cross-runtime user root (this repo documents it as the shared alias; Codex moved off `~/.codex/skills`).
   - `~/.claude/skills`
   - `~/.config/opencode/skills`

`~/.agents/skills` is listed first in the user table so a skill that exists in both the cross-runtime root and `~/.claude/skills` catalogs from `.agents` (first-seen wins). That matches the harness note that `.agents/skills` takes precedence when both exist at the same scope.

### `SUPERSUIT_SKILL_PATH` separator

Split the env var with the **platform path separator**, same idea as `PATH`:

| Platform | Separator | Example |
|----------|-----------|---------|
| Unix / macOS | `:` (colon) | `/packs/skills:~/.extra/skills` |
| Windows | `;` (semicolon) | `C:\packs\skills;%USERPROFILE%\.extra\skills` |

In Python this is `os.pathsep`. Do not hard-code colon.

`~` is expanded. Relative entries are resolved from `project_root`. A Shape B plugin (OpenCode, Pi, …) that already registered skill dirs may append those absolute paths via this env var, or a later `--skill-path` CLI flag on `resolve-workflow`. Do not infer them from `CURSOR_PLUGIN_ROOT` / `CLAUDE_PLUGIN_ROOT`.

### Do not scan

Do **not** scan: plugin caches, `node_modules`, `.supersuit/skills`, product-named capability claims, or a project-root `skills/` unless that path was listed in `SUPERSUIT_SKILL_PATH`. A checkout of `jamesthomasonjr/skills` is added by putting its `skills/` on the env var or installing those skills into a table dir the harness already uses.

Symlinks: follow a skill dir symlink; do not recurse into arbitrary trees. Skip non-regular `SKILL.md` (same rule as the migration rewriter).

## Resolved map

For each cataloged skill, the registry entry (if still identity / empty) gains:

```json
{
  "path": "/abs/path/to/skill-dir",
  "outcomes": ["approved", "changes-requested", "skip"]
}
```

`outcomes` here is the skill-frontmatter list (labels the skill emits), not `run.outcomes`.

### Overlay remaps and `outcomes` attachment

If a higher-precedence overlay already set `path`, `skill`, or `run`/`exec` for that id, keep that entry. Attach skill-frontmatter `outcomes` using the **winning SKILL.md**, not a shadowed earlier discovery hit.

| Winning overlay entry | Which `SKILL.md` to read | If that file is missing, not cataloged, or has no valid marker |
|-----------------------|--------------------------|----------------------------------------------------------------|
| `path` is set | The `path` directory’s `SKILL.md`. If `skill` is also set, **`path` wins**. | Omit `outcomes`. |
| `{ skill: other-name }` and no `path` | The aliased skill’s `SKILL.md` — the skill **named in `skill:`**, using the same catalog rules (valid `metadata.supersuit.outcomes` on that skill). | Omit `outcomes`. |
| `run` / `exec` | None. | Do not attach skill-frontmatter `outcomes`. |
| Identity / empty | The first-seen discovered `SKILL.md` for this logical id. | Omit `outcomes` (and do not add a catalog-only entry if there is no valid marker). |

`{ skill: other-name }` with no `path` therefore copies `outcomes` from the aliased skill when that skill was cataloged with a valid marker. It does not re-read a shadowed path for the overlay’s own logical id, and it does not invent outcomes.

Today’s resolver still rejects combining `skill`, `path`, and `run`/`exec` on one entry. If both `skill` and `path` are ever present, this catalog rule is: **`path` wins for which `SKILL.md` is read.**

`transitions` are unchanged. Overlay YAML remains the only way to add `(from, on, to)`.

Validation: `to` must still be a known logical id, `null`, or `wait`. Cataloged ids join `known_ids` the way bundled directory names do today, so an overlay may target a discovered skill without a stub `skills:` entry.

## SessionStart / context

`hooks/session-start` keeps injecting `using-superpowers` + `WORKFLOW_MAP` JSON only. No second catalog block. No discovered skill bodies. Agents load a foreign skill through the harness Skill tool or by reading that `path` when the map says to.

## Harness / agent impact

- **Harnesses:** unknown `metadata` keys are ignored. Skills remain callable only where the harness already discovers them.
- **Agents:** frontmatter is often stripped before the model sees `SKILL.md`. Outcomes in the map are for the resolver and for `(from, on)` lookup after the skill emits one.
- **Context:** a few tokens per cataloged skill on entries already in the JSON. Not a new SessionStart document.
- **Capabilities:** scanning `~/.claude/skills` or `~/.agents/skills` does not advertise `session-inject` or any other token.

## Success criteria

- A skill with a valid marker under `SUPERSUIT_SKILL_PATH` or a table dir (including `~/.agents/skills` and `<project_root>/.opencode/skills`) appears in resolved `skills` with `outcomes` and `path`.
- A skill without the marker in those dirs does not appear (unless it is already a bundled / overlay id).
- A candidate `SKILL.md` with a malformed or invalid `metadata.supersuit.outcomes` is skipped (warned, not cataloged). Resolve **continues**. Default v1 does **not** raise a global `WorkflowResolveError` for that file.
- Overlay `{ skill: other-name }` with no `path` attaches `outcomes` from the aliased skill when that skill is cataloged with a valid marker; otherwise omits `outcomes`.
- Overlays and skill-default `next` may add transitions. Emitting an undeclared or unmapped outcome is `wait`.
- SessionStart payload does not contain that skill’s body.
- Resolve does not read `.supersuit/skills` unless someone put that path on `SUPERSUIT_SKILL_PATH`.
- Project-root `skills/` is not scanned unless listed on `SUPERSUIT_SKILL_PATH`.
- Capability overlays stay in `workflows/overlays/*.yaml`. Cataloged identity skills have no `run` keys.

## Alternatives considered

| Approach | Why not |
|----------|---------|
| Each skill ships a default `workflow.yaml` | Ungated replace-by-`from`; last writer wins. |
| Soft `to` defaults on the skill | Hidden merge of next hops; two skills can claim the same edge. |
| `.supersuit/skills` as the install home | Harnesses do not load it; duplicate tree. |
| Scan every harness plugin cache | Noisy, product-specific, not a SessionStart API. |
| Env-only, no path table | Builders must set env before any public pack is visible. Table dirs are ones they already use. |
| Inject all catalog SKILL.md at SessionStart | Context cost; harness already loads on invoke. |
| Global `WorkflowResolveError` on invalid marker | One broken file in `~/.claude/skills` or `~/.agents/skills` would fail SessionStart for every project. Default v1 skips. |

## Implementation notes (not this PR)

Implementation is a later PR against `dev`:

- Teach `scripts/lib/workflow_resolve.py` to walk the roots, parse frontmatter, and attach `outcomes` / `path`.
- Split `SUPERSUIT_SKILL_PATH` with `os.pathsep` (colon on Unix, semicolon on Windows).
- Tests: marker present / absent; first-seen wins; `SUPERSUIT_SKILL_PATH`; skip project `skills/` unless listed; invalid marker **warns and skips** (resolve still succeeds); `{ skill: other-name }` attaches aliased outcomes or omits them; SessionStart fixture does not include a foreign body.
- Docs: `docs/workflow-config.md` plus a short note for skill authors (`jamesthomasonjr/skills` and third-party plugins). Cross-link skill frontmatter `outcomes` vs `skills.<id>.run.outcomes` so authors do not mix them.
