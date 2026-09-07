# Example: a minimal Ansible repo for `ansible-create`

A small, working Ansible repository laid out the way [`ansible-create`](../) expects.

That skill writes playbooks, inventory lines and roles into a repo whose conventions it
documents but doesn't create. **This is that repo** — copy it, point it at your own hosts,
and what the skill emits drops straight in.

It is the counterpart to [`terraform-create/example/`](../../terraform-create/example/), and
the two compose: build a VM with the Terraform module, then manage it with this.

## How you actually install roles — and what `ansible-galaxy role import` really does

The consumer command is **`ansible-galaxy install -r requirements.yml`**. It reads the
pinned list in `requirements.yml` and pulls each role and collection from Galaxy or straight
from git. No Galaxy account, no token, no publishing step.

`ansible-galaxy role import <github_user> <github_repo>` is a different thing entirely: it is
a **publisher** command that tells galaxy.ansible.com to pull a role *you own* on GitHub into
*your own* namespace, and it requires a Galaxy API token. It installs nothing for anyone
else. If you were hoping it was the one-liner users run — it isn't.

And if you were considering publishing a standalone role to Galaxy: **don't build on it.**
galaxy-ng, the codebase behind the next Galaxy and Ansible Hub, has no support for standalone
roles and no plans to add it; roles on the current site are expected to go read-only.
Collections are the forward path for genuinely distributed content. For a fleet repo like
this one, you don't need to distribute anything — you need `requirements.yml`.

```bash
ansible-galaxy install -r requirements.yml
```

`requirements.yml` here shows all three sources: a pinned collection, a pinned Galaxy role,
and the commented form for pulling a role directly from a git tag.

## Files

| Path | What it is |
|---|---|
| `ansible.cfg` | Relative paths, logging, SSH tuning. Read the notes in it before copying settings forward |
| `inventory/home/host` | Static **INI** inventory. `<hostname> ipv4=<address>` |
| `group_vars/all.yml` | Fleet-wide non-secret defaults. Deliberately tiny |
| `common.yml` | The fleet-wide entry point — what a nightly job runs |
| `chrony.yml` | A single-purpose root playbook; the shape `ansible-create` produces |
| `roles/README.md` | The "prefer a public role" convention, and the house rules lint won't catch |
| `roles/chrony/` | One worked role: defaults, tasks, handler, template, meta |
| `requirements.yml` | Pinned collections and roles |
| `.gitignore` | Keeps `.ansible`, logs and any password file out of git |

## Quick start

```bash
ansible-galaxy install -r requirements.yml

# From THIS directory — see the trap below.
ansible-inventory --list                       # does the inventory parse?
ansible-playbook --syntax-check chrony.yml

ansible-playbook chrony.yml --check --diff --limit web01
ansible-playbook chrony.yml --limit web01

# Converged only when a second run reports zero changed:
ansible-playbook chrony.yml --limit web01
```

## Three traps this layout is shaped around

**1. `ansible.cfg` paths are relative to your working directory.** Run Ansible from anywhere
else and the inventory resolves to nothing. Demonstrated:

```
$ ansible-inventory --list                      # from this directory
  ubuntu_servers: ['db01', 'web01']

$ cd .. && ansible-inventory --list             # one level up
  [WARNING]: No inventory was parsed, only implicit localhost is available
```

A play against zero hosts **succeeds**. It reports `ok=0` and exits clean, so nothing tells
you the run did nothing.

**2. The SSH user has to match the account the image actually has.** A VM built by the
Terraform example gets a key-only `ansible` user with root and password login both disabled.
Drop that host into a group whose `ansible_ssh_user` is `root` or a personal login and every
play fails at connection, before a single task runs. `[ubuntu_servers:vars]` sets
`ansible_ssh_user=ansible` for exactly this reason.

**3. A `[group:vars]` block for a group with no members breaks the whole inventory.** Every
play then silently matches zero hosts — same failure as trap 1, from a different direction.
Never add a `:vars` block speculatively.

## Conventions

Matching what `ansible-create` expects, so its output pastes in unchanged:

- **Inventory** is INI at `inventory/home/host`, lines `<hostname> ipv4=<address>`. Note
  `ipv4` is an ordinary host variable, **not** a connection setting — Ansible still connects
  to the name, so the name must resolve in DNS. If yours don't, add `ansible_host`; there's a
  commented example under `[edge]`.
- **Groups** are snake_case; **role directories** are kebab-case; **role variables** are
  prefixed with the role subject.
- **Playbooks** live at the root, one job each, with a `# Usage:` comment block including a
  `--limit` form.
- **Plays are unnamed.** That is the house style, and it is why `ansible-lint` reports
  `name[play]` — see below.
- **Tunables go in the role's `defaults/main.yml`**, not in `group_vars/`. A role whose
  settings live in `group_vars/` can't be reused without dragging that file along.
- **Secrets are never literals.** Empty default plus an `assert` on the placeholder, or a
  vault reference, plus `no_log: true` on anything carrying a token. And keep them out of
  vaulted `group_vars/`: those decrypt whenever any group member appears in *any* play,
  including the nightly `common.yml`. Scope with `vars_files` in the one playbook instead.
- **`forks` is unset**, so it stays at the default of 5. A five-host group already runs fully
  parallel; adding `serial:` to "help" makes it slower.

## Verification

Run against ansible-core 2.19.12 and ansible-lint 26.8.0, following `ansible-create`'s own
Phase 4:

- `ansible-inventory --list` parses the INI inventory; `ubuntu_servers` → `db01, web01`,
  `edge` → `edge01`, `timeservers` → all three, and `ansible_ssh_user` plus `ipv4` land on
  each host as expected
- `ansible-playbook --syntax-check` passes on `chrony.yml` and `common.yml`, run from this
  directory
- The wrong-directory case was confirmed to produce "No inventory was parsed" — that's where
  the output quoted in trap 1 comes from
- `chrony.conf.j2` was rendered for real with `-i 'localhost,' -c local`, in both the
  client and server branches; both produce valid config, with the `allow` lines appearing
  only when `chrony_is_server` is set
- `ansible-lint --offline` in an isolated directory: **2 findings, both `name[play]`**, on
  the two deliberately unnamed plays. Left in place — they are the documented house style.
  No other rule fired
- `git check-ignore` confirms `logs/*`, `.ansible` and `sudo_pass.txt` are excluded while
  `logs/.gitkeep` is kept

**Not verified: anything against a real host.** Nothing here has been applied to a live
machine — not even `--check`, which still opens SSH and gathers facts. The `chrony` role
targets Debian/Ubuntu (`ansible.builtin.apt`); on RHEL you'd swap the module and set
`chrony_service: chronyd`.

## One thing that changed upstream

Older repos — including the one `ansible-create` documents — set
`error_on_undefined_vars = True` in `ansible.cfg`. **Don't copy that forward.** ansible-core
has deprecated it: the option "is no longer used in the Ansible Core code base" and is
removed in 2.23, so setting it now only earns a deprecation warning on every run.

The behaviour it described is the default anyway — an undefined variable is a hard failure,
not an empty string. That is still the reason every tunable belongs in `defaults/main.yml`.
