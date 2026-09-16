---
name: code-development
description: >-
  Guides a feature, bugfix, or patch through three tasks in strict sequence: (1) scope
  and design — read the repo, research best practices, surface every open question and
  design choice, and stop for explicit sign-off on a written plan; (2) implement —
  feature branch, smallest change, security first, written to pass SonarQube/CodeQL/lint,
  no commit until local tests actually run and pass; (3) document — update or create
  README/docs with fresh Playwright screenshots from a local run or mocks, sweeping stale
  images even on a bugfix. Ends by pushing and opening a fully filled PR (stacked PRs for
  larger work), then hands CI to pipeline-monitor. `/code-development init` records validated
  test, lint and PR conventions in `.claude/code-development.yml`. Use on
  /code-development, "develop a feature", "fix a bug", or any ask to build, implement,
  fix, or patch code — even if coding already started. Not for CI failures
  (/pipeline-monitor), releases (/code-release), or reviewing others' PRs. Needs git and gh —
  Claude Code only.
---

# code-development

Takes a feature, bugfix, or patch from "I want X" to an open pull request, in three tasks
that run strictly in sequence — scope, implement, document — so no task steps on another.

This skill has real side effects: it creates branches, commits, pushes, and opens PRs. It
never touches the default branch directly and never commits code whose tests haven't
actually passed.

Everything repo-specific — how to run the tests, what CI enforces, which branch to cut
from, whether PRs open ready or draft, whether screenshots are expected — comes from
**`.claude/code-development.yml` in the repo being worked on**, written by
`/code-development init`. Without that file the skill rediscovers the same facts on every
single run and has no record of the answers you gave last time.

Hard rules, restated up front because they're the ones that erode mid-task:

1. **Never guess on direction.** Any design decision with more than one viable approach is
   a stop-and-ask: present the options with tradeoffs and wait. Research first — the repo's
   own conventions, then current best practice — before proposing anything.
2. **Task gates are hard.** Task 2 does not start until the Task 1 plan has the user's
   explicit sign-off. Task 3 does not start until Task 2's tests are green and committed.
   No look-ahead, no "while I'm here."
3. **No commit until local tests pass.** Run them for real. If they can't run, there is no
   commit — say why and stop. Never claim a command ran that didn't. This governs commits
   that change code; setup mode's single config commit is the one exemption, and it reports
   a pre-existing red suite rather than committing on top of a green one it invented.
4. **Never push directly to the default branch**, or to whatever `branch.default` names.
   All work lands on a `feature/`, `fix/`, or — in setup mode only — `chore/` branch, via a
   PR.
5. **Smallest change, explicit staging.** No unrelated edits, no renames or refactors the
   task doesn't require, and never `git add -A` — stage each file by name.
6. **Setup mode commits exactly one path**, `.claude/code-development.yml`, and authors
   nothing else — no code, no tests, no docs, no workflow. It *runs* the repo's own commands
   to validate them; it never stages what those runs leave behind. A development run commits
   only what the signed-off plan named.
7. **The config is the contract; the repo is the truth.** Where they disagree — a recorded
   command that no longer exists, a default branch that was renamed — stop and say which
   key is stale. Never improvise a substitute command to keep the run moving.

## The two modes

Pick the mode before doing anything else, and say which one you're in.

| Invocation | Mode | Writes anything? |
|---|---|---|
| `/code-development init`, "set up code-development", "configure code-development" | **Setup** — discover the toolchain, validate it by running it, write `.claude/code-development.yml`, open a PR for it | One file, on a branch, after confirmation |
| `/code-development`, "develop a feature", "fix a bug", "implement X" | **Development run** — Phase 0, then Tasks 1–3, then the PR | A branch, commits, a push, a PR |

**Plain `/code-development` in a repo with no config offers Setup first.** Say that's what
you're offering rather than silently interviewing. If the user declines, run the Phase 0
discovery inline for this run only and say plainly that nothing is being recorded — the
next run will rediscover all of it.

