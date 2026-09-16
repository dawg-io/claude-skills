# `.claude/code-release.yml` — config schema

The file lives in the **repo being released**, at `.claude/code-release.yml` (`.yaml` is also
accepted). It is the only project-specific input the `code-release` skill takes; everything else
is discovered from the repo at run time.

Worked configs to copy: `examples.md`.

## Top level

| Key | Type | Required | Notes |
|---|---|:--:|---|
| `version` | number | **yes** | Schema version. Currently `1`. An unrecognised value is a hard stop, not a warning |
| `release` | map | **yes** | What to dispatch, and on what ref |
| `approval` | map | **yes** | The human sign-off gate. Not optional — it's what makes the skill safe to point at production |
| `docs` | map | no | Omit → the docs gate (Phase 3) and the docs deploy check (Phase 7) are both skipped |
| `outcome` | map | no | Omit → the skill stops when the workflow run succeeds |
| `announce` | map | no | Omit → no announcement |
| `record` | map | no | Omit → the HTML release record is written to the default path. See below |

## `release`

| Key | Type | Required | Default | Notes |
|---|---|:--:|---|---|
| `workflow` | string | **yes** | — | The workflow's **exact display name**, never a file path. See below |
| `default_ref` | string | **yes** | — | Branch, tag, or SHA to release when the user doesn't name one. Confirmed with the user in Phase 6 before anything is dispatched |
| `ref_input` | string | no | — | Name of the workflow input that receives the version/ref string. **Omit when the workflow declares no such input** |
| `inputs` | map | no | `{}` | Static extra inputs sent on every dispatch |

### Why display name, never file path

`.github/workflows/promote.yml` may present itself as "Promote Release to Public
Repository". The file name and the `name:` field drift apart routinely, and a path that
looks right can point at a different workflow than the one anyone refers to by name. The
skill always resolves by display name and stops if no workflow matches.

### `ref` and `ref_input` are different things

This is the easiest thing in the schema to get wrong. GitHub's dispatch API takes two
independent parameters:

- **`ref`** — the git ref the run happens on. Always required by GitHub itself. This comes
  from `default_ref` (or whatever the user confirms in Phase 6).
- **`inputs`** — the workflow's declared `workflow_dispatch.inputs`. Only exists if the
  workflow declares them.

So `ref_input` names an *additional input key* that also receives the version string, for
workflows that want it passed explicitly. A workflow can run on a ref while declaring no
inputs at all — that's the `ref_input`-omitted case, and it's perfectly normal.

The full payload the skill sends:

```
ref    = the ref confirmed in Phase 6
inputs = release.inputs                                   (static extras, may be empty)
       + { <release.ref_input>:     <that same ref> }     only if ref_input is set
       + { <approval.number_input>: <issue number>  }     only if number_input is set
```

## `approval`

| Key | Type | Required | Default | Notes |
|---|---|:--:|---|---|
| `issue_label` | string | **yes** | — | Label applied to both the review issue and any `[ON HOLD]` issue. This is the **lookup handle** — see below |
| `body_is_release_notes` | bool | no | `false` | True when the workflow fetches the closed issue's body verbatim |
| `number_input` | string | no | — | Workflow input that receives the approved issue's number. Omit when the workflow doesn't take one |

### `issue_label` is a lookup handle, not decoration

Earlier versions of this process found prior issues by matching a date in the title. That
breaks the moment a date format changes, a run spans midnight, or two releases happen in a
day. The label is durable: the skill finds prior work by querying **open issues carrying
this label**, and distinguishes a blocking hold by an `[ON HOLD]` prefix on the title.

Titles stay human-readable and dated. The label is what's actually matched on.

If the label doesn't exist in the repo, the skill creates it and says so.

### `body_is_release_notes` is why the issue splits in two

When true, the closed issue's **body ships verbatim** — typically as the promotion commit
message, the downstream PR description, and the release notes. Anything internal in that
body becomes public. So the skill splits the issue:

- **body** → real public release notes, plain user-facing language, no PR references, no
  internal jargon
- **comment** → baseline SHA, range compared, docs-audit result, risk callouts, full linked
  PR list

When false, nothing is fetched, so there's nothing to protect: the skill writes one issue
for the human reviewer and says in its report that the body isn't shipping anywhere.

Set this to `true` only if the workflow really does fetch the issue body. Check the workflow
YAML for the fetch step rather than assuming.

