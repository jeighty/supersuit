# Skill-Default Hops — Design Spec

**Status:** Approved design (2026-08-23). JT directed this locked B cut. JT accepted the thin-registry and replace-one-hop clarifications (2026-08-24). Implementation waits on this spec.
**Product:** Supersuit (`jeighty/supersuit`). Superpowers skills stay bundled in this repo (B now).
**Depends on:** Configurable workflow graph; capability overlays; skill outcome catalog ([2026-08-23-skill-outcome-catalog-design.md](2026-08-23-skill-outcome-catalog-design.md)).
**Does not implement:** Resolver changes; SKILL.md `outcomes` / `next` bodies; deleting `workflows/default.yaml`; deleting `entries`; overlay merge code; a `supersuit-superpowers` extract; `disable-model-invocation`.

A draft pull request for this spec is process (review and landing), not a contradiction of the approved-design status.

## Problem

The catalog lets a skill declare the outcomes it emits. It still forbids `to` in frontmatter. The Superpowers pipeline hops therefore live in `workflows/default.yaml` as a second source of truth.

That file has two costs:

1. **Replace-by-`from`.** An ungated overlay that overrides one brainstorming hop must re-list every other brainstorming hop, or those skill-default edges disappear.
2. **A graph that is not the skill.** Authors who already list outcomes on `SKILL.md` still have to edit plugin YAML (or ship an overlay) to name the next hop from *this* skill.

`entries` (`creative-work`, `bugfix`) was meant to disambiguate starts. Starts are already description-driven plus `using-superpowers` Skill Priority prose. The field is unused as a start mechanism, unreleased, and has no adoption.

## Goals

| Priority | Goal |
|----------|------|
| Primary | A cataloged skill may declare *outgoing* hops from itself in frontmatter. The resolver materializes those hops as ungated transitions. |
| Merge | User/project overlays win per `(from, on)` only. Other skill-default hops for that `from` stay. Gated overlay transitions stay appended; most-specific satisfied `when` still wins at resolve. |
| Baseline | Delete `workflows/default.yaml`. Bundled Superpowers hops move onto the relevant `SKILL.md` files. Resolver bundled YAML base is empty. |
| Schema | Delete `entries`. No compatibility shim. Starts stay description-driven plus Skill Priority. |
| Safety | Catalog discovery, invalid-marker warn+skip, no `.supersuit/skills` home, and SessionStart (`using-superpowers` + `WORKFLOW_MAP` only) stay as the catalog spec locked them. |

## Non-goals

- Extracting `supersuit-superpowers` (cut A). Parked: JT will research whether a monorepo with sibling dirs is possible. This spec does not design a split, a second plugin, or sibling-directory layout.
- `disable-model-invocation` work of any kind.
- Moving capability overlays onto skill frontmatter. They remain `workflows/overlays/*.yaml`.
- A `transitions:` list on the skill, or any graph of *other* skills’ edges.
- Changing catalog discovery order, first-seen identity, invalid-`outcomes` warn+skip, or SessionStart payload shape.
- Rewriting skill-body Red Flags tables or “human partner” language in this cut.
- Keeping `workflows/default.yaml` as a fallback if catalog hops are missing.
- A compatibility shim for `entries`.
- Re-seeding empty identity stubs so every bundled skill appears in resolved `skills`.
- Forcing `outcomes` (with or without `next`) onto every bundled skill so they show up in JSON. Outcomes-without-next for that purpose is a separate cut.

## Glossary

| Term | Meaning |
|------|---------|
| **Skill-default hop** | One outgoing edge declared on a cataloged skill: `metadata.supersuit.next[<outcome>] = <to>`. Implicit `from` is that skill’s logical id. Materialized as an ungated transition. |
| **Overlay transition** | A `transitions:` item in bundled capability YAML or user/project `workflow.yaml`. May be ungated or gated (`when:`). |
| **`entries` (removed)** | Former flat map (`creative-work`, `bugfix`) on workflow YAML. Not a schema field after this cut. Not a start mechanism. |
| Skill frontmatter `outcomes` | Labels the skill emits. Unchanged catalog marker. Not `skills.<id>.run.outcomes`. |
| `skills.<id>.run.outcomes` | Exit-code → label for a deterministic action. Unchanged. |

