---
name: terraform-create
description: >-
  Interviews you for a new Proxmox VM and emits a ready-to-paste `servers` entry for your
  Terraform tfvars plus the matching Ansible inventory host line, then checks both against
  the existing tfvars for a duplicate hostname, IP, MAC or VMID. Prefills — VLAN,
  addressing, sizing, nodes, tfvars and inventory paths — come from a
  `.claude/terraform-create.yml` that `/terraform-create init` derives from your real tfvars
  and commits; with no config, one homelab's values are used as labelled fallbacks. Output
  only: it prints the blocks and the commands to run, never edits your tfvars, inventory or
  any Terraform/Ansible file, and never runs terraform or ansible. Use on /terraform-create,
  "terraform create", or any ask to create/add/spin up/provision a node, VM or server on
  Proxmox, or for a tfvars entry for a new host — even without saying "Terraform". Not for
  reviewing a plan, changing an existing server, or the homelab/ Talos cluster. Needs the
  Terraform repo checked out; init needs git and gh, so Claude Code.
---

# terraform-create

Walks you through defining one new Ubuntu VM and hands back two blocks of text: an entry for
the `servers` variable in your Terraform tfvars, and a host line for the matching Ansible
inventory. You paste both and run terraform yourself.

Everything environment-specific — which tfvars, which variable holds the servers, the VLAN
and addressing, the sizing prefills, the Proxmox nodes, where the inventory lives — comes
from **`.claude/terraform-create.yml` in the Terraform repo**. `/terraform-create init`
interviews you for it, derives most of it from your real tfvars, and commits it. With no
config present the skill falls back to one homelab's values (VLAN 100, 2 cores, 4096 MB,
40 GB, `192.168.<vlan>.x`), and **says out loud that they are somebody else's defaults**.

Hard rules, restated up front because they're the ones that erode under "just paste it in"
pressure:

1. **Output only, with exactly one carve-out.** **In every mode, including `init`**, this
   skill never edits your `terraform.tfvars`, your Ansible inventory, or any
   `.tf`/playbook/role file, and never runs a terraform or ansible command — not `plan`, not
   `validate`, not `fmt`, and above all not `apply`. Reading files is fine; that is how the
   collision checks work. **The single carve-out: `/terraform-create init` writes and commits
   one file, `.claude/terraform-create.yml`, after showing it to you.** That file is this
   skill's own configuration — never your tfvars, never your inventory, never a `.tf` file —
   and init validates it by *reading*, running no terraform command to produce or check it.
2. **Never guess a required value.** `name`, `node_name` and `disk_datastore_id` have no
   safe default. Ask for each one and wait for an answer. **The Ansible SSH user is asked
   every run too** — offer whatever the config or the real inventory suggests, but never
   take it silently. It decides whether the first play connects at all, and a stale
   inventory, a new group or a rebuilt image makes any inferred answer wrong. Everything
   else is prefilled and confirmable in one pass.
3. **Never print a secret.** `terraform.tfvars` holds `pm_api_token`, and may hold SSH keys.
   Read the file for the checks, quote nothing from the API/SSH sections, and if a credential
   shows up somewhere it should not be, say so in the report as a finding rather than
   reproducing it. The config file init writes holds paths, names and numbers — **never a
   token, key or password**.
4. **Never claim a check ran when it did not.** "Collision check: not run — no tfvars at
   `<path>`" is a correct answer. A fabricated "no conflicts found" is the one failure mode
   that makes this skill worse than doing it by hand.
5. **The config is the contract; the tfvars is the truth.** The config says what to
   *propose*; the file says what *exists* — its entries, its `default_*`, its gateway. A
   prefill that differs from a module default is not a conflict, it's the normal case, and
   Phase 2 writes it out explicitly. But when the config names something the file doesn't
   have — a renamed servers variable, a node that's gone, a tfvars that isn't there — **the
   file wins: name the stale key and stop**, rather than emitting an entry that matches the
   config instead of reality.

## The two modes

Pick the mode before doing anything else, and say which one you're in.

| Invocation | Mode | Writes anything? |
|---|---|---|
| `/terraform-create init`, "set up terraform-create", "configure terraform-create" | **Setup** — interview, write `.claude/terraform-create.yml`, open a PR for it | One file, on a branch, after confirmation |
| `/terraform-create`, "terraform create", "add a VM" | **Emit** — Phases 0–2, then the report | **Nothing.** No file, no terraform, no ansible |

