# Skill Outcome Catalog — Design Spec

**Status:** Approved design (2026-08-23). Implementation waits on review of this spec.
**Product:** Supersuit (`jeighty/supersuit`).
**Depends on:** Configurable workflow graph; capability overlays. Does not depend on #21 or PR #23 merging.
**Does not implement:** Per-skill default workflow JSON; merging many full graphs; a `.supersuit/skills` install home; injecting foreign SKILL.md bodies into SessionStart.

## Problem

Standalone skills (a public repo such as `jamesthomasonjr/skills`, a private pack, a plugin that installs extra skills) should be able to emit Supersuit-style outcomes and show up in the resolved map without packaging a workflow overlay.

Today the resolver only lists bundled skill *directory names*. It never reads `SKILL.md`. Unmapped `(from, on)` is already `wait`. There is no catalog of what outcomes a foreign skill declares, and no discovery of skills the harness already loaded outside this plugin.

Shipping a default `workflow.yaml` per skill is the wrong fix: ungated overlays replace every edge for that `from`, so many “default graphs” last-writer-win.

## Goals

| Priority | Goal |
|----------|------|
| Primary | A skill opts in by listing outcomes in frontmatter. The resolver catalogs those skills. |
| Discovery | Find opted-in `SKILL.md` files on `SUPERSUIT_SKILL_PATH` plus a small table of dirs harnesses already use. |
| Safety | Catalog, not inject. No extra skill prose in SessionStart. No `to` pointers in frontmatter. |
| Callable | Skills stay where the harness already loads them. Do not invent `.supersuit/skills`. |

## Non-goals

- Per-skill default workflow JSON or soft `approved: writing-plans` defaults on the skill.
- Walking plugin caches, `node_modules`, or inferring capabilities from product names / skill paths.
- A “list loaded skills” RPC. Almost no Shape A host exposes one; in-process hosts pass paths instead.
- Making `.supersuit/skills` a harness skill root.
- Changing `workflows/default.yaml` shape or adding `run` keys there.
- Rewriting skill bodies or Red Flags tables.
- Auto-wiring discovered skills into the Superpowers pipeline.

## Design decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Opt-in marker is YAML frontmatter `metadata.supersuit.outcomes` (non-empty list of non-empty strings). | Extra keys at the top level can collide with harness frontmatter. `metadata` is the reserved pocket. No marker → not a catalog skill. |
| 2 | Frontmatter must not contain `to`, `transitions`, or a graph. | Skills emit outcomes; the map / overlay picks `to`. |
| 3 | Logical id is frontmatter `name` if present, else the parent directory name. | Matches how harnesses label the skill. |
| 4 | Unmapped `(from, on)` stays `wait`. | Already the rule; catalog does not invent edges. |
| 5 | Discovery is path-based. First-seen logical id wins. User/project workflow remaps still override registry entries. | No harness API required for the first cut. |
| 6 | Do not create or scan `.supersuit/skills`. | Harnesses do not load that directory. A second tree is copy/symlink overhead and skills the Skill tool cannot see. `.supersuit/` stays config + scratch. |
| 7 | SessionStart does not inject discovered SKILL.md bodies. At most, compact `outcomes: [...]` on registry entries already in `WORKFLOW_MAP` JSON. | Context stays the bootstrap + map. Harnesses often strip frontmatter before the model sees a skill anyway. |
| 8 | Only read the YAML frontmatter block (first `---` … `---` ). Do not parse the skill body. | Cheap, no prompt-sized I/O. |
| 9 | Invalid marker (wrong type, empty list) is a resolve error for that file, not a silent skip, once the file was selected as a candidate `SKILL.md`. Missing `metadata.supersuit` is a skip. | Fail closed on a claimed catalog skill; ignore ordinary skills. |

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

Bundled Supersuit skills may grow the same marker in a later implementation PR so the catalog is one mechanism. That is not required to land discovery for foreign skills.

## Discovery order

A **root** is a directory that contains skill folders (`<root>/<id>/SKILL.md`). A path that itself is a skill directory (`<path>/SKILL.md`) is also a root of one.

