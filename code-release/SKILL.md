---
name: code-release
description: >-
  Runs a repository's full release process end to end, driven by a `.claude/code-release.yml`
  committed to that repo — no hardcoded repo, workflow, or branch names. `/code-release init`
  interviews you, writes that config, and opens a PR for it. `/code-release dry-run` rehearses a
  release read-only, changing nothing. A full run baselines from the last successful release,
  reviews every PR merged since, audits docs and screenshots and stops with an [ON HOLD]
  issue if anything is stale (it reports staleness, never fixes it), opens a labelled review
  issue for explicit human approval, confirms the ref, deploys the docs site first,
  dispatches the release workflow with the approved issue's number, tracks it, locates the
  resulting PR or GitHub Release, announces it, and writes a self-contained HTML record of
  what shipped. Use on /code-release, or any ask to cut, ship, publish, or promote a release. Not
  for feature work (/code-development) or a red pipeline (/pipeline-monitor). Needs `gh` or a
  GitHub MCP server — Claude Code only.
---

# code-release

Runs a repository's release process end to end: audit what changed and whether docs and
screenshots still match it, get human approval on a review issue, make sure the live docs
site is current, dispatch the release workflow with that issue's number, track it, announce
the outcome, and leave behind an HTML record of what shipped.

Everything project-specific — which workflow, which branch, which inputs, where the release
lands, where to announce it — comes from **`.claude/code-release.yml` in the repo being
released**. This skill hardcodes nothing. `references/config-schema.md` documents every
field; `references/examples.md` has worked configs to copy.

This has real side effects: it opens and closes GitHub issues, dispatches a production CI
workflow, and posts an announcement. Move deliberately.

Hard rules, restated up front because they're the ones that erode under "just ship it"
pressure:

1. **Never skip the docs gate (Phase 3) or the approval gate (Phase 4).** They are the two
   things standing between a stale release and production.
2. **The docs gate reports, never fixes.** Finding and describing the gap precisely is this
   skill's job. Drafting docs or regenerating screenshots is the user's.
3. **Never guess a name** — workflow, input, label, or repo. Every one is either read from
   the config or discovered from the repo, then validated against the live workflow YAML.
4. **The config is the contract; the repo is the truth.** Where they disagree, stop and say
   which — never force the run to match the config.
5. **Never fabricate an approval issue number**, and never reuse a stale one from a previous
   run.
6. **Never auto-merge the release outcome, and never announce on the workflow merely
   succeeding.** Confirm the outcome actually exists first.
7. **The only file this skill ever *commits* is `.claude/code-release.yml`**, in setup mode, on a
   branch off the default branch, after you've seen it. It writes exactly one other file —
   the Phase 10 release record — and leaves it untracked. It never pushes to the default
   branch and never merges anything without an explicit yes.

## The three modes

Pick the mode before doing anything else, and say which one you're in.

| Invocation | Mode | Writes anything? |
|---|---|---|
| `/code-release init`, "set up release", "configure release" | **Setup** — interview, write `.claude/code-release.yml`, open a PR for it | One file, on a branch, after confirmation |
| `/code-release dry-run`, "practice run", "what would a release do" | **Rehearsal** — Phases 0–2 plus a printed dispatch payload, then stop | **Nothing.** No issue, no dispatch, no announcement |
| `/code-release`, "cut a release", "ship it" | **Full run** — Phases 0–10 | Issues, a workflow dispatch, an announcement, an HTML record |

**Plain `/code-release` in a repo with no config routes into Setup first**, then continues into
the full run once the config exists. Say that's what you're doing rather than silently
interviewing.

## Environment and tooling

- Use a connected **GitHub MCP server** if this session has one — that's the preferred path
  for everything here. Otherwise the **`gh` CLI**. Check the tools actually available in
  this session, not a registry of installable ones.
- **Write access is required** in Setup and Full-run mode. Issue creation, workflow dispatch,
  and the config PR all need it. If neither path is authenticated with write access, stop and
  say so — don't try to fake it with unauthenticated web fetches. **Rehearsal mode needs read
  access only**, and should say so when write access is missing rather than stopping.
