---
name: ansible-create
description: >-
  Builds the Ansible side of a node terraform-create provisioned, driven by a
  `.claude/ansible-create.yml` in that repo — no hardcoded inventory path or branch name.
  `/ansible-create init` checks the repo has that shape, records its real paths,
  conventions and lint commands, and PRs that config. A build run asks first whether this
  is an existing role on a new host (fast path: one inventory line and a group) or
  something new (full interview), then writes the minimal playbook and inventory line on a
  branch off the default branch and opens a draft PR. Verifies with `--syntax-check` and
  `ansible-lint` only; never runs a playbook against real inventory, not even `--check`.
  Use on /ansible-create, "ansible create", an ask for a playbook or role for a node, to
  apply an existing role to a new host, to wire a new VM into Ansible, or a handed-over
  tfvars entry plus "now the ansible side". Not for debugging a failing run, or a Talos
  cluster. Needs an Ansible repo (see `example/`), `git` and `gh` — Claude Code only.
---

# ansible-create

The other half of `terraform-create`. That skill stops at a printed tfvars entry and a
host line; this one turns a host into working automation and a draft PR.

Everything repo-specific — which inventory file, which roles directory, which branch to cut
from, which commands verify the result, what the repo's own naming looks like — comes from
**`.claude/ansible-create.yml` in the Ansible repo being written into**. This skill
hardcodes no path. `/ansible-create init` checks the repo has the shape at all, then writes
that file from what it actually found.

Hard rules:

1. **Check access, load the config, then ask new-or-existing, before anything else.**
   `git ls-remote origin` first. Then Phase 1: is this a role the repo already has, or
   something new? Applying an existing role is minutes; writing one is a build. Getting
   that fork wrong wastes the whole session. Both sessions this skill is distilled from
   lost the most time here — one built on guessed conventions while locked out of the
   repo, the other wrote a docker prune that already existed nightly and was merely
   misconfigured.
2. **The config is the contract; the repo is the truth.** Where they disagree — a recorded
   path that moved, a convention that changed — **stop and say which key is stale** rather
   than forcing the run to match the config or silently re-deriving around it.
3. **Ship the literal ask, minimal.** Default to the smallest thing that does what was
   asked. Offer extras as a sentence in the reply, never pre-installed in the file. A
   ~100-line first draft got cut to 38 lines and one task; the extras were also what made
   it slow.
4. **Match the repo, not the linter.** Whether `ansible-lint` governs the repo is a fact
   about that repo, recorded at init as `verify.lint_enforced_by_ci`. Where plays are
   unnamed by house style, lint fires `name[play]` on every one of them. Run lint for real
   findings, leave the warnings listed in `verify.allowed_lint_rules` in place, and say in
   the report which ones you left and why.
5. **Never executes against real hosts.** `--syntax-check`, `--list-tasks`, `ansible-lint`
   and `ansible-inventory --list` **against a static inventory** only. Not `ansible-playbook`
   against inventory, not `--check`, not `ansible -m ping`. A check run still opens SSH and
   gathers facts, and a *dynamic* inventory is code that `--list` would execute.
6. **Never guess a repo fact or an upstream behaviour.** Read `ansible.cfg`, the
   inventory, and the nearest existing code. For upstream claims, read the source — in
   the gitea session, `netplan set`, the runner's `register` exit code, its env-var
   support and its lockfile requirement all behaved differently from the obvious
   assumption, and three contradicted the docs.
7. **Never write a secret into a file.** Tokens and passwords become an empty default
   with a `CHANGEME`-style assert, or a vault reference. Never a literal.
8. **Never claim a command ran when it did not.** "ansible-lint: not run — venv build
   failed" is correct. A fabricated clean lint is the one failure that makes this skill
   worse than doing it by hand.
9. **Two kinds of commit, and neither is `git add -A`.** Setup mode commits exactly one
   path — `.claude/ansible-create.yml` — and nothing else. A build run commits only the
   files it created *or modified* that run — the inventory line counts — staged by name.
   Both go on a branch cut from the default branch. Nothing is ever committed to the
   default branch, and no PR is merged or marked ready without an explicit yes.

## The two modes

Pick the mode before doing anything else, and say which one you're in.

| Invocation | Mode | Writes anything? |
|---|---|---|
| `/ansible-create init`, "set up ansible-create", "configure ansible-create" | **Setup** — verify the repo's shape, record its real paths and conventions in `.claude/ansible-create.yml`, open a PR for it | One file, on a branch, after you've seen it |
| `/ansible-create`, "ansible create", "wire this VM into Ansible" | **Build** — Phases 0–5 | A playbook, an inventory line, sometimes a role — on a branch, in a draft PR |

