---
name: ci-pipeline
description: Watches every CI run a gitops action kicks off — push, PR, merge, tag or dispatch — on the checked-out repo/branch. Load it automatically, without being asked, the moment a push, PR or merge happens in this session, including one you just made; finishing a push is not finishing the task. Monitors all active runs; on a failure it reads that job's real logs, prints what broke, then re-runs once for a real infra blip (OOM, timeout, rate limit), or makes the smallest safe fix with a regression test, pushes, and comments on the PR. For a larger problem it stops and lays out options with tradeoffs, recommending a stacked PR. Never guesses. Never skips, disables or loosens a check, or pushes to trunk. `/ci-pipeline init` records which checks gate a merge and how to run each locally. Also use on /ci-pipeline, /devops, /pr-pipeline-watch, "set up ci-pipeline", any question about CI, a build or a red check, or a bare "did that pass?". Not for feature work or releases (/release). Needs `gh` — Claude Code only.
---

# ci-pipeline

Watches the CI pipeline for the repo and commit you're working on — after a push, an opened
or merged pull request, a tag, or any other gitops action that kicks off a run — figures out
why a check failed, fixes the actual cause, and reports back. This skill has real side
effects: it re-runs jobs, cancels runs, commits, pushes, and comments on PRs. Move
deliberately in Phase 5, which is where "am I fixing the bug or hiding it" gets decided.

What this repo's CI actually *is* — which checks exist, which ones block a merge, how to
reproduce each one locally, which are safe to re-run — comes from
**`.claude/ci-pipeline.yml` in the repo being watched**, written by `/ci-pipeline init`.
Without it the skill still runs, deriving all of that from the repo on every single wake —
slower, and worse at exactly the moment a pipeline is red. Either way this skill hardcodes
nothing.

The hard rules, restated up front because they're the ones that erode under "just get it
green" pressure:

1. **Root cause, not symptom.** Trace the failure back to what is actually broken.
2. **No cheap fixes.** If the pipeline goes green but the underlying bug is still there,
   that is a failure of this skill, not a success.
3. **No unrelated changes.** Fix the failing check. Nothing else.
4. **Never push to the trunk branch.** A fix always lands on a topic branch via a PR.
5. **Never claim a command ran that didn't run.** "Not run — <reason>" is a fine answer. A
   fabricated pass is not.
6. **Never guess.** Not at a root cause, not at a job id, not at what a log said, not at
   what a check enforces. If you don't know, go find out with a real command — and if you
   can't, say so and stop. A guess baked into a CI fix gets pushed.
7. **Setup mode commits exactly one file; a run commits only the fix.**
   `.claude/ci-pipeline.yml` is written by `/ci-pipeline init` alone, on a branch cut from
   trunk, after the user has seen it — and **never edited during a run to change how that
   run ends**. Downgrading a check in the config is the same cheap fix as downgrading it in
   CI. `git add -A` is never correct in either mode.

## The two modes

Pick the mode before doing anything else, and say which one you're in.

| Invocation | Mode | Writes anything? |
|---|---|---|
| `/ci-pipeline init`, "set up ci-pipeline", "configure CI watching" | **Setup** — inventory the repo's real CI, write `.claude/ci-pipeline.yml`, open a PR for it | One file, on a branch, after confirmation |
| `/ci-pipeline`, a push/PR/merge in this session, "did that pass?", any red check | **Run** — Phases 0–9 | One job re-run, run cancellations, a fix commit on the topic branch, PR comments |

**Setup never diagnoses and never fixes. A Run never writes the config.** If a check is red
while you're in Setup, say so, finish setup, and then offer to watch.

Phase 0 then picks a *run mode* from the state of the checks — watch, post-hoc, or nothing
to do. That's a different axis from the two modes above; all three run modes live inside
**Run**.

**A Run with no config never silently interviews you.** Say the config is missing, then
split on whether anything is actually happening:

- **Checks are queued, running, or already failed** — watching wins. Do the whole run by
  deriving from the repo, exactly as this skill worked before configs existed, and offer
  `/ci-pipeline init` at the end. An interview started while a pipeline is in flight means
  nobody is watching the pipeline.
- **Nothing is running and nothing has failed** — there is nothing to watch, so **offer**
  Setup and stop. Do not start it unasked. This skill loads by itself after every push and
  on a bare "did that pass?", and Setup commits a file and opens a PR — a status question is
  not consent to either. Say there's nothing running, that `/ci-pipeline init` would record
  which checks gate a merge, and wait to be asked.

## Environment and tooling

- Prefer a connected **GitHub MCP server** if one is available — check the tools actually
  available in this session, not a registry of installable ones. Otherwise use the **`gh`
  CLI**. If neither is authenticated for this repo, stop and say so — never infer pipeline
  state from what the code "should" do.
- **Write access is required in Setup mode** (it pushes a branch and opens a PR) and at four
  points in a Run: re-running a job (Phase 3), cancelling runs (Phase 6), pushing the fix
  (Phase 8), and commenting on the PR (Phase 9). Reading runs, logs and checks — Phases 0,
  1, 2, 4 and 5 — needs read access only. If you have read access but not write, say so up
  front and stop at the diagnosis rather than discovering it at the push.
- Repo and branch are whatever Claude Code's working directory and checked-out branch
  actually are. Never assume a repo name.
- `git` is used directly throughout — status, SHAs, branches, the fix commit. This is not a
  chat skill.
- `gh` commands appear throughout as the concrete form. Use the MCP equivalent if that's
  what's connected; the sequence is the same either way.

## Setup mode — `/ci-pipeline init`

