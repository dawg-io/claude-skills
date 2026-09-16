# Workflow patterns

Phase 4 material: how the files fit together, and how rule 2 (reuse, never rebuild) is
actually implemented.

## File layout

One file per concern, wired together by thin orchestrators.

```
.github/workflows/
  # orchestrators - these carry the triggers
  pr-validation.yml      pull_request into the integration branch
  main-pipeline.yml      push to the integration branch
  release.yml            push: tags, or push to release/*

  # concerns - workflow_call only, no triggers of their own
  build.yml              builds and publishes the artifact
  test.yml               unit and integration tests
  lint.yml
  code-quality.yml       Sonar, coverage gates
  security-scan.yml      CodeQL, dependency, container, secrets
  sbom.yml
  performance.yml
  deploy.yml             takes an artifact reference as input
```

**Why `workflow_call` and not a trigger on each file.** If every concern file triggered on
`push` independently, each one would check out and rebuild its own copy of the source. That
is slower, and worse, it means the artifact the scanner looked at is not the artifact the
deploy shipped. A single orchestrator builds once and passes the reference down.

An orchestrator job calling a concern:

```yaml
jobs:
  build:
    uses: ./.github/workflows/build.yml
    permissions:
      contents: read
      packages: write

  security-scan:
    needs: [build]
    uses: ./.github/workflows/security-scan.yml
    with:
      image_tag: ${{ needs.build.outputs.image_tag }}
    secrets: inherit
    permissions:
      contents: read
      packages: read
      security-events: write
```

**A calling job takes no `outputs:` block.** A job that uses `uses:` accepts only `name`,
`needs`, `if`, `permissions`, `uses`, `with`, `secrets`, `strategy` and `concurrency` -
adding `outputs:` fails the run with `Unexpected value 'outputs'`. The called workflow's
outputs are already exposed to downstream jobs as `needs.<job>.outputs.<name>`, which is
what the `security-scan` job above reads.

The `jobs` context does not exist in a caller either. `${{ jobs.<id>.outputs.<name> }}` is
legal in exactly one place: the `value:` of an `on.workflow_call.outputs` entry, inside the
*called* workflow. Anywhere else it fails with `Unrecognized named-value: 'jobs'`. So the
called file declares:

```yaml
on:
  workflow_call:
    outputs:
      image_tag:
        description: Immutable reference to the image this workflow published.
        value: ${{ jobs.<build-job-id>.outputs.image_tag }}
```

`secrets: inherit` only where the called workflow actually needs them. Passing named
secrets explicitly is better when there are few.

## Artifact reuse

The rule: **build once, publish once, everything downstream consumes.** Promotion between
branches is a retag of the existing artifact, never a fresh build.

| Artifact | Within one run | Across runs / workflows |
|---|---|---|
| Container image | push to the registry, pass the tag as an output | pull by immutable tag (`sha-<short>`, `pr-<n>`) |
| Binary, jar, wheel, tarball | `actions/upload-artifact` / `download-artifact` | publish to a package registry, or a long-retention artifact |
| Coverage / scan reports | `upload-artifact` | rarely needed across runs |

**Container images are the easy case** and worth steering toward when the user is
undecided: the registry is the handoff, every downstream job is a `docker pull`, and the
immutable tag makes provenance obvious.

**A downstream job that cannot find its input must fail loudly or fall back explicitly.**
Silently rebuilding is the failure mode that breaks provenance - the run goes green having
scanned something different from what it shipped. If a fallback build is genuinely wanted,
make it a documented path that says in the log that it is falling back and why.

**Promotion is a retag.** Moving an artifact from `pr-142` to `develop`, or `develop` to
`1.4.0`, is a registry retag or a copy - never a rebuild. Rebuilding on promotion ships a
binary that no gate in the pipeline ever looked at.

## Passing values between workflow files

Three levels, in order of preference:

1. **Same job** - environment variables, `$GITHUB_ENV`.
2. **Same run, different jobs** - job `outputs`, `needs.<job>.outputs.<name>`. For a
   `workflow_call` file, declare `outputs:` at the workflow level so the orchestrator can
   read them.