## `docs`

Omitting the whole block skips **both** the Phase 3 staleness gate and the Phase 7 deploy
check. The skill says it's skipping and why, so an absent block never reads as a passed
gate.

| Key | Type | Required | Notes |
|---|---|:--:|---|
| `paths` | list(string) | **yes** (within the block) | Glob paths that count as documentation. Drives the Phase 3 audit |
| `deploy_workflow` | string | no | Display name of a separate docs-publishing workflow. Omit → Phase 3 still runs, Phase 7 is skipped |
| `deploy_watches` | map | no | What `deploy_workflow`'s push trigger actually watches — `{branch: <name>, paths: [<glob>]}` |

### `deploy_watches` exists to catch a silent failure

A docs-deploy workflow triggered by `push` to `main` on `paths: docs/**` never fires if docs
changes only ever land on a release branch. The site then goes stale **indefinitely, with no
error anywhere**. Recording what the workflow watches lets the skill compare it against
where the docs changes in this range actually landed, instead of inferring "current" from
"nothing failed recently".

## `outcome`

Omit when the workflow's own success is the end state — the skill reports the run and stops
rather than hunting for an artifact the project doesn't produce.

| Key | Type | Required | Default | Notes |
|---|---|:--:|---|---|
| `type` | enum | **yes** (within the block) | — | `pull_request` or `release` |
| `repo` | string | no | current repo | `owner/name` where the outcome lands |

- **`pull_request`** — the workflow opens a PR (the private→public promotion shape). The
  skill locates it and confirms it's actually **open** before announcing.
- **`release`** — the workflow publishes a GitHub Release. The skill locates it by tag and
  confirms it exists and **is not a draft**.

Either way the skill never merges, publishes, or promotes the thing it found.

## `announce`

Omit for no announcement. A failed announcement is never treated as a failed release — the
release already happened.

| Key | Type | Required | Notes |
|---|---|:--:|---|
| `slack` | string | **yes** (within the block) | `dm_self` to DM the connected Slack user, or a `#channel` name |
| `template` | string | no | Message text with placeholders. A sensible default is used if omitted |

### Template placeholders

| Placeholder | Value |
|---|---|
| `{repo}` | The repo being released, `owner/name` |
| `{ref}` | The ref actually released |
| `{url}` | The outcome URL — the PR or release. **Falls back to the run URL** when no `outcome` block is configured |
| `{run_url}` | The workflow run's URL, always |

Anything else in braces is left alone.

## `record`

Phase 10 writes one self-contained HTML file recording what shipped. It runs **only after a
release actually shipped** — a run that stopped at a gate produces the text report and
nothing else. Omit this block entirely for the defaults.

| Key | Type | Required | Default | Notes |
|---|---|:--:|---|---|
| `dir` | string | no | `.claude/release-records` | Directory the record is written to, relative to the repo root. Created if missing |
| `enabled` | bool | no | `true` | Set `false` to skip Phase 10. The skill says it skipped, like any other skipped phase |

The file is named `release-<YYYY-MM-DD>-<short sha>.html` and is left **untracked** —
committing it, ignoring it, or deleting it is yours to decide. Point `dir` at a published
docs folder if you want the records to become a public changelog; leave it at the default if
you'd rather they stay local.

Self-contained is a hard requirement, not a preference: inline styles, no CDN, no external
fonts, no scripts. The record has to open from a local disk with no network, years later.

## Validation, and what is a hard stop

Phase 0 validates twice — the file against this schema, then the config against the live
workflow. Both stop the run rather than warning:

| Checked | Failure |
|---|---|
| `version` recognised | Hard stop |
| Required keys present | Hard stop, naming the key |
| File parses as YAML | Hard stop |
| `release.workflow` resolves to a real workflow by display name | Hard stop |
| Every input key the config sends exists in `workflow_dispatch.inputs` | Hard stop |
| Every input the workflow marks `required: true` is supplied | Hard stop |

The input-name check is a stop rather than a warning because of how GitHub behaves on a
wrong name: the dispatch may **succeed** and the workflow silently use its own default. A
release that ships the wrong ref because an input name drifted is indistinguishable from a
correct one until someone looks at what actually shipped.

Where the config and the repo disagree, **the repo wins**. The skill stops, names the stale
key, and leaves fixing the config to the user — it never edits the config to match reality,
and never forces a run to match a stale config.