- The repo being released is **whatever repo is checked out**. Discover it; never assume a
  name.
- Slack tooling is needed only if the config has an `announce` block.

`gh` appears throughout as the concrete form. Use the MCP equivalent if that's what's
connected; the sequence is the same either way.

## Setup mode — `/code-release init`

Guides a first-time user from nothing to a committed, validated config. Build it *from what
the repo actually has* rather than by interrogating the user about things you can read.

**1. Ground it.** Confirm write access, then discover the repo, the current branch, and the
default branch:

```bash
git rev-parse --show-toplevel && git branch --show-current
gh repo view --json nameWithOwner,defaultBranchRef
```

**2. Check for an existing config** at `.claude/code-release.yml` (or `.yaml`). If one exists,
show it and ask whether to update it or keep it — never overwrite a config the user hasn't
seen.

**3. Check the prerequisite that actually blocks people.** This skill *dispatches* a
workflow; it does not create one. List the repo's workflows and find which of them declare a
`workflow_dispatch` trigger:

```bash
gh workflow list --repo <owner/repo> --all
gh workflow view "<display name>" --repo <owner/repo> --yaml
```

**If no workflow declares `workflow_dispatch`, stop here.** Say plainly that the repo has no
manually-dispatchable release workflow, that `/code-release` has nothing to trigger until one
exists, and that the workflow needs a `workflow_dispatch:` trigger to be reachable. Show the
minimal shape:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        description: Ref or version to release
        required: true
```

Do **not** write that workflow yourself — building CI is `/code-development`'s job, not this
skill's. Point there and stop.

**4. Ask which of the dispatchable workflows performs the release.** Don't preselect. If
exactly one exists, still confirm it rather than assuming.

**5. Read that workflow's YAML and derive what you can.** Its `workflow_dispatch.inputs` give
you the input names — `ref_input`, `number_input`, and any static extras are *derived here,
not asked*. Its triggers tell you the likely default ref. Grep its steps for a fetch of an
issue body (`gh issue view`, `issues.get`, `${{ github.event.inputs... }}` feeding a body)
to answer `body_is_release_notes` from evidence rather than from a question the user
probably can't answer.

**6. Ask only what genuinely can't be read**, offering the derived answer for each so the
user is correcting rather than composing:

- the default ref to release — offer the repo's real branches
- which paths count as docs — offer what the repo actually has (`docs/`, `README.md`, a
  `site/` or `mkdocs.yml`)
- whether a separate docs-deploy workflow exists — offer the dispatchable ones you listed
- where the release lands: a PR in another repo, a GitHub Release, or nothing to locate
- where to announce it, if anywhere
- where to write the HTML release record, if not the default

**7. Write `.claude/code-release.yml`**, show it back in full, and ask for confirmation.

**8. Validate it against the live workflow before committing anything** — the same two checks
as Phase 0 step 4. Never commit a config that would hard-stop on its first real run.

**9. Commit it on a branch and open a PR.** This is the one write this skill makes into a
repo, and it stays narrow:

```bash
git fetch origin <default branch>
git checkout -b chore/code-release-config origin/<default branch>   # branch off the default, not
                                                               # whatever happens to be checked out