Runs once per repo. It inventories the CI that repo actually has and writes it down, so
every later run stops re-deriving the same facts from workflow YAML while a pipeline is
burning. Build it *from what the repo actually has* rather than by interrogating the user
about things you can read.

**1. Ground it.** Confirm you have `gh` or a GitHub MCP server **with write access** — Setup
pushes a branch and opens a PR. Then discover the repo, the current branch, and the trunk,
and check the tree is clean *before* you write anything:

```bash
git rev-parse --show-toplevel && git branch --show-current
gh repo view --json nameWithOwner,defaultBranchRef
git status --porcelain                     # must be empty
```

If the tree is dirty, stop and say so. Setup's one commit must not sweep up someone else's
work, and once the config is written you can no longer tell your change from theirs. Do not
stash on the user's behalf.

**2. Check for an existing config** at `.claude/ci-pipeline.yml` (accept `.yaml` too). If
one exists, show it in full and ask whether to update it or keep it — never overwrite a
config the user hasn't seen.

**3. Check the prerequisite that actually blocks people.** This skill *watches* CI. It does
not write CI. Find out whether there is anything to watch:

```bash
ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null
gh workflow list --all
gh api repos/{owner}/{repo}/commits/<trunk sha>/check-runs --jq '.check_runs[].name'
```

**If all three come back empty, stop here.** Say plainly that the repo has no CI — no
workflows, no external checks — so there is nothing for `/ci-pipeline` to watch and nothing
to record. Point at **`/code-development`**, which offers to add a basic workflow as part of
setting a project up. Show the shape so the user knows what's missing:

```yaml
on:
  push:
    branches: [ <trunk> ]
  pull_request:
```

Do **not** write that workflow yourself. Writing CI is `/code-development`'s job, not this
skill's. Point there and stop.

Two near-misses that are not the same stop, and should be named rather than lumped in:

- **Workflows exist, but none triggers on `push` or `pull_request`** — everything is
  `schedule` or `workflow_dispatch` only. Say exactly what they do trigger on, and that
  nothing will fire on a push, so a Run will correctly find no checks. Dispatching is out of
  scope here (`/release` does that). Ask whether to record the scheduled workflows anyway;
  usually the answer is no.
- **No workflow files, but external check-runs exist** on recent commits (SonarQube,
  Codecov, a hosted CI). That is a perfectly good config — record them as `workflow:
  external` and carry on.

**4. Inventory the checks as they actually appear.** The names on a real PR are ground
truth; names reconstructed from job keys are not. A matrix job named `build` in YAML shows
up as `build (20, ubuntu-latest)` on the PR, and a config that records `build` will never
match anything.

```bash
gh pr checks <a recent PR number>
gh api repos/{owner}/{repo}/commits/<recent sha>/check-runs --jq '.check_runs[] | {name, app: .app.slug}'
gh api repos/{owner}/{repo}/commits/<recent sha>/status --jq '.statuses[].context'
```

Take the observed names. Use `gh workflow view "<display name>" --yaml` to map each observed
check back to the workflow that produced it, and to read its triggers into `on:`.

**5. Derive the per-check facts you can read.**

- **`gate`** — required or advisory. Read it, don't ask:

  ```bash
  gh api repos/{owner}/{repo}/branches/<trunk>/protection --jq '.required_status_checks.contexts'
  gh api repos/{owner}/{repo}/rulesets                     # newer repos enforce via rulesets
  ```

  A `continue-on-error: true` job is direct evidence of `advisory`. If both endpoints come
  back 403 or 404 — they need admin — say the protection rules are unreadable from here and
  ask which checks block a merge. Do not assume every check is required, and do not assume
  none is.

- **`typical_minutes`** — from real runs, not a guess:

  ```bash
  gh run list --workflow "<display name>" --status success --limit 10 --json startedAt,updatedAt
  ```

- **`merge_queue`** — a merge-queue rule in the rulesets output, or `required_merge_queue`
  in branch protection. If neither is readable, ask once; it changes where Phase 1 looks
  after a merge, and getting it wrong looks exactly like "no checks exist".

**6. Derive the local reproduction commands, then confirm each one resolves.** Start from
the workflow's own `run:` steps — that is what CI actually executes. Then check each
candidate against this machine before offering it:

```bash
command -v <binary>
jq -r '.scripts | keys[]' package.json     # or: make -n <target>, cargo --list, tox -l
```

A workflow step is often *not* directly runnable here: it may run in a container, under a
`working-directory`, or with env the local shell doesn't have. Offer the derived command so
the user is correcting rather than composing, and record `null` where there genuinely is no
local equivalent. `null` is a correct answer — Phase 4 then says the check can't be
reproduced locally instead of inventing a command.

**7. Ask only what genuinely can't be read**, offering your derived answer for each:

- **`rerun` safety.** A job with an `environment:`, or steps that deploy, publish, push an
  image, or write to a shared external system, is a `rerun: never` candidate — offer that,
  and let the user confirm. Everything else defaults to `safe`. This is the one field where
  a wrong value has a side effect outside the repo.
- **Report preferences.** Does a CI finding belong on the PR as a comment, or in chat only?
  And is an infra flake that a re-run cleared worth a comment at all, or is that noise on a
  busy PR?
- Any check the repo runs that you could not observe on a recent commit — a workflow gated
  behind a path filter or a label, say.

**8. Write `.claude/ci-pipeline.yml`**, show it back in full, and ask for confirmation.

**9. Validate what you recorded, before committing anything.** A config that names a check
which doesn't exist is worse than no config — it makes Phase 1 wait forever for something
that will never appear. Three checks, all against reality:

1. Every `name:` appears in the check names you actually observed in step 4. Anything that
   doesn't, go back and fix — do not commit it "in case it shows up later".