There is no dry-run mode, because an ordinary run already changes nothing.

**Plain `/terraform-create` with no config does not route into Setup.** It runs on the
fallback values, labels every prefill as a fallback in the report, and offers `init` at the
end. Setup commits a file; a request for a tfvars entry is not consent to commit one.

## Environment and tooling

- **Emit mode** needs the Terraform repo checked out, with the tfvars present, for the
  collision checks. Nothing is executed, so no terraform, ansible or Proxmox CLI is
  required. If the repo or the tfvars is missing, don't stop — run the reduced path (Phase
  0) and label the report.
- **Setup mode additionally needs `git` and `gh`** (or a connected GitHub MCP server) with
  write access, because it commits the config and opens a PR. Check what this session
  actually has rather than assuming.
- The tfvars is normally **gitignored**, so a fresh clone will not have it. That is normal
  and it is handled — but it is also the thing that silently disables every collision check,
  so it is always named in the report.
- Optional: the Ansible repo, for reading the real group list and cross-checking the SSH
  user you were given against each group's `ansible_ssh_user`. Nothing here ships group
  names or SSH users to fall back on.

`gh` appears below as the concrete form. Use the MCP equivalent if that's what's connected.

## Setup mode — `/terraform-create init`

Takes a first-time user from "this skill knows one stranger's homelab" to "this skill knows
mine". Build it **from what the repo actually has**; ask only what genuinely can't be read.

**1. Ground it.** Confirm `git` and `gh` with write access, then discover the repo, the
current branch, and the default branch:

```bash
git rev-parse --show-toplevel && git branch --show-current
gh repo view --json nameWithOwner,defaultBranchRef
```

If there's no repo — claude.ai chat, or the wrong directory — **stop**. There is nothing to
configure and nowhere to commit. Say so and point at Emit mode, which still works on the
fallbacks.

Then check the tree is clean, **here and not later**:

```bash
git status --porcelain      # anything at all → stop and say so
```

It has to be checked before step 7 writes the config, because after that `git status` can no
longer tell your change from somebody else's uncommitted work. A dirty tree is a stop, not a
warning — the alternative is sweeping someone's work into the config commit.

**2. Check for an existing config** at `.claude/terraform-create.yml` (accept `.yaml`). If
one exists, show it in full and ask whether to update it or keep it — **never overwrite a
config the user hasn't seen**.

**3. Check the prerequisite that actually blocks people: is there a tfvars to read?**

```bash
find . -name 'terraform.tfvars' -not -path './.terraform/*' 2>/dev/null
find . \( -name 'terraform.tfvars.example' -o -name '*.auto.tfvars' \) 2>/dev/null
```

Three outcomes, and you must say which:

- **A tfvars was found.** Good — derive from it in step 4.
- **Only a `.example` was found** (the live file is gitignored, the usual case on a fresh
  clone). Derive the *shape and defaults* from the example, and record the path the live
  file will have. Then say plainly: **until that file exists, every duplicate check —
  hostname, IP, MAC, VMID — is "not run", and the only thing standing between two VMs on the
  same address is you.** That is this skill's whole safety value, so it is worth a sentence,
  not a footnote.
- **Neither was found.** Do not invent a path. Ask where the tfvars is or will be, record
  exactly that, and repeat the warning above. Do not write a Terraform module to make one —
  that's `/code-development`'s job, and `example/` in this skill is a working module to copy
  if they want a starting point.

**4. Derive everything you can from the tfvars** (or the example). Read it and pull out:

- the **variable holding the servers** and its shape — `servers = [ ... ]` (a list of
  objects) or `servers = { ... }` (a map keyed by name). Don't assume the name is `servers`;
  read it.
- every existing entry's `name`, `ip`, `net_mac`, `vm_id`, `node_name`, `disk_datastore_id`
  — the raw material for the collision checks, and the source of the node and datastore
  lists to offer as hints.
- the module-level defaults actually set in *this* file: `net_vlan`, `network_gateway`,
  `network_cidr`, `net_bridge`, `search_domain`, `default_cores`, `default_sockets`,
  `default_memory_mb`, `default_disk_size_gb`, `username`, `ansible_group`.