git add .claude/code-release.yml          # explicit path, never -A
git commit -m "Add code-release config for the /code-release skill"
git push -u origin chore/code-release-config
gh pr create --fill --base <default branch>   # never omit --base
```

Never commit anything else in that commit, and never push to the default branch. If the tree
was dirty before you started, stop and say so rather than sweeping someone's work into that
commit.

**10. Ask whether to merge it.** Merge only on an explicit yes, and only after the PR's own
checks are in a state the user accepts. If they'd rather review it themselves, leave the PR
open and say the next `/code-release` won't work until it lands on the branch being released.

**11. Say which branch they're on now**, and switch back to where they started unless
they're continuing straight into a release from this branch.

**12. Offer to continue into a full run.** The approval gate in Phase 4 still stands between
that point and any dispatch, so continuing is safe — but say so rather than assuming.

## Rehearsal mode — `/code-release dry-run`

A complete read-only rehearsal, for a first-time user who doesn't want to find out what this
skill does by watching it do it.

Run **Phase 0, Phase 1, and Phase 2 exactly as written — with one exception**: an absent
config does *not* route into Setup here, because Setup writes files. Report that there's no
config, point at `/code-release init`, and stop. There is nothing to rehearse without one.

Otherwise, print what the rest *would* do and stop:

- the resolved config, and the result of validating it against the live workflow
- the baseline run and the PR list
- which optional phases would be skipped, and because of which absent config block
- the **exact dispatch payload** — the ref, and every input key and value — that a real run
  would send
- what the review issue's title would be, and where the outcome would be looked for
- where the announcement would go, and where the HTML record would be written

Then say clearly that nothing was created or dispatched, and what to run for the real thing.

Rehearsal mode **never**: opens or closes an issue, creates a label, dispatches any workflow,
posts an announcement, or writes a record file. The docs audit in Phase 3 is *reported*
("would block: …", "would pass") but no `[ON HOLD]` issue is opened — that's a real artifact
and this mode makes none.

## Phase 0 — Orient, load config, validate

Four steps, in order. Verify with real commands; assume nothing.

**1. Tooling.** Establish which path you have and that it can write (read-only is fine for
Rehearsal mode — say so).

**2. Repo.** Discover it — never assume:

```bash
git rev-parse --show-toplevel && git branch --show-current
gh repo view --json nameWithOwner,defaultBranchRef
```

**3. Config.** Read `.claude/code-release.yml` (accept `.claude/code-release.yaml` too). Three
outcomes — say which one you're in before doing anything else, and never silently degrade:

- **Found** — parse it, then echo the resolved config back in one short block: workflow,
  ref, inputs to be sent, whether the docs gate is active, where the outcome is expected,
  where the announcement goes. The user should be able to catch a wrong value here, before
  any of it matters.
- **Absent** — route into Setup mode above, then continue.
- **Present but unparseable, or missing a required key** — stop. Name the offending key and
  point at `references/config-schema.md`. Do not fall back to defaults for a required
  field, and do not improvise a config to keep the run going.

**4. Validate the config against the live workflow.** Fetch the workflow YAML by its exact
display name from `release.workflow`:

```bash
gh workflow view "<release.workflow>" --repo <owner/repo> --yaml
```

Always look a workflow up **by display name, never by file path** — file names don't
reliably match display names. Then hard-stop on any mismatch:

- Every input key the config will send (`release.ref_input`, `approval.number_input`, and
  each key in `release.inputs`) must exist in the workflow's `workflow_dispatch.inputs`.
- Every input the workflow marks `required: true` must be supplied by the config.

A wrong input name either fails outright or **silently falls back to the workflow's
default** — and the silent case is why this is a stop rather than a warning. Report exactly
which key mismatched and what the workflow actually declares.

## Phase 1 — Find what's new since the last successful release

1. Find the most recent **successful** run of `release.workflow` — skip past any failed or
   cancelled attempts when picking the baseline. You want the last thing that actually
   shipped, not the last attempt. Note its head SHA/ref.
2. Compare that SHA against the branch being released (`release.default_ref` — final
   confirmation happens in Phase 6, but you need the range now to know what to review).
3. If there's nothing new, say so plainly and stop. Don't open an issue for an empty
   release.

If the workflow has **never** run successfully, there's no baseline. Say so and ask what
range to review rather than silently reviewing the entire history.

## Phase 2 — Review every merged PR and build the summary

Work from merged PRs, not raw commits — PR titles and descriptions carry the actual "why"
behind a change, and reviewing at the PR level is both cheaper and more meaningful than
diffing every commit individually.

1. Resolve the range from Phase 1 into the set of PRs merged into the release branch since
   the baseline.
2. For each PR, read its title, description, and changed-file list. That's usually enough to
   classify it (feature/fix/chore/docs) and to spot risk.
3. Only pull the full diff for a PR when its changed files look risky — schema/migration
   files, auth or security-related code, CI/workflow config. Don't pull full diffs for
   everything; for most PRs the title and file list already tell you what happened, and
   fetching every diff wastes calls and context for no real gain.
4. Build a grouped summary (features, fixes, chores/CI, docs) with risk callouts pulled to
   the top for anything you diffed. Link each PR.

## Phase 3 — Audit docs and screenshots (blocking — report only, never fix)

**Skipped entirely when the config has no `docs` block.** Say that you're skipping it and
why, so a missing block never looks like a passed gate.

This is a hard gate: if documentation doesn't match what's about to ship, the release
doesn't move forward until a human closes the gap. Your job is to find and describe the gap
precisely, not to close it.

1. From the PRs in Phase 2, identify which ones changed what a user actually sees —
   components, pages, styles, layout — as opposed to backend-only logic, tests, or config.
2. For each, check whether the content under `docs.paths` still accurately describes the new
   behavior. **Read the actual page** rather than checking whether a docs-adjacent commit
   exists in the range — a doc file being present isn't the same as it being correct.
3. **If anything is stale:** open an issue titled `[ON HOLD] Release — <today's date>`,
   labelled `approval.issue_label`, explaining exactly what's stale — which PR, which doc
   page, what's wrong or missing. Leave it open, tell the user what you found and where, and
   **stop the run completely**. Do not open the normal review issue, do not guess at what
   the docs should say, and do not run screenshot tooling or edit doc files yourself. This
   phase surfaces the gap; it doesn't close it. Whoever owns docs fixes it, and `/code-release`
   gets re-run from the top when it's ready.
