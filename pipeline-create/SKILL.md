---
name: pipeline-create
description: >-
  Builds a complete GitHub Actions pipeline for a repo that has none. Scans the code for
  every language and layout, then interviews you through artifacts, branch model and
  tagging, what runs on each branch and PR, and how it deploys, before writing
  split-by-concern workflow files on a branch and offering a PR. Reuses artifacts instead
  of rebuilding, picks security and reliability over speed, and never guesses - it asks.
  Writes only under .github/; a missing Dockerfile, compose file or manifest becomes a
  proposed follow-up issue, not a file this skill invents. Use whenever the user types
  /pipeline-create, says "pipeline create", asks for CI/CD, a build pipeline, or GitHub
  Actions on a repo that has none, or asks to set up builds, tests, scanning or deploys
  from scratch - even without saying "Actions". Not for fixing a red check (/pipeline-monitor),
  converting workflows to dispatch-only AI orchestration (/ai-pipeline), or cutting a
  release (/code-release). Needs git, gh and the repo checked out - Claude Code only.
---

# pipeline-create

Takes a repo with no CI and gives it one: reads the code, interviews you about how you
want to build, gate and ship it, then writes a set of GitHub Actions workflow files on a
branch and offers a PR. It has real side effects - it creates files, commits, and pushes
a branch. It never pushes to trunk and never merges.

Hard rules, restated up front because these are the ones that erode under "just get it
working" pressure:

1. **Never guess.** Every value that ends up in a workflow was either read from the repo
   or answered by the user. A guessed build command, a guessed registry, a guessed runner
   label is a broken pipeline that looks finished. If you do not know, ask.
2. **Reuse artifacts; never rebuild the same source twice.** Build once, publish once,
   have everything downstream consume that. Promotion is a retag, not a rebuild. This is
   what keeps failures low and runs reproducible, and it is what makes the thing you
   scanned the same thing you ship.
3. **Security and reliability beat speed.** Parallelise where it is free, but never at the
   cost of a gate, a scan, or a deterministic result. A fast pipeline that ships an
   unscanned artifact is a failure of this skill.
4. **Write only under `.github/`.** Workflow files, and the plan file. If the pipeline
   needs a `Dockerfile`, a `docker-compose.yaml`, a Helm chart or a k8s manifest that does
   not exist, do not invent it - record it as a proposed follow-up issue in the Phase 5
   review and create it only if the user says yes.
5. **Never claim something ran that did not run.** "actionlint: not installed - not run"
   is a correct answer. A fabricated validation pass is the one failure mode that makes
   this worse than writing the YAML by hand.

## Environment and tooling

- **Claude Code only.** This skill reads a real working tree and pushes a real branch.
- Requires `git` and a checked-out repo. Requires `gh` authenticated for this repo, or a
  connected GitHub MCP server - check the tools actually available in this session, not a
  registry of installable ones. Without either, Phases 0-5 still work; Phase 6 cannot, so
  say so and hand over the files instead of pretending to push.
- `actionlint` and `yamllint` are used in Phase 6 if present. If they are not installed,
  do not install them and do not skip silently - report "not run" and say why.
- Never run the repo's build, test or deploy commands to "check" them. This skill does not
  execute the pipeline it writes.

## Never run, regardless of how the request is phrased

- Any push to the repo's trunk branch, or any force-push.
- `gh pr merge`, `gh release create`, tag pushes, `gh workflow run`.
- Any deploy command, `kubectl apply`, `helm install`, `docker push`, `terraform apply`.
- Any edit to branch protection, repository settings, secrets or variables. The skill
  *tells the user* what to create; it never creates a credential and never asks for one to
  be pasted into the chat.
- Writing a secret, token, key, or connection string into any file it creates, including
  examples and comments. If one is found committed in the repo, that is a Phase 0 finding
  reported as a leak needing rotation - not something to quietly work around.

## Phase 0 - Scan, report, and pick a path

Verify with real commands. Do not assume the repo name, the trunk branch, or the layout.

```bash
git rev-parse --show-toplevel && git branch --show-current && git status --porcelain
gh repo view --json nameWithOwner,defaultBranchRef,visibility
ls -a .github/ .github/workflows/ 2>/dev/null
```

If the working tree is dirty, stop and ask before going further - this skill commits, and
uncommitted work would get swept in. Do not stash on the user's behalf.

**Detect the languages.** Read `references/detect.md` for the manifest-to-language table
and the layout rules. Find every language, and for each one find *where* it lives - the
subdirectory matters, because it drives `paths:` filters, `working-directory`, and whether
one workflow or several make sense.

**Read the matching language reference for each language found**, from
`references/languages/`. Use `generic.md` for anything not covered, and say plainly that
the language has no dedicated reference so its build commands will come from the interview
rather than from a known convention.