**Plain `/ansible-create` in a repo with no config routes into Setup first**, then continues
into the build once the config exists. Say that's what you're doing rather than silently
interviewing.

## Environment and tooling

Required: an Ansible repo checked out, `git`, and `gh` authenticated **with write access** —
Setup mode pushes a branch and opens a PR, and so does every build run. Discover the repo —
`git rev-parse --show-toplevel`, `gh repo view --json nameWithOwner,defaultBranchRef` —
never assume a name, and never assume the default branch is `main`.

The repo needs the shape this skill writes into: an `ansible.cfg`, an inventory file, and a
`roles/` directory, with `group_vars/` and a requirements file alongside. Init checks for
exactly that. `example/` in this skill's own folder is a working implementation of the shape
— point someone at it; never generate one on their behalf.

`ansible-core` and `ansible-lint` have to be reachable for Phase 4. They are often **not**
installed in a Claude Code session image, and `pip install` into system Python can break —
one image's preinstalled `cryptography` raises `pyo3_runtime.PanicException` on import. A
scratch venv is the fallback and it needs network to PyPI. Init settles which of the three
situations you're in — system, venv, or neither — and records it as `verify.ansible_from`,
so a build run knows at Phase 0 instead of finding out at Phase 4 with the files already
written.

Optional: the Terraform repo that provisioned the host, to confirm it exists and read its
IP rather than asking again.

## Setup mode — `/ansible-create init`

Takes a repo from "I think this is an Ansible repo" to a committed, validated config. Build
it *from what the repo actually has* rather than by interrogating the user about things you
can read.

**1. Ground it.** Confirm access first — init pushes a branch and opens a PR, so read-only
access is not enough. Work **from the repo root** throughout: `ansible.cfg`'s paths are
`$PWD`-relative, so every check below reads the wrong thing from a subdirectory.

```bash
git ls-remote origin >/dev/null && echo OK
gh auth status
git rev-parse --show-toplevel && git branch --show-current && git status --short
gh repo view --json nameWithOwner,defaultBranchRef      # defaultBranchRef, never assumed
```

If `ls-remote` fails, **stop and say so**. A 403 on clone/push while `gh api user` succeeds
means the GitHub App isn't installed on the repo. Do not write a config on guessed
conventions.

**If `git status --short` shows anything, stop there too.** The tree has to be checked here,
before step 7 writes the config — after that `git status` can no longer separate your change
from somebody else's uncommitted work, and the alternative is sweeping it into the config
commit.

**2. Check for an existing config** at `.claude/ansible-create.yml` (accept `.yaml` too). If
one exists, show it in full and ask whether to update it or keep it — **never overwrite a
config the user hasn't seen**.

**3a. Check the prerequisite that actually blocks people: is this the right shape at all?**
This skill writes playbooks, inventory lines and roles into an existing repo. It does not
create one.

```bash
ls -1 ansible.cfg 2>/dev/null
ls -d roles group_vars host_vars 2>/dev/null
ls -1 *.yml 2>/dev/null | head
ls -1 requirements.yml requirements.yaml 2>/dev/null

# the inventory, which is load-bearing and easy to forget to look for: take the path
# ansible.cfg declares, and fall back to the conventional locations only if it declares none
sed -n 's/^ *inventory *= *//p' ansible.cfg 2>/dev/null
ls -1d inventory inventory.yml inventory.ini hosts 2>/dev/null
```

Three things are load-bearing and their absence is a stop: an **`ansible.cfg`**, an
**inventory file that exists** — check for it *here*, not at step 8, or the run interviews
the user before discovering there's nowhere to put a host — and a **`roles/` directory**. `group_vars/` and a
requirements file are wanted but survivable — record their absence rather than inventing
them, and say what it costs (nowhere to put a group-scoped var; no pinning story).

**If the shape isn't there, stop here.** Say exactly which of the three is missing, and
point at **`example/` in this skill's own folder** — a working minimal repo with all of it:
`ansible.cfg`, an INI inventory, `group_vars/`, one worked role, a root playbook, a fleet
`common.yml`, and a pinned `requirements.yml`. **Do not scaffold an Ansible repo.** Building
one is a decision about someone's fleet, not a side effect of running init. If the user
explicitly asks for it, copying `example/` is the answer — and say that it's a copy to edit,
not a generated repo.