4. **If everything checks out**, say so briefly and move to Phase 4. If a prior run left an
   `[ON HOLD]` issue open for an overlapping range and it's now resolved, close it and
   reference the new review issue in the closing comment so the history stays legible.

Find prior holds by **label and open state** — `approval.issue_label` with an `[ON HOLD]`
title prefix — never by matching a date in the title. Dates in titles are for humans; the
label is the lookup key.

## Phase 4 — Open the review issue

Only reached if Phase 3 came back clean (or was skipped by config). Create an issue in the
repo being released, labelled `approval.issue_label`. If that label doesn't exist on the
repo yet, create it and say so.

**When `approval.body_is_release_notes` is true**, the workflow fetches the closed issue's
**body verbatim** and reuses it — as the release notes, and often as a commit message or a
PR description too. Whatever it reuses it for, that text becomes public the moment the
workflow runs. That is the whole reason the issue splits in two:

**Issue body — write as real public release notes.** Plain user-facing language, grouped by
impact. No bare `#123` PR references (once the body lands in another repo they auto-link to
whatever issue holds that number *there* — almost certainly the wrong thing, not just
inaccessible). No internal jargon (scanner rule IDs, CI-only changes, severity labels). No
process language ("waiting on approval", "audited"). Pure-internal chores get folded into
one generic line or omitted — they add nothing for a public reader.

```
Title: Release review — <today's date> (N PRs)

<one-line summary of what this release does>

### New
- <user-facing feature, plain language>

### Fixed
- <user-facing bug fix, plain language>

### Improved
- <non-jargon summary of accessibility/reliability/quality work, if any>
```

**Issue comment — internal review notes, never fetched by the workflow.** Everything you
actually need to review the release lives here instead: the baseline run and SHA, the
branch/ref compared, the docs-audit result, risk callouts, and the full linked PR-by-PR
breakdown.

```
**Internal review notes (not part of release notes)**

Comparing against: last successful run <link> (`<sha short>`, <date>) → `<ref>` @ `<sha short>`, N merged PRs.

Docs & screenshots: <audited, up to date — or what was found — or "no docs block configured">.

<risk callouts, if any>

Full PR list: #<n>, #<n>, ...
```

**When `body_is_release_notes` is false**, nothing is fetched verbatim, so the split is
unnecessary: write one issue that serves the human reviewer, and say in the report that the
body is not shipping anywhere.

