# Branch models, triggers and tagging

Phase 2 material. Offer a named model rather than making the user describe one from
scratch, then confirm every branch individually - teams routinely say "git-flow" and mean
something else.

## The models

**Trunk-based** - `feature/*` -> `main`. Short-lived branches, everything merges to trunk,
releases cut from trunk by tag. Simplest pipeline, fewest surprises. The right default for
a repo that does not already have something else.

**GitHub flow** - `feature/*` -> `main`, deploy from `main` on every merge. Trunk-based
plus continuous deployment. Only viable with a real test suite and a rollback story; ask
about both before recommending it.

**git-flow** - `feature/*` -> `develop` -> `release/*` -> `main`, plus `hotfix/*` -> `main`.
Two long-lived branches, an explicit release stabilisation window. More pipeline surface:
`develop` needs its own integration run, `release/*` needs a validation run, `main` is
promotion only.

**Add-ons, independent of the model:** `nightly` or scheduled builds (a `schedule:`
trigger, not a branch); `hotfix/*` branching from the production branch and merging back to
both; environment branches (`staging`, `production`) used as deployment pointers rather
than development lines.

## Trigger matrix

The default shape per branch class. Every cell is a recommendation to confirm, never a
decision to make silently.

| Branch class | Trigger | Typical work | Publishes? |
|---|---|---|---|
| `feature/*` | `push` | build, unit test, lint | Immutable per-commit artifact only (`sha-<short>`), so a PR can reuse it |
| PR into integration | `pull_request` | full validation: build (or reuse), test, code quality, security scan | Per-PR artifact (`pr-<n>`) that the PR's own checks consume |
| Integration merge (`develop`/`main`) | `push` on that branch | full validation on what actually landed | Promote the PR's artifact to the moving tag - retag, do not rebuild |
| `release/*` | `push` + `pull_request` | validation, release-candidate checks, staging deploy | `rc-<version>` tag on the same artifact |
| Tag `v*` | `push: tags` | release publication, deploy to production | Final semver tag, again a retag |
| Scheduled | `schedule:` | long-running scans, dependency audits, nightly build | `nightly-<date>` |
| Manual | `workflow_dispatch` | anything, on any of the above | as chosen |

Two rules that fall out of this table:

- **A `pull_request` trigger from a fork gets a read-only token and no secrets.** Any job
  that needs a registry push or a deploy credential cannot run on a fork PR. On a public
  repo, ask whether fork PRs are expected, and design so the untrusted path validates
  without secrets while the trusted path publishes.
- **A `paths:` filter on a required status check will leave PRs stuck pending forever** if
  the check never fires. Either do not require it, or let it run and skip internally.

## Tagging

Recommend semantic versioning for releases, always. Then add the convention the language
actually uses - the language reference names it, and it is not always plain semver.

**Two tags per artifact, not one.** A moving tag for humans and a resolvable immutable tag
for the pipeline:

| Purpose | Example | Moves? |
|---|---|---|
| Per-commit handle | `sha-a1b2c3d` | never - this is what downstream jobs pull |
| Per-PR handle | `pr-142` | per push to the PR |
| Integration | `develop`, `edge` | yes |
| Release candidate | `1.4.0-rc.2` | never |
| Release | `1.4.0`, plus moving `1.4`, `1`, `latest` | the short ones move |

The immutable tag is not optional. It is the handle that makes rule 2 work: without a name
that resolves to exactly one build, a downstream stage has no choice but to rebuild.

**Version source.** Ask where the version number comes from, because a pipeline that
invents one drifts from the manifest. The options: read from the manifest
(`package.json`, `pom.xml`, `Cargo.toml`, `pyproject.toml`), derive from the git tag, or
`git describe`. Whichever it is, one source only - two places to bump is how a release
ships with the wrong version.

## Before leaving Phase 2

Restate the whole flow and get an explicit yes: every branch, its purpose, what merges into
it, what it tags with. Then check for these contradictions specifically:

- A branch was named but nothing merges into it and nothing triggers on it.
- Two branches both claim to be where releases come from.
- A tag scheme was chosen that the language's registry will not accept (see the language
  reference - Go, PEP 440 and OCI tags all have their own rules).
- Deploys were described for an environment that no branch or tag maps to.
- Fork PRs are expected on a public repo, and a PR-triggered job needs a secret.