**3b. Check the other prerequisite: can anything verify the result?**

```bash
ansible-playbook --version
ansible-lint --version
```

Both on PATH → record `verify.ansible_from: system`. Neither → build the scratch venv
**now**, in init, and record `venv` if it works; discovering at Phase 4 that it can't be
built means finding out after everything is already written.

If neither system tooling nor a venv is reachable, don't fail silently and don't pretend:
say plainly that every build run will report `not run` for both checks, **ask whether to
continue on that basis**, and record `verify.ansible_from: unavailable` so Phase 0 states it
up front instead of Phase 4 discovering it.

**4. Derive the paths from `ansible.cfg`, not from this file.**

```bash
cat ansible.cfg
```

`inventory`, `roles_path` and `collections_path` are the authoritative answers. If
`inventory` names a **directory**, list what's in it and ask which file host lines belong
in. If `ansible.cfg` sets no `inventory` at all, ask — do not default to a path you've seen
in an example.

**5. Derive the conventions from what the repo already does.** Every one of these is
readable; none of them is a question:

- **Host line shape** — read the last few host lines out of the inventory. `<host> ipv4=<ip>`,
  `<host> ansible_host=<ip>`, or a bare name. Copy what's there; don't add `ansible_host` to
  a repo that doesn't use it.
- **Group and role naming** — read the actual `[group]` headers and `ls roles/`. Snake_case
  groups and kebab-case role dirs are common but not universal.
- **Role var prefix** — grep one role's `defaults/main.yml` and see what its keys start with.
- **Named plays or not** — grep the root playbooks for `- hosts:` and check whether a `name:`
  sits alongside. That single fact decides whether `name[play]` is a house-style warning to
  leave in place or a real finding to fix.
- **The role to model on** — the newest role using fully qualified collection names,
  `defaults/main.yml` for every tunable, and handlers. Legacy roles are spotted by style —
  bare module names, `- include:`, `key=value` args — not by name. Say which one you picked
  and why.
- **Does CI lint?** — `ls .github/workflows/` and grep for `ansible-lint`. That answers
  `verify.lint_enforced_by_ci` from evidence rather than assumption.

**6. Ask only what genuinely can't be read**, offering the derived answer for each so the
user is correcting rather than composing:

- which inventory file new host lines go in, if the repo has more than one
- where host-specific vars belong: the role's `defaults/`, `group_vars/`, or `host_vars/`
- whether lint findings are advisory house style or enforced, and which rules are permanently
  allowed — offer what you found in step 5
- the fleet-wide playbook, if there is one, and confirm that wiring into it stays a separate,
  explicit decision per run
- the branch prefix

**7. Write `.claude/ansible-create.yml`**, show it back in full, and ask for confirmation.
The whole file:

```yaml
version: 1

repo:
  default_branch: main            # discovered, never assumed — branches are cut from this
  branch_prefix: add-             # a build run's branch is <prefix><name>

paths:
  ansible_cfg: ansible.cfg
  inventory: inventory/home/host  # the file host lines are written to
  roles_dir: roles
  group_vars_dir: group_vars
  host_vars_dir: host_vars        # omit if the repo has none
  requirements: requirements.yml  # omit if the repo has none
  fleet_playbook: common.yml      # omit if there is none
  playbook_dir: .                 # where root playbooks live

conventions:
  host_line: "{hostname} ipv4={ip}"
  group_case: snake_case
  role_dir_case: kebab-case
  role_var_prefix: role_subject   # role vars start with the role's subject
  vars_location: role_defaults    # role_defaults | group_vars | host_vars
  plays_named: false              # false = unnamed plays are house style
  model_on: roles/chrony          # the role a new one is modeled on

verify:
  ansible_from: venv              # system | venv | unavailable
  syntax_check: "ansible-playbook --syntax-check {playbook}"
  lint: "ansible-lint --offline"
  lint_dir: temp                  # repo | temp — where lint is run from
  lint_enforced_by_ci: false
  allowed_lint_rules: ["name[play]"]   # left in place, with the reason, every run
```

`version`, `repo`, `paths`, `conventions` and `verify` are all required. Inside them, four
keys are optional and mean "the repo doesn't have this": `paths.host_vars_dir`,
`paths.requirements`, `paths.fleet_playbook`, and `conventions.model_on` — omit that last one
when `roles/` is empty, and Phase 2 Step 3 falls through to the "nothing close enough to model
on" stop rather than inventing a model.