## Design decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Skill frontmatter owns *outgoing* hops only. A skill may name `to` only for edges **from itself**. Implicit `from` is the skill’s logical id. | The skill is the authority on what it emits and where *it* goes next. It is not a workflow file for other nodes. |
| 2 | Marker stays `metadata.supersuit.outcomes` (non-empty list of non-empty strings). Optional `metadata.supersuit.next` is a map: outcome string → `to` (logical id, or `null`, or `wait`). | Same pocket as the catalog. `next` is additive. No marker → not cataloged → no skill-default hops. |
| 3 | Every `next` key **must** already appear in `outcomes`. Extra keys: **warn and skip that hop** (do not raise a global `WorkflowResolveError`). Missing keys stay `wait` (existing unmapped-outcome rule). | One typo in a foreign `next` key must not brick SessionStart. An undeclared outcome still has no hop. |
| 4 | User/project overlay transitions win per `(from, on)` only. They do **not** replace-by-`from`. Other skill-default hops for that `from` stay. An overlay does **not** clear a hop: it **replaces** that one `(from, on)` with the overlay’s `to`. `to: null` means continue session (description-triggered skills still apply). `to: wait` means stop and ask the human. These values stay distinct; they are not one “remove the edge” that becomes `wait`. | This is why hops can live on the skill: an overlay can change one edge without deleting the rest. |
| 5 | Revises catalog spec Decision #2 and the author note “do not put `to` in frontmatter”: `to` is allowed **only** inside `next` values. No `transitions:` list on the skill. No graph of other skills’ edges. | Catalog Decision #2 forbade `to` because replace-by-`from` made per-skill defaults last-writer-win. Per-`(from, on)` merge removes that reason. The forbid is narrowed, not dropped. |
| 6 | Revises workflow-config ungated overlay merge: replace-by-`from` becomes per-`(from, on)` for **ungated** transitions. Gated overlay transitions (`when:`) stay **appended**. At resolve, the most-specific satisfied `when` still wins on a matching `(from, on)`. | `native-worktree` can still insert `ensure-worktree` over `brainstorming → writing-plans`. Gated-append is unchanged. Ungated no longer wipes sibling hops. |
| 7 | Delete `workflows/default.yaml` entirely. Resolver bundled base is empty (`version: 1`). Graph = cataloged `next` edges + bundled capability overlays + user/project overlays. Resolved `skills` is **thin**: entries appear only via catalog attach (valid `metadata.supersuit.outcomes`) or an overlay remap. Do **not** re-seed identity stubs. Non-cataloged bundled skills stay reachable by logical id (`discover_known_skills` + same-name invoke). | One baseline: the skills. No second YAML graph, no fallback copy of the deleted file, and no stub list that exists only to fill JSON. |
| 8 | Delete the `entries` field from schema, resolver, docs, and tests. No compatibility shim. Unreleased / no adoption. Starts stay description-driven plus `using-superpowers` Skill Priority prose. | The field never started sessions. Skill Priority already says “Let’s build X” → brainstorming and “Fix this bug” → systematic-debugging. |
| 9 | Catalog discovery, warn+skip invalid `outcomes`, no `.supersuit/skills` home, SessionStart still `using-superpowers` + `WORKFLOW_MAP` only — unchanged. | This cut adds hops. It does not reopen catalog safety. |
| 10 | Any cataloged skill (bundled or foreign) may set `next`. Same rules. | One mechanism. A pack on `SUPERSUIT_SKILL_PATH` is not a special case. |
| 11 | `to` in `next` uses the **same validation as overlay transitions**. Unknown id (not `null` / `wait` / known logical id) is a **resolve error**. Overlays and skill `next` share one rule. | JT picked match-overlay over warn+skip-unknown-value so authors cannot get a silent no-op hop from a typo in `to`. Extra *keys* still warn+skip (Decision #3). |
| 12 | Capability overlays remain `workflows/overlays/*.yaml`. They do not move onto skill frontmatter in this cut. | `when:` stays overlay-only. Skills do not declare capability gates. |
| 13 | Bundled Superpowers hops that today live in `default.yaml` move onto the relevant `SKILL.md` files in a **later** implementation PR (brainstorming / writing-plans / SDD / executing-plans). This spec lists the complete current table. | Spec locks the destination and the edges. This PR does not edit those skills. |
| 14 | Implementation (not this PR) updates `docs/workflow-config.md` layer list, merge rules, catalog “no `to`” sentence, and graph-design cross-links. | Docs track the resolver, not the other way around. |

## Marker and `next`

```yaml
---
name: brainstorming
description: You MUST use this before any creative work.
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
---
```

Rules:

- `metadata.supersuit` must be a mapping. `outcomes` remains required to catalog (same invalid-marker table as the catalog spec).
- `next` is optional. Omit it: the skill catalogs with outcomes only; it contributes no skill-default hops.
- `next` must be a mapping when present. Outcome keys are strings. Values are a logical id (string), YAML `null`, or the string `wait`.
- `from` is not written. The resolver uses the skill’s logical id (frontmatter `name` if present and non-empty, else the parent directory name — catalog identity).
- Duplicates in `outcomes` still collapse, first-seen order kept. YAML mapping semantics apply to duplicate `next` keys (last key in the mapping wins, as the frontmatter loader already does).
- `to` appears only as a `next` value. A top-level frontmatter `to` is not a hop. `transitions:` on the skill (top-level or under `metadata.supersuit`) is not read.
- Other keys under `metadata.supersuit` besides `outcomes` and `next` are ignored (forward-compatible). They do not create hops.
- Skill-default hops have no `when:`. Capability gates stay on overlay YAML.

This list is **skill frontmatter `outcomes`** plus optional **skill-default hops**. It is not `skills.<id>.run.outcomes`.

### Invalid `outcomes` (unchanged)

A file is a **candidate** when discovery selected it as a `SKILL.md` under a scanned root. Catalog Decision #9 still applies:

| Frontmatter | Default v1 |
|-------------|------------|
| No `metadata.supersuit` | Silent skip. Ordinary skill. Not cataloged. No skill-default hops. |
| `metadata.supersuit` present but `outcomes` missing, wrong type, empty list, empty strings, or `supersuit` is not a mapping | **Warn** and **skip that file**. Do not catalog it. Do **not** raise `WorkflowResolveError`. Continue resolve. |
| Valid non-empty `outcomes` list | Catalog it. Then apply `next` rules below. |

`next` cannot catalog a skill by itself. A file with `next` and no valid `outcomes` is an invalid marker and is skipped.

### Invalid or extra `next` (this cut)

Apply these rules only after the file is cataloged (`outcomes` ok).

| `next` | Effect |
|--------|--------|
| Absent | No skill-default hops from this skill. |
| Present but not a mapping | **Warn** and ignore `next` (catalog the skill; contribute no hops). Do not raise `WorkflowResolveError` for the type error. |
| Key not in this skill’s `outcomes` | **Warn** and **skip that hop**. Other keys still apply. Not a global `WorkflowResolveError`. |
| Key in `outcomes`, value is YAML `null` or `wait` | Materialize that hop. |
| Key in `outcomes`, value is a known logical id | Materialize that hop. |
| Key in `outcomes`, value is anything else (unknown id, empty string, number, list, mapping, …) | **Resolve error** — same as overlay `transition to unknown logical id` / missing-valid-`to`. |
| Outcome in `outcomes` with no `next` key | No hop. Emitting that outcome is `wait`. |

“Known logical id” is the same set overlay transitions already use: cataloged ids, overlay/registry ids, and bundled skill directory names from `discover_known_skills`. Those directory names remain valid `to` targets even when the skill is **absent** from resolved `skills`. Empty bundled YAML does **not** re-seed identity stubs for them. See [Thin registry + reachable-by-id](#thin-registry--reachable-by-id).

Skill-default hops are ungated. They follow the same gated-only-target rule as ungated overlay transitions: an ungated hop cannot point at a skill that exists only behind a `when:` the hop does not carry. Example: brainstorming’s `next` stays `writing-plans`, not `ensure-worktree`. The bundled `native-worktree` overlay still inserts `ensure-worktree` when that token is advertised.

## Migration table

These are the hops that today live in `workflows/default.yaml`. A later implementation PR moves **all** of them onto the named `SKILL.md` files and deletes that YAML file. Omitting a `to: null` hop would change today’s continue-session terminals into `wait`.

| `SKILL.md` | `from` | `on` | `to` |
|------------|--------|------|------|
| `skills/brainstorming/SKILL.md` | `brainstorming` | `approved-architectural` | `writing-plans` |
| `skills/brainstorming/SKILL.md` | `brainstorming` | `approved-bounded` | `null` |
| `skills/brainstorming/SKILL.md` | `brainstorming` | `approved-spike` | `null` |
| `skills/writing-plans/SKILL.md` | `writing-plans` | `subagent-driven` | `subagent-driven-development` |
| `skills/writing-plans/SKILL.md` | `writing-plans` | `inline` | `executing-plans` |
| `skills/subagent-driven-development/SKILL.md` | `subagent-driven-development` | `complete` | `finishing-a-development-branch` |
| `skills/executing-plans/SKILL.md` | `executing-plans` | `complete` | `finishing-a-development-branch` |

`finishing-a-development-branch` has no outgoing hop in `default.yaml` and does not gain one here.

Cross-cutting skills (TDD, systematic-debugging, verification-before-completion, requesting-code-review, receiving-code-review, dispatching-parallel-agents, writing-skills, using-superpowers, using-git-worktrees, visual-surface) stay description-triggered / remap-only. They do not require `next` in this cut, and they **must not** be required to appear as identity stubs in resolved `skills`. They stay reachable by logical id.

Capability-overlay hops (`ensure-worktree`, `using-git-worktrees` run remap, `visual-surface` run remap) stay in `workflows/overlays/*.yaml`. They are not copied onto skill frontmatter.

## Resolve order

1. **Discover the catalog** — same roots, first-seen logical id, frontmatter-only parse as the catalog spec. Unchanged.
2. **Empty bundled base** — in memory `{version: 1}`. Do not read `workflows/default.yaml`. Do not synthesize identity stubs for bundled skill directories. Do not keep a fallback copy of the deleted file.
3. **Merge skill remaps** (registry only) from bundled capability overlays (name-sorted), then user overlay, then project overlay. Skills merge is unchanged: ungated replace-by-logical-id; gated (`when:`) accumulate.
4. **Winning `SKILL.md`** — same winner as catalog outcomes attachment (`path` wins over `skill`; `{ skill: other-name }` uses the aliased skill; `run` / `exec` has no `SKILL.md`).
5. **Materialize skill-default hops** from each winning `SKILL.md`’s `next`. Implicit `from` is the **logical id being resolved** (the overlay key when remapped, not the aliased directory name). Extra keys warn+skip. `run` / `exec` entries contribute no skill-default hops.
6. **Merge overlay transitions** onto that baseline, in the same layer order (bundled capability overlays, user, project):
   - **Ungated:** replace per `(from, on)` only. Sibling hops for that `from` stay.
   - **Gated (`when:`):** append. Never drop baseline edges for that `from`.
7. **Validate** the merged document. Unknown `to` on overlay transitions and on remaining skill-default hops is a resolve error. No `entries` in the schema or the emitted artifact.
8. **Filter by capabilities** — among matching `(from, on)` candidates, the most-specific satisfied `when` (largest capability set) wins. Equal-size ties remain a resolve error. Strip `when`.
9. **Attach** compact `path` / `outcomes` as the catalog spec already does.

`--bundled-only` still skips user/project workflow overlays only. Catalog discovery is unchanged (plugin `skills/` plus the catalog path table / `SUPERSUIT_SKILL_PATH`). Bundled resolve is empty YAML + cataloged `next` + bundled capability overlays.

### Winning `SKILL.md` and remaps

| Winning overlay entry | Whose `next` materializes | Implicit `from` |
|-----------------------|---------------------------|-----------------|
| `path` is set | That path’s `SKILL.md` | The remapped logical id |
| `{ skill: other-name }` and no `path` | The aliased skill’s `SKILL.md` when that skill is cataloged | The remapped logical id |
| `run` / `exec` | None | — |
| Identity / empty | First-seen cataloged `SKILL.md` for this logical id | That logical id |

A custom brainstorming remap therefore carries *that* file’s hops under `from: brainstorming`, then overlay transitions may still replace one `(from, on)` (see [Replace one hop](#replace-one-hop)).

## Merge rules

Later layers override earlier ones as follows.

| Field | Merge |
|-------|-------|
| `skills` | Unchanged. Ungated replace-by-logical-id (whole entry). `skills.brainstorming: {}` clears a lower-layer alias or path back to identity. Gated entries accumulate. |
| `transitions` (ungated) | **Per `(from, on)`.** An overlay transition with the same `from` and `on` replaces that one hop. Other hops with the same `from` and a different `on` remain (skill-default or lower-layer). |
| `transitions` (gated) | **Append.** A host-specific enhancement does not drop the baseline edges for that `from`. |
| `entries` | **Removed.** Resolver does not read or emit `entries`. An overlay that still lists `entries:` is an unknown top-level key and is ignored the same way other unknown keys already are. There is no merge, no resolved copy, no deprecation warning, and no read-fallback. |
| Capability filter | Unchanged. Most-specific satisfied `when` on a matching `(from, on)` wins. |

### Replace one hop

An overlay does **not** clear a hop. It **replaces** that one `(from, on)` with the overlay’s `to` value. Sibling hops for that `from` stay.

| Overlay `to` | Meaning |
|--------------|---------|
| `<logical id>` | Invoke that id next. |
| `null` | Continue session. Description-triggered skills (TDD, debugging, verification, and so on) still apply. |
| `wait` | Stop and ask the human what to do next. |

`null` and `wait` stay distinct. Do not collapse them in prose or in future code to one “remove the edge” that becomes `wait`. The migration table’s brainstorming `approved-bounded` / `approved-spike` hops stay `null`.

Project `.supersuit/workflow.yaml` that **replaces** the architectural hop with `wait` and leaves bounded / spike as the skill’s `next` (`null`):

```yaml
version: 1

transitions:
  - from: brainstorming
    on: approved-architectural
    to: wait
```

`approved-bounded` and `approved-spike` stay `null` from brainstorming’s `next`. The overlay does **not** re-list them. The architectural overlay value stays `wait` — not `null`, and not a deleted edge that later becomes `wait`.

### `native-worktree` still inserts

Skill-default (ungated):

`brainstorming` / `approved-architectural` → `writing-plans`

Bundled overlay `workflows/overlays/native-worktree.yaml` (gated, appended):

`brainstorming` / `approved-architectural` → `ensure-worktree` when `native-worktree` is advertised, then `ensure-worktree` / `complete` → `writing-plans`.

At resolve, the gated edge is more specific and wins on that `(from, on)`. Hosts without the token keep the skill-default hop. This cut does not move those gated edges onto brainstorming frontmatter.

### What replace-by-`from` no longer does

Today, an ungated overlay that names `from: brainstorming` **drops every** earlier brainstorming edge, then appends only the overlay’s list. After this cut, that overlay replaces only the `(from, on)` pairs it names. Documented examples that say “you must list all outcomes for `brainstorming` you want to keep” are wrong after implementation; update them in the docs PR that lands with the resolver.

## Thin registry + reachable-by-id

After `workflows/default.yaml` is gone, resolved `skills` is **thin**. It only gains entries via:

1. **Catalog attach** — the skill has a valid `metadata.supersuit.outcomes` marker (and then compact `path` / `outcomes` as the catalog spec already does), or
2. **Overlay remap** — user, project, or bundled capability overlay set `path`, `skill`, or `run` / `exec` for that logical id.

Non-cataloged bundled skills (TDD, systematic-debugging, verification-before-completion, and the rest of the description-triggered set) **must not** be required to appear as identity stubs in resolved `skills`.

They remain **reachable by logical id**:

- `discover_known_skills` still lists bundled skill directories.
- SessionStart / `using-superpowers` already falls back to same-name invoke when the registry has no `path` / `skill` / `run` for that id.
- Unknown-`to` validation still treats those directory names as known ids. A hop may target `test-driven-development` even when that key is absent from resolved `skills`.

Do **not** “fix” thin registry by re-seeding empty stubs (`skills.test-driven-development: {}` in the bundled base) or by forcing `outcomes` onto every bundled skill. Adding outcomes-without-`next` later so those skills show up in JSON is a **separate cut**, not this one.

An overlay may still remap a non-cataloged bundled skill (`path`, `skill`, or `run` / `exec`). That remap is what creates the registry entry, not a bundled stub.

## SessionStart / context

`hooks/session-start` still injects `using-superpowers` + `WORKFLOW_MAP` JSON only. No second catalog block. No discovered skill bodies. No `next` map in the injected payload — hops appear as ordinary `transitions` in the resolved JSON.

Agents follow the filtered map as they do today. They do not re-read frontmatter `next` or overlay `when:`.

On SessionStart overlay failure, the hook still warns and injects the bundled map (empty YAML + cataloged hops + bundled capability overlays). If even that resolve fails, it warns that no `WORKFLOW_MAP` is available. There is no `default.yaml` fallback.

A cataloged skill (bundled or foreign) whose `next` value is an unknown logical id fails resolve the same way a user overlay with `to: not-a-skill` fails. That is Decision #11. SessionStart already handles resolve failure; this cut does not add a second policy for foreign `next`.

## `entries` removal

Delete `entries` from:

- Resolver merge, validate, and emitted JSON (`scripts/lib/workflow_resolve.py` and CLI stdout)
- `workflows/default.yaml` (the whole file goes away)
- `docs/workflow-config.md` and graph-design docs that treat `entries` as a live field
- Tests that assert `entries` on resolved JSON or merge `entries`

Starts:

- Description-triggered skills still apply (`using-superpowers` workflow-map rule 5).
- Skill Priority still applies: “Let’s build X” → `supersuit:brainstorming`; “Fix this bug” → `supersuit:systematic-debugging`.
- There is no `creative-work` / `bugfix` remap and no replacement start table.

Resolved JSON shape after this cut (no `entries` key). `skills` is thin: the empty object here is the empty bundled base. After catalog attach, only cataloged or remapped ids appear — not every bundled directory name.

```json
{
  "version": 1,
  "capabilities": [],
  "skills": {},
  "transitions": [],
  "ok": true
}
```

## SessionStart and harness impact

- **Harnesses:** unknown `metadata` keys remain ignored. `next` is resolver-owned, same as `outcomes`.
- **Agents:** frontmatter is often stripped before the model sees `SKILL.md`. Hops in the map are for `(from, on)` lookup after the skill emits an outcome.
- **Context:** no extra SessionStart document. Resolved transitions replace the hops that `default.yaml` used to supply.
- **Capabilities:** unchanged. Scanning skill dirs does not advertise tokens. `when:` stays off skill frontmatter.

## Success criteria

- A cataloged skill with valid `outcomes` and a `next` key that is in `outcomes` and a valid `to` contributes that ungated hop. Implicit `from` is the skill’s logical id (or the remapped logical id when an overlay won).
- Extra `next` keys warn and are skipped. Resolve continues.
- Missing `next` keys stay `wait`.
- Unknown `to` on a `next` value that is not `null` / `wait` / known id is a resolve error (same as overlay transitions).
- An ungated overlay that sets one `(from, on)` does not drop other skill-default hops for that `from`.
- An overlay **replaces** that one hop with its `to`. `to: null` means continue session; `to: wait` means stop and ask the human. They are not one “remove the edge” that becomes `wait`. The migration table’s brainstorming nulls stay `null`. The architectural overlay example stays `to: wait`.
- Gated overlay transitions are still appended. With `native-worktree` advertised, `brainstorming` / `approved-architectural` still resolves to `ensure-worktree`, then `writing-plans` on `complete`.
- `workflows/default.yaml` is gone. Resolver does not read it and does not fall back to it.
- Bundled YAML base is `{version: 1}`. Resolved `skills` is thin: no identity stubs for non-cataloged bundled skills.
- A non-cataloged bundled skill (for example `test-driven-development`) is a valid `to`, may be absent from resolved `skills`, still resolves as identity (same-name invoke), and an overlay may still remap it. Do not re-seed a stub or require `outcomes` on that skill.
- Resolved JSON has no `entries`. Overlay `entries:` is not merged.
- Catalog discovery, invalid-`outcomes` warn+skip, no `.supersuit/skills` home, and SessionStart payload (`using-superpowers` + `WORKFLOW_MAP` only) match the catalog spec.
- Foreign cataloged skills may set `next` under the same rules as bundled skills.
- Capability overlays still load from `workflows/overlays/*.yaml`.
- No `disable-model-invocation` work. No A-split design or extract.

## Alternatives considered

| Approach | Why not |
|----------|---------|
| Keep `default.yaml` as bundled baseline; add `next` as optional sugar | Two sources of truth. The Superpowers hops would still live in plugin YAML. |
| Soft `to` defaults without revising replace-by-`from` | Catalog spec already rejected this: last writer wins; two skills can claim the same edge. |
| Per-skill `workflow.yaml` files | Same replace-by-`from` problem the catalog called out. |
| Extract `supersuit-superpowers` now (cut A) | JT locked B: skills stay bundled in `jeighty/supersuit`. A is parked research, not this design. |
| Replace-by-`from` for ungated overlays, per-`(from, on)` only for skill `next` | Two merge rules. An overlay that names one brainstorming hop would still wipe the skill’s other hops — the bug this cut fixes. |
| Warn+skip unknown `next` values | Diverges from overlay transition validation. JT locked one rule: unknown `to` is a resolve error. Extra *keys* are the warn+skip case. |
| Move capability overlays onto frontmatter | `when:` on skills mixes host gates with skill-owned hops. Locked for a later cut if ever. |
| Keep `entries` for compatibility | Unreleased, no adoption. Starts are already Skill Priority + descriptions. A shim is leftover surface. |
| Keep `default.yaml` as SessionStart fallback | Reintroduces the deleted graph the first time catalog hops fail. Fail the same way today’s bundled resolve fails. |
| `transitions:` list on the skill | Lets a skill write other nodes’ edges. Frontmatter owns outgoing hops only. |
| `disable-model-invocation` in this cut | JT excluded it. |
| Re-seed empty identity stubs / force `outcomes` onto every bundled skill | Thin registry is correct. Reachable-by-id is enough. Outcomes-without-`next` so those skills appear in JSON is a separate cut. |

## Implementation notes (not this PR)

Implementation is a later PR against `dev`. This spec PR adds only this file.

- Delete `workflows/default.yaml`. Resolver starts from `{version: 1}` in memory. Do not re-seed identity stubs for bundled skill directories.
- Teach `scripts/lib/workflow_resolve.py` to parse `metadata.supersuit.next` from the winning `SKILL.md`, materialize ungated hops, and merge ungated overlay transitions per `(from, on)`.
- Remove `entries` from merge, validate, emitted JSON, and tests. Do not copy leftover overlay `entries` onto the artifact.
- Add `outcomes` + `next` to `skills/brainstorming/SKILL.md`, `skills/writing-plans/SKILL.md`, `skills/subagent-driven-development/SKILL.md`, and `skills/executing-plans/SKILL.md` using the migration table. Do not rewrite Red Flags tables to do it.
- Keep `workflows/overlays/native-worktree.yaml` and `workflows/overlays/native-canvas.yaml` as overlay files.
- Tests: extra `next` key warns+skips; missing key is `wait`; unknown `to` resolve-errors; per-`(from, on)` overlay **replace** of `approved-architectural` with `to: wait` leaves bounded/spike as the skill’s `next` (`null`); overlay `to: null` stays continue-session (do not collapse to `wait`); gated `native-worktree` still wins; no `default.yaml` read; resolved JSON has no `entries`; foreign cataloged `next` uses the same rules; `--bundled-only` is empty YAML + catalog hops + bundled overlays; a non-cataloged bundled skill is a valid `to`, may be absent from resolved `skills`, still resolves as identity, and an overlay may still remap it.
- Docs: `docs/workflow-config.md` layer list (bundled defaults are cataloged `next`, not `default.yaml`); merge rules (per-`(from, on)` ungated; gated append); delete the “list all outcomes for `from`” example; revise the catalog “do not put `to` in frontmatter” sentence to “`to` only inside `next`”; cross-link this spec from the graph design and the catalog spec Decision #2.
- Do not implement `disable-model-invocation`. Do not design or land a `supersuit-superpowers` extract.