2. Every `workflow:` other than `external` appears in `gh workflow list --all` under that
   exact display name.
3. Every non-null `local:` resolves here — the binary is on `PATH` and the script, target,
   or subcommand exists. Offer to run one of them as a smoke test; run it only if the user
   says yes, and report the real result. Never record a command you have neither resolved
   nor run.

Report the validation result explicitly. If something fails, fix the config and validate
again rather than committing and hoping.

**10. Commit it on a branch and open a PR.** This is the only write Setup makes into the
repo, and it stays narrow:

```bash
git status --porcelain                     # expect .claude/ci-pipeline.yml, plus anything a
                                           # smoke test in step 9 left behind
git fetch origin <trunk>
git checkout -b chore/ci-pipeline-config origin/<trunk>   # branch off trunk, not whatever
                                                          # happens to be checked out
git add .claude/ci-pipeline.yml            # explicit path, never -A
git commit -m "Add ci-pipeline config for the /ci-pipeline skill"
git push -u origin chore/ci-pipeline-config
gh pr create --fill --base <trunk>         # never omit --base
```

Never commit anything else in that commit, and never push to trunk. `git add` names the one
path, so nothing else can be staged by accident. If that first `git status` shows anything
beyond the config and the artifacts step 9's smoke test just created — `.pytest_cache/`,
`coverage/`, `node_modules/` — stop: the tree was clean at step 1, so something else changed
while you worked and it is not yours to commit. Leave the smoke-test artifacts unstaged, and
report any that aren't gitignored as a finding worth fixing. If the
branch switch refuses because a committed config already differs on trunk, switch first and
write the file again on the new branch rather than forcing anything.

**11. Ask whether to merge it.** Merge only on an explicit yes, and only after the config
PR's own checks are in a state the user accepts. **This is the only PR this skill may ever
merge.** If they'd rather review it themselves, leave the PR open and say that runs will
keep deriving from the repo until it lands on the branch being watched.

**12. Say which branch they're on now**, and switch back to where they started.

**13. Offer to continue.** If there are checks in flight or already failed on the current
commit, offer to go straight into a Run and watch them — noting that until the config PR
lands, that run still derives from the repo, because the config only exists on the config
branch. If there aren't, say so: there is nothing to watch, and the skill will fire on its
own at the next push.

## The config file — `.claude/ci-pipeline.yml`

One file per repo, committed to the repo being watched. It records what this skill would
otherwise re-derive from workflow YAML on every wake.

```yaml
version: 1

local:
  setup: "npm ci"                        # optional — run once before any `local` below

checks:
  - name: "build (20, ubuntu-latest)"    # the check name exactly as it appears on a PR
    workflow: "CI"                       # workflow display name, or `external`
    on: [push, pull_request]             # when this check is expected to appear
    gate: required                       # required | advisory
    local: "npm run build"               # how to reproduce it here, or null
    rerun: safe                          # safe | never
    typical_minutes: 4

  - name: "SonarQube Code Analysis"
    workflow: external
    on: [pull_request]
    gate: required
    local: null
    rerun: never
    details: "https://sonarcloud.io/dashboard?id=acme_app"

merge_queue: false                       # true → checks run on a queue ref, not your head SHA

report:
  pr_comment: true                       # false → report in chat only, never comment on the PR
  comment_on_flake: true                 # false → stay quiet when a re-run clears an infra blip
```

**Required:** `version`, and a non-empty `checks` in which every entry has `name`, `gate`
and `rerun`. Everything else is optional and defaults as shown: `local` and `details` null,
`on` unknown, `typical_minutes` unknown, `merge_queue: false`, both `report` flags true.

| Field | What it changes |
|---|---|
| `gate: required` | Must be green before the PR is done (Phase 8). A failure here gets diagnosed and fixed. |
| `gate: advisory` | Reported, never chased, never blocking. A red advisory check is a finding, not a task — say it's red, say it doesn't block, move on. |
| `rerun: safe` | Eligible for the single Phase 3 re-run, and only on a confirmed infra signal. |
| `rerun: never` | Never re-run, even on a clean infra signal — the job mutates something outside itself. Report the signal and go to Phase 4. |
| `local` | The Phase 4 reproduction command. `null` means this check cannot be reproduced here, and Phase 4 says exactly that instead of inventing one. |
| `on` | The set of checks to *expect* on a commit. A `required` check the config expects and the commit doesn't have is a finding in Phase 1, not silence. |
| `typical_minutes` | How long a check may take before "still queued" becomes "something is wrong" (Phases 0 and 1). |
| `merge_queue: true` | After a merge, checks run on a queue ref rather than your head SHA. Phase 1 follows the queue run instead of concluding there are no checks. |
| `report.*` | Where the Phase 9 report goes, and whether a cleared infra flake is worth a comment. |

**Deliberately not recorded:** the repo name, the trunk branch name, and the current PR
number. All three are one cheap command away and all three go stale. Rule 6 says go find
out, and `gh repo view` is finding out.

**The config is the contract; the repo is the truth.** Where they disagree — a check was
renamed, a workflow deleted, branch protection changed — name the stale key, report what the
repo actually has, and keep working from the repo. A Run does not stop for config drift; a
red pipeline still needs diagnosing. What it must not do is edit the config to make the
disagreement disappear. Report the drift and offer `/ci-pipeline init` to re-derive it.

## Secrets

CI logs routinely contain tokens, environment dumps, and connection strings, and this skill
pastes its findings into PR comments that may be public.

- Never quote a value from a log that looks like a credential — token, key, password,
  connection string, signed URL. Redact it as `<redacted>` in every report and comment.