**8. Validate what you just recorded, before committing any of it.** A config naming an
inventory that doesn't exist is worse than no config — it turns a stop into a host line
written to a file nothing reads.

```bash
ansible-playbook --version                       # or the venv's
ansible-lint --version
test -f <paths.inventory> && test -d <paths.roles_dir> && echo OK
ansible-inventory --list -i <paths.inventory> >/dev/null && echo PARSES
git rev-parse --verify origin/<repo.default_branch>
```

When `verify.ansible_from` is `unavailable`, the first two and the parse check **cannot** run
— that was already established and agreed in step 3b, so record them as `not run` and move
on. They are not a validation failure and must not become a loop. The `test` lines and
`git rev-parse` still apply, and they are the ones that matter most.

`ansible-inventory --list` **parses** an inventory. It opens no SSH connection and contacts
no managed host, which is why it's the one Ansible command init may run and why it doesn't
touch hard rule 5. **The exception:** a *dynamic* inventory — an executable script, or a
plugin config that calls out to a cloud API — is code, and `--list` runs it. Don't. Confirm
the path exists, record it, and say the parse check was skipped and why.

If any check fails, fix the config and re-validate. Never commit a config whose first real
run would hard-stop.

**9. Commit it on a branch and open a PR.** This is the only write Setup mode makes, and it
stays narrow:

```bash
git fetch origin <repo.default_branch>
git checkout -b chore/ansible-create-config origin/<repo.default_branch>   # off the default,
                                                                           # not whatever is
                                                                           # checked out
git add .claude/ansible-create.yml    # explicit path, never -A
git commit -m "Add ansible-create config for the /ansible-create skill"
git push -u origin chore/ansible-create-config
gh pr create --fill --base <repo.default_branch>   # never omit --base: without it the PR
                                                  # targets GitHub's default branch, which
                                                  # on a develop-based repo is the wrong one
```

Never commit anything else in that commit, and never push to the default branch. **If the
tree was dirty before you started, stop and say so** rather than sweeping someone's work
into it.

**10. Ask whether to merge it.** Merge only on an explicit yes. If they'd rather review it
themselves, leave the PR open and say this precisely: the config has already been read, so
continuing into a build right now works — but a build run cuts its branch from
`origin/<repo.default_branch>`, so the *next* run won't see the config until this PR lands.

**11. Say which branch they're on now**, and switch back to where they started unless
they're continuing straight into a build from here.

**12. Offer to continue into a build run.** Phase 1's new-or-existing fork still stands
between that point and anything written, so continuing is safe — but say so rather than
assuming.

## Phase 0 — Access, load config, orient

**1. Access.**

```bash
git ls-remote origin >/dev/null && echo OK
git rev-parse --show-toplevel && git branch --show-current && git status --short
```

If `ls-remote` fails, **stop and say so**. A 403 on clone/push while `gh api user` succeeds
means the GitHub App isn't installed on the repo. Do not produce a deliverable on guessed
conventions — ask whether to proceed blind, and label everything if told to.

**2. Config.** Read `.claude/ansible-create.yml` (accept `.yaml` too). Three outcomes — say
which one you're in before doing anything else, and never silently degrade:

- **Found** — parse it, then echo the resolved values back in one short block: inventory
  file, roles dir, group_vars dir, default branch, the two verification commands and where
  `ansible` comes from, and the naming conventions. The user should be able to catch a wrong
  path here, before anything is written into it.
- **Absent** — route into Setup mode above, then continue **only if Setup finished**. If
  Setup stopped — no `ansible.cfg`, no inventory, no `roles/` — the build stops with it.
  There is nothing to write into, and no config to write with.
- **Present but unparseable, or missing a required key** — stop. Name the offending key. Do
  not fall back to a default for a path: a guessed inventory path is exactly how a host line
  lands in a file nothing reads.

**3. Read the repo, don't assume.** Using the recorded paths, never a remembered one:

```bash
cat <paths.ansible_cfg> <paths.inventory>
cat <paths.requirements> <paths.roles_dir>/README.md   # each only if the repo has one
git ls-tree -r --name-only origin/<repo.default_branch> | head -50
```

The repo is the only source of truth for layout, house style and naming. Derive them by
reading the roles directory's own README if it has one, and the role named in
`conventions.model_on` — not from memory, and not from anything asserted here. **If a recorded path no longer
exists, stop and name the stale key** (hard rule 2); where the config and the repo merely
differ in style, the repo wins and the drift is worth a line in the report.

