# Grok Bot Harness Support — Design Spec

**Status:** Approved design (2026-09-08). Locked by JT / Skills Builder /
Skill Craft / Adversarial Reviewer. A draft pull request for this spec is
process (review and landing), not a contradiction of the approved-design
status.
**Product:** Supersuit (`jeighty/supersuit`).
**Depends on:** Configurable workflow graph; capability-aware overlays
([2026-08-17-workflow-capability-overlays-design.md](2026-08-17-workflow-capability-overlays-design.md));
native-worktree handshake
([2026-08-21-native-worktree-preference-design.md](2026-08-21-native-worktree-preference-design.md));
run/exec actions
([2026-08-17-workflow-run-actions-design.md](2026-08-17-workflow-run-actions-design.md));
SessionStart inject of `using-superpowers` + `WORKFLOW_MAP`. Spawn-seat
facts mirror [jamesthomasonjr/skills#52](https://github.com/jamesthomasonjr/skills/pull/52)
and [#53](https://github.com/jamesthomasonjr/skills/pull/53)
(`review-spawn-seats` / cloud-seat mode of `review-changes`).
**Does not implement:** Resolver changes; overlay YAML; skill-body edits;
`skills/using-superpowers/references/grok-bot-tools.md`; SessionStart detect
probes; PROFILE/SEED shipping; marketplace version bump; eval fixtures.

This PR is docs only. Implementation waits on a later PR against `dev`.

## Problem

Supersuit methodology prose already works on a Grok Bot desktop agent **if
skills load**. The product does not. Three host edges are wrong or
unspecified, so agents invent behavior:

1. **Spawn.** A nested Task / subagent tool may be present while children
   cannot load slot `SKILL.md` (empty plugin catalog, unloadable install).
   Treating “Task exists” as `subagents` nests into unloadable children.
   Isolation is not one CloudAgent that reviews inline, and it is not a fan
   of nested seats that themselves lack Task.
2. **Workspace.** Repo work on this host is a CloudAgent branch / PR, not a
   box checkout and not a local `git worktree`. Claiming `native-worktree`
   because a CloudAgent *tip* is reachable, without a host-owned isolation
   handshake, still leaves agents running `git worktree add` on the box.
   Box clone is forbidden by policy.
3. **Bootstrap.** SessionStart-like inject of `using-superpowers` +
   `WORKFLOW_MAP` must happen, or skills sit on disk. Product-name detect
   (“Grok”, “Grok Bot”) is the wrong way to get `session-inject`.

Approach: **advertise existing capability tokens** with precise meanings, plus
**thin overlays** already in this fork. Never infer tokens from product or
tier words. Do not invent a capability noun named after this harness. Do not
fork Superpowers skill bodies. Do not enable Superpowers and Supersuit in
the same agent profile.

## Goals

| Priority | Goal |
|----------|------|
| Primary | Make Supersuit runnable on Grok Bot desktop agents by binding spawn, workspace, and bootstrap to existing capability tokens. |
| Tokens | Extend `session-inject`, `native-worktree`, and `subagents` with precise meanings. No new token named after the harness. |
| Overlays | Reuse bundled `native-worktree` handshake; document what remaps when which tokens are advertised. |
| Bootstrap | Specify advertisement (preferred) and conservative detect. Outline a later harness ref that maps *actions* → CloudAgent / Task / no local worktree. |
| Spawn | Mirror review-family facts: Task nest only when loadable; else CloudAgent fan; one agent per seat; partial seat return → whole-call stop. |
| Safety | Never infer capabilities from “Grok”, “Grok Bot”, “Medium”, “cloud”, “quick”, or other product / tier words. |

## Non-goals

- Extracting `supersuit-superpowers` (cut A) or a monorepo pack split.
- GREEN/RED eval fixtures in this PR (later, with Skill Evaluator).
- Shipping PROFILE / SEED via Partners Manager.
- Rewriting Red Flags, rationalization lists, or “human partner” skill prose.
- Rewriting `using-git-worktrees/SKILL.md`, SDD, `dispatching-parallel-agents`,
  or `finishing-a-development-branch` bodies.
- Creating `skills/using-superpowers/references/grok-bot-tools.md` (path
  locked; file deferred).
- Resolver, overlay YAML, SessionStart probe, or marketplace version changes.
- Advertising `exec-hook` or `native-canvas` for this host in this cut.
- A second methodology, a `review-changes-cloud` sibling, or a lighter pack
  inferred from “Medium”.
- Enabling Superpowers and Supersuit in one agent profile (forbidden; not a
  token).

## Glossary

| Term | Meaning |
|------|---------|
| **Capability token** | Existing overlay token: `session-inject`, `native-worktree`, `subagents`, `exec-hook`, `native-canvas`. Advertised via `SUPERPOWERS_CAPABILITIES`, `--capabilities`, and (for `session-inject` only) conservative detect. |
| **Task-nest fact** | `task_tool && skills_loadable`. Nested Task / subagent tool that opens a fresh context **and** the child can load that slot’s `SKILL.md` (plugin catalog or a probe Read of the seat skill path succeeding for a child). |
| **CloudAgent fan** | One CloudAgent per announced seat / gatherer. Not a nest of Task children. Not one CloudAgent doing every seat inline. |
| **Handshake** | Bundled `scripts/ensure-worktree` (or a same-gate overlay replacement). Reports isolation or host ownership. Never runs `git worktree add`. |
| **CloudAgent tip access** | The parent can launch or observe a CloudAgent. That is a spawn primitive, not workspace ownership of *this* session. |
| **Harness ref** | `skills/using-superpowers/references/grok-bot-tools.md` — action → tool mapping. Not a capability token. File does not exist yet. |
| **cloud-seat** | Invocation mode of `review-changes` when the Task-nest fact is false and CloudAgent launch is present. Same packs, same seeds, same HARNESS-STOP. Not a sibling skill. |

## Binding decisions (three edges)

| # | Edge | Binding |
|---|------|---------|
| 1 | **Bootstrap** | Advertise `session-inject` (`SUPERPOWERS_CAPABILITIES` / `--capabilities`). Conservative detect may add `session-inject` only from a SessionStart-like **hook-presence** env (today: `CURSOR_PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`, `COPILOT_CLI`). Prefer advertise over inventing a product-name detect. Inject `using-superpowers` + `WORKFLOW_MAP`. A later PR adds the harness ref and, if needed, a one-line Platform Adaptation pointer in `using-superpowers` (the only SKILL.md edit a port may make). |
| 2 | **Workspace** | Binding **(a)**: advertise `native-worktree` **only** when CloudAgent (or equivalent) is the **host-owned workspace primitive** **and** overlays remap `ensure-worktree` / `using-git-worktrees` to a handshake that never runs `git worktree add` on the box. On this host, repo work is CloudAgent branch / PR, not a box checkout. Box clone is forbidden by policy. Binding (b) (leave the skill agent-mediated until a handshake exists) is the fallback for hosts that lack that primitive — it is **not** the Grok Bot CloudAgent-workspace binding. |
| 3 | **Spawn** | `subagents` is **not** “Task tool exists.” Nest / Task-driven fan **only** when the Task-nest fact is true. If Task exists but skills are unloadable → CloudAgent fan (one CloudAgent per seat) or stop. Never nest because Task exists. Isolation ≠ one CloudAgent that reviews inline / fans nested seats that lack Task. Partial seat return from one spawn call → whole-call stop. |

## Capability token meanings (this host)

These are the **same** tokens as
[docs/workflow-config.md](../../workflow-config.md). This spec tightens
what advertising each one **means**. It does not add a harness-named token.

| Token | Meaning on this host | Auto-detected? |
|-------|----------------------|----------------|
| `session-inject` | Host injects `using-superpowers` + `WORKFLOW_MAP` at session start (SessionStart-like bootstrap). | Conservative hook-env probe only. Prefer advertise. Do not detect from the product name or from `GROK` / `GROK_BOT` / `XAI` env. A later implementation PR may add a **hook-presence** env to `detect_capabilities` only if that env is evidence of SessionStart, the same class as `CURSOR_PLUGIN_ROOT` — not because the product is named Grok. |
| `native-worktree` | Host owns workspace creation. On this host that primitive is CloudAgent branch / PR isolation, with `ensure-worktree` / `using-git-worktrees` remapped to the handshake. | No. Advertise explicitly. Product name is not evidence. CloudAgent tip access without the handshake is not evidence. |
| `subagents` | Task-nest fact is true: `task_tool && skills_loadable`. Probe: plugin catalog contains the family, or a child can Read the slot `SKILL.md`. | No. Advertise only after that probe. A Task tool whose children cannot load skills is **not** this token. |
| `exec-hook` | Unchanged. This cut does not advertise it for this host. | No. SessionStart running is not an exec hook. |
| `native-canvas` | Unchanged. This cut does not advertise it for this host. | No. Do not infer from any product name. |

Active set stays the union of detect ∪ `SUPERPOWERS_CAPABILITIES` ∪
`--capabilities` (first-seen order). Forward the resolved map’s
`capabilities` list into `run-workflow-action --id` so advertised tokens
cannot drop. A missing probe still yields `[]` and keeps gated overlays off.

### How to advertise (preferred)

```bash
export SUPERPOWERS_CAPABILITIES=session-inject,native-worktree
# add ,subagents only when the Task-nest fact is true

./scripts/resolve-workflow --plugin-root "$PWD" --project-root "$PWD" \
  --user-home "$HOME" --capabilities session-inject,native-worktree --pretty
```

Typical Grok Bot CloudAgent-workspace profile: `session-inject` +
`native-worktree`. Add `subagents` only when children can load slot skills.
Never set tokens from the words “Grok”, “Medium”, or “cloud”.

## Overlay sketch

No product-named overlay file. Gate on the tokens above. Bundled
`workflows/overlays/native-worktree.yaml` already implements the workspace
handshake when `native-worktree` is advertised.

| Advertised set | What remaps | What must not happen |
|----------------|-------------|----------------------|
| *(empty / missing probe)* | Superpowers baseline. `using-git-worktrees` stays the identity skill. No `ensure-worktree` run. | On a Grok Bot CloudAgent-workspace session this set is wrong: advertise `session-inject` and `native-worktree` instead of relying on detect. |
| `session-inject` | SessionStart (or equivalent) injects `using-superpowers` + `WORKFLOW_MAP`. | Do not claim this token from the product name. Do not skip inject because a skill directory exists on disk. |
| `native-worktree` | Bundled overlay: `brainstorming` / `approved-architectural` → `ensure-worktree` run → `writing-plans` on `complete`. `using-git-worktrees` remaps to the same run (`complete` → `null`). Agent must not load that skill or invent `git worktree` steps. | Handshake never runs `git worktree add`. Box clone remains forbidden. Do not advertise this token on CloudAgent **tip** access alone. |
| `session-inject` + `native-worktree` | Bootstrap plus handshake. This is the intended Grok Bot CloudAgent-workspace pair. | Local worktree creation and box clone stay forbidden. |
| `subagents` | No bundled overlay today. Do not add one named after this harness. SDD / `dispatching-parallel-agents` stay identity skills. The later harness ref maps the **action** “dispatch a subagent” to Task nest. | Advertise only when Task-nest fact is true. Skills stay Superpowers methodology. |
| Task present, `subagents` **not** advertised (skills unloadable or unprobed) | Same identity skills. Harness ref maps “dispatch a subagent” to CloudAgent fan (one agent per seat) or stop. | Do not nest into unloadable Task children. Do not review inline as one agent. Do not invent a second methodology skill. |
| `exec-hook` / `native-canvas` | Unchanged existing overlays. This cut does not require them. | Do not infer either token for this host. |

Workspace overlay (already shipped; shown so the handshake contract is
explicit):

```yaml
# workflows/overlays/native-worktree.yaml — gated on native-worktree
skills:
  ensure-worktree:
    run:
      argv: [scripts/ensure-worktree]
      allow: [plugin]
    when:
      capabilities: [native-worktree]
  using-git-worktrees:
    run:
      argv: [scripts/ensure-worktree]
      allow: [plugin]
    when:
      capabilities: [native-worktree]
```

`scripts/ensure-worktree` reports isolation if present, otherwise reports
host-owned workspace, always `complete` unless the process errors. It does
not create a worktree.

Spawn and finishing are **not** new overlay YAML in this cut. They are
host-fact translations in the harness ref so SDD, `dispatching-parallel-agents`,
`finishing-a-development-branch`, and `using-git-worktrees` follow the same
methodology with this host’s primitives.

## Spawn seats (workflow implications)

Mirror the review-family contract from skills #52 / #53. Supersuit does not
fork that family and does not invent a parallel pack table.

| Fact | Rule |
|------|------|
| Task-nest fact true | Nest. One fresh Task child per seat. Do not prefer CloudAgent “because it runs in parallel.” |
| Task-nest fact false, CloudAgent launch present | CloudAgent fan. One CloudAgent per seat. Same announced set. |
| Task-nest fact false, no CloudAgent launch | Stop. Name the missing primitive. Do not review inline. |
| Skills unloadable (probed) | Task-nest fact is false even if Task exists. Fan or stop. |
| One agent per seat | Never one CloudAgent doing every seat in one window. Never nested seats that lack Task. |
| Partial return | A subset of dumps from **one** spawn call is a whole-call stop. Do not merge the seats that did return. Do not re-announce a thinner pack. |
| Pack | Caller-named `full` / `core` (default `full`). Do not infer `core` from “quick”, “light”, “small”, “Medium”, or a missing Task tool. |
| Verify | Stays parent-Follow where the review family says so. Isolation is not verify’s duty. |

`cloud-seat` is an invocation mode of the same router, not a sibling skill
and not a reason to advertise a lighter pack. The words “Grok”, “Medium”,
and “cloud” are not harness facts.

SDD and `dispatching-parallel-agents` use the same spawn binding when they
dispatch: nest only when loadable; otherwise CloudAgent fan or stop. Do not
rewrite those skill bodies; the harness ref carries the primitive mapping.

## Bootstrap ref outline (deferred file)

**Path:** `skills/using-superpowers/references/grok-bot-tools.md`

Do **not** create that file in this PR. A later implementation PR writes it
and may add one Platform Adaptation pointer in `using-superpowers/SKILL.md`
(pointer list only; not behavior-shaping prose). Skills continue to name
actions, not tools.

| Section | Contents |
|---------|----------|
| **Capabilities** | How this host advertises `session-inject` / `native-worktree` / `subagents`. Env `SUPERPOWERS_CAPABILITIES`, CLI `--capabilities`, conservative detect. Explicit: do not infer tokens from product or tier words. |
| **Action map** | Table: skill action → this host’s primitive (Read / Write / Shell / CloudAgent launch / Task nest / no local worktree). Get machine tool names from the live harness; do not invent them in the spec. |
| **Workspace** | CloudAgent branch / PR is the workspace. Handshake via `ensure-worktree` when `native-worktree` is advertised. Never `git worktree add`. Box clone forbidden. |
| **Spawn** | Task-nest fact; CloudAgent fan; one agent per seat; partial return → whole-call stop; probe loadability (`plugin-catalog` or `child-read`). |
| **Finishing** | Map “push / open PR / finish the branch” to the host’s CloudAgent PR path. Do not drive a local worktree merge menu as if this were a box checkout. Skill body stays Superpowers. |
| **Profile** | Superpowers **xor** Supersuit. One plugin identity (`supersuit`, skills `supersuit:<skill>`). Enabling both in one agent profile is RED. |
| **SessionStart** | Inject `using-superpowers` + `WORKFLOW_MAP` every session, no per-session opt-in. Acceptance test (later PR): “Let's make a react todo list” auto-triggers `brainstorming` before code. |

## RED cases

These are binding. An implementation that does any of them is wrong even if
skills appear to “work.”

| RED | Why |
|-----|-----|
| **Infer-from-product-name** | Picking Task vs CloudAgent, `core` vs `full`, unloadable vs loadable, or any capability token from “Grok”, “Grok Bot”, “Medium”, “cloud”, “quick”, “light”, or “small”. Probe tools and installs. Advertise tokens. |
| **Nest-into-unloadable** | Task tool present, children cannot load the slot `SKILL.md`, parent nests anyway. Task-nest fact is false. Fan CloudAgents or stop. |
| **Claim `native-worktree` with only CloudAgent tip and no handshake** | Tip access is a spawn primitive. Workspace ownership requires host-owned isolation **and** `ensure-worktree` / `using-git-worktrees` remapped to a handshake that never runs `git worktree add`. Advertising the token without that remap leaves the identity skill free to create a box worktree. |
| **Superpowers + Supersuit same profile** | Two bootstraps, two namespaces, conflicting maps. Enable one plugin identity. This fork’s id is `supersuit`. |

Related REDs (same family; already locked in skills #52 / #53): reviewing
inline when a primitive is missing; returning a partial seat set; declaring
unloadable from a word instead of a probe; fanning CloudAgent when
Task-nest fact is true because the product name suggested it.

## Live score target

Operational precedent, **not** a Supersuit CI fixture in this PR:

- Repo / PR: [jamesthomasonjr/stations.dev#475](https://github.com/jamesthomasonjr/stations.dev/pull/475)
- Commit: [`5411e7414b62ea32f4139620d1fcfb1e126d2394`](https://github.com/jamesthomasonjr/stations.dev/commit/5411e7414b62ea32f4139620d1fcfb1e126d2394)
  (`fix(infra): #475 cloud-seat Medium — …`)

That tip is the live score target for a later Skill Evaluator pass of
cloud-seat / spawn-seat behavior. Do not copy GREEN/RED dump fixtures into
this repository in this PR.

## Profile constraint

Install **either** Superpowers **or** Supersuit in a given agent profile,
never both. Skill namespace here is `supersuit:<skill>`. Config dirs are
`.supersuit/` / `~/.supersuit/` (`.superpowers/` is a one-release read
fallback). Dual install is the Superpowers+Supersuit RED above, not a
capability-token problem.

## Success criteria (this spec)

- Binding decisions table for bootstrap, workspace, and spawn.
- Explicit meanings of `session-inject`, `native-worktree`, and `subagents`
  on this host, with advertise-vs-detect rules.
- Overlay sketch: what remaps when which tokens are advertised; no
  harness-named capability token; workspace handshake is the existing
  bundled overlay.
- Bootstrap ref outline: path `skills/using-superpowers/references/grok-bot-tools.md`
  plus the section list above. File not created here.
- Explicit RED cases: infer-from-product-name; nest-into-unloadable; claim
  `native-worktree` with only CloudAgent tip and no handshake;
  Superpowers+Supersuit same profile.
- Live score target recorded as stations.dev #475 @ `5411e74` (operational
  precedent, not a CI fixture).
- Implementation deferred: no resolver, overlay, or skill-body changes in
  this PR.

## Later implementation (not this PR)

A follow-up PR against `dev` may:

1. Write `skills/using-superpowers/references/grok-bot-tools.md` to this
   outline and add the Platform Adaptation pointer.
2. Advertise tokens in the host’s SessionStart / profile (prefer env / CLI).
   Extend `detect_capabilities` only for a real SessionStart hook-presence
   env, never for a product-name env.
3. Confirm the bundled `native-worktree` overlay is the handshake when that
   token is advertised; do not teach `git worktree add` on the box.
4. Keep Superpowers skill bodies intact. Map spawn/finish/worktree
   **actions** in the harness ref.
5. Run the harness acceptance test (clean session: “Let's make a react todo
   list” → `brainstorming` before code) and record the transcript.
6. Add Skill Evaluator GREEN/RED coverage, including the stations.dev #475
   live-score target, in that later eval cut — not here.

## Alternatives considered

| Approach | Why not |
|----------|---------|
| New capability token named after this harness | Product-name switch. Overlays already reject `when.harness`. Tokens stay `session-inject` / `native-worktree` / `subagents`. |
| Infer tokens from “Grok” / “Medium” / “cloud” | Over-claims spawn and workspace. Skills #53 already scores this as wrong-primitive. |
| Binding (b) for this host: never advertise `native-worktree`, keep agent-mediated `using-git-worktrees` | Leaves `git worktree add` on a box that must not clone. Binding (a) applies because CloudAgent **is** the host-owned workspace primitive **and** the handshake overlay already exists. |
| Advertise `native-worktree` on CloudAgent tip access without remapping `using-git-worktrees` | The identity skill still creates a local worktree. Tip access ≠ isolation. |
| Treat Task-present as `subagents` | Unloadable children HARNESS-STOP every slot and never exercise CloudAgent fan (skills #53). |
| One CloudAgent that reviews inline / fans nested seats without Task | Isolation is per seat. Inline is never a back end. |
| Fork `using-git-worktrees` / SDD bodies for this host | Drift; contributor rules reject compliance rewrites of skill prose. Tool mapping belongs in the harness ref. |
| Enable Superpowers and Supersuit together “for compatibility” | Two bootstraps. Forbidden. |
| Ship eval fixtures / PROFILE / marketplace bump with the spec | Different cuts. Spec first. |
| Per-harness `*.grok.md` skill copies | Same drift as `*.cursor.md`; overlays exist to avoid this. |

## Spec self-review

- No placeholders and no open design forks on the three edges.
- No capability token named after this harness.
- Runtime inference from product / tier words is RED, not a detect strategy.
- Superpowers skill bodies are not rewritten here; the later ref maps actions.
- Scope is one host’s three edges on existing tokens. Implementation is a
  separate PR.