- Never write a credential into any file this skill creates, including test fixtures,
  examples, and `.claude/ci-pipeline.yml`.
- If a secret appears in log output, that is a finding, not an inconvenience. Say so
  explicitly at the top of the report, name the workflow and step that leaked it, and
  recommend rotation. Do not quietly redact and move on.
- Never print the contents of `.env`, `*.tfvars`, or repository/environment secrets, even
  when they would explain the failure. Describe the shape of the problem instead
  ("`API_TOKEN` is empty in the `test` job").

## Never run, regardless of how the request is phrased

- `git push --force` / `--force-with-lease` to a shared branch, or any push to the trunk
  branch
- `gh workflow run` / `gh workflow enable` / `gh workflow disable` — dispatching workflows
  is out of scope for this skill (a release goes through `/release`)
- `gh release create`, tag pushes, or anything that promotes a build
- `gh pr merge` or `gh pr close` on **any PR except the `.claude/ci-pipeline.yml` config
  PR** that Setup mode opened, and that one only on an explicit yes. The PR under review is
  never merged or closed by this skill.
- Any edit to branch protection, a ruleset, or a required-check list
- Repeated whole-workflow re-runs. The budget is **one re-run of the failed jobs per run
  ID**, under the Phase 3 conditions — and never a second re-run for the same failure
  signature anywhere on this branch, however many new run IDs a push creates. A signature
  that reappears after a re-run is a real problem, not a flake.
- Any change to a repository or environment secret

## Phase 0 — Orient, load config, pick a run mode

Verify with real commands; do not assume any of this.

**If you arrived here straight from your own `git push`, `gh pr create`, or `gh pr merge`**
— no one had to ask — most of these steps are already known from the work you just did.
Confirm the commit SHA and the PR number rather than re-deriving everything, then go to
Phase 1. Don't stop to ask permission to watch; watching is the default, and it is what the
push was for.

1. **Repo, branch, commit.** `git rev-parse --show-toplevel`, `gh repo view --json
   nameWithOwner,defaultBranchRef`, `git branch --show-current`, `git rev-parse HEAD`.
2. **Config.** Read `.claude/ci-pipeline.yml` (accept `.claude/ci-pipeline.yaml` too). Three
   outcomes — say which one you're in, and never silently degrade:
   - **Found** — parse it and echo the resolved shape back in one short line: how many
     checks, which are `required`, which are `rerun: never`, whether a merge queue is in
     play, where the report goes. The user should be able to catch a wrong value here,
     before it matters.
   - **Absent** — say so and keep going. Which way it splits depends on whether anything is
     actually running, and you don't know that until step 8, so decide there: checks in
     flight or already failed → derive everything from the repo for this run and offer
     `/ci-pipeline init` in the report; nothing running and nothing failed → route into
     Setup and say so.
   - **Present but unparseable, or missing a required key** — say which key, then **carry on
     without it**, deriving from the repo for the rest of this run. **Never route into Setup
     from here**: a broken config gets replaced deliberately, not in the middle of a
     diagnosis, and a red pipeline is not a reason to stop and interview someone. Put the
     parse error in the report and point at `/ci-pipeline init`.
3. **Is the working tree clean?** `git status --porcelain`. If it isn't, stop and ask before
   going further — this skill commits and pushes, and uncommitted work would get swept into
   a CI-fix commit. Do not stash on the user's behalf.
4. **Is local HEAD what the remote has?** `git rev-list --left-right --count HEAD...@{u}`
   prints two numbers: **left = commits you have that the remote doesn't (ahead), right =
   commits the remote has that you don't (behind)**. Behind: the diagnosis would be built on
   a stale tree — say so and stop. Ahead: the run you're about to read predates your local
   commits; name that explicitly before continuing. If the command fails with "no upstream
   configured", the branch was never pushed, so there is no run to diagnose — say that and
   stop rather than improvising.
5. **Branch class.** Compare the current branch to the repo's trunk (`defaultBranchRef` from
   step 1 — do not assume it is called `main`; some repos use `develop` or something else
   entirely, and some have no `main` at all).
   - **Topic branch** — fixes land here directly.
   - **Trunk** — fixes never land here directly. See Phase 8.
6. **Open PR?** `gh pr view --json number,url,state,body,baseRefName`. Note the number for
   Phase 9. If there is no PR, **stop and ask** whether to proceed anyway or wait until one
   exists — with no PR there's nowhere to post the report, and nobody is reviewing the
   branch you'd be pushing commits to. Diagnosing is fine either way; it's the pushing that
   needs the go-ahead.
7. **Know what the change is actually for** — its PR description, linked issue, or what you
   already know from the session that wrote it. This is the whole advantage of running here
   rather than from a detached auto-fix workflow: a fix has to be consistent with what the
   change is *trying to do*, not merely produce a green checkmark. Carry this into Phase 5,
   where it decides whether a candidate fix is the right one or just the fast one.
8. **Pick a run mode**, from whether checks on this commit are still running:
   - **Watch mode** — checks are queued or in progress. Phase 1 follows them to completion.
   - **Post-hoc mode** — every check has already concluded and at least one failed. Phase 1
     collects them.
   - **Nothing to do** — every check the config expects has passed, or no checks exist for
     this commit. Checks take a few seconds to register after a push, and "just pushed,
     follow the pipeline" is this skill's most common entry point — so before concluding no
     checks exist, wait ~15s and re-poll at least twice. With a config, compare against the
     checks its `on:` says to expect rather than against nothing, and with `merge_queue:
     true` look for the queue's run after a merge before concluding the checks vanished.
     Only then say so. Never report on a run from an older commit as though it were current.
     This is also where step 2's absent-config split resolves: with no config and nothing to
     watch, **offer** `/ci-pipeline init` and stop — never start it unasked. With a config,
     stop here.