- the **addressing already in use.** Compare the existing `ip` values against `net_vlan`. If
  the third octet equals the VLAN across the board, the convention is `192.168.{vlan}.{octet}`
  — offer that. If they're all in one fixed /24 regardless of VLAN, offer that literal prefix
  instead. If there's no pattern, offer no scheme and say the run will ask for a full IP.
  **Infer the convention; never impose the author's.**
- the **next free VMID**, if any entry pins one: the lowest unused value above the highest
  pinned. Offer it as a hint in the run, not as a stored value — it goes stale the moment
  someone adds a VM.
- the **image or template** the module builds from (`cloud_image_url`, `template_id`, or
  whatever this module calls it), so the run can say what the VM will be built from.
- `terraform.dir` — the directory holding that tfvars, which is where the next-steps block
  tells the user to `cd`. Take it from the path you found; only ask if terraform is actually
  run somewhere else.

**5. Find the Ansible inventory.** Look for a sibling checkout or a path under this repo:

```bash
ls ../ansible/inventory 2>/dev/null; find . -path '*inventory*' -name 'host*' 2>/dev/null
```

If one is found, read its groups and each group's `ansible_ssh_user` — the groups become the
list a run offers, and the users are what Phase 2 cross-checks the answered SSH user against. If none is found, ask for the path, or record none: with no
inventory configured the run emits no host line and says so.

**6. Ask only what genuinely can't be read**, offering the derived answer for each so the
user is correcting rather than composing:

- the **default VLAN** for new VMs — offer the file's `net_vlan`
- the **addressing scheme** — offer what step 4 inferred
- **cores, memory, disk** prefills for a new VM — offer the file's `default_*`, and note
  that a prefill above the default is fine and simply gets written out explicitly
- the **Proxmox node(s)** to offer as choices — offer the node names already in the file
- the **datastores** to offer — same
- the **inventory group** a new host usually joins, and the **SSH user terraform actually
  creates** (`username`, default `ansible`)

**7. Write `.claude/terraform-create.yml`**, show it back in full, and ask for confirmation.
The full schema:

```yaml
version: 1

terraform:
  dir: ubuntu-servers                       # where you run terraform, relative to repo root
  tfvars: ubuntu-servers/terraform.tfvars   # the file read for the collision checks
  servers_variable: servers                 # the variable holding the entries
  servers_shape: list                       # list | map — how entries are keyed

defaults:                                   # interview prefills for a NEW vm
  vlan: 100
  cores: 2
  memory_mb: 4096
  disk_size_gb: 40
  on_boot: true

addressing:
  scheme: "192.168.{vlan}.{octet}"          # or a literal prefix, or omit to always ask
  cidr: 24
  gateway: "192.168.100.1"                   # omit → read network_gateway from the tfvars

proxmox:
  nodes: ["pve01"]                          # offered as choices, never preselected
  datastores: ["local-lvm"]
  template: "noble-server-cloudimg-amd64"   # what the module builds from, for the report

ansible:                                    # omit → no inventory line is emitted
  inventory: ../ansible/inventory/home/host
  format: ini                               # ini | yaml
  default_group: ubuntu_servers
  ssh_user: ansible                         # prefill only — still asked every run
```

Only `version` and `terraform` are required. `defaults`, `addressing`, `proxmox` and
`ansible` are each independently optional; omitting one falls back to this skill's bundled
values for that block alone, and the run labels it as a fallback.

**The bundled fallbacks are the ones named at the top of this file — VLAN 100, 2 cores,
4096 MB, 40 GB, `192.168.<vlan>.x`.** They are one homelab's *prefills*, and they are not the
same numbers as the `default_*` in `references/tfvars-schema.md`, which record what that
homelab's Terraform module falls back to when an entry omits a field. Two different things
that both get called "defaults": one is what to propose in the interview, the other is what
the module does with an omitted field. Never read a module `default_*` as a prefill.

**8. Validate what you recorded, before committing anything.** A config pointing at a tfvars
that isn't there silently disables every collision check, which is the whole reason this
skill is worth running. **Validate by reading — never by running `terraform validate`,
`fmt`, `init` or any other terraform command.** Check:

- `terraform.tfvars` resolves to a real file — or, in the gitignored case from step 3, its
  `.example` sibling does and the user has confirmed the live path.
- Whichever file you have parses far enough to locate `terraform.servers_variable` and
  enumerate its entries. If you can find neither the variable nor a reason it's absent,
  **stop and fix the config** — do not record a name you couldn't verify.