**4. State** the branch, working-tree status, whether verification will be available
(`verify.ansible_from`), and which existing role or playbook you're taking conventions from
— all before the first question. If the tree is already dirty, say what's uncommitted and
ask.

## Phase 1 — New role, or an existing one?

**This is the first question, and it decides everything after it.** Applying a role the
repo already has is an inventory line and possibly a group membership — minutes, not a
build. Writing a new role is the long path. Do not start interviewing content until this
is settled.

Look before asking, so the question comes with the real list:

```bash
ls <paths.roles_dir>/
grep -ril "<capability keywords>" <paths.roles_dir>/ <paths.playbook_dir>/*.yml
```

Then ask plainly: *is this an existing role applied to a new node, or something new?*
Offer the roles that plausibly match, with one line each on what they do, and let them
pick. Do not preselect.

Three answers:

- **Existing role** → Path A below. Short.
- **New** → Path B, the full interview in Phase 2.
- **Exists but isn't working** → neither. Stop and report what you found. The interesting
  question is "why isn't the existing thing working," not "how do I build this." The
  docker-prune session found a nightly prune already wired through the fleet playbook,
  failing only because `community.docker.docker_prune` with `images: true` removes
  *dangling* images only — it needs `images_filters: {dangling: false}`. Fixing an existing
  role is out of scope here (see Scope boundaries), so say what's wrong and let the human
  decide.

If it half-exists — the role covers most of it but not this node's variation — say which
half and ask before assuming a new role is the answer. A new tunable in the existing
role's `defaults/` is usually better than a near-duplicate role, and it is also an edit
to an existing role, so it is the human's call.

### Path A — existing role, new node

No content interview. Read the role, then ask only what the role itself demands:

1. Read `<paths.roles_dir>/<role>/defaults/main.yml` and `meta/main.yml`. Every default with
   no safe value for this host is a question; everything else is left alone.
2. Find how the role is already applied — an existing root playbook targeting a group, an
   `import_role` in the fleet playbook, or nothing. Adding the host to a group that an
   existing playbook already targets is usually the whole job.
3. Confirm the role's dependencies are satisfied for this host, and that anything it uses
   is pinned in `<paths.requirements>`.
4. Run the Phase 2 Step 4 wiring table (group, host line, vars location, SSH user check).

Then skip to Phase 3. What gets written is typically one inventory line, sometimes a
`group_vars` or `host_vars` entry for a required variable, and only occasionally a thin
new playbook — if an existing one already targets the group, adding another is noise.

Say in the report that Path A was taken and name the role. A one-line diff is the correct
outcome here, not a sign the skill did too little.

## Phase 2 — Interview (Path B only)

Skip Steps 1–3 entirely on Path A; Step 4 applies to both.

**Step 1 — scope.** Decide the shape before the content, and propose the smaller one:

| Shape | When |
|---|---|
| One root playbook, no role | A single operation across a group. This is the default. |
| Playbook + one role | Multi-step convergent config a second host would want. |
| Playbook + Galaxy role | Something validated exists. Most `roles/README.md` files say prefer this — check the repo's. |
| Two-play playbook | The node's address or identity changes mid-run — the first play does the change, the second re-targets the new address. This is the one shape that can strand a node; see "Stop and ask when". |

If the repo's roles directory carries a convention document, follow it. The bundled
`example/` states the common one: prefer public validated roles, don't build custom unless
required, and prefix project-specific custom roles with the project name. Search Galaxy
before proposing a hand-rolled role — in the gitea session the hand-rolled netplan logic
was exactly where the production bug lived.

**Step 2 — identity.** Ask together:

- `hostname` — as it will appear in `<paths.inventory>`. If the terraform repo is present,
  confirm it exists in its tfvars; if not, say so.
- `purpose` — one sentence in their words.
- `name` for the playbook (and role, if any) — propose one matching `conventions.group_case`
  and `conventions.role_dir_case`, and let them correct it. A name collision with an existing
  role is a hard stop.

**Step 3 — content.** Do not use a fixed question list. Start from `conventions.model_on` —
the closest existing role or playbook — and derive questions from what it parameterizes:
every key in its `defaults/main.yml` is a question this repo already decided was worth
asking. Say which one you are modeling on and why. Imitate the **newest** generation, never
the legacy roles — read one of each and the split is obvious: the newer ones use fully
qualified collection names, `defaults/main.yml` for every tunable, and handlers; the legacy
ones use bare module names, `- include:` and `key=value` args.