If the repo turns out to have no CI at all — no workflows, no external checks on any recent
commit — that isn't "nothing to do", it's nothing to watch, ever. Say so and point at
`/code-development`, exactly as Setup step 3 does. Do not write a workflow.

## Phase 1 — Attach to every check on this commit

The unit is the **commit**, not "the latest run". A single push commonly triggers several
workflows (build, lint, CodeQL) plus external checks that are not GitHub Actions at all.

1. List Actions runs for the exact SHA: `gh run list --commit <sha>`. Expect more than one.
   Handle all of them, not just the most recent.
2. List every check, including external ones: `gh pr checks <pr>` — or, with no PR, `gh api
   repos/{owner}/{repo}/commits/<sha>/check-runs` and `.../status`. SonarQube, Codecov, and
   similar report as commit statuses or check runs with no Actions run behind them.
3. **Compare what showed up against what the config expects.** A check with `gate: required`
   whose `on:` includes this event, and which is nowhere on the commit, is a finding — a
   renamed check, a deleted workflow, or a path filter that excluded it. Report it by name.
   Never treat an absent required check as a passing one. With no config, there is no
   expected set, so say that the completeness of this list is unverified.
4. **Watch mode:** follow to completion rather than sampling once. With a PR, `gh pr checks
   <pr> --watch` covers external checks too. With no PR, `gh run watch <run-id>
   --exit-status` follows each Actions run — but it will not see external checks, so re-poll
   `gh api repos/{owner}/{repo}/commits/<sha>/check-runs` alongside it rather than dropping
   them silently. Do not poll a couple of times and declare a result — a check that is still
   queued is not a passing check. Report transitions as they happen (queued → running →
   pass/fail, per check) rather than going silent until everything concludes.
   `typical_minutes` is what separates "slow, as usual" from "this one is stuck"; say which
   you think it is rather than going quiet either way.
5. Keep **all** active runs under watch — not just the one that looks most relevant. The
   moment any job concludes as a failure, go straight to Phase 2 and assess it; do not wait
   for the other checks to finish first. They stay running in the background, and Phase 6
   decides what happens to them.
6. **A failing `gate: advisory` check does not start a fix.** Read its log and report what
   it found, then keep watching the required ones. It is a finding for the report, not a
   task. Only fix it if the user asks.
7. When everything the config marks `required` concludes green, say so plainly — naming any
   advisory check that is red — and stop. That is a successful outcome, not a reason to look
   for something to fix.

## Phase 2 — Read the actual failing log

The check name tells you *what* failed. Only the log tells you *why*. Never skip to a fix
from the job name alone.

