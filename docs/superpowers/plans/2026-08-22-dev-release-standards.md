# Dev / release standards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put feature work on `dev`, keep `main` released, reset plugin versions to `0.1.0-dev` on `dev`, and add deterministic PR CI — without implementing #21.

**Architecture:** Fast-forward the stale `dev` ref to current `main`, then one PR **targeting `dev`** that (1) runs `scripts/bump-version.sh 0.1.0-dev` on every file in `.version-bump.json`, (2) retargets contributor copy from `main` to `dev`, and (3) adds a GitHub Actions workflow that runs the non-LLM plugin suites. GitHub default branch stays `main`. First `0.1.0` release is a later `dev` → `main` PR, not this one.

**Tech Stack:** git, `scripts/bump-version.sh` (jq + yq), bash test scripts under `tests/`, GitHub Actions (`ubuntu-latest`).

**Spec:** `docs/superpowers/specs/2026-08-22-dev-release-standards-design.md` (PR #22).

## Global Constraints

- Feature PRs MUST target `dev`. `main` is released / marketplace. Do not change the GitHub default branch.
- On `dev`, every declared manifest version is `0.1.0-dev`. Do not write `0.1.0` (no suffix) on `dev`. Do not bump `main` in this PR.
- Human review is process (template + CLAUDE.md). Do not add branch protection, rulesets, CODEOWNERS, close-without-review automation, or eval-or-die. That is #21.
- PR CI runs deterministic `tests/` only. Do not add `evals/`, Drill, or live harness sessions (`tests/claude-code`, `tests/explicit-skill-requests`).
- Do not rewrite Red Flags / “human partner” skill tables.
- `using-superpowers` folder name stays. Superpowers LICENSE / credit stays.
- After this lands, new cloud agents start from `dev` and open PRs against `dev`.

## File map

| Path | Role |
|------|------|
| `scripts/bump-version.sh` | Existing bumper. Regex `^[0-9]+\.[0-9]+\.[0-9]+` accepts `0.1.0-dev`. |
| `.version-bump.json` | Declared manifests (do not edit unless audit finds a real miss). |
| `package.json` | version |
| `.hermes-plugin/plugin.yaml` | version |
| `.claude-plugin/plugin.json` | version |
| `.cursor-plugin/plugin.json` | version |
| `.codex-plugin/plugin.json` | version |
| `.devin-plugin/plugin.json` | version |
| `.kimi-plugin/plugin.json` | version |
| `.claude-plugin/marketplace.json` | `plugins.0.version` |
| `gemini-extension.json` | version |
| `.github/PULL_REQUEST_TEMPLATE.md` | Banner: MUST target `dev` |
| `CLAUDE.md` | Same sentence. `AGENTS.md` is a symlink to this file. Check `GEMINI.md`. |
| `.github/workflows/plugin-tests.yml` | New CI |
| `docs/testing.md` | Note PR CI vs evals |
| `#21` | Do not implement |

---

### Task 1: Fast-forward `dev` to `main`

**Files:** none in the tree. Git ref only.

**Interfaces:**
- Consumes: `main` tip that includes merged spec (PR #22) if that docs PR has landed; otherwise current `main` at PR #20 (`323094b`) plus any later main commits.
- Produces: `dev` SHA equals `main` SHA. `dev` is a fast-forward of its old tip `39e4562` (PR #13). Do not force-push if git refuses a FF.

- [ ] **Step 1: Confirm ancestry**

```bash
git fetch origin main dev
git merge-base --is-ancestor origin/dev origin/main && echo ancestor-ok
```

Expected: `ancestor-ok`. If this fails, STOP and tell the human. Do not force-push.

- [ ] **Step 2: Fast-forward the remote `dev` ref**

```bash
git push origin origin/main:refs/heads/dev
```

Expected: fast-forward, not a rejected non-FF update.

- [ ] **Step 3: Verify**

```bash
git rev-parse origin/dev origin/main
```

Expected: identical SHAs.

This task has no commit. The implementation PR starts from this updated `dev`.

---

### Task 2: Version `0.1.0-dev` on `dev`

**Files:**
- Modify: every path in `.version-bump.json` `files` (listed in the file map)
- Test: `tests/version-bump/test-bump-version.sh` (existing; must still pass)
- Possibly modify: any test that asserts the literal string `6.3.0` as *this* plugin’s current version (not Superpowers history in RELEASE-NOTES.md)

**Interfaces:**
- Consumes: `scripts/bump-version.sh <new-version>`
- Produces: all declared fields equal `0.1.0-dev`; `bump-version.sh --check` exits 0

- [ ] **Step 1: RED — show current version is not `0.1.0-dev`**

From repo root on a branch cut from current `dev`:

```bash
./scripts/bump-version.sh --check
```

Expected: every declared file prints `6.3.0` (or whatever is on `dev` now), not `0.1.0-dev`.

- [ ] **Step 2: Bump**

```bash
./scripts/bump-version.sh 0.1.0-dev
```

Expected: each declared file `6.3.0 -> 0.1.0-dev`. Audit may list undeclared hits (RELEASE-NOTES.md is already excluded). If a *live* manifest or test asserts `6.3.0` as current version, add it to `.version-bump.json` or update the assertion. Do not rewrite historical Superpowers notes.

- [ ] **Step 3: GREEN**

```bash
./scripts/bump-version.sh --check
/bin/bash tests/version-bump/test-bump-version.sh
```

Expected: “All declared files are in sync at 0.1.0-dev”; “Version-bump tests passed”.

- [ ] **Step 4: Commit**

```bash
git add .version-bump.json package.json .hermes-plugin/plugin.yaml \
  .claude-plugin/plugin.json .cursor-plugin/plugin.json \
  .codex-plugin/plugin.json .devin-plugin/plugin.json \
  .kimi-plugin/plugin.json .claude-plugin/marketplace.json \
  gemini-extension.json
# plus any test assertion files you had to update — not RELEASE-NOTES.md
git commit -m "chore: set plugin version to 0.1.0-dev on dev"
```

---

### Task 3: PRs target `dev`

**Files:**
- Modify: `.github/PULL_REQUEST_TEMPLATE.md` (banner at the top)
- Modify: `CLAUDE.md` (section “Pull Request Requirements”). `AGENTS.md` is a symlink — do not create a second copy.
- Modify: `GEMINI.md` if it is a real file that still says target `main`
- Test: `rg` over the repo (command below). Add a tiny assertion only if an existing identity test already pins the old sentence.

**Interfaces:**
- Consumes: current banner and CLAUDE.md sentence that say MUST target `main`
- Produces: those sentences say MUST target `dev`; `main` is described as released

Current PR template banner (replace in place):

```markdown
> **This PR MUST target `main`.** `main` is this fork’s default and
> released branch. Open feature-branch PRs against `main`.
```

Replacement:

```markdown
> **This PR MUST target `dev`.** `dev` is the work branch. `main` is
> released (marketplace / installs). Open feature-branch PRs against
> `dev`. A release is a `dev` → `main` PR.
```

Current CLAUDE.md sentence (replace in place):

```markdown
**All PRs MUST target `main`.** `main` is this fork’s default and released branch. Use a feature branch for the work; open the PR against `main`.
```

Replacement:

```markdown
**All PRs MUST target `dev`.** `dev` is the work branch. `main` is released (marketplace / installs). Use a feature branch for the work; open the PR against `dev`. A release is a `dev` → `main` PR.
```

- [ ] **Step 1: RED — the old contract is still in the tree**

```bash
rg -n "MUST target \`main\`" .github/PULL_REQUEST_TEMPLATE.md CLAUDE.md GEMINI.md
```

Expected: matches in the PR template and CLAUDE.md (GEMINI.md only if it is not a symlink to CLAUDE.md).

- [ ] **Step 2: Apply the replacements above.** Do not retune other contributor-pack wording (close-without-review, eval-or-die). That is #21.

- [ ] **Step 3: GREEN**

```bash
rg -n "MUST target \`main\`" --glob '!RELEASE-NOTES.md' --glob '!docs/superpowers/**' --glob '!docs/plans/**'
rg -n "MUST target \`dev\`" .github/PULL_REQUEST_TEMPLATE.md CLAUDE.md
```

Expected: first command has no hits in live contributor copy (historical specs/plans may still mention the old rule). Second command hits both files.

- [ ] **Step 4: Commit**

```bash
git add .github/PULL_REQUEST_TEMPLATE.md CLAUDE.md GEMINI.md
git commit -m "docs: require PRs to target dev"
```

---

### Task 4: Deterministic plugin CI

**Files:**
- Create: `.github/workflows/plugin-tests.yml`
- Modify: `docs/testing.md` (add a short “PR CI” paragraph after the plugin-tests list)

**Interfaces:**
- Consumes: these existing runners (no new test files):
  - `tests/workflow/test-resolve-workflow.sh`
  - `tests/workflow/test-skill-handoff-lint.sh`
  - `tests/workflow/test-native-worktree.sh`
  - `tests/workflow/test-visual-surface.sh`
  - `tests/workflow/test-exec-hook.sh`
  - `tests/hooks/test-session-start.sh`
  - `tests/migration/test-migrate-to-supersuit.sh`
  - `tests/shell-lint/test-lint-shell.sh`
  - `tests/version-bump/test-bump-version.sh`
- Produces: workflow `Plugin tests` on `pull_request` and `push` for branch `dev` (also run on `pull_request` so a PR into `dev` is gated)

- [ ] **Step 1: RED — no workflow yet**

```bash
test ! -f .github/workflows/plugin-tests.yml && echo missing-ok
```

Expected: `missing-ok`.

- [ ] **Step 2: Write `.github/workflows/plugin-tests.yml`**

```yaml
name: Plugin tests

on:
  push:
    branches: [dev]
  pull_request:
    branches: [dev]

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install yq
        run: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq
      - name: Run deterministic plugin suites
        run: |
          set -euo pipefail
          /bin/bash tests/workflow/test-resolve-workflow.sh
          /bin/bash tests/workflow/test-skill-handoff-lint.sh
          /bin/bash tests/workflow/test-native-worktree.sh
          /bin/bash tests/workflow/test-visual-surface.sh
          /bin/bash tests/workflow/test-exec-hook.sh
          /bin/bash tests/hooks/test-session-start.sh
          /bin/bash tests/migration/test-migrate-to-supersuit.sh
          /bin/bash tests/shell-lint/test-lint-shell.sh
          /bin/bash tests/version-bump/test-bump-version.sh
```

Do not add `evals/`. Do not add `tests/claude-code`. If a listed script needs an extra apt package, install it in the workflow rather than dropping the script.

- [ ] **Step 3: Run the same suite locally**

```bash
/bin/bash tests/workflow/test-resolve-workflow.sh
/bin/bash tests/workflow/test-skill-handoff-lint.sh
/bin/bash tests/workflow/test-native-worktree.sh
/bin/bash tests/workflow/test-visual-surface.sh
/bin/bash tests/workflow/test-exec-hook.sh
/bin/bash tests/hooks/test-session-start.sh
/bin/bash tests/migration/test-migrate-to-supersuit.sh
/bin/bash tests/shell-lint/test-lint-shell.sh
/bin/bash tests/version-bump/test-bump-version.sh
```

Expected: each script exits 0. Fix any breakage you introduced (version assertions). Do not “fix” unrelated flakes by deleting tests.

- [ ] **Step 4: Document CI in `docs/testing.md`**

Insert after the “Run plugin tests via the relevant directory…” paragraph:

```markdown
PR CI (`.github/workflows/plugin-tests.yml`) runs the deterministic
suites listed above on `push`/`pull_request` to `dev`: workflow,
hooks/session-start, migration, shell-lint, and version-bump. It does
not run `evals/` or live harness sessions.
```

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/plugin-tests.yml docs/testing.md
git commit -m "ci: run deterministic plugin tests on PRs to dev"
```

---

### Task 5: Open the PR against `dev`

**Files:** none new.

- [ ] **Step 1:** Push the feature branch and open a PR with **base `dev`**, not `main`.
- [ ] **Step 2:** PR body states: implements the spec; does **not** close #21; does **not** ship `0.1.0` on `main`.
- [ ] **Step 3:** Confirm `gh pr view --json baseRefName` is `dev`.

---

## Self-review

| Spec item | Task |
|-----------|------|
| FF stale `dev` | Task 1 |
| Default branch stays `main` | Global + Task 1 (no default-branch API call) |
| Feature PRs target `dev` | Task 3 |
| `0.1.0-dev` on `dev` | Task 2 |
| First `0.1.0` on `main` later | Global + Task 5 (explicit non-goal) |
| Deterministic CI | Task 4 |
| Human review as process only | Global; Task 3 does not add rulesets |
| #21 untouched | Global + Task 5 |
| Cloud agents start from `dev` after land | Global (coordinator, not this PR) |