Ask only what the purpose makes relevant. On top of the model's own questions, these come
up on most nodes:

| | |
|---|---|
| Install source | Distro package, upstream apt repo, tarball/binary release, or container |
| Version pinning | Pinned or latest, and which variable holds it |
| Service | systemd unit from a template, or shipped by the package |
| Service account | Dedicated system user, or root |
| Config | Which files, which handler restarts on change |
| State/data paths | Directories to create, and who owns them |
| Secrets | Names only — values come from vault or from the human later |
| Scheduling | systemd timer or cron, and how often |
| Dependencies | Other roles first; `meta/main.yml` or the play's role list |
| Idempotency risk | Anything reporting changed every run — a bare `command`, a download |

**Step 4 — wiring.** Prefilled from the config, corrections in one reply:

| Field | Prefill | Notes |
|---|---|---|
| Inventory group | ask — offer the real list from `<paths.inventory>` | |
| New group? | no | A `[group:vars]` block for a group with **no members** breaks the entire inventory — every play silently sees zero hosts. Never add one speculatively. |
| Host line | `conventions.host_line`, filled in | The repo's own shape, recorded at init. Don't add `ansible_host` to a repo that doesn't use it. |
| Vars location | `conventions.vars_location` | Vaulted `group_vars/` decrypts whenever a group member is merely present in any play — including the fleet playbook. Scope secrets via `vars_files` in the one playbook instead. |
| `become` | `true` | Not `yes` — in-convention and lint-clean. |
| `gather_facts` | `false` | Unless facts are used; then `true` with an inline comment saying why. |
| Wire into `<paths.fleet_playbook>` | no | Only if it should run on the fleet schedule. That changes fleet-wide behaviour. |
| Branch | `<repo.branch_prefix><name>` off `origin/<repo.default_branch>` | |

## Phase 3 — Write

A playbook in `<paths.playbook_dir>`, matching `conventions.plays_named`, with dense `#`
comments explaining *why* and a `# Usage:` block with example invocations including a
`--limit` form. Take the full house style from the file you picked as the model in Step 3;
a single-purpose playbook well under 50 lines is a good length target.

Scope of one run:

- One playbook.
- One role under `<paths.roles_dir>`, only if Step 1 said so.
- One host line in `<paths.inventory>`, plus a `[group]` + `[group:vars]` block only
  when the group has members.
- A `<paths.requirements>` pin, only if a new dependency was agreed — and if that key is
  absent because the repo has no requirements file, adding one is a stop, not a side effect.

What makes the draft good rather than merely present:

- Every tunable in `defaults/main.yml`, prefixed per `conventions.role_var_prefix`, and
  commented. An undefined variable is a hard failure in ansible-core, not an empty string —
  so no bare `{{ maybe_defined }}`. (If the repo's `ansible.cfg` still sets
  `error_on_undefined_vars`, leave it alone but don't copy it into anything new: it's
  deprecated, removed in 2.23, and now only earns a deprecation warning on every run. The
  behaviour it described is the default.)
- No `command`/`shell` where a module exists. Where unavoidable it gets `creates:`,
  `removes:` or `changed_when:` — an unqualified `command` reports changed forever.
- Fail loudly on unset placeholders rather than guessing. The `CHANGEME` assert pattern
  works well.
- Handlers for restarts, lowercase imperative names.
- `no_log: true` on anything carrying a token.
- Re-read the hard rules and the role you modeled on against what you just wrote.
  The failure mode here is output that looks correct — an unqualified `command` that
  reports changed forever, a `{{ var }}` with no default, an empty `[group:vars]` — so
  check the written file, not your memory of writing it.

Sizing note: check whether `<paths.ansible_cfg>` sets `forks`; unset means the default of 5.
A group at or under that size already runs fully parallel, so don't add `-f` or `serial:`
reflexively. Adding `serial: 25%` to a five-host group once split it into four sequential
batches and made the play *slower*.

## Phase 4 — Verify

Run all of these, in this order. Nothing here connects to a managed host.

1. Get `ansible-core` and `ansible-lint`, per `verify.ansible_from`. `system` means they're
   already on PATH. `venv` means build a scratch venv — not system pip, which can break on a
   preinstalled `cryptography`. `unavailable` means **skip steps 2–4 and report every one of
   them as `not run`**, with the reason Phase 0 already stated; do not improvise a third way,
   and do not let an unverified draft be described as verified.
