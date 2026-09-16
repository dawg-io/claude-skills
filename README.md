# claude-skills

A collection of [Claude Code](https://claude.com/claude-code) skills for application
development and infrastructure work.

Each skill lives in its own folder with a `SKILL.md` (the skill itself) and a `README.md`
documenting what it does, when it fires, how it works phase by phase, and what it will
refuse to do.

## The skills

| Skill | What it does | Scope |
|---|---|---|
| [`code-development`](code-development/) | Takes a feature, bugfix, or patch from "I want X" to an open PR — scope, implement, document, in that strict order. `/code-development init` records your real test and lint commands after running them | **General-purpose** |
| [`pipeline-create`](pipeline-create/) | Gives a repo with **no** CI one — scans every language, interviews you through artifacts, branching, gates and deploys, then writes split-by-concern GitHub Actions workflows on a branch. Build once, promote by retag, never guess. Ships a [practice repo](pipeline-create/example/) with no CI and the [pipeline it produces](pipeline-create/example/expected-pipeline/) | **General-purpose** |
| [`pipeline-monitor`](pipeline-monitor/) | Watches CI after a push or PR, reads the real failing logs, root-causes it, and fixes it or escalates with options. `/pipeline-monitor init` records which checks gate a merge and how to reproduce each locally | **General-purpose** |
| [`code-release`](code-release/) | Drives a repo's release end to end — PR audit, blocking docs gate, approval issue, workflow dispatch, outcome announcement, HTML record — from a `.claude/code-release.yml` that `/code-release init` writes for you. `/code-release dry-run` rehearses it read-only | **General-purpose** |
| [`ansible-create`](ansible-create/) | Turns a host into a minimal playbook, an inventory line, and a draft PR. `/ansible-create init` checks your repo has the shape it needs and records the real paths. Ships a working [example repo](ansible-create/example/) to use it against | **General-purpose** |
| [`terraform-create`](terraform-create/) | Interviews you for a new Proxmox VM and emits a ready-to-paste tfvars entry plus the matching Ansible inventory line. `/terraform-create init` records *your* VLAN, sizing, addressing and node names in place of the example ones. Ships a working [example module](terraform-create/example/) to use it against | Environment-specific |

**General-purpose** skills are repo-agnostic — they discover your toolchain rather than
assuming one, and should work in any project as-is. They no longer rediscover it on every
run: each has an `init` that writes a small `.claude/<skill>.yml` in the repo it serves,
recording what it found so the next run reads instead of re-deriving. `ansible-create`
additionally expects a particular repo *shape*, and ships a working `example/` that
implements it — its `init` checks for that shape rather than assuming it.

`pipeline-create` is the one exception: it runs essentially once per repo, so there is
nothing worth caching for a next run. Its record is the `.github/pipeline-plan.md` it commits
alongside the workflows, and it has no `init`.

**Environment-specific** means the skill targets a particular platform — `terraform-create`
assumes Proxmox. Its two `references/` files carry concrete VLANs, addressing and node names
as fallbacks so the skill has something to reason about before you've configured it. They're
illustrative, not defaults worth keeping: `init` reads your real tfvars and replaces them,
and its README lists every value to swap. The structure is the reusable part.

## Installing

Skills are just folders. Copy the ones you want to either location:

```bash
# personal — available in every project
mkdir -p ~/.claude/skills
cp -r code-development pipeline-monitor ~/.claude/skills/

# project-scoped — checked in alongside the code it serves
mkdir -p /path/to/repo/.claude/skills
cp -r code-development /path/to/repo/.claude/skills/
```

Both `mkdir -p` lines matter. Without the first, `cp` fails outright on a machine that has
never installed a skill. Without the second it's worse: `cp -r` into a missing directory
**succeeds** and copies the folder's *contents* there, so you get `.claude/skills/SKILL.md`
instead of `.claude/skills/code-development/SKILL.md`, no error, and a skill that never
loads.

Claude Code picks them up on the next session. Each skill fires either on its slash command
(`/code-development`) or automatically when the request matches its `description` — the
trigger phrases are listed in every skill's README.

Most of these need `git` and an authenticated `gh` CLI, or a connected GitHub MCP server.
Per-skill requirements are documented in each folder.

### Then run `init`

**Five of the six need a second step after copying.** Each is driven by a small config that
lives in *your* repo, not in the skill, and each writes that config for you:

```
/code-development init     /pipeline-monitor init     /code-release init
/ansible-create init       /terraform-create init
```

They all work the same way: discover what they can from the repo, ask only what they
genuinely can't read, show you the file in full, **validate it for real** — running the
commands, resolving the paths, checking the names against a live run — then commit that one
file on a branch and open a PR. Nothing is merged without an explicit yes, and none of them
commits anything else.

Three are worth calling out:

- **`code-release`** also has `/code-release dry-run`, which rehearses an entire release read-only.
  Run it before the real thing. Full walkthrough in [`code-release/README.md`](code-release/README.md).
- **`terraform-create`** ships illustrative fallback values. Its `init` replaces them with
  yours, read from your existing tfvars where it can.
- **`pipeline-create`** has no `init` at all. It runs once per repo, so there is nothing to
  cache — copy it and run `/pipeline-create` in a repo that needs a pipeline.

Skipping `init` isn't fatal — the skills still discover what they need each run and say
they're doing so. You just pay for it every time, and anything they had to guess stays a
guess.

## Conventions these skills share

They're written to the same shape, which is most of why they behave predictably:

- **Hard rules restated up front.** Each skill opens by naming the two to seven rules that
  erode first under pressure, because that's where they need to be visible.
- **Discover, don't assume.** Ground truth comes from real commands and the actual repo —
  `.github/workflows/`, `ansible.cfg`, `terraform.tfvars`, the nearest existing role. Where
  a skill documents a repo fact, it's marked as a snapshot, and **the repo wins on any
  disagreement**.
- **An `init` that records what it discovered.** Each skill except `pipeline-create` writes
  one `.claude/<skill>.yml` in the repo it serves, so discovery happens once instead of every
  run — and so environment-specific values are recorded rather than baked in. That file is
  the only thing **`init` itself** commits, always on a branch, always after you've seen it.
  What a skill commits during its actual work is its own business — `code-development`
  commits your implementation, `ansible-create` a playbook and an inventory line,
  `pipeline-monitor` a fix and its regression test, `pipeline-create` a set of workflow files.
- **Validated, not assumed.** Every `init` proves what it wrote before committing it: the
  test command is run, the inventory is parsed, the check names are matched against a real
  run. A config that names something that doesn't exist is worse than no config, because it
  reads as verified.
- **A diagram where the shape is the hard part.** Each README carries a "where the files go"
  graph — the skill folder and the per-repo config are two different things in two different
  places, and that confuses everyone once — and a flow of what a real run does, with every
  stop marked.
- **Explicit stop-and-ask gates.** Every skill has a "Stop and ask when" list. Any design
  decision with more than one viable approach is a stop, not a coin flip.
- **Explicit out-of-bounds lists.** "Never in bounds, even when it would be faster" — no
  `git add -A`, no pushing to the default branch, no weakening a check to get it green, no
  scope creep past what was approved.
- **No fabricated command output.** All six carry the same rule, worded for what they
  actually run — `"not run — <reason>"` for a command, `"Not reached — <reason>"` for a
  phase. Either is a correct answer, and a fabricated pass is the one failure mode that
  makes a skill worse than doing the work by hand.
- **A fixed report template.** Every run ends in the same shape, so the output is scannable
  and it's obvious what was actually verified versus merely claimed.
- **Secrets are findings, not inconveniences.** Credentials in logs or config get named,
  redacted, and flagged for rotation — never quietly stepped around.

## About the values in here

No credentials, tokens, or keys anywhere in the tree — or anywhere in the history.

Every concrete value in `terraform-create/references/` and in both `example/` directories is
illustrative: RFC1918 addresses, `example.lan`, placeholder hostnames, a `deploy` SSH user.
They exist so a skill has something specific to reason about before you've run its `init`,
and every one of them is superseded by the `.claude/<skill>.yml` that `init` writes from your
own repo. Nothing here describes a real network.

The two `example/` directories are working code, not illustrations of code — each has its own
README recording exactly which commands were run against it and what wasn't checked.

## License

[MIT](LICENSE). Copy a skill, change it, ship it — attribution is the only condition.