Post the issue link and explicitly ask the user to review it. Do not proceed to Phase 5
until they say something that's clearly approval ("approved", "go ahead", "ship it"). If
they ask for changes, make them and ask again — don't treat silence or an unrelated reply as
approval.

## Phase 5 — Close the issue and carry its number forward

Once approved, close the review issue. That closure is your record that this specific
release was actually reviewed and signed off, and — when `approval.number_input` is set —
the issue number becomes that workflow input. Note the number; you'll need it in Phase 8.

When `approval.number_input` is omitted, the issue is still opened and closed as the
approval record; the number simply isn't passed to anything.

## Phase 6 — Confirm the ref to release

Ask what to release if the user hasn't already said. Default to `release.default_ref` if
they don't name a branch, tag, or SHA. Either way, state back exactly what you're about to
release ("Releasing `<ref>` at `<short sha>`") before moving on — last checkpoint before you
touch production CI.

If what they name covers a different range than what you audited in Phases 2–3, go back and
redo those against the real range before continuing. The docs gate has to cover what's
actually shipping, not what you happened to check first — and that likely means a fresh
review issue too, since the approved one's summary would now be out of date.

## Phase 7 — Check documentation deployment (before releasing)

**Skipped when the config has no `docs.deploy_workflow`.** Also skip if Phase 3 found no
doc-relevant changes in this range — nothing to redeploy.

Runs after the ref is confirmed (Phase 6) and **before** dispatching the release workflow
(Phase 8) — the live docs site should already be current by the time the release goes out,
not sometime after. This is a separate, decoupled workflow, not a step inside the release
workflow, so it has to be checked and, if needed, run on its own.

1. Find `docs.deploy_workflow` by its exact display name — same rule as Phase 0, never guess
   a file path or assume which repo it lives in.
2. Check whether it already ran for the current docs content on the ref you're about to
   release: look at its most recent runs and compare their timestamp, trigger, and ref
   against when the docs changes from Phase 3 actually landed.

   The trap: that workflow's push trigger only fires on a push to the specific branch and
   paths it watches (`docs.deploy_watches`). If that branch never actually receives the
   relevant push — it watches `main` but docs changes only ever land on the release branch,
   say — the live site can go stale **indefinitely, with no error anywhere to notice it by**.
   Don't infer "site is current" from "no run failed recently". Check what actually
   triggered the latest run, against what ref, and when.
3. **Already current** → say so and move to Phase 8.
4. **Not current** → ask whether to dispatch it now against the ref being released. Don't
   run it unprompted; it deploys straight to the live docs site.
5. If they say yes, dispatch and poll to completion — report state changes as they happen,
   and stop and report on failure rather than retrying. Only move on once it finishes (or
   the user declines).

## Phase 8 — Dispatch the release workflow and track it

The dispatch has two independent parts, and conflating them is the easiest mistake to make
here. `ref` is the git ref the run happens on. `inputs` are the workflow's declared
`workflow_dispatch.inputs`. A workflow may take a version input *as well as* running on a
ref, or may take no inputs at all.

```
ref    = the ref confirmed in Phase 6
inputs = release.inputs                                        (static extras, may be empty)
       + { <release.ref_input>:     <that same ref> }          only if ref_input is set
       + { <approval.number_input>: <issue number> }           only if number_input is set
```

1. Dispatch with exactly that payload — every key already validated in Phase 0.
2. Capture the run ID. Poll it and report state changes as they happen — queued → running →
   success/failure — rather than going quiet until the end. On failure, report it and stop;
   don't retry automatically.
3. Keep the run ID and the released ref handy for Phases 9 and 10.

## Phase 9 — Locate the outcome and announce

**When the config has no `outcome` block**, the run succeeding *is* the end state. Report it
with the run link and go to Phase 10 — don't go looking for a PR or release that this
project doesn't produce.

**`outcome.type: pull_request`** — the workflow opens a PR, in `outcome.repo` if set,
otherwise the current repo. Find it via the run's logs/output if it prints the URL, or by
listing recent PRs in that repo authored by the automation. **Confirm it's actually open
before announcing** — don't announce based on the workflow merely succeeding.