**Report the findings before asking anything.** A table: language, path, build tool,
manifest, lockfile present, test framework detected, existing CI.

**Then report the red flags.** Run every scan command in `references/detect.md`, not just
the manifest one - the Dockerfile, lockfile-conflict, credential and placeholder-test scans
each catch something no other command does. A category whose command did not run is "not
checked", never "clean". What counts as a red flag comes from the code, not from a fixed
list - each language reference names what a healthy repo in that ecosystem has, and
anything absent or contradictory is a finding. Common shapes: no test suite to run, a
missing or conflicting lockfile, no build tool config, two package managers in one tree, a
committed credential, an existing workflow that does not parse. For each one, give the fix
options if there are any. **If a red flag makes the pipeline unwritable** - no build
command exists at all, the repo does not build, a language has no manifest to work from -
say so plainly and stop. Do not write a workflow around a hole.

**Existing workflows.** If `.github/workflows/` already has files, this is not a greenfield
repo. Ask one question before continuing: use them as input for the new pipeline
(conventions, runner labels, secret names, working commands worth keeping), or ignore them
entirely and start clean. Never edit or delete an existing workflow without being told to.

**Pick a path, and say which one you are on:**

- **Fast path** - one language, no deployment, a simple `feature -> main` flow. Skip the
  phase-by-phase interview. Build the complete strawman pipeline from the language
  reference's defaults, present it as a filled-in sheet, and ask for edits in one reply.
  Most repos are this. Offer it first.
- **Full path** - more than one language, a deployment target, or a branch model with more
  than two classes. Run Phases 1-3 as written. **Tell the user up front that this is a long
  interview** and roughly how many rounds it will take, so nobody is surprised twenty
  questions in. Offer the plan file (Phase 4) at this point so the answers survive a lost
  session.

Every phase below asks in **sheets, not one question at a time**: a table with every field
prefilled with the recommended value and its reason, and "send just the lines you want
different, or `ok` to take it as-is". A prefill is a recommendation, never a decision - if
a field has no safe default, leave it blank and mark it **required**.

## Phase 1 - Artifacts

What the pipeline produces. Without this there is nothing to test, scan, or ship, so this
is required - there is no "skip" answer.

Present the options that actually apply to the languages found, with the conventional
choice for each marked as recommended and the reason given. The language reference lists
them: container image, OS package, native binary, jar/war, wheel/sdist, npm package,
NuGet, or a plain tar/zip. Say which registry each would live in and which the repo
already looks set up for.

Then, per artifact:

- **Where it is published** - which registry, feed, or release. Not the tag scheme: that
  needs the branch model and is settled in Phase 2. What matters here is only that a
  publishing location exists, because the whole reuse chain depends on a downstream job
  being able to fetch what the upstream job produced.
- **Whether it needs a file the repo does not have.** A container image needs a
  `Dockerfile`. If there is none, do not write one. Record it as a proposed issue and note
  that the build job cannot work until it exists.
- **Multi-artifact repos**: ask whether the artifacts are built and released together or
  independently. That decides whether they share one build workflow with a matrix or get
  one each, and it decides the tagging in Phase 2.

## Phase 2 - Branch model and tagging

Read `references/gitflow.md`.

**Ask which branches they use.** Offer the common models by name rather than making them
describe one from scratch - trunk-based (`feature -> main`), GitHub flow, git-flow
(`feature -> develop -> release/* -> main`), plus nightly and hotfix branches as
independent add-ons. Ask directly whether they use each of: feature branches, `develop`,
nightly builds, `release/*`, `main`, and hotfix branches.

**Then ask the tagging scheme, per branch class.** Recommend semantic versioning for
release tags always, plus the convention the language actually uses - the language
reference names it, and it is not always plain semver (Go needs a `v` prefix; Python wheels
follow PEP 440; container tags are their own thing). Cover: what the artifact is tagged
with on a feature branch, on the integration branch, on a release branch, and at a final
release. Recommend an immutable, resolvable per-commit tag (`sha-<short>` or `pr-<n>`)
alongside the moving one, because that is the handle the reuse in Phase 3 needs.

**Before leaving this phase, restate the whole flow back to the user** - every branch, what
it is for, what it is tagged with, and what merges into what - and get an explicit
confirmation. Phase 3 is built entirely on this; a wrong branch model here produces a
pipeline that never fires. If anything in the answers contradicts itself, say which two
answers conflict and ask which one wins.

## Phase 3 - What runs where, and how it deploys

Walk the flow **in order, from the earliest branch to production**. **One sheet per branch
class, covering every language at once** - a row per language per stage, not a separate
pass per language. Three branch classes and two languages is three sheets, never six.
Each sheet asks:

