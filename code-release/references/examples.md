# `.claude/code-release.yml` — worked examples

Three shapes, from most to least machinery. Field reference: `config-schema.md`.

**Every example below goes in *your* repo, at `.claude/code-release.yml` — the repo you want to
release, not the repo the skill was copied from.** Names like `your-org/your-app` are
placeholders: replace every one of them with your own before the config means anything.
`/code-release init` fills them in for you from what your repo actually has, which is the less
error-prone route.

---

## 1. Private → public promotion

**When this shape fits:** development happens in a private repo, and releasing means an
automated workflow opening a PR against a separate public repo. The public PR's description
and release notes come from the approved review issue's body, fetched verbatim — so
`body_is_release_notes` is true and the skill splits the issue into public notes (body) and
internal bookkeeping (comment).

> **Replace `your-org/your-app-public` with your own public repo**, and put this file in your
> private repo at `.claude/code-release.yml`. The workflow name, the input names, and the label
> below are examples of the *shape* — yours will differ, and Phase 0 hard-stops if they don't
> match your real workflow.

```yaml
version: 1

release:
  workflow: "Promote Release to Public Repository"   # your workflow's display name
  default_ref: develop
  ref_input: version
  inputs: {}

approval:
  issue_label: release-review
  body_is_release_notes: true
  number_input: review_issue_number

docs:
  paths: ["docs/**"]
  deploy_workflow: "Deploy Documentation to GitHub Pages"
  deploy_watches:
    branch: main
    paths: ["docs/**"]

outcome:
  type: pull_request
  repo: your-org/your-app-public                     # the public repo the PR lands in

announce:
  slack: dm_self
  template: "🚀 {repo} release: `{ref}` → {url}"

record:
  dir: .claude/release-records
```

**Two things to confirm against your real workflow before trusting a config in this shape**,
because both are exactly the kind of fact that drifts:

- `ref_input` — the name of the input that carries the version/ref. It is *not* the same as
  the git ref the run happens on, and workflows disagree about what to call it (`version`,
  `tag`, `release_ref`). Phase 0 hard-stops if it's wrong and tells you the real name.
- `deploy_watches` — written here as `main` + `docs/**`. If your docs changes only ever land
  on `develop`, that workflow never fires and the live site goes stale silently. That's the
  precise failure `deploy_watches` exists to catch, so record what your workflow *actually*
  watches, not what you wish it watched.

---

## 2. Ordinary release workflow

**When this shape fits:** one repo, no promotion. A workflow builds and publishes a GitHub
Release from a tag or branch. Nothing fetches the issue body, so the review issue is written
for the human reviewer alone. The announcement goes to a team channel.

```yaml
version: 1

release:
  workflow: "Publish Release"
  default_ref: main
  ref_input: version
  inputs:
    channel: stable

approval:
  issue_label: release-review
  body_is_release_notes: false
  number_input: approval_issue

docs:
  paths: ["docs/**", "README.md"]
  deploy_workflow: "Publish Docs Site"
  deploy_watches:
    branch: main
    paths: ["docs/**"]

outcome:
  type: release

announce:
  slack: "#releases"
  template: "{repo} {ref} is out → {url}"

record:
  dir: docs/releases
```

Notes on the differences from example 1:

- `outcome.type: release` with **no `repo`** — the release lands in the current repo, so the
  key is omitted rather than repeated.
- `body_is_release_notes: false` — the issue body ships nowhere, so it doesn't have to be
  written as public-facing prose.
- `inputs: {channel: stable}` — a static extra sent on every dispatch, on top of the ref and
  issue-number inputs.
- `record.dir: docs/releases` — the HTML record lands in the published docs folder instead
  of the default `.claude/release-records/`, so the records become a browsable changelog.
  It's written untracked either way; committing it is your call.

---

## 3. Minimal

**When this shape fits:** a workflow that releases, a human who approves, and nothing else.
No docs to audit, no artifact to locate, no announcement. This is the smallest valid config
— everything omitted here is genuinely optional.

```yaml
version: 1

release:
  workflow: "Release"
  default_ref: main

approval:
  issue_label: release-review
```

What the skill does differently with this config:

| Phase | Behaviour |
|---|---|
| 3 — docs gate | **Skipped entirely** — no `docs` block. Said aloud, so it never looks like a passed gate |
| 4 — review issue | Opened and labelled as always. Body written for the human reviewer, since `body_is_release_notes` defaults to false |
| 7 — docs deploy | Skipped — no `docs.deploy_workflow` |
| 8 — dispatch | `ref` only, **no inputs at all** — neither `ref_input` nor `number_input` is set |
| 9 — outcome | Stops at run success. No PR or release is hunted for, and nothing is announced |
| 10 — record | Still written. A release shipped, so there's something to record — to `.claude/release-records/` unless `record.dir` says otherwise |

The approval gate still runs. It's the one block that can't be omitted, because it's what
makes the skill safe to point at a production workflow.

---

## Adding a docs gate without a deploy workflow

A common middle ground: docs live in the repo and should block a stale release, but they're
rendered by something outside GitHub Actions (or not rendered at all).

```yaml
docs:
  paths: ["docs/**"]
```

Phase 3 audits those paths and blocks on staleness; Phase 7 is skipped because there's no
`deploy_workflow` to check. Both are reported.