- `terraform.servers_shape` matches what you actually saw.

  In step 3's third outcome there is no file at all to read yet. Don't loop on it: report
  these two as **"not run — no file to read yet"**, write down the name and shape the user
  gave you, and say in the report that both are **unverified until the tfvars exists**.
- Every name in `proxmox.nodes` appears somewhere in the tfvars. A node that appears nowhere
  is a warning, not a stop — it may be genuinely new — but say so.
- `ansible.inventory` resolves to a real file. A warning if not; the host line is still
  emitted, marked as unverified against a real group list.

Report each check as passed, warned, or stopped, and fix the config before moving on.

**9. Commit it on a branch and open a PR.** This is the one write this skill makes, and it
stays narrow:

```bash
# The tree was checked at step 1. Only .claude/terraform-create.yml should be new here;
# anything else appeared while you worked and is not yours to commit, so stop.
git status --porcelain
git fetch origin <default branch>
git checkout -b chore/terraform-create-config origin/<default branch>   # off the default,
                                                                        # not whatever's
                                                                        # checked out
git add .claude/terraform-create.yml        # explicit path, never -A
git commit -m "Add terraform-create config for the /terraform-create skill"
git push -u origin chore/terraform-create-config
gh pr create --fill --base <default branch>   # never omit --base
```

Never commit anything else in that commit, and never push to the default branch.

If `.claude/` is gitignored in this repo, `git add` refuses the file. **Do not reach for
`-f`.** Say what happened and ask whether to un-ignore `.claude/terraform-create.yml` — the
config is meant to be shared with whoever else uses this skill on this repo, so it belongs in
git, but that is the user's call to make, not yours.

**10. Ask whether to merge it.** Merge only on an explicit yes. If they'd rather review it
themselves, leave the PR open and say the config takes effect for `/terraform-create` once
it's on the branch they work from.

**11. Say which branch they're on now**, and switch back to where they started unless
they're continuing straight into a run from this branch.

**12. Offer to continue into a run.** Emit mode writes nothing, so continuing is safe — but
say so rather than assuming.

## Phase 0 — Orient, load config, read the tfvars

Four steps, in order. Verify with real commands; assume nothing.

**1. Tooling.** Note whether this is Claude Code with a repo, or chat. Emit mode needs
neither `git` nor `gh` — only the ability to read files.

**2. Repo.**

```bash
git rev-parse --show-toplevel 2>/dev/null; git branch --show-current 2>/dev/null
```

**3. Config.** Read `.claude/terraform-create.yml` (accept `.yaml`). Three outcomes — say
which one you're in before the first question, and never silently degrade:

- **Found** — parse it and echo the resolved values back in one short block: tfvars path,
  servers variable, VLAN, addressing, sizing prefills, nodes, inventory path. The user should
  be able to catch a wrong value here, before any of it matters.
- **Absent** — say so, say the prefills below are **one homelab's values and not yours**, and
  carry on. Offer `/terraform-create init` in the report. Do not route into Setup: it commits
  a file, and this run wasn't asked to.
- **Present but unparseable, or missing the required `terraform` block or its `tfvars` key**
  — stop. Name the offending key and point at the schema in Setup mode above. Do not
  improvise a config to keep the run going.

**4. Read the tfvars** at `terraform.tfvars` from the config, or by search if there's no
config:

```bash
ls <configured path> 2>/dev/null || find . -name terraform.tfvars -not -path './.terraform/*' 2>/dev/null
```

Three run modes. Say which:

| Mode | Condition | What it means |
|---|---|---|
| **Full** | The tfvars was found and the servers variable parsed out of it | Every check runs |
| **Partial** | Repo found, no live tfvars — defaults read from `terraform.tfvars.example` | Defaults are real, **collision checks do not run** |
| **Reduced** | No repo, or no tfvars and no example | Interview and emit from fallbacks; **nothing is checked against reality** |

In Full mode, extract the existing entries (`name`, `ip`, `net_mac`, `vm_id`, `node_name`,
`disk_datastore_id`) and the module-level defaults actually set in *this* file: `net_vlan`,
`network_gateway`, `network_cidr`, `default_cores`, `default_memory_mb`,
`default_disk_size_gb`, `net_bridge`, `search_domain`, `username`.

**Precedence, when two sources disagree — and it splits in two, which is the part that gets
misread.** The config records what to *propose*; the file records what is *true*.