**`outcome.type: release`** — the workflow publishes a GitHub Release. Find it by tag in
`outcome.repo` (or the current repo) and confirm it exists and is not a draft.

Then, **if the config has an `announce` block**, send the message. `announce.slack` is
either `dm_self` (send to your own user ID — the Slack tool reports the connected user's ID
for exactly this purpose) or a `#channel` name. Fill `announce.template`'s placeholders:
`{repo}`, `{ref}`, `{url}` (the outcome URL, falling back to the run URL when no `outcome`
is configured), and `{run_url}`.

If Slack tooling isn't available in this session, say so and print the message you would
have sent. Never treat a failed announcement as a failed release — the release already
happened; say plainly that it shipped and the announcement didn't.

**Never auto-merge the resulting PR.** This skill's job stops at "the outcome exists, you've
been told, and here's the record."

## Phase 10 — Write the release record

**Reached only when a release actually shipped** — the workflow was dispatched and Phase 9
either located the outcome or confirmed the run's success is the end state. A run that
stopped at a gate produces the text report and nothing else; there is no record of a release
that didn't happen.

**Skipped when the config sets `record.enabled: false`.** Say so, like any other skipped
phase.

Write **one self-contained HTML file** — the durable, shareable record of what shipped, for
someone who wasn't in this session.

- **Path:** `<record.dir>/release-<YYYY-MM-DD>-<short sha>.html`, defaulting to
  `.claude/release-records/`. Create the directory if needed.
- **Self-contained means self-contained:** one file, inline `<style>`, no CDN, no external
  fonts, no scripts, no images fetched at view time. It has to open correctly from a local
  disk with no network, and print to PDF cleanly.
- Respect `prefers-color-scheme` for light and dark, and keep it readable at phone width.

Content, all of it filled from what actually happened in this run:

| Section | Contents |
|---|---|
| Header | Repo, ref released, short SHA, date, and a one-line summary of the release |
| Gates | Docs gate result, approval issue (number, link, who approved, when), docs deploy result — each showing *passed*, *skipped and why*, or *not reached* |
| What shipped | The Phase 2 grouped summary — features, fixes, chores, docs — every PR linked, risk callouts kept at the top |
| Dispatch | The exact ref and input keys/values sent, and the workflow run link and result |
| Outcome | The located PR or Release, linked, with its confirmed state — or "run succeeded, nothing to locate" |
| Announcement | Where it went, or why it didn't |
| Follow-up | Anything noticed but not handled |

Then tell the user the path, and say it's **untracked** — committing it, ignoring it, or
deleting it is their call. If this session has artifact-publishing tooling and the user wants
a link to share, offer to publish the same file; don't publish unprompted.

The record obeys the same rule as the text report: **it may only contain things that actually
happened.** A skipped gate says "skipped — no `docs` block configured", not a green check.

## Secrets

A release run reads workflow logs and PR bodies, then writes an HTML record, a review issue,
and — if the config asks for it — a Slack announcement. Every one of those is a place a
credential can escape, and the record and the announcement outlive the run.

- Never quote a value from a workflow log, PR body, or issue that looks like a credential —
  token, key, password, connection string, signed URL. Redact it as `<redacted>` in the
  report, the review issue, the announcement, and the HTML record alike.
- If a secret appears in a run's output, that is a finding, not an inconvenience. Say so at
  the top of the report, name the workflow and step that leaked it, and recommend rotation.
  Do not quietly redact and move on — and do not dispatch a release on it without saying so.
- Never write a credential into any file this skill creates, including `.claude/code-release.yml`
  and the release record.
- Never print repository or environment secrets, even when they would explain a failed
  dispatch. Describe the shape instead ("the workflow's `PUBLISH_TOKEN` input is unset").

## Scope boundaries

**Always in bounds**

- Reading anything in the repo being released, its workflows, its PRs and its docs.
- Creating the approval label if it doesn't exist; opening and closing the review issue and
  the `[ON HOLD]` issue.