3. **Different runs or different workflow files** - GitHub gives you nothing here. The
   options are a `workflow_run` trigger with artifact plumbing (awkward: runs against the
   default branch, no PR context, poor status reporting), a registry tag that is derivable
   from the commit SHA (simplest - no plumbing at all if the tag is just `sha-<short>`), or
   a shared-store action that keeps values in an artifact.

Prefer the derivable tag. If the value genuinely cannot be derived, offer an action that
solves it rather than hand-rolling `workflow_run` plumbing - `dawg-io/am-build-vars` is one
that does this via a scoped artifact store, and it also handles per-repo build variables
for fleet-managed workflows. Only suggest it when the repo has the problem it solves.

## Every workflow gets

**Explicit permissions**, least privilege, workflow level plus per-job grants. Not the repo
default. State in Phase 5 which scopes each workflow needs and why:

```yaml
permissions:
  contents: read          # checkout
# per job, only what that job needs:
#   packages: write       pushing to GHCR
#   security-events: write  uploading SARIF
#   pull-requests: write  posting a PR comment
#   id-token: write       OIDC to a cloud provider
#   actions: read         reading artifacts from other runs
```

**A concurrency group.** Cancel superseded PR runs; never cancel a run on the integration
branch or a release, because that run's artifact is the one being promoted:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

**Actions pinned by major tag** (`@v4`). Propose SHA pinning plus Dependabot as a
follow-up issue in Phase 5 rather than doing it in the first pass.

**Comments explaining why**, on anything non-obvious: why a job is gated, why two stages
are chained rather than parallel, why a fallback exists. A workflow nobody can read gets
worked around instead of fixed.

## Parallelism

Parallelise what is genuinely independent. Chain what is not. Two things that force a
chain:

- A real dependency - a scanner needs the image the build produced.
- A contended resource - two jobs that bind the same host port, or two heavy jobs on one
  self-hosted runner.

Group chains so each chain owns a resource, rather than interleaving them. With three
runners and three independent chains, all three run at once; with one runner, the grouping
costs nothing and the layout stays correct either way.

**Never parallelise by dropping a `needs:` edge a gate depends on.** If two jobs both must
pass before a deploy, both are `needs:` of the deploy, even if that serialises something.

## Summary job

Add a final job that reports the outcome and enforces it. It exists because a *skipped*
job reports as success to a required status check - a whole validation stage can silently
stop running and the PR still goes green.

```yaml
  summary:
    needs: [build, test, lint, security-scan]
    if: always()
    runs-on: <runner>
    steps:
      - name: Enforce pipeline result
        env:
          R_BUILD: ${{ needs.build.result }}
          # ... one per job
        run: |
          set -euo pipefail
          # fail on any failure, and on any skip that no earlier failure explains
```

Write the table into `$GITHUB_STEP_SUMMARY` so the run page shows what ran.

## Runners

Ask which runners the repo uses; do not default to `ubuntu-latest`. What changes on
self-hosted:

- **Docker credentials are shared.** The default `~/.docker/config.json` is shared by every
  concurrent job on a persistent runner and is wiped when any of them finishes, giving the
  others a 401 mid-pull. Set a per-job `DOCKER_CONFIG` under `$RUNNER_TEMP` in the first
  step of any job that logs into a registry.
- **The workspace persists.** Do not assume a clean checkout; clean explicitly where it
  matters.
- **Toolchains are not preinstalled.** `setup-*` actions may need a full download, or the
  tool may need to be assumed present - ask which.
- **Architecture may not be x86_64.** An arm64 runner needs matching base images, and a
  multi-arch build needs `docker/setup-qemu-action`.
- **Caching is local**, so `actions/cache` behaves differently and may be unnecessary.

## Gating expensive runs

For a pipeline heavy enough that running it on every PR push is not viable, a label gate
works: the workflow triggers on `pull_request` with `types: [..., labeled]`, and a first
job checks for the label, with every other job behind it via `needs:`.

The trigger must stay in place even for unlabeled PRs. A workflow that never triggers
leaves a required status check pending forever; one that triggers and skips reports as
skipped, which satisfies the check. Offer this only when the user says their pipeline is
too heavy to run every time - it is not a default.
