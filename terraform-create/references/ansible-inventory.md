# `inventory/home/host` — static INI inventory

A hand-maintained static inventory of the shape this skill emits lines for. It is INI
format, not YAML, and it is **separate** from the `inventory.yml` the terraform module
generates. A host added by terraform does not appear here until someone adds the line.

The hostnames and addresses below are illustrative — a worked example of the line format,
not a description of any particular fleet. **This file deliberately carries no group names
and no SSH users.** Groups come from your own inventory, and the SSH user is asked on every
run rather than derived from a group. `/terraform-create init` records the path to *your*
inventory and its format in `.claude/terraform-create.yml`.

## Line format

Two shapes are in use:

```ini
pi-01        ipv4=192.168.100.12   # name plus an ipv4 host var
db01                              # bare name, resolved by DNS
```

For a terraform-built VM with a static IP, emit the first shape:

```ini
<hostname> ipv4=192.168.<vlan>.<octet>
```

For a DHCP node, the bare name only works if DNS knows about it. Say so rather than
assuming it resolves.

## The SSH user mismatch

Terraform creates a key-only account named by `username` (default `ansible`) and disables
password auth and root login. A static inventory typically sets its own `ansible_ssh_user`
per group — often `root`, or a login that predates the fleet. If that account does not exist
on a new terraform-built Ubuntu guest, a host dropped into the group fails to connect on the
first play, before any task runs. **That is why the skill asks for the SSH user every run
instead of deriving it from the group.**

The two honest fixes, for the human to choose between:

1. Per-host override on the inventory line:

   ```ini
   <hostname> ipv4=192.168.100.x ansible_ssh_user=ansible
   ```

2. A new group with its own vars, which is tidier once there is more than one such VM:

   ```ini
   [ubuntu_servers]
   <hostname> ipv4=192.168.100.x

   [ubuntu_servers:vars]
   ansible_ssh_user=ansible
   ```

Option 2 lines the static inventory up with `ansible_group` in the terraform config,
which also defaults to `ubuntu_servers`.

## Also worth knowing

The terraform module writes `ubuntu-servers/inventory.yml` on every apply (path set by
`ansible_inventory_path`, `""` disables it), keyed on the `groups` field of each server
entry plus the shared `ansible_group`. Two inventories now describe the same host; that
is by design here, but it means the `groups` field and the INI group are set separately
and can drift apart. Set both, and say what each one is for.