- Dispatching `release.workflow` and `docs.deploy_workflow`, each with its own gate.
- Writing `.claude/code-release.yml` in Setup mode, after showing it and getting confirmation —
  committing it on a branch, pushing, opening a PR, and merging that PR on an explicit yes.
- Writing the HTML release record after a release has shipped.

**Never in bounds, even when it would be faster**

- Skipping the docs gate or the approval gate, or treating silence as approval.
- Fixing stale docs, drafting doc content, or regenerating screenshots — the gate reports.
- Dispatching any workflow the config doesn't name, or a docs deploy without being asked.
- Merging or closing the release outcome PR, editing branch protection, or publishing a
  draft release.
- Guessing a workflow name, an input name, a label, or the outcome repo.
- Sending an input the workflow doesn't declare, or omitting one it marks required.
- Fabricating or reusing an approval issue number.
- Announcing before confirming the outcome exists.
- Writing, committing, or authoring **any file other than `.claude/code-release.yml` and the
  release record** — no workflow files, no docs, no code. `git add -A` is never correct here;
  stage the one path by name.
- Pushing to the default branch, force-pushing, or merging the config PR without an explicit
  yes.
- Creating, opening, or dispatching anything at all in Rehearsal mode.

## Stop and ask when

- Neither `gh` nor a GitHub MCP server has write access to the repo (Phase 0; Rehearsal mode
  continues read-only instead).
- No workflow in the repo declares `workflow_dispatch`, so there's nothing to release with
  (Setup).
- A config already exists and Setup was asked to write one (Setup).
- The config is missing a required key, won't parse, or names an input the workflow doesn't
  declare (Phase 0).
- `release.workflow` has never completed successfully, so there's no baseline (Phase 1).
- The docs audit finds anything stale — open the `[ON HOLD]` issue and stop (Phase 3).
- The user hasn't clearly approved the review issue (Phase 4).
- The ref they name covers a range you didn't audit (Phase 6).
- The docs site isn't current and needs a deploy dispatched (Phase 7).
- The release workflow run fails (Phase 8).
- The workflow succeeded but the expected outcome can't be found (Phase 9).

## Reporting

Every run ends with this block, filled from what actually happened:

    ## release — <repo> @ <ref>

    **Mode:** <full run | rehearsal — nothing was created | setup>
    **Config:** `.claude/code-release.yml` <loaded | written this run, PR <link> | absent — interviewed>
    **Workflow:** <release.workflow> — run <link> — <success | failed | not dispatched>
    **Baseline:** <last successful run link> (`<sha>`, <date>) → N merged PRs

    **Docs gate:** <clean | ON HOLD — issue link | skipped — no docs block configured>
    **Approval:** issue #<n> <closed, approved <date> | not opened — reason>
    **Docs deploy:** <already current | dispatched, <result> | skipped — <reason>>

    **Dispatched with:**
    - ref: `<ref>`
    - inputs: <the exact keys and values sent, or "none">

    **Outcome:** <PR link, open | release link | run succeeded, nothing to locate |
    not reached — reason>
    **Announced:** <where | not configured | failed — reason>
    **Record:** <path to the HTML file | not written — reason>

    **Risks / follow-up:** <anything noticed but not handled>

Never fill **Dispatched with**, **Outcome**, or **Record** with anything that didn't actually
happen. "Not reached — <reason>" is a correct answer; a fabricated success is the one failure
mode that makes this skill worse than releasing by hand.

## If something doesn't match reality

The config describes what a project *said* was true when someone wrote it. The repo is what
is true now. When they disagree — the workflow was renamed, an input was added or removed,
the docs moved, the outcome repo changed — **trust the repo, say exactly what you found, and
stop rather than forcing the run to match the config**. Tell the user which key is stale so
they can fix `.claude/code-release.yml` in the same breath.

The same applies to anything this file asserts about how a release works. If the actual
workflow YAML, repo structure, or run output contradicts something here, what's in the repo
wins. Never reconstruct a workflow's inputs from memory, never infer a release shipped from
a run merely succeeding, and never report a gate as passed when it was skipped.