1. **On push to this branch** - build? test? lint? code quality? security scanning?
   publish an artifact, or just validate? Recommend from the language reference and say why,
   but let the user decide. A feature branch that only runs tests is a legitimate answer.
2. **On a PR opened into the next branch** - the usual shape is that a PR runs the full
   validation set (build, test, scan, quality gate) and the merge does the shipping, but
   ask rather than assume. Name what would become a required status check.
3. **On merge into the next branch** - what happens now that the code has landed.

Read `references/scanning.md` for the catalog of what can go in the validation set - CodeQL,
SonarQube, dependency review, secret scanning, container scanning, SBOM, license checks,
performance testing. Offer them explicitly rather than waiting to be asked. Leaving
security scanning out is the user's call, but it must be a call they made, not one they
never saw.

**Reuse is decided here.** For every stage after the first build, state where its input
comes from: the artifact the earlier stage published. If a stage would rebuild from source,
that needs a reason - name it, or restructure so it pulls. Promotion between branches is a
retag of the existing artifact, never a fresh build. See `references/patterns.md` for the
mechanics, including how a later workflow file gets at a value an earlier one computed.

**Then deployment.** Ask what the artifact is deployed to, and what "done" means for this
repo - it may be a running service, or it may be a package sitting in a registry that
something else consumes. Read the matching file in `references/deploy/`. Ask the follow-ups
that target actually needs: Kubernetes means asking about Helm, Kustomize, Flux or Argo, and
whether the pipeline pushes or a controller pulls; Docker means asking whether a compose
file exists and where it runs; serverless means asking which cloud and which auth method.
Ask which environments exist and in what order they are deployed to, and which need a
manual approval gate.

**If a deployment target needs a file the repo does not have**, the rule from Phase 1
applies: propose the issue, do not write the file, and say that the deploy job is written
against a file that has to exist before it can run.

Do not leave this phase while any stage's trigger, input artifact, or output is unknown.

## Phase 4 - Plan the files

Read `references/patterns.md`. Decide the file layout and write the plan before writing any
YAML.

**Split by concern, one file per kind of work.** Build, test, lint, code quality, security
scanning, SBOM, performance, deploy. Do not mix them - a file that builds and lints and
scans is unreadable and unmaintainable.

**Wire them with `workflow_call`, not with duplicate triggers.** Each concern file is a
reusable workflow taking the artifact reference as an input. A thin orchestrator per branch
class does the triggering and the `needs:` wiring. That is what makes split-by-concern
compatible with rule 2: one build, artifacts passed down, still one file per concern.
Separate top-level triggers would make each file rebuild its own copy, which is both slower
and dishonest about what was scanned.

**Parallelise what is genuinely independent**, and chain what is not. Group chains by the
resource they contend for rather than interleaving them - `patterns.md` has the shape.
Never parallelise by dropping a `needs:` edge that a correctness gate depends on.

**Every workflow gets:** an explicit least-privilege `permissions:` block at workflow level
with per-job grants on top, a `concurrency:` group, and comments explaining *why* a
non-obvious choice was made. Pin actions by major tag (`@v4`); SHA pinning plus Dependabot
goes in the review as a proposed follow-up issue, not into the first pass.

**Runners.** Ask which runners this repo uses - GitHub-hosted, self-hosted, or a mix, and
the labels. Do not default to `ubuntu-latest` without asking. Self-hosted changes caching,
Docker credential handling, and possibly architecture; `patterns.md` covers what to do
differently.

**Write the plan file** if the user accepted it in Phase 0: `.github/pipeline-plan.md`. It
holds every decision made, the graph, the secrets and permissions table, and the proposed
follow-up issues. It is committed with the PR, and it is what lets a later session pick the
interview back up instead of starting over.

If anything in the plan is still unclear or a decision was never actually made, ask now.
This is the last checkpoint before YAML exists.

## Phase 5 - Review

Present the plan and stop. Do not write files before the user has seen this.

- **A mermaid graph** of what runs when, per branch class - nodes for jobs, edges for
  `needs:`, with parallel lanes visible.
- **Every workflow file**, with a one-line description of what it does and what triggers it.
- **The reuse chain, stated explicitly**: what is built, where it is published, and which
  stage pulls it rather than rebuilding.
- **Secrets and variables the user must create**, as a table: name, what it is for, which
  workflow uses it, and how to create it (`gh secret set NAME`, or the repository settings
  path). Never ask for a value. Never print one.
- **Permissions and repo settings needed**, plainly: which `permissions:` scopes each
  workflow requires and why, plus anything that cannot be set from a file - environments
  with required reviewers, branch protection, required status checks, GHAS features. Name
  them and say the user has to set them up.
