# Pipeline plan — widgetsvc

Written by `/pipeline-create`. In a real run this file lands at `.github/pipeline-plan.md`
and is committed with the workflows. It exists so a later session can pick the interview
back up instead of starting over, and so a reviewer can see *why* the pipeline looks like
this without reverse-engineering the YAML.

**Path taken:** fast — 1 language (Python 3.11+), one artifact, no deployment target
**Branch model:** trunk-based — `feature/*` → `main`, releases cut from `main` by a `v*` tag

## What was found in Phase 0

| Language | Path | Build tool | Manifest | Lockfile | Tests | Existing CI |
|---|---|---|---|---|---|---|
| Python | `.` | hatchling | `pyproject.toml` | `requirements-dev.txt` (pinned) | pytest, 8 tests in `tests/` | none |

Red flags: none blocking. `requirements-dev.txt` pins dev tooling but there are no runtime
dependencies to pin, so reproducibility holds. Ruff config present. `requires-python` set,
so the version matrix did not have to be asked for — it was confirmed instead.

## Decisions

| Question | Answer | Why |
|---|---|---|
| Artifact | Container image | The repo has a `Dockerfile` and this is a service, not a library |
| Registry | GHCR | No secret to create — `GITHUB_TOKEN` with `packages: write` is enough |
| Immutable tag | `sha-<short>` | Derivable from the SHA, so a later workflow reconstructs it with no plumbing |
| Moving tags | `edge` on main, `<version>` / `<major.minor>` / `latest` on a release | Humans read the moving tag; the pipeline only ever pulls the immutable one |
| Version source | `[project] version` in `pyproject.toml` | One place to bump. The `v*` tag is expected to match it |
| Test matrix | 3.11, 3.12 | `requires-python = ">=3.11"` plus current stable |
| Coverage | `--cov-report=xml`, 3.12 only | The format a quality gate can read; one report, not a merge problem |
| Security set | CodeQL + Trivy on the image | Trivy scans the built digest, so what was scanned is what ships |
| Deployment | None | "Done" for this repo is an image in GHCR that something else consumes |
| Runners | GitHub-hosted `ubuntu-latest` | Confirmed, not assumed |

## The reuse chain

```
build.yml  →  ghcr.io/<owner>/<repo>:sha-<short>     (built once, pushed once)
                 ├─ security-scan.yml pulls it by that exact tag
                 ├─ main-pipeline.yml retags it to :edge          (no rebuild)
                 └─ release.yml retags it to :1.4.0 / :1.4 / :latest  (no rebuild)
```

Nothing after `build.yml` compiles source. Promotion is `docker buildx imagetools create`,
which copies the manifest — the digest is unchanged, so the image a scanner cleared is
provably the image that ships.

The one place the chain breaks is a **fork PR**: `GITHUB_TOKEN` is read-only there, the
build cannot push, and the image scan has nothing to pull. It is skipped explicitly rather
than replaced with a rebuild.

## Files

| File | Triggers | Does |
|---|---|---|
| `pr-validation.yml` | `pull_request` → `main` | Build, test, lint, scan, and the required `summary` check |
| `main-pipeline.yml` | `push` → `main` | Same validation on what landed, then retag to `edge` |
| `release.yml` | `push` tag `v*` | Retag to the release versions, SBOM, GitHub release |
| `build.yml` | `workflow_call` | Builds and pushes the image; returns the immutable reference |
| `test.yml` | `workflow_call` | pytest across the matrix, coverage from one version |
| `lint.yml` | `workflow_call` | `ruff check`, `ruff format --check` |
| `security-scan.yml` | `workflow_call` | CodeQL, and Trivy against the built image |

## Secrets and variables to create

| Name | Used by | How to create it |
|---|---|---|
| — | — | None. GHCR authenticates with the built-in `GITHUB_TOKEN` |

## Permissions and settings you must configure

- `contents: read` at workflow level everywhere; `packages: write` on the build and promote
  jobs, `packages: read` on the image scan, `security-events: write` on anything uploading
  SARIF, `contents: write` on the release job only.
- **Branch protection on `main`**, requiring the `summary` check from `PR validation`.
  Requiring the individual jobs instead would let a silently-skipped stage pass.
- **Actions → Workflow permissions**: read-only default, which the explicit blocks override.
- CodeQL and SARIF upload are free on a public repo; a private repo needs GitHub Advanced
  Security or the upload step fails.

## Proposed follow-up issues

1. **Pin actions by SHA and enable Dependabot** — the first pass pins by major tag (`@v4`).
2. **Add a GHCR retention policy** — `sha-*` tags accumulate on every commit to `main`.
3. **Add a coverage threshold** — coverage is measured and uploaded but nothing fails on a drop.