- **For a prefill** (what the sheet suggests): the user's answer beats the config, which
  beats this skill's bundled fallbacks. The tfvars does **not** override a configured prefill
  — `defaults.vlan: 60` still prefills 60 on a file whose `net_vlan` is 20. Overriding it
  would make the `defaults` block that `init` exists to write do nothing.
- **For a fact** (what already exists, what the module actually defaults to, what names and
  addresses are taken): the tfvars wins over everything, always. It is the only source that
  can say what is true right now.

A prefill that differs from the file's `default_*` is not a conflict — it's the normal case,
and Phase 2 writes it out explicitly. A config that names something the file doesn't have *is* a conflict; see "If
something doesn't match reality".

If the file is there but the configured `servers_variable` isn't in it, that's a **stop**:
say which name you looked for and which variables you did find. Emitting an entry for a
variable that doesn't exist is worse than emitting nothing.

With no config there is no recorded name, so look for `servers` — the fallback — and if the
file uses something else, **use what the file has and say so**, rather than reporting a
missing variable. Offer `init` so the name gets recorded instead of re-discovered every run.

## Phase 1 — Interview

Two steps, in this order.

**Step 1 — the three that cannot be prefilled.** Ask for them together, in one message:

- `hostname` — becomes both `name` and the guest hostname. Must be a lowercase DNS label:
  `[a-z0-9-]`, no underscores, no dots, no leading or trailing hyphen. If the answer breaks
  that, say why and ask again; do not silently normalise it.
- `node_name` — the Proxmox node. Offer `proxmox.nodes` from the config and the node names
  already in the tfvars as hints, but **do not preselect one**.
- `disk_datastore_id` — must be images-capable. Same: offer `proxmox.datastores` and what
  other entries use, pick nothing.

**Step 2 — the prefilled sheet.** Show every remaining field with its default filled in, as
a table, and ask for changes in one reply ("send just the lines you want different, or `ok`
to take it as-is"). Do not ask these one at a time.

| Field | Prefill | Fallback with no config / notes |
|---|---|---|
| `net_vlan` | `defaults.vlan`. If the file's `net_vlan` differs, say so — the entry carries it explicitly | `100` |
| `ip` | `addressing.scheme` with the VLAN filled in — **ask for the last octet** | `192.168.<vlan>.` |
| `cores` | `defaults.cores` | `2` |
| `memory_mb` | `defaults.memory_mb` | `4096` |
| `disk_size_gb` | `defaults.disk_size_gb` | `40` |
| `net_mac` | blank = Proxmox assigns one | Pinning it keeps a DHCP reservation valid across a rebuild |
| `vm_id` | blank = Proxmox assigns one | Offer the next free VMID as a hint if other entries pin theirs |
| `groups` (terraform) | blank | Ansible groups written into the *generated* inventory |
| Inventory group | `ansible.default_group`, offering the real group list | ask |
| Inventory SSH user | **Always ask.** Offer `ansible.ssh_user`, or the chosen group's `ansible_ssh_user` when the inventory was read — never take either silently | ask; terraform's `username` is usually `ansible` |
| `tags` | blank | Merged with `default_tags` |
| `on_boot` | `defaults.on_boot` | `true` |

A blank `ip` means DHCP, and the entry omits `ip` entirely.

**Every prefill states where it came from** — "your config", "your tfvars", or "a fallback,
not yours". A run with no config says so on the sheet, not only in the report.

**The addressing scheme is a template, not arithmetic.** `192.168.{vlan}.{octet}` with VLAN
60 gives `192.168.60.<octet>` — and that move usually needs an explicit `gateway` too; see
the gateway checkpoint in Phase 2. If `{vlan}` sits in an octet position and the VLAN is
above 255, the scheme cannot produce a valid address: **say so and ask for the full IP**
rather than emitting something that isn't an address.

For the inventory group list, read the configured `ansible.inventory` if it's present. If
it is not, **ask for the group**. This skill ships no group names of its own; inventing
plausible ones is how a host lands in a group that does not exist.

## Phase 2 — Check before emitting

Read `references/tfvars-schema.md` if you need the full attribute table. Run every check
below that the available files allow, and report each one as passed, failed, or not run.

**Against the existing entries:**

- Duplicate `name` — a repeat means terraform would key two entries the same. Hard stop.
- Duplicate `ip` — hard stop.
- Duplicate `net_mac` or `vm_id`, when either was pinned — hard stop.
- `node_name` / `disk_datastore_id` that appear nowhere else in the file — not an error, but
  flag it: a typo'd datastore fails at apply, long after this skill is done.

In Partial or Reduced mode, all four report **"not run — <reason>"**. Never soften that into
"no conflicts found".

**Addressing:**

- If `ip` is set and its /24 does not match the file's `network_gateway` (or
  `addressing.gateway` when the file has none), the entry needs an explicit `gateway` — and
  `cidr` if it isn't 24. Emit them in the entry and say why. This is the usual consequence of
  moving a VM off the default VLAN.
