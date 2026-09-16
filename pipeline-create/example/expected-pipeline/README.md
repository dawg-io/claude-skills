# What a run produces — worked output for `example/`

The seven workflow files and the plan that a **fast path** run of
[`pipeline-create`](../../) writes for the [`example/`](../) service: one Python package,
a container image, GHCR, trunk-based branching, no deployment.

**These are illustrative.** They were written by hand to document the output shape, not
captured from a live run — your repo's answers change every one of them. What is worth
copying is the *structure*: split by concern, wired with `workflow_call`, one build, and
every promotion a retag.

They live under `workflows/` here so nothing in this repo tries to execute them. In a real
run they land in `.github/workflows/`, and `pipeline-plan.md` lands at
`.github/pipeline-plan.md`.

## What was checked

| Check | Result |
|---|---|
| `actionlint` 1.7.7, all seven files | clean, exit 0 |
| `shellcheck` / `pyflakes` sub-checks | **not run** — neither is installed here, so the `run:` blocks were not shell-linted |
| Executed on GitHub Actions | **no.** Nothing here has been run against a real repo |

## The files

| File | Trigger | What it does |
|---|---|---|
| [`pr-validation.yml`](workflows/pr-validation.yml) | `pull_request` → `main` | Orchestrator. Build, test, lint, scan, then the `summary` gate |
| [`main-pipeline.yml`](workflows/main-pipeline.yml) | `push` → `main` | Orchestrator. Same validation on what landed, then retag to `edge` |
| [`release.yml`](workflows/release.yml) | `push` tag `v*` | Orchestrator. Retag to the release versions, SBOM, GitHub release |
| [`build.yml`](workflows/build.yml) | `workflow_call` | The only job that turns source into an artifact |
| [`test.yml`](workflows/test.yml) | `workflow_call` | pytest on 3.11 and 3.12, coverage XML from 3.12 |
| [`lint.yml`](workflows/lint.yml) | `workflow_call` | `ruff check`, `ruff format --check` |
| [`security-scan.yml`](workflows/security-scan.yml) | `workflow_call` | CodeQL, and Trivy against the built image |
| [`pipeline-plan.md`](pipeline-plan.md) | — | Every decision, the reuse chain, secrets, settings, follow-up issues |

## Five things to notice

**1. Only the orchestrators have triggers.** The four concern files are `workflow_call`
only. If each had its own `push:` trigger they would each check out and rebuild their own
copy of the source — slower, and the image the scanner looked at would not be the image the
release shipped.

**2. One build, and the reference travels.** `build.yml` returns
`ghcr.io/<owner>/<repo>:sha-<short>` as a workflow output. `security-scan.yml` pulls that
exact tag. Nothing downstream compiles anything.

**3. Promotion is `docker buildx imagetools create`.** Both `edge` and the release versions
are manifest copies of a digest that already passed every gate. A rebuild on promotion would
ship a binary no scanner ever saw.

**4. The `summary` job is the required check, not the individual jobs.** A *skipped* job
reports success to branch protection. Without a job that reads every result and fails on an
unexplained skip, a whole validation stage can quietly stop running while PRs stay green.

**5. `cancel-in-progress` differs by branch.** True on PRs, where a superseded run is noise.
False on `main` and on tags, where the run's artifact is the thing being promoted.

## The fork-PR hole, stated rather than hidden

A pull request from a fork gets a read-only `GITHUB_TOKEN`. It cannot push to GHCR, so the
intended behaviour is:

- `build.yml` is called with `push: false` — the image is built and discarded
- `security-scan.yml` gets an empty `image` input and skips the Trivy job explicitly
- CodeQL still runs, because it scans source rather than the image

**Unverified, and the most likely thing here to be wrong.** `pr-validation.yml` declares
`packages: write` on the `build` job and `security-events: write` on `security_scan`.
A fork PR's token is capped at read. Whether GitHub silently downgrades those grants — in
which case the guards above do their job — or rejects the run outright with *"The workflow
is requesting 'packages: write', but is only allowed 'packages: read'"* decides whether
this path works at all or whether the `summary` check never reports and the PR is stuck
pending forever. These files have never run on Actions, so this was not tested.

If it is the second case, the fix is structural: the fork path needs its own workflow that
requests no write scopes, rather than one workflow guarded by an expression. Settle that
against a real fork PR before relying on any of it.

Either way it is a real gap in coverage for fork contributions, written down rather than
papered over with a rebuild inside the scan job. If your repo takes fork PRs, this is the
trade-off to decide deliberately.