1. `gh run view <run-id> --log-failed` for a first look.
2. On a large or matrix run that returns a wall of text, get the failing job's numeric id
   from `gh run view <run-id> --json jobs` (the `databaseId` field — not the job's name) and
   narrow to it with `gh run view --job <databaseId> --log`. `--job` resolves the run on its
   own; don't also pass the run id. If output is still truncated, work backwards from the
   end of the log — the failing step's output is near the tail, and a truncated middle is a
   real risk of reading the wrong error.
3. **For a non-Actions check** (SonarQube, Codecov, an external status), there is no Actions
   log to read. Start from the config's `details:` URL for that check if it has one,
   otherwise follow the check's `details_url` from the check-run API, or the annotations
   attached to it (`gh api repos/{owner}/{repo}/commits/<sha>/check-runs` includes
   `output.summary` and `output.annotations_url`). If the detail is behind a service this
   session cannot reach, say exactly that and report what the check surfaced — do not guess
   at the rule it flagged.
4. Distinguish the first real error from its downstream noise. A single missing dependency
   produces dozens of red lines; the first one is the one that matters.
5. **Print what you found, in chat, as soon as you have it** — this is the immediate
   plain-English readout, separate from and earlier than the formal Diagnosis comment posted
   at the end of Phase 5. Do both; the chat readout is not optional just because a template
   comes later. Include: the failing check, the exact failing step, the relevant log excerpt
   (secrets redacted), and what it means in plain terms. Don't hold it until the fix is
   ready.

## Phase 3 — Classify: infra blip or real failure

Decide which kind of failure this is *before* deciding what to do about it.

**Infrastructure signals** — the log shows one of these and nothing implicating the code
under test:

- Runner disk exhaustion ("No space left on device")
- OOM kills (exit code 137, "Killed", "OOMKilled")
- Timeouts or connection failures reaching an external service (registry pulls, package
  installs, "could not resolve host", "connection reset")
- Rate limiting (429, "API rate limit exceeded")
- Cache service errors ("Failed to restore cache", 503 from the cache service)
- Runner allocation problems (queued and never picked up, self-hosted runner offline)

If and only if you see one of these:

1. **Check the job's `rerun` setting first.** `rerun: never` means the job mutates something
   outside itself — a deploy, a publish, a shared environment — and re-running it has
   consequences a green checkmark won't show. Report the infra signal, say the job is marked
   never-rerun, and go to Phase 4. With no config, ask before re-running any job whose name
   suggests deployment or publication; everything else is treated as `safe`.
2. Re-run **only the failed jobs**, not the whole workflow: `gh run rerun <run-id>
   --failed`.
3. **Wait for the result** — `gh run watch <run-id> --exit-status`. Do not assume it passed
   and do not move on while it is in flight.
4. Passes on that single re-run: no code change needed. Post the infra-flake comment (Phase
   9, subject to `report.comment_on_flake`), then **return to Phase 1 and keep watching the
   remaining checks**. A flaky job is often the first of several to conclude — don't exit
   while build, lint, or e2e are still in flight.
5. Fails again with the same signature: it is not a one-off. This signature is now spent for
   the whole branch — do not re-run it again on a later run ID either. The resource
   constraint itself is now the root cause — continue to Phase 4. A legitimate fix might be
   a larger runner, a real memory leak, or retry/backoff around a genuinely flaky network
   call in the workflow. **Do not re-run a second time.** A repeat failure means something
   has to actually change.

**Everything else** — a failing assertion, a type error, a missing dependency, a bad config,
a quality-gate violation, a real bug a test caught — skip the re-run entirely and go to
Phase 4.

Re-running is for a confirmed infra signal, once. Re-running a failure without one, or
re-running repeatedly hoping for green, is the same cheap-fix pattern rule 2 rules out.

## Phase 4 — Root-cause it, and reproduce it

1. Trace the failure back to the change that caused it. "Test X failed" is not a root cause;
   "the new nullable column isn't handled in the serializer, so X fails on any record
   created before the migration" is.
2. **Reproduce it locally before writing a fix.** The config's `local.setup` and that
   check's `local:` command are exactly this — run them rather than reconstructing a command
   from workflow YAML. With no config, derive the command from the workflow's `run:` steps
   and say that's what you did, since a derived command can differ from what CI runs. A fix
   that goes green without a reproduced failure is a guess, and this is the cheapest place
   to find out you were wrong.
3. If the check's `local:` is `null`, or you cannot reproduce it for any other reason, say
   so explicitly and carry that caveat all the way into the report. It lowers confidence in
   the fix; it should be visible. Never invent a reproduction command to fill the gap.
4. Check whether the failure is in code this branch actually touched. If it isn't, this is
   likely pre-existing breakage or an upstream change, which is a Phase 5 escalation, not a
   quick fix.

## Phase 5 — Size the fix: targeted, or escalate

**Escalate and stop** — report the root cause and hand it back, rather than attempting it
inline — when any of these is true:

- The fix touches more than one module, or more than two source files (the regression test
  doesn't count toward the limit).
- The fix is small but could plausibly have side effects elsewhere — a shared utility, a
  config default, an exported signature, anything other code depends on. Countable size is
  the easy criterion; small-but-risky is the one that actually bites.
- It requires a schema change or a data migration.
- It requires a dependency or provider version change.
- It requires changing workflow YAML beyond what a genuine infra fix requires.
- The failure is in code this branch didn't touch (pre-existing or upstream breakage).
- The root cause still isn't clear-cut after reading the actual logs.
- The correct fix and the fast fix disagree. Surface the tradeoff; do not pick one silently.

Escalating is a successful outcome for this skill. A diagnosed failure handed back with a
clear root cause beats a sprawling inline fix made under pressure.

**Escalating means offering options, not just declining.** Don't stop at "this is too big."
Lay out **two or more concrete ways to solve it**, each with its real tradeoff — what it
costs, what it risks, what it leaves unresolved, and how long it plausibly takes. Say which
you'd pick and why, then let the user choose. A single take-it-or-leave-it recommendation
isn't an escalation, it's a decision made on their behalf.

**Recommend a stacked PR.** The fix belongs on its own branch cut from the *current* branch,
with its own PR targeting the current branch — not merged into this one, and not branched
off trunk. That keeps the two development streams separate: the feature under review stays
reviewable on its own, and the larger fix gets reviewed on its own merits, without one
blocking the other. Name the branch and the base explicitly in the recommendation (`git
switch -c <fix-branch>` from the current branch, then `gh pr create --base
<current-branch>`). Recommend it — don't create it unless the user says to. Say it directly
to the user in chat as well as in the PR comment; don't let an escalation live only in a
comment they might not read for hours.

If Phase 0 classed the current branch as **trunk**, there is no feature branch to stack on:
the fix branch is cut from trunk and its PR targets trunk, which is the Phase 8 trunk
procedure. Follow that instead — same shape, different base.

After recommending: post the formal diagnosis (next paragraph), pass through Phase 6 to stop
the rest of the run, then stop for good on *this* failure — don't half-fix it. If other
checks in this run were still being watched and haven't failed, the escalation ends work on
this failure only; say plainly which checks are being left unresolved.

Judge a candidate fix against what the change is *for* (Phase 0, step 7), not just against
the check. A fix that clears the gate but contradicts the intent of the PR is the wrong fix,
even when it's small.

**Post the diagnosis now, before writing any code** (template in Phase 9) — whichever way
the sizing went. It's the paper trail either way, and it puts a root cause on record even if
the fix stalls. This is the point where the Plan line can be filled in honestly, because
fix-or-escalate has just been decided.

These two lists bound the **fix**. Setup mode's single write is bounded separately, in hard
rule 7 and in Setup steps 8 and 10.

**Always in bounds** (when none of the above triggered):

- The smallest change that addresses the actual root cause.
- A targeted regression test for the specific thing that broke, in the area that changed.

**Never in bounds, even if it makes the pipeline pass:**

- Skipping, disabling, or loosening a failing test, assertion, lint rule, or quality gate
  instead of fixing what it caught.
- Lowering a coverage threshold, adding a SonarQube exclusion, or annotating a finding as
  won't-fix to clear a gate.
- **Editing `.claude/ci-pipeline.yml` to change how this run ends** — flipping a check to
  `advisory`, a job to `rerun: safe`, or `pr_comment` to false. That is the same cheap fix
  in a different file. The config is written in Setup mode and read everywhere else; drift
  gets reported, not edited away.
- Padding timeouts, adding blanket retries, or adding `continue-on-error` to hide a real
  failure. Narrow, justified backoff around a *specific* external call whose flakiness you
  confirmed in Phase 3 is a different thing and is allowed — the test is whether you can
  name the call and the observed failure. "Retry the job" is never that.
- Hardcoding an expected value, mocking around the actual bug, or swallowing an exception
  instead of fixing its cause.
- Pinning a dependency to dodge a break without understanding why it broke.
- Any rename, restructure, or "while I'm in here" cleanup unrelated to the failing check.
- Any change to `.github/workflows/*.yml` beyond what a genuine infra fix requires — and
  never one that makes a check optional, conditional, or non-blocking. Reordering steps,
  bumping an action version, or adding a step to route around the failure are all out. A
  check that seems wrong or flaky by design is a finding to report, not something to quietly
  work around.
- Any change to a file the failing check doesn't implicate.

## Phase 6 — Clear the rest of the run (watch mode only)

Once you know a check failed for a real reason and a code fix is needed — **whether you're
about to make it yourself or you just escalated it** — the other still-running checks on
this commit are about to be superseded by a new commit anyway (yours, or whoever picks up
the escalation). Cancel them so they aren't burning runners on a commit that's being
replaced: `gh run cancel <run-id>` for each in-flight run on this SHA.

An escalation still passes through this phase before stopping. The run needs to stop either
way. In post-hoc mode nothing is in flight, so this phase is a no-op — say "none" on the
Checks cancelled line rather than skipping the line.

Before cancelling, let any check that is nearly finished conclude — a second failure you
could have observed for free is worth more than the runner minutes saved, and once cancelled
you cannot diagnose it on this commit. `typical_minutes` is how you tell "nearly finished"
from "just started". Record every run you cancel; those checks are undiagnosed, not passing,
and they go in the report.

- Only once the diagnosis is confirmed and a code fix is known to be needed — whether *you*
  are about to make it or you escalated it for someone else to make. Never cancel while
  still diagnosing; you may still need those logs.
- Only runs tied to the current head SHA. Never another PR's runs, and never anything
  already completed.
- External checks (SonarQube and similar) generally cannot be cancelled this way. Leave
  them; they'll be superseded on their own.
- This is **not** the same as disabling a check. Nothing about any check's configuration
  changes, and everything runs fresh and in full the moment a new commit lands.
- If a diagnosis later turns out to be a false alarm, say so in the PR comment. Never leave
  cancelled runs unexplained — every one appears in the report's "Checks cancelled" line.

## Phase 7 — Fix and test honestly

1. Write the fix, scoped to Phase 5.
2. Add or update a regression test that would have caught this specific failure.
3. Re-run the reproduction from Phase 4 and confirm it now passes.
4. Run the repo's relevant test/lint commands — the config's `local:` entries are exactly
   that list — and **report the actual result**. If you can't run them, say so plainly in
   chat and in the PR comment. Never state or imply that anything passed unless it actually
   ran.
5. If the run had multiple unrelated failures **that you actually observed before Phase 6
   cancelled anything**, fix and commit them separately — one root cause per commit — rather
   than bundling them. Never infer a second failure from a run you cancelled.

## Phase 8 — Land it

Commit with a message describing the root cause and the fix, not "fix CI". Stage the files
you changed by name; `git add -A` is never correct here.

- **On a topic branch:** push to that same branch. Don't create a new branch, don't
  force-push over existing commits.
- **On the trunk branch:** never push directly. **Stop and confirm the topic-branch-and-PR
  path with the user before creating anything** — then create a topic branch from the
  current commit, land the fix there, and open a PR (`gh pr create`). Say explicitly in the
  report that the fix is waiting on a PR rather than already applied.
- Then re-read `git rev-parse HEAD` for the new commit and return to Phase 1 to follow the
  run it triggered. Phase 1 keys off "this commit", so it needs the new SHA, not the one you
  started with. The job isn't done when the fix is pushed; it's done when **every check the
  config marks `required`** is green, or you've escalated. With no config, that means every
  check on the commit that isn't visibly advisory — and say that you're using the observed
  set rather than a recorded one.
- If `merge_queue: true` and the PR then merges, the checks that matter next run on the
  queue's ref, not on your branch. Follow those before calling it done.

If the same check fails again after a fix attempt, don't try another fix along the same
trajectory — go back to Phase 4 and re-diagnose with fresh eyes, because the first diagnosis
was wrong. If a check fails **three times** across fix attempts on this branch, stop
looping: post what you tried, why each attempt didn't hold, and hand it to the user rather
than iterating alone.

## Phase 9 — Report

Get the real date from `date -I`. Do not invent one.

If Phase 0 found an open PR **and `report.pr_comment` isn't false**, post there (`gh pr
comment <n> --body-file -`). With no PR, or with `pr_comment: false`, report the same
content in chat and say which it was. One block per root cause — never one vague combined
summary.

Every block from a Run carries the same `**Config:**` footer, so it's always obvious what
that run was working from — and, when it's absent or broken, `/ci-pipeline init` gets
mentioned where someone will actually see it. The Setup block reports the config directly
and doesn't repeat the footer.

**Diagnosis** — post this at the end of Phase 5, once fix-or-escalate is decided and before
any code is written:

```
## CI failure — <check name> — <date>

**Run:** <link>
**Failing step:** <the exact step inside the job, not just the job name>
**Root cause:** <what's actually broken, in plain terms>
**Plan:** <the small targeted fix you're about to make — or, if escalating, that, and why>
**Config:** `.claude/ci-pipeline.yml` <loaded, N checks | absent — derived from the repo | unparseable at <key> — derived from the repo>
```

**Fix applied:**

```
## CI fix — <date>

**Failing check:** <check name> (<required | advisory>) — <run link>
**Root cause:** <what was actually broken>

**Files changed:**
- <path> — <what changed and why>

**Checks cancelled:** <runs cancelled in Phase 6, undiagnosed — or "none">
**Reproduced locally:** <yes, the exact command — or "no, <reason>">
**Tests:** <exact commands and their real results, or "not run — <reason>">

**Risks / follow-up:** <noticed but not fixed; worth a second look>
**Config:** `.claude/ci-pipeline.yml` <loaded, N checks | absent — derived from the repo | unparseable at <key> — derived from the repo>
```

**Infra flake, no code change** — skipped entirely when `report.comment_on_flake` is false,
in which case say it in chat instead:

```
## CI — infra flake — <date>

**Failing check:** <check name> — <run link>
**Cause:** <signal observed, e.g. runner OOM, exit 137> — resolved by re-running the failed job. No code change needed.
**Config:** `.claude/ci-pipeline.yml` <loaded, N checks | absent — derived from the repo | unparseable at <key> — derived from the repo>
```

**Escalation — diagnosed, not fixed:**

```
## CI failure — needs separate work — <date>

**Failing check:** <check name> (<required | advisory>) — <run link>
**Root cause:** <what is actually broken>

**Why this wasn't fixed here:** <which Phase 5 escalation condition applied>

**Options:**
1. <approach> — <what it costs, what it risks, what it leaves open>
2. <approach> — <same>
<add more as they exist>

**Checks cancelled:** <runs cancelled in Phase 6, undiagnosed — or "none">

**Recommended:** <which option, and why>
**Suggested next step:** stacked PR — branch `<fix-branch>` cut from `<this branch>`, PR targeting `<this branch>`, so this PR stays reviewable on its own.
**Not attempted:** no code was changed by this run.
**Config:** `.claude/ci-pipeline.yml` <loaded, N checks | absent — derived from the repo | unparseable at <key> — derived from the repo>
```

**Setup mode — config written.** Setup ends with this instead of any of the above; it
diagnosed nothing, so it reports nothing about a failure:

```
## ci-pipeline setup — <repo> — <date>

**CI found:** N workflows, M checks observed on <sha short> — or "none, stopped"
**Recorded:** N checks — <count> required, <count> advisory, <count> marked rerun: never
**Merge queue:** <yes | no | unreadable, asked>
**Local reproduction:** <count> checks have a command, <count> are null
**Validated:** <every name seen on a real run, every workflow resolved, every local command resolves — or exactly what failed>
**Config PR:** <link> — <open, awaiting your review | merged>
**Branch:** you are on `<branch>` <(back where you started)>

**Next:** <checks in flight, offering to watch — or "nothing running; it'll fire on your next push">
```

## Stop and ask when

- Neither `gh` nor a GitHub MCP server is authenticated for this repo (Phase 0), or you have
  read access but the run needs to push (Phase 8).
- The repo has no CI at all — no workflows, no external checks — so there is nothing to
  watch. Point at `/code-development` and stop (Setup step 3, Phase 0).
- A config already exists and Setup was asked to write one (Setup step 2).
- Branch protection and rulesets are both unreadable, so which checks block a merge can't be
  derived (Setup step 5).
- A recorded check name never appears on a real run, a workflow display name doesn't
  resolve, or a `local:` command doesn't exist on this machine (Setup step 9). Fix the
  config before committing it.
- The working tree is dirty, or local HEAD doesn't match the remote (Phase 0, Setup step 1).
- There's no open PR for this branch — diagnose freely, but confirm before pushing (Phase
  0).
- The failing job is marked `rerun: never`, or has no config and looks like a deploy or
  publish, and an infra signal would otherwise trigger a re-run (Phase 3).
- Any Phase 5 escalation condition is true.
- The failing check is on the trunk branch — confirm the topic-branch-and-PR path before
  creating anything (Phase 8).
- A secret appears in log output.
- A check has failed three times across fix attempts on this branch (Phase 8).

## What this skill does not do

- Write features, or fixes unrelated to a failing check. That's separate work.
- Write, generate, or repair CI workflows. A repo with no CI is handed to
  `/code-development`.
- Cut, promote, or announce a release. That's `/release`.
- Dispatch workflows, or edit branch protection.
- Merge or close any PR except the `.claude/ci-pipeline.yml` config PR that Setup opened,
  and that one only on an explicit yes. It never merges the PR under review.
- Commit anything but the fix and its regression test in a Run, or anything but
  `.claude/ci-pipeline.yml` in Setup.
- Fix a failing check by making the check weaker. Ever — in CI or in the config.
- Edit or delete a workflow step that this skill supersedes — an older auto-fix or
  auto-remediation job, say. Removing one is a one-time edit to `.github/workflows/*.yml`
  and belongs in its own small PR, not as a side effect of watching a pipeline. Report it as
  a finding instead.

## If something doesn't match reality

If there's no CI configured, no `gh`/MCP access, no checks on the current commit, or the
failing check turns out to be something this skill can't read, say so and stop. Don't
reconstruct a run from reading the workflow YAML, and don't report on a stale run as though
it were current — an invented diagnosis is worse than no diagnosis. This is hard rule 6 at
the end of the line: when the world doesn't match what this skill expected, the answer is to
say so, never to fill the gap with a plausible guess.

The same goes for `.claude/ci-pipeline.yml`. It describes what someone recorded about this
repo's CI at some point in the past; the checks that actually ran on this commit are what is
true now. Where they disagree, the repo wins: report the drift by key, keep working from
what you observed, and offer `/ci-pipeline init` to re-derive it. Never edit the config
mid-run to make the two agree.