- If `ip` is set, a gateway must resolve to something. If the file's is null, the config has
  none, and the entry has no `gateway`, that is a stop-and-ask.

**Sizing against the file's own defaults:**

- Emit `cores`, `memory_mb` and `disk_size_gb` explicitly **whenever they differ from the
  file's `default_*` values**, and only then. Compare against what you actually read; don't
  assume a prefill differs. A config whose prefills match the module defaults produces a
  shorter entry, and that's correct.
- In Partial mode you are comparing against the **example's** defaults, not the live file's.
  Say that in the report; the live file may set different ones.
- In Reduced mode there is no file to compare against at all, so emit all three explicitly
  and say that's why.

**Ansible reachability — the one that bites:**

The terraform config creates a key-only account named by `username` (commonly `ansible`) and
disables password and root login. A static inventory usually sets its own `ansible_ssh_user`
per group. Dropping a new terraform-built VM into a group whose `ansible_ssh_user` names an
account the guest doesn't have gives every play a connection failure before any task runs.

The SSH user used here is **the answer given in Phase 1** — never a value inferred from a
group name, and never one this skill ships. The real inventory's `:vars` is only a
cross-check: if the chosen group sets an `ansible_ssh_user` different from that answer, say
so plainly and offer the two honest options — a per-host `ansible_ssh_user=<username>` on
the inventory line, or a new group with its own `:vars`. **Do not pick one silently.** If
the inventory could not be read, report this check as not run rather than assuming the two
agree.

If the config has no `ansible` block and no inventory was found, emit no host line and say
so — an invented path is worse than none.

## Scope boundaries

**Always in bounds**

- Reading the repos to prefill defaults and check for collisions.
- One new server entry per run.
- Emitting the exact commands for the human to run next.
- Writing `.claude/terraform-create.yml` in Setup mode, after showing it and getting
  confirmation — committing that one path on a branch, pushing, opening a PR, and merging
  that PR on an explicit yes.

**Never in bounds, even when it would be convenient**

- Editing `terraform.tfvars`, the Ansible inventory, or any `.tf` file — **in any mode, init
  included**. The only file this skill writes anywhere is its own config.
- Committing anything other than `.claude/terraform-create.yml`. `git add -A` is never
  correct here; stage the one path by name. Never push to the default branch, never
  force-push, never merge the config PR without an explicit yes.
- Running `terraform apply`, `plan`, `validate`, `fmt`, `init`, `import`, or anything
  touching state — including "just a plan to check", and including inside `/terraform-create
  init`. A plan takes a state lock and talks to the Proxmox API; that is the human's call,
  not this skill's.
- Running `ansible-playbook` in any form, `--check` included.
- Modifying an existing server entry, or a `default_*` at the top of the file. If the new
  node genuinely needs a different module default, say so and let the human decide.
- Touching `homelab/` — a separate config, separate state, Talos not Ubuntu.
- Inventing a `node_name`, `disk_datastore_id`, MAC, VMID, tfvars path or inventory path
  that was not supplied or read.
- Writing a Terraform module, a variables file, or CI to make the prerequisites exist.
- Putting a token, key or password in the config file.
- Reflowing, reformatting or "tidying" the rest of the tfvars in the emitted block. Emit only
  the new entry.

## Stop and ask when

- Any duplicate check fails (name, IP, MAC, VMID) — Phase 2.
- `ip` is set but no gateway is derivable — Phase 2.
- The addressing scheme can't produce a valid address for the chosen VLAN — Phase 1.
- The requested hostname is not a valid DNS label after one correction round — Phase 1.
- The chosen group's SSH user does not match the terraform `username` — Phase 2.
- The config won't parse, or is missing the `terraform` block or its `tfvars` key — Phase 0.
- The tfvars is there but the configured servers variable isn't in it — Phase 0.
- The node needs something the servers object schema has no field for — that is a module
  change, not a tfvars entry.