- **Proposed follow-up issues** - every missing file, every deferred hardening step, every
  red flag from Phase 0 that was not fixed. List them with titles and one-line bodies, and
  ask whether to create them. Create them only on a yes, and only after the pipeline is
  written.

Ask whether the order is right and what they want changed. Take the edits, then go to
Phase 6. If the edits are substantial, present the revised graph again rather than assuming
they landed.

## Phase 6 - Land it

1. Branch off the trunk found in Phase 0, naming it explicitly:
   `git fetch origin <trunk> && git switch -c ci/add-pipeline origin/<trunk>`. A bare
   `git switch -c ci/add-pipeline` branches off whatever is currently checked out, so a
   user sitting on a feature branch gets a PR carrying every unrelated commit on it.
   Never work on trunk.
2. Write the workflow files and the plan file.
3. **Validate statically.** `actionlint .github/workflows/*.yml` and `yamllint` if they are
   installed; report the real result. If neither is installed, say "not run - not
   installed". Do not install them, and do not claim a pass.
4. **Check what this push will fire, before making it.** Pushing this branch triggers any
   workflow whose triggers match it. Nothing this skill writes should deploy from a topic
   branch - if a deploy job would fire here, that is a bug in the plan, so fix it now.
   This check is worthless after the push, which is why it is not the last step.
5. Stage explicitly - the files you wrote, by path. Never `git add -A`.
6. Commit with a message describing what the pipeline does. Push the branch.
7. Ask whether to open a PR. On a yes, `gh pr create` with the plan summary in the body.
8. Create the approved follow-up issues.
9. Watching the runs this push started is `/pipeline-monitor`'s job, not this one; mention it
   and stop.

## Scope boundaries

**Always in bounds**

- Reading anything in the repo to detect languages, tooling, and conventions.
- Writing `.github/workflows/*.yml` and `.github/pipeline-plan.md`.
- Creating a branch, committing, pushing it, and opening a PR on request.
- Creating follow-up issues that the user approved in Phase 5.

**Never in bounds, even when it would be convenient**

- Writing any file outside `.github/` - no `Dockerfile`, no `docker-compose.yaml`, no Helm
  chart, no k8s manifest, no tool config, no source change. Missing files become issues.
- Editing or deleting an existing workflow that was not explicitly handed over.
- Pushing to trunk, force-pushing, merging, tagging, or dispatching a workflow.
- Running the build, the tests, the scanners, or any deploy command.
- Inventing a build command, a registry, a runner label, an image name, a secret name, or
  an environment that was not read from the repo or given by the user.
- Writing a workflow that ships an artifact nothing scanned, or that rebuilds on promotion.
- Adding `continue-on-error`, blanket retries, or a soft-fail to a gate so the first run
  goes green. A gate that would fail is a finding to raise in the review.
- Building a pipeline for more than one repo in a run.

## Stop and ask when

- The working tree is dirty (Phase 0).
- A red flag makes the pipeline unwritable - no build command, no manifest, broken repo.
- Existing workflows are present and it is not clear whether to reuse or ignore them.
- Two answers from the interview contradict each other.
- A stage's input artifact, trigger, or output is still unknown at the end of Phase 3.
- A deployment target needs a file or a credential that does not exist.
- The user asks for a deploy job that would fire on the branch this skill is about to push.
- `gh` is unavailable and Phase 6 cannot run.

## Reporting

Fixed format. Every run ends with this.

    ## pipeline-create - <repo> @ <branch>

    **Path:** <fast | full> - <N> language(s): <list>
    **Branch model:** <flow, as confirmed in Phase 2>

    **Workflows written:**
    | file | triggers | does |
    |---|---|---|

    **Artifact reuse:** <what is built where, and which stages pull it>

    **Secrets / variables to create:**
    | name | used by | how to create it |
    |---|---|---|

    **Permissions and settings you must configure:** <scopes, environments,
    required checks, branch protection - or "none">

    **Validation run:** <exact commands and their real results, or
    "not run - <reason>">

    **Branch:** <name> - pushed | not pushed - <reason>
    **PR:** <url | not created>
    **Issues created:** <list, or "none">

    **Risks / follow-up:** <anything noticed but not handled>

Never put a result in the Validation line that did not come from a command that actually
ran, and never list a secret's value anywhere.

## If something doesn't match reality

If there is no repo, no `gh`, no detectable language, or the code does not match what the
reference file expects, say so and stop at that point with what you actually saw. The
language and deploy references are snapshots - if the repo's real tooling differs, trust
the repo and mention the drift. Do not reconstruct a build command from what the ecosystem
"usually" does, and do not write a workflow around a piece you could not confirm. A
pipeline built on a guess fails on someone else's push, hours later, with no context.