2. `verify.syntax_check` with the playbook substituted, **from the repo root** — `ansible.cfg`
   uses `$PWD`-relative paths, so from anywhere else the inventory resolves to nothing and
   every play sees zero hosts.
3. `verify.lint`, run from `verify.lint_dir`. `temp` means an isolated temp dir rather than
   the repo root, where lint can fail for environmental reasons — an unwritable `logs/`, or
   its shell-out to `ansible-galaxy role install` hitting an egress proxy.
4. Stub-test any Jinja reporting expression with `-i 'localhost,' -c local`.
5. `rm -rf .ansible` — lint leaves it in the repo root, it usually isn't gitignored, and it
   will otherwise end up in the commit.

Report both results verbatim, including the `verify.allowed_lint_rules` warnings
deliberately left in place. A finding on a rule *not* in that list is a real finding: fix it
or say why not.

## Phase 5 — Branch, commit, draft PR

```bash
git fetch origin <repo.default_branch>
git checkout -b <repo.branch_prefix><name> origin/<repo.default_branch>
git add <the files this run created or modified>   # explicit paths, never -A
git commit -m "<summary>"
git push -u origin <repo.branch_prefix><name>
gh pr create --draft --base <repo.default_branch> \
  --title "..." --body "<the report below>"     # always --draft, and never without --base
```

`git checkout -b` fails if the branch already exists — that is the intended behaviour.
**Never `-B`**, which would silently reset someone's earlier branch of the same name. A
collision is a stop: say so and ask for another name.

Stage files explicitly — never `git add -A`. When `verify.lint_enforced_by_ci` is false there
are no checks to wait on; say so rather than reporting a pending state that will never
resolve. When it's true, name the checks that started and leave the PR a draft anyway.

## Scope boundaries

**Always in bounds**

- Reading anything in either repo, and reading upstream source to verify a claim.
- **Applying an existing role to a new host** — an inventory line, a group membership, a
  `group_vars`/`host_vars` entry the role requires. This is not editing the role.
- One playbook, optionally one new role, one inventory line, per run.
- `--syntax-check`, `--list-tasks`, `ansible-lint`, `ansible-inventory --list` against a
  static inventory, localhost stub tests, read-only git.
- Adding a `[group]` + `[group:vars]` block **with members**.
- Writing `.claude/ansible-create.yml` in Setup mode, after showing it and getting
  confirmation — committing that one path on a branch, pushing, opening a PR, and merging
  that PR on an explicit yes.

**Never in bounds, even when it would be convenient**

- Running `ansible-playbook` against inventory in any form, `--check` and `--diff`
  included, or anything that opens SSH to a host.
- Running `ansible-inventory --list` against a **dynamic** inventory — that executes the
  inventory script or plugin. Static INI/YAML files only.
- Scaffolding an Ansible repo, in Setup mode or any other. A missing `ansible.cfg`,
  inventory or `roles/` is a stop that points at `example/`, not a build task.
- Editing an existing role's tasks, templates or defaults — as distinct from applying it,
  which is in bounds. If the new node needs a change to the role itself, including a new
  tunable, stop and say so: separate PR.
- Adding a near-duplicate role to avoid editing an existing one. Say that is the tradeoff
  and let the human choose.
- Wiring into `<paths.fleet_playbook>` without being asked. That is a fleet-wide change.
- Committing to the default branch, or force-pushing.
- Merging any PR without an explicit yes — and the only PR ever merged is Setup's config PR.
  A build run's draft PR is never merged and never marked ready, yes or no.
- `git add -A`, or committing `.ansible/`, log directories, or a password file.
- Editing the terraform repo, including its tfvars.
- Adding to `<paths.requirements>` unpinned, or without being asked.
- Imitating the repo's older-generation roles. Spot them by their style, not their names:
  bare module names instead of FQCN, `- include:` instead of `import_tasks`/`include_tasks`,
  and `key=value` args are all deprecated. Model on `conventions.model_on`.
- More than one node or capability per run.
- `ansible-galaxy init` boilerplate — empty `files/`, `vars/`, stub `meta/main.yml`.

## Stop and ask when

- `git ls-remote origin` fails, or `gh auth status` shows no authenticated account with
  write access (Setup; Phase 0).
- The repo has no `ansible.cfg`, no inventory file, or no `roles/` directory — it is not the
  shape this skill writes into. Name what's missing, point at `example/`, and **do not
  scaffold** (Setup).