- More than one node was asked for in a single run. Do them one at a time; batching is how a
  wrong datastore gets copied four ways.
- A config already exists and Setup was asked to write one — Setup step 2.
- Setup was invoked with no repo to commit to — Setup step 1.
- The tree is dirty when Setup is ready to commit — Setup step 9.
- `.claude/` is gitignored, so the config can't be staged without `-f` — Setup step 9.

## Reporting

Fixed format. Every run ends with this, no exceptions:

    ## terraform-create — <hostname>

    **Mode:** <full | partial — no live tfvars, collision checks not run | reduced —
    nothing checked against existing config | setup>
    **Config:** `.claude/terraform-create.yml` <loaded | written this run, PR <link> |
    absent — prefills below are one homelab's fallbacks, not yours>
    **Target:** <repo root> @ <branch> — <tfvars path>: <read | example only | not found>

    **Node:**
    | field | value | source |
    |---|---|---|
    | name | <...> | you |
    | node_name | <...> | you |
    | disk_datastore_id | <...> | you |
    | ip | <... or DHCP> | config prefill / fallback prefill / you |
    | ... | | |

    **tfvars entry** — append inside `<servers_variable> = [ ... ]` in `<tfvars path>`:

    ```hcl
    {
      name              = "<hostname>"
      node_name         = "<node>"
      disk_datastore_id = "<datastore>"

      ip       = "<ip>"
      net_vlan = <vlan>

      cores        = <n>       # only the fields that differ from the file's default_*
      memory_mb    = <n>
      disk_size_gb = <n>

      groups = ["<group>"]
    },
    ```

    When `terraform.servers_shape` is `map`, key the entry by name instead — `"<hostname>" = {
    ... }` — rather than emitting it as a list element.

    **Ansible inventory** — add to `<inventory path>` under `[<group>]`:

    ```ini
    <hostname> ipv4=<ip>
    ```

    That's the `ini` shape. For a `yaml` inventory emit the equivalent host entry under the
    group. With no `ansible` block configured and no inventory found, this section reads
    **"not emitted — no inventory configured"** and nothing is invented.

    **Checks:**
    - Duplicate name / ip / mac / vmid: <passed against N existing entries | not run — <reason>>
    - Gateway matches subnet: <...>
    - Inventory group SSH user: <...>

    **Next steps — run these yourself:**
    ```bash
    cd <terraform.dir>

    # 1. syntax
    terraform fmt -check && terraform validate

    # 2. plan, saved to a file so the apply is exactly what you reviewed
    terraform plan -out=tfplan

    # 3. apply that saved plan (no second prompt — the review above was the gate)
    terraform apply tfplan

    # 4. what got built — use the outputs this module actually declares;
    #    read outputs.tf rather than assuming these two names
    terraform output -json servers
    terraform output -raw ansible_inventory_yaml
    ```
    Expect exactly one resource to be created. If the plan shows a replace or a destroy on
    an existing server, stop and work out why before applying — `recreate_on_cloud_init_change`
    is false by default precisely so that does not happen quietly.

    Emit these commands filled in with the real directory, always. Handing over the exact
    command is the point of stopping here; making the human reconstruct it is not.

    **Risks / follow-up:** <anything noticed but not handled>

A Setup run reports the same header plus which config it wrote, each validation check's
result, the PR link, and which branch the user is on — and no tfvars entry, because none was
produced.

Never fill the Checks section with anything that did not actually happen, and never put a
terraform command's output in the report — no command is run.

## If something doesn't match reality

The config describes what somebody said was true when they ran `init`. The tfvars is what is
true now. When they disagree — the file moved, the servers variable was renamed, a node is
gone, the addressing changed — **trust the file, say exactly what you found, and stop rather
than emitting an entry that matches the config instead of reality.** Name the stale key so
the user can fix `.claude/terraform-create.yml` in the same breath.

The same applies to anything this file asserts. The schema in `references/tfvars-schema.md`
and the line formats in `references/ansible-inventory.md` are illustrative: if the real
`variables.tf` has fields the reference doesn't, or the real inventory is shaped differently,
trust the repo and mention the drift. Group names and the SSH user are never taken from a
reference at all — the group is read or asked for, and the SSH user is always asked. If the repo is missing, run reduced and label it. Do
not reconstruct the current tfvars from memory, and do not present a prefill as though it
were read from the file.
