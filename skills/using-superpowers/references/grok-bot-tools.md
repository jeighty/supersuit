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
Forward the resolved map's `capabilities` into `run-workflow-action --id` so
advertised tokens cannot drop.

## Action map

| Skill action | Grok Bot primitive |
|--------------|--------------------|
| Read a file | `Read` on the box (no local repo clone) |
| Write / edit a file | `Write` / `Read`+`Write` on the box if present in the live list; never clone the repo onto the box to edit |
| Run a shell command | `Shell` on the box |
| Dispatch a subagent (Task-nest fact true) | `Task` (executor) — one nested child per seat |
| Dispatch a subagent (`Task` present, `subagents` **not** advertised) | `CloudAgent` fan — one CloudAgent per seat — or stop. Never nest into unloadable `Task` children. Never one CloudAgent reviewing every seat inline. |
| Dispatch a subagent (no `Task`, no CloudAgent launch) | Stop. Name the missing primitive. Do not review inline. |
| Ensure isolated workspace | Host CloudAgent branch / PR. When `native-worktree` is advertised, run `ensure-worktree` (handshake). Never `git worktree add`. |
| Finish / push / open PR | CloudAgent PR path (see Finishing). Not a local worktree merge menu. |

Box clone is forbidden. There is no local repo clone and no `git worktree add`
on the box. If the live list names a tool differently, use that name; do not
invent `EnterWorktree` or a harness-named capability.

## Workspace

Repo work on this host is a **CloudAgent branch / PR**, not a box checkout.

- When `native-worktree` is advertised, `using-git-worktrees` and
  `ensure-worktree` are `run` actions (`scripts/ensure-worktree`). Do not load
  the worktree skill and do not invent `git worktree` steps.
- The handshake reports isolation if present, otherwise reports host-owned
  workspace, always `complete` unless the process errors. It never runs
  `git worktree add`. The script is host-agnostic; this ref names `CloudAgent`
  as Grok Bot's workspace primitive.
- Box clone is forbidden. Do not clone the repo onto the box to get a worktree.
- Do not advertise `native-worktree` from CloudAgent **tip** access alone. Tip
  access is a spawn primitive, not workspace ownership of this session.

## Spawn

Task-nest fact = `task_tool && skills_loadable`. Nest only when that fact is true
**and** `subagents` is advertised.

Probe loadability before advertising `subagents`: plugin catalog contains the
family, or a child can `Read` the slot `SKILL.md`. A `Task` tool whose children
cannot load skills is not `subagents`.

| Fact | Rule |
|------|------|
| Task-nest fact true | Nest with `Task`. One fresh child per seat. Do not prefer CloudAgent "because it runs in parallel." |
| `Task` exists but skills unloadable / `subagents` not advertised | CloudAgent fan (one agent per seat) or stop. Never nest into unloadable children. |
| No CloudAgent launch either | Stop. Name the missing primitive. Do not review inline. |
| One agent per seat | Never one CloudAgent doing every seat in one window. Never nested seats that lack `Task`. |
| Partial return | A subset of dumps from **one** spawn call is a whole-call stop. Do not merge seats that did return. Do not re-announce a thinner pack. |
| Pack | Caller-named `full` / `core` (default `full`). Do not infer `core` from "Medium", "quick", "light", "small", or a missing `Task` tool. |

SDD and `dispatching-parallel-agents` use this same binding; do not rewrite
those skill bodies. `cloud-seat` is an invocation mode of the same router, not
a sibling skill.

## Finishing

Map "push / open PR / finish the branch" to the host's **CloudAgent PR path**.
Do not drive `finishing-a-development-branch` as a local worktree merge menu
(`git worktree remove`, merge-into-main on the box). The skill body stays
Superpowers; this host's primitive is CloudAgent branch / PR.

## Profile

Superpowers **xor** Supersuit. Enable one plugin identity. This fork's
plugin id `supersuit`; skills are `supersuit:<skill>`. Config dirs are
`.supersuit/` / `~/.supersuit/` (`.superpowers/` is a one-release read fallback).
Enabling both in one agent profile is RED.

## SessionStart

Inject `using-superpowers` + `WORKFLOW_MAP` **every session**. No per-session
opt-in. A skill directory on disk is not bootstrap. Advertise `session-inject`
via `SUPERPOWERS_CAPABILITIES` / `--capabilities` (this host has no
hook-presence detect env yet). Do not claim `session-inject` from the product
name.

Acceptance test (later eval cut, not this PR): a clean session whose user
message is exactly `Let's make a react todo list` must auto-trigger
`brainstorming` before any code.