- A config already exists and Setup was asked to write one (Setup).
- Neither system Ansible nor a buildable scratch venv is reachable, so `--syntax-check` and
  `ansible-lint` can never run — ask whether to continue knowing both will report `not run`
  (Setup, restated at Phase 0).
- The recorded inventory is dynamic, so the parse check can't be run safely (Setup).
- The config won't parse, is missing a required key, or names a path that no longer exists
  (Phase 0).
- The tree is dirty before a commit (Setup step 9; Phase 0).
- The capability already exists in the repo but isn't working.
- An existing role nearly covers it and would need a new tunable — that is a role edit.
- The hostname is already in the inventory, the role name already exists, or the branch
  `<repo.branch_prefix><name>` already exists.
- The chosen group's `ansible_ssh_user` does not match the account the host actually has.
  Read the group's `:vars` out of the inventory and compare it to the terraform `username`
  — never assume they agree. Terraform typically builds a key-only account with no root
  login, while existing groups often set `root` or a personal login, and a mismatch fails
  at connection before any task runs. Offer a per-host
  `ansible_ssh_user=<the terraform username>` on the inventory line, or a new group — do
  not pick, and do not edit an existing `:vars` block, which would change every other host
  in that group.
- A new collection or Galaxy role is needed.
- The work involves a reboot or an address change — that is the only step that can strand
  a node behind the console. A netplan or IP change needs the two-play shape from
  Phase 2 Step 1, and it needs the human to agree to it before it is written.
- A secret was pasted into the conversation.
- The repo has nothing close enough to model on.

## Reporting

Fixed format. Doubles as the PR body:

    ## ansible-create — <name> for <hostname/group>

    **Mode:** <build | setup>
    **Config:** `.claude/ansible-create.yml` <loaded | written this run, PR <link> |
    absent — ran init first>
    **Target:** <repo root> @ <branch> — remote access: <ok | failed — reason>
    **PR:** <url, draft | not opened — reason>
    **Path:** <A — applied existing role `<role>` | B — new automation>
    **Prior art search:** <searched roles/ + playbooks for X: nothing | found <path>>
    **Modeled on:** <existing file> — <why that one>   (Path B only)

    **Scope:** <inventory only | playbook only | playbook + role> — <one line on why the
    smaller shape was or wasn't enough>

    **Files created / modified:**
    - `<path>` — <what and why>

    **Verification run:**
    - ansible from: <system | scratch venv | unavailable — reason>
    - `<verify.syntax_check>`: <verbatim | not run — reason>
    - `<verify.lint>`: <verbatim | not run — reason>
    - lint warnings left in place: <rule — in verify.allowed_lint_rules | not run>
    - `.ansible` removed: <yes | n/a>

    **Checks:**
    - Config paths still exist: <all | stale: <key> — stopped>
    - Duplicate hostname / role name: <passed | failed>
    - Branch name free: <yes | collision — stopped>
    - Inventory group SSH user: <matches terraform `username` | mismatch — chose ...>
    - Empty `[group:vars]` introduced: <no>
    - Collections pinned: <all in requirements | needs ... — not added>

    **Next steps — run these yourself, from the repo root:**
    ```bash
    # fresh terraform guest: cloud-init holds the apt lock until it finishes
    ansible <hostname> -m shell -a 'cloud-init status --wait' --become
    ansible <hostname> -m ping

    ansible-playbook <playbook>.yml --check --diff --limit <hostname>
    ansible-playbook <playbook>.yml --limit <hostname>

    # not converged until a second run reports zero changed
    ansible-playbook <playbook>.yml --limit <hostname>
    ```

    **Risks / follow-up:** <secrets still unset, unpinned deps, tasks likely to report
    changed every run, existing repo issues noticed but not fixed>

Fill the commands in with the real names. Never put output from a command that did not
run into the Verification section. Report pending checks only when
`verify.lint_enforced_by_ci` says the repo has any.

In **Setup** mode the Path, Scope, Verification and Next-steps sections read `n/a — setup`.
Their place is taken by the config file shown in full, the result of every step-8 validation
command, and the config PR link.

## If something doesn't match reality

Say so and stop, with what you saw. Every repo fact in `.claude/ansible-create.yml` is a
snapshot of what init found on the day it ran, and every repo fact in *this* file is a
snapshot from two real sessions. Both can have drifted. The repo wins on every
disagreement, the stale config key goes in the report, and the fix is a corrected config —
not a run that works around it. Do not reconstruct the inventory, the house style, or an
upstream tool's behaviour from memory.