## Environment and tooling

- Needs `git`, `gh`, and a checked-out repo — Claude Code only. Prefer a connected GitHub
  MCP server if one is in this session's tools; otherwise `gh`. Check the tools actually
  available in this session, not a registry of installable ones.
- **Push access is required** in both modes. Both end in a pushed branch and a PR. If
  neither path is authenticated with write access, stop and say so before Task 1 rather
  than after the code is written.
- The repo is **whatever repo is checked out**. Discover it; never assume a name.
- Task 3 captures screenshots with **Playwright**, which needs its browsers installed
  (`npx playwright install chromium` or the repo's own equivalent). A repo whose config
  records `screenshots.mode: none` never needs it.

This skill is repo-agnostic, so the quality toolchain is **discovered, not assumed**. When
`.claude/code-development.yml` exists, that discovery already happened and its result is in
the file. When it doesn't, read, in this order, whatever exists:

- `.github/workflows/*.yml` — what CI actually enforces: linters, test commands, scanners,
  matrices. This is the ground truth for what the code must pass.
- `Makefile`, `package.json` scripts, `pyproject.toml`, `tox.ini`, `go.mod`, `Cargo.toml` —
  how to run those same checks locally.
- Linter and scanner configs: `.eslintrc*`, `ruff.toml`, `.golangci.yml`,
  `sonar-project.properties`, `.pre-commit-config.yaml`, `codeql` config.

**If no CI workflows exist**, that is a finding, not a free pass: in a development run,
offer to add a basic lint + test workflow (its own commit, or its own stacked PR if
non-trivial). Offer — never silently create it, and never skip local checks just because CI
wouldn't have caught the gap. Setup mode makes no such offer; it records the absence in the
config's `ci` block and points at a development run.

SonarQube and CodeQL generally cannot run locally. Handle that honestly: run everything that
*can* run (linters, the test suite, any local scanner the repo configures), write the code
to the standards those scanners enforce (Task 2 lists them), and let pipeline-monitor catch the
remainder after the push. Never report a scan as passed locally when it did not run locally.

## Setup mode — `/code-development init`

Takes a repo from nothing to a committed, **validated** config, so every later run starts
from recorded fact instead of rediscovery. Build it *from what the repo actually has* rather
than by interrogating the user about things you can read.

**1. Ground it.** Confirm push access, then discover the repo, the current branch, the
default branch, and whether the tree is clean:

```bash
git rev-parse --show-toplevel && git branch --show-current
git remote -v
git status --porcelain          # must be empty — see below
gh repo view --json nameWithOwner,defaultBranchRef
```

**Stop now if the tree is dirty.** Setup's commit has to contain the config and nothing
else, and you cannot guarantee that starting from someone else's uncommitted work. Checking
this here rather than at commit time matters, because step 7 writes a file and from then on
"dirty" no longer distinguishes your change from theirs.

If `gh repo view` errors, don't work around it — step 3 covers why it can fail.

**2. Check for an existing config** at `.claude/code-development.yml` (or `.yaml`). If one
exists, show it and ask whether to update it or keep it — never overwrite a config the user
hasn't seen.

**3. Check the prerequisites that actually block people**, in this order, and stop
helpfully on each:

- **Not a git repo** → nothing here works. Say so and stop.
- **No remote** (`git remote -v` is empty) → the skill ends in a push and a PR, so there is
  nothing to push to. Say so, name `git remote add origin <url>` as the fix, and stop.
- **No `gh`/MCP write access** → same reason. Stop rather than discovering it after the code
  is written.
- **No detectable way to run tests** — no test target in a Makefile, no test script in
  `package.json`, no `pytest`/`tox`/`go test`/`cargo test` reachable, nothing in CI that
  runs one. **Stop here.** Say plainly that `/code-development` refuses to commit without a
  real passing test run (hard rule 3), so a repo with no runnable test command has no
  usable gate. List exactly what you looked for and didn't find. Do **not** write a test
  harness, a CI workflow, or a placeholder command to get past this — building those is a
  development run's job, under the Task 1 gate, not setup's.

**4. Read CI first — it's the ground truth.** List the workflows and read what they
actually run:

```bash
ls .github/workflows/
gh workflow list --repo <owner/repo> --all
```

Take the concrete step commands out of the YAML — `npm run lint`, `pytest -q`, `make check`
— rather than inferring them from the language. Those are what the code must pass.

**5. Derive the local equivalents** from `Makefile`, `package.json`, `pyproject.toml`,
`tox.ini`, `go.mod`, `Cargo.toml`, and the linter/scanner configs. Note every check CI runs
that has **no local equivalent** — SonarQube, CodeQL, a hosted scanner, a matrix leg that
only exists on CI. That gap goes in the config verbatim so it's visible on every run instead
of being rediscovered or forgotten.

**6. Ask only what genuinely can't be read**, offering the derived answer for each so the
user is correcting rather than composing:

- which command is *the* test command, when the repo offers several (`test`, `test:unit`,
  `test:ci`) — offer the one CI uses
- whether PRs open ready for review or as drafts
- whether this repo has a UI worth screenshotting at all — offer `none` for a library, a
  CLI, or a backend service with no rendered surface
- how the app comes up for a screenshot run, and at what URL
- which paths count as docs, and where images live — offer what the repo actually has

**7. Write `.claude/code-development.yml`**, show it back in full, and ask for confirmation.

**8. Validate it by actually running the recorded commands, before committing anything.** A
config claiming `npm test` works when it doesn't is worse than no config at all — it turns
Task 2's gate into a lie that only surfaces mid-implementation.

Say which commands you're about to run and get a go-ahead first: these are the repo's own
scripts, and a `test` target can have side effects. Then run each of `commands.test`,
`commands.lint`, and any `typecheck`/`format`/`build` you recorded, and read the result
carefully, because the two failure modes mean opposite things:

- **The command doesn't exist, isn't executable, or errors on invocation** (`command not
  found`, an unknown npm script, a missing module) → the *config* is wrong. Fix the entry
  and re-run. Never commit a config in this state.
- **The command ran and the repo's own tests or lint failed** → the config is right and the
  repo is red. That's not a setup problem. Record the config as-is, say clearly which
  command failed and that it's pre-existing, and note that `/code-development` will refuse
  to commit until it's green.

If you fix an entry here, **show the corrected config again** before going further — the
user confirmed the version you had in step 7, not the one you changed.

If the user declines to run them, the commands are **unvalidated** — say so in the report
and in the PR body. Never describe them as verified.

**9. Commit it on a branch and open a PR.** This is the only write setup mode makes, and it
stays narrow. Step 1 established the tree was clean, so the config from step 7 should be the
only tracked change — but a validation run can leave untracked artifacts (`coverage/`,
`.pytest_cache/`, a `dist/`). Never stage those. If any of them aren't gitignored, say so;
that's a finding for a development run, not something to sweep into this commit:

```bash
git fetch origin <default branch>
git checkout -b chore/code-development-config origin/<default branch>   # branch off the
                                                                       # default, not
                                                                       # whatever is checked out
git add .claude/code-development.yml         # explicit path, never -A
git commit -m "Add code-development config for the /code-development skill"
git push -u origin chore/code-development-config
gh pr create --fill --base <default branch>
```

Never commit anything else in that commit, and never push to the default branch.

**10. Ask whether to merge it.** Merge only on an explicit yes, and only after the PR's own
checks are in a state the user accepts. If they'd rather review it themselves, leave the PR
open and say that the next `/code-development` run won't see the config until it lands on
the branch being worked from.

**11. Say which branch they're on now**, and switch back to where they started unless
they're continuing straight into a development run from here.

**12. Offer to continue into a development run.** The Task 1 sign-off gate still stands
between that point and any code being written, so continuing is safe — but say so rather
than assuming.

Setup mode **never** edits code, adds a test, adds a CI workflow, or starts Task 1. It
discovers, validates, records, and stops.

## The config

`.claude/code-development.yml`, in the repo being worked on:

```yaml
version: 1

branch:
  default: main                   # what feature branches are cut from
  prefixes:
    feature: feature/
    fix: fix/

commands:                         # the local gate — all of these must pass before a commit
  test: "npm test"
  lint: "npm run lint"
  typecheck: "npm run typecheck"  # omit if the repo has none
  format: "npm run format -- --check"
  build: "npm run build"          # omit if a build isn't part of the local gate

ci:
  workflows: [".github/workflows/ci.yml"]
  enforces: ["lint", "test", "typecheck", "codeql"]
  local_gap: "CodeQL runs only in CI — nothing local reproduces it"

pr:
  base: main                      # a stacked PR targets the stage below instead
  ready: true                     # false → open as a draft
  conventional_commits: true
  template: ".github/pull_request_template.md"   # omit if the repo has none

docs:
  paths: ["README.md", "docs/**"]
  images: "docs/images"

screenshots:
  mode: playwright-local          # playwright-local | playwright-mock | none
  start: "npm run dev"            # omit when mode is none
  url: "http://localhost:5173"
  viewport: "1280x800"
```

Required: `version`, `branch.default`, and a `commands` block containing at least `test`.
Everything else is optional, and **every omission has exactly one defined behavior** — never
improvise a different one:

| Omitted | Behavior |
|---|---|
| `branch.prefixes` | `feature/` and `fix/` |
| `commands.lint` | No lint step in the Task 2 gate — say so, don't invent one |
| `commands.typecheck` / `format` / `build` | Not part of the gate |
| `ci` | Nothing is claimed about what CI enforces; the CI-vs-local gap goes unstated |
| `pr.base` | `branch.default` |
| `pr.ready` | Ready for review, not draft |
| `pr.template` | The Finish template below |
| `pr.conventional_commits` | True |
| `docs.paths` | Discover `docs/`, `README.md`, a wiki dir — whatever the repo has |
| `docs.images` | `docs/images` |
| `screenshots.viewport` | `1280x800` |
| `screenshots` entirely | Treat as `mode: playwright-local`, discovering the app's start command in Task 3 exactly as an unconfigured repo would |

## Phase 0 — Orient

Three steps, in order. Verify with real commands; assume nothing.

**1. Ground it.**

```bash
git rev-parse --show-toplevel && git branch --show-current
gh repo view --json nameWithOwner,defaultBranchRef
git status --porcelain      # dirty tree → stop and ask; never sweep stray work into a feature
```

**2. Load the config.** Read `.claude/code-development.yml` (accept `.yaml` too). Three
outcomes — say which one you're in before doing anything else, and never silently degrade:

- **Found** — echo the resolved config back in one short block: the test and lint commands
  that will gate the commit, the branch it'll cut from, whether the PR opens ready or draft,
  the screenshot mode, and the recorded CI-vs-local gap. The user should be able to catch a
  wrong value here, before any of it matters. **Skip toolchain rediscovery** — the file is
  the answer. Skipping it isn't the same as trusting it blindly: rule 7 still holds, and a
  recorded command that turns out not to exist gets caught at the point of use in Task 2,
  where it's a stop rather than a substitution.
- **Absent** — say so and offer `/code-development init`. If they take it, run Setup, then
  come back here. If they decline, run the toolchain discovery inline for this run only and
  say plainly that nothing is being recorded.
- **Present but unparseable, or missing a required key** — stop. Name the offending key.
  Don't fall back to defaults for a required field, and don't improvise a config to keep the
  run going.

`branch.default` is the branch feature work is cut from, which is usually — but not always —
the repo's GitHub default. A project that develops off `develop` records that, and rule 4
still forbids pushing directly to either. If the two differ, say so in the echo rather than
letting it surprise someone at PR time.

**3. Check the branch you'll actually cut from is current**, now that you know which one it
is:

```bash
git fetch origin
git rev-list --count <branch.default>..origin/<branch.default>   # >0 → local is behind:
                                                                 # say so and ask whether to
                                                                 # pull before branching
```

Classify the request — **feature, bugfix, or patch**. All three run all three tasks. A
bugfix can change how something looks, and stale screenshots left in the docs after a fix
are a defect; Task 3 may conclude "no doc changes needed," but only after actually checking,
never by category ("it's just a bugfix").

Then state the toolchain: the CI checks, the local equivalents, and any gap between them —
read from the config, or discovered inline if there isn't one.

## Task 1 — Scope and design

Goal: a written plan with zero open questions, signed off by the user.

Open by reminding the user this task is best run in **plan mode** (Shift+Tab twice in Claude
Code), so nothing gets edited while the design is still open.

1. Restate the request in your own words — what the change is *for*, not just what it says.
   A fix that clears the symptom but contradicts the intent is the wrong fix.
2. Read before asking: the code in the affected area, related modules, existing tests,
   existing docs, and recent PRs touching the same files. Repo conventions win over generic
   best practice when they conflict.
3. Research best practices for anything unfamiliar — web search the library, pattern, or
   security guidance involved. Cite what was found; "best practice says" with no source is a
   guess wearing a suit.
4. Enumerate every open question and every design decision with more than one viable
   approach. For each decision: the options, their tradeoffs, which you'd pick and why. Ask
   them together in one message where possible, not as a drip-feed.
5. Size it. A standard task is one PR a reviewer can hold in their head — one concern, a
   handful of files. Bigger than that → propose a **stacked-PR breakdown**: stage 1 branches
   off `branch.default`, each later stage branches off the previous, each PR targets the
   branch below it, landed bottom-up. Docs get their own stacked PR on top of the
   implementation stage(s) when the change is large; on a standard-size task they ride the
   same PR as separate commits. Name every branch in the plan.
6. Write the plan: scope, out of scope, each design decision as resolved, files expected to
   change, test plan, doc and screenshot impact, PR structure (single or stacked, with
   branch names and bases).

**Gate:** post the plan and stop. Task 2 starts only on explicit sign-off — "approved",
"go", or an edit followed by a go. Silence is not sign-off. If implementation later reveals
the plan was wrong, this gate reopens; the plan is amended and re-approved, not quietly
outgrown.

## Task 2 — Implement

Goal: the planned change, at quality, committed on a branch with green local tests.

1. Branch: `<branch.prefixes.feature><slug>` or `<branch.prefixes.fix><slug>` — `feature/`
   and `fix/` by default — cut from an up-to-date `branch.default`, or from the previous
   stage's branch when stacked.
2. Implement exactly the plan — the smallest change that fully delivers it. Anything that
   turns out to need more than the plan said is a stop: reopen the Task 1 gate.
3. Write to scanner standards even where the scanner can't run locally. The recurring
   Sonar/CodeQL/lint findings to design out rather than patch up afterward:
   - Validate and bound every external input. Parameterize queries. Never build shell
     commands, SQL, or file paths by concatenating user input.
   - Handle every error path explicitly — no swallowed exceptions, no bare `except`/empty
     `catch`, no ignored return values.
   - No secrets in code, config, tests, or fixtures. Ever. Not even placeholders that look
     real.
   - No duplicated blocks, no dead code, no TODO standing in for an implementation. Keep
     cognitive complexity down by extracting functions, not by nesting deeper.
   - Release everything acquired — files, connections, locks. Prefer context managers,
     `defer`, try-with-resources.
   - No new dependency and no version pin the plan didn't approve.
4. Tests: targeted tests for the changed area, per the plan's test plan. A bugfix's test
   must fail on the pre-fix code — verify that by actually running it against the unfixed
   code, don't assume it.
5. Run the gate: every command in the config's `commands` block — `test`, `lint`, and any
   `typecheck`/`format`/`build` recorded — or, with no config, the equivalents discovered in
   Phase 0. All green → commit. Anything red → fix it or stop and report. Committing red is
   never in bounds, and neither is narrowing the test run until it passes. **If a recorded
   command isn't found**, the config is stale: stop, name the key, and say what the repo has
   instead. Don't substitute a command of your own choosing.
6. Commits: Conventional Commits when `pr.conventional_commits` is true (`feat:`, `fix:`,
   `test:`, `refactor:` only when the plan called for one), one concern per commit,
   implementation only — docs come in Task 3's own `docs:` commits. Stage files by name.

**Gate:** tests green, work committed, tree clean. Report the exact commands run and their
real output before moving on.

## Task 3 — Document

Goal: the docs match the code that was just written, images included.

1. Find the docs: `docs.paths` from the config, else `docs/`, `README.md`, a wiki directory
   — whatever the repo actually has. **No docs at all → create or extend `README.md`.** That
   is the floor, not an option to skip.
2. Write or update: what the change does, how to use it, config or flags added, breaking or
   behavior changes. For a bugfix: check whether existing docs describe the old, broken
   behavior, and correct them.
3. Screenshots, whenever the change is user-visible and `screenshots.mode` isn't `none`:
   - Get the application running locally with `screenshots.start` at `screenshots.url` —
     or, with no config, discover how from the README, scripts, and compose files, the same
     way the toolchain was discovered. If a real run isn't possible in this environment,
     fall back to mocked data or component-level rendering under Playwright — and say
     plainly which of the two produced each image.
   - Capture with Playwright at `screenshots.viewport` (1280×800 by default, unless the
     repo's existing images establish otherwise), saved to `docs.images` (else where
     existing images live, else `docs/images/`), named for the feature, not the date.
   - **Stale-image sweep, every run, bugfixes included:** list the existing doc images that
     touch the changed area and re-capture any the change visibly altered.
   - If neither a local run nor a mock will render: capture nothing, claim nothing. List the
     exact captures still needed in the PR body as follow-up. A fabricated or misattributed
     screenshot is worse than a missing one.
   - `screenshots.mode: none` means this repo has nothing to screenshot. Say that's why
     there are no images; don't treat it as a skipped step.
4. Commit docs separately (`docs:` commits) on the same branch — or on the docs stage's
   branch when stacked.

## Finish — push and open the PR

1. Push the branch. For stacked work, push each stage's branch.
2. Open the PR with an **explicit base** — `pr.base` (defaulting to `branch.default`), or
   the previous stage's branch for a stacked PR. `gh pr create` without `--base` targets the
   repo's default branch, which silently flattens a stack into one enormous PR:

   ```bash
   gh pr create --base <pr.base or the stage below> --title "<title>" --body-file <file>
   ```

   Ready for review unless `pr.ready` is false or the user said otherwise; add `--draft`
   when it is.
3. PR body, fully filled. Use `pr.template` if the repo has one; otherwise this template:

   ```
   ## What
   <the change in plain terms — what it does and why>

   ## Changes
   - <path> — <what changed and why>

   ## Tests
   <exact commands run and their real results — or "not run — <reason>">

   ## Docs
   <what was updated; screenshots added or replaced and how they were captured
   (real run vs. mock); stale images swept — or why no doc change was needed>

   ## Risks / follow-up
   <noticed but not handled; screenshot captures still needed; etc.>
   ```

4. Hand off. The push triggers CI, and **pipeline-monitor loads automatically from here** —
   watching runs, diagnosing failures, fixing or escalating is its job, not this skill's.
   Say the handoff happened; do not duplicate it.

## Scope boundaries

**Always in bounds**

- Reading anything in the repo; web research during Task 1.
- The planned change, its tests, its docs, its screenshots.
- Offering (never silently adding) a basic CI workflow when none exists — in a development
  run, under the Task 1 gate.
- Writing `.claude/code-development.yml` in setup mode, after showing it and getting
  confirmation — committing that one path on a branch, pushing, opening a PR, and merging
  that PR on an explicit yes.
- Running the repo's own recorded commands to validate the config in setup mode, after
  saying which ones and getting a go-ahead.

**Never in bounds, even when it would be faster**

- Starting Task 2 without sign-off, or Task 3 with red tests.
- Committing or pushing code whose local tests didn't run or didn't pass.
- Pushing directly to the default branch or to `branch.default`, force-pushing, or
  `git add -A`.
- Weakening any check to get green — skipping tests, loosening lint rules, lowering
  coverage, `continue-on-error`, excluding files from a scanner.
- Expanding scope beyond the signed-off plan without reopening the gate.
- A new dependency, schema change, or workflow edit the plan didn't approve.
- Fabricating a screenshot, or presenting a mock as the real application.
- Writing, committing, or authoring **any file other than `.claude/code-development.yml`
  while in setup mode** — no code, no tests, no docs, no CI workflow. Setup records; it
  doesn't build.
- Recording a command in the config without running it, or describing an unvalidated
  command as verified.
- Substituting a different command when a recorded one is missing, instead of stopping.
- Merging the config PR without an explicit yes.
- Watching, re-running, or diagnosing CI — that's pipeline-monitor's job.

## Stop and ask when

- The repo has no remote, or `gh`/MCP has no write access to it (Phase 0 and Setup) — both
  modes end in a push and a PR.
- No test command is detectable anywhere, so there is no gate to commit behind (Setup).
- A config already exists and Setup was asked to write one (Setup).
- The config is missing a required key, won't parse, or names a command the repo doesn't
  have (Phase 0 and Task 2).
- Any design decision has more than one viable approach — Task 1 exists to surface these,
  not to smooth past them.
- The working tree is dirty (Phase 0 and Setup), or the branch you'd cut from is behind
  origin (Phase 0).
- Implementation reveals the plan was wrong or incomplete.
- The correct fix and the fast fix disagree — surface the tradeoff, pick nothing.
- A schema change, new dependency, or workflow change turns out to be needed.
- Local tests can't run in this environment.
- The app won't run and mocks won't render, so a needed screenshot can't be captured.
- No CI workflows exist — offer to create them, then wait for the answer.

## Reporting

Every task ends with its own block; the run ends with the PR link. Fixed format:

    ## code-development — <setup | scope | implement | document | finish> — <slug>

    **Target:** <repo> @ <branch> (default: <trunk>)
    **Config:** `.claude/code-development.yml` <loaded | written this run, PR <link> |
    absent — discovered inline, nothing recorded>
    **Status:** <config written, commands validated | config written, commands UNVALIDATED |
    plan awaiting sign-off | committed, tests green | docs committed | PR open: <link>>

    **Done:** <what this task actually produced>
    **Commands run:** <exact commands and their real results, or "not run — <reason>">
    **Open questions:** <anything blocking the next task, or "none">

Never fill **Commands run** with anything that did not execute. "Not run — <reason>" is a
correct answer; a fabricated pass is the one failure mode that makes this skill worse than
developing by hand. In setup mode the same rule covers validation: a command that wasn't run
is reported as unvalidated, never as working.

## If something doesn't match reality

The config describes what the repo *was* when someone wrote it. The repo is what is true
now. When they disagree — the test script was renamed, the default branch moved, the docs
directory changed — **trust the repo, say exactly what you found, and stop** rather than
forcing the run to match the config. Tell the user which key is stale so they can fix
`.claude/code-development.yml` in the same breath.

No repo, no `gh`, no discoverable way to run the tests, an application that won't start, a
toolchain this skill can't identify — say exactly which, report what was and wasn't done,
and stop. Don't reconstruct test results from reading the code, don't infer what CI enforces
from the language alone, and don't present a mocked render as the live app. A plan built on
an unverified assumption gets signed off and then implemented — which is exactly how a wrong
guess becomes permanent.