Scan in this order. First-seen logical id wins; later hits are ignored (not an error).

1. **This plugin’s `skills/`** — `plugin_root/skills/*/SKILL.md` (today’s `discover_known_skills`, plus frontmatter when present).
2. **`SUPERSUIT_SKILL_PATH`** — colon-separated extra roots (empty or unset is fine). `~` is expanded. Relative entries are resolved from `project_root`.
3. **Project table** (each only if it is a directory):
   - `<project_root>/.agents/skills`
   - `<project_root>/.claude/skills`
4. **User table** (each only if it is a directory):
   - `~/.claude/skills`
   - `~/.config/opencode/skills`
5. **Host-passed roots** — optional. A Shape B plugin (OpenCode, Pi, …) that already registered skill dirs may append those absolute paths via the same env var, or a later `--skill-path` CLI flag on `resolve-workflow`. Do not infer them from `CURSOR_PLUGIN_ROOT` / `CLAUDE_PLUGIN_ROOT`.

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

If a higher-precedence overlay already set `path`, `skill`, or `run`/`exec` for that id, keep that entry and attach `outcomes` when the marker was read from the *winning* `SKILL.md` (the remapped path, not a shadowed earlier hit).

`transitions` are unchanged. Overlay YAML remains the only way to add `(from, on, to)`.

Validation: `to` must still be a known logical id, `null`, or `wait`. Cataloged ids join `known_ids` the way bundled directory names do today, so an overlay may target a discovered skill without a stub `skills:` entry.

## SessionStart / context

`hooks/session-start` keeps injecting `using-superpowers` + `WORKFLOW_MAP` JSON only. No second catalog block. No discovered skill bodies. Agents load a foreign skill through the harness Skill tool or by reading that `path` when the map says to.

## Harness / agent impact

- **Harnesses:** unknown `metadata` keys are ignored. Skills remain callable only where the harness already discovers them.
- **Agents:** frontmatter is often stripped before the model sees `SKILL.md`. Outcomes in the map are for the resolver and for `(from, on)` lookup after the skill emits one.
- **Context:** a few tokens per cataloged skill on entries already in the JSON. Not a new SessionStart document.
- **Capabilities:** scanning `~/.claude/skills` does not advertise `session-inject` or any other token.

## Success criteria

- A skill with the marker under `SUPERSUIT_SKILL_PATH` or a table dir appears in resolved `skills` with `outcomes` and `path`.
- A skill without the marker in those dirs does not appear (unless it is already a bundled / overlay id).
- No new transitions unless an overlay added them. Emitting an undeclared or unmapped outcome is `wait`.
- SessionStart payload does not contain that skill’s body.
- Resolve does not read `.supersuit/skills` unless someone put that path on `SUPERSUIT_SKILL_PATH`.
- `workflows/default.yaml` stays ungated and free of `run` keys.

## Alternatives considered

| Approach | Why not |
|----------|---------|
| Each skill ships a default `workflow.yaml` | Ungated replace-by-`from`; last writer wins. |
| Soft `to` defaults on the skill | Hidden merge of next hops; two skills can claim the same edge. |
| `.supersuit/skills` as the install home | Harnesses do not load it; duplicate tree. |
| Scan every harness plugin cache | Noisy, product-specific, not a SessionStart API. |
| Env-only, no path table | Builders must set env before any public pack is visible. Table dirs are ones they already use. |
| Inject all catalog SKILL.md at SessionStart | Context cost; harness already loads on invoke. |

## Implementation notes (not this PR)

Implementation is a later PR against `dev`:

- Teach `scripts/lib/workflow_resolve.py` to walk the roots, parse frontmatter, and attach `outcomes` / `path`.
- Tests: marker present / absent; first-seen wins; `SUPERSUIT_SKILL_PATH`; skip project `skills/` unless listed; invalid marker fails; SessionStart fixture does not include a foreign body.
- Docs: `docs/workflow-config.md` plus a short note for skill authors (`jamesthomasonjr/skills` and third-party plugins).
