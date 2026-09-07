# Example: Proxmox VM module for `terraform-create`

A complete, working Terraform configuration for building Ubuntu cloud-init VMs on Proxmox.

The [`terraform-create`](../) skill interviews you for a new VM and emits a `servers` entry
to paste into a `terraform.tfvars`. That skill assumes a module already exists to consume
the entry. **This is that module** — a starting point you copy into your own repo and adapt,
so the skill has something real to write for.

It implements exactly the schema documented in
[`../references/tfvars-schema.md`](../references/tfvars-schema.md), so an entry the skill
emits pastes in and works.

## Files

| File | What it is |
|---|---|
| `versions.tf` | Terraform and provider version constraints |
| `providers.tf` | Proxmox provider, including the SSH block the snippets upload needs |
| `variables.tf` | Every module-level default, plus the `servers` object schema and its validations |
| `main.tf` | Defaults merge, generated inventory, cloud image, cloud-init snippets, the VMs |
| `outputs.tf` | `servers` and `ansible_inventory_yaml` — the two the skill's next-steps block reads |
| `templates/user-data.yaml.tftpl` | cloud-init user data, rendered per guest |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` and fill in. Three worked server entries |
| `.gitignore` | Keeps `terraform.tfvars`, state, and the generated inventory out of git |

## Before you start — four Proxmox prerequisites

Three of these produce errors that look like a Terraform problem but aren't. They're the
same ones `../references/tfvars-schema.md` lists under troubleshooting.

1. **An API token.** On the node:
   ```
   pveum user token add terraform@pve provisioner --privsep 0
   ```
   Then grant its user a role with `VM.Allocate`, `VM.Config.*`, `Datastore.AllocateSpace`,
   `Datastore.Audit`, `Sys.Audit`.

2. **`Snippets` enabled** on `snippets_datastore_id` — *Datacenter → Storage → (store) →
   Content*. Without it, apply fails with `datastore does not support content type
   snippets`, because cloud-init user data is uploaded as a snippet.

3. **`Import` enabled** on `image_datastore_id`, same place. Without it you get
   `has wrong type 'iso' - needs to be 'images' or 'import'`. This module sets
   `content_type = "import"`, which needs bpg/proxmox ≥ 0.61.

4. **SSH to the node works** for `pm_ssh_username`. The provider needs SSH for operations
   the API can't do alone — uploading snippets among them — so a working `ssh` block is not
   optional.

One more that isn't an error, just a silently broken VM: **use a cloud image, not an
installer ISO.** An installer boots to a prompt, never runs cloud-init, and so never takes
an address or appears in the inventory. The default `cloud_image_url` is a proper cloud
image.

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars          # endpoint, token, node names, your SSH public key

terraform init
terraform fmt -check && terraform validate
terraform plan -out=tfplan        # review it
terraform apply tfplan

terraform output -json servers
terraform output -raw ansible_inventory_yaml
```

Expect one resource created per server entry, plus the cloud image download and one snippet
per guest. **If the plan shows a replace or destroy on a server that already exists, stop
and work out why before applying** — see "Editing an existing server" below.

## How it pairs with the skill

Run `/terraform-create`, answer the interview, and it prints a block like this — paste it
inside the `servers = [ ... ]` list:

```hcl
{
  name              = "web02"
  node_name         = "pve01"
  disk_datastore_id = "local-lvm"

  ip = "192.168.100.12"

  cores     = 4
  memory_mb = 8192

  groups = ["web"]
},
```

The skill reads your `terraform.tfvars` first, so **the values in your file win over the
skill's built-in prefills**. It also checks the new entry against the existing ones for
duplicate name, IP, MAC and VMID before handing it over.

Point the skill at this directory by keeping the layout it expects, or tell it where your
tfvars actually lives — it discovers the file rather than assuming a fixed path.

## The `servers` schema

Only three attributes are required. Everything else falls back to a module-level default of
a similar name, so a minimal entry is three lines:

```hcl
{ name = "web01", node_name = "pve01", disk_datastore_id = "local-lvm" }
```

| Attribute | Falls back to | Notes |
|---|---|---|
| `name` | — | **Required.** Lowercase DNS label; also the guest hostname and the Terraform map key |
| `node_name` | — | **Required.** Proxmox node to build on |
| `disk_datastore_id` | — | **Required.** Must be images-capable |
| `ip` | DHCP | Bare IPv4, no prefix. Omit entirely for DHCP |
| `cidr` | `network_cidr` | Prefix length for `ip` |
| `gateway` | `network_gateway` | Required when `ip` is set and the global gateway is null or in another subnet |
| `net_mac` | auto | Pin it and a DHCP reservation survives a rebuild |
| `net_bridge` / `net_vlan` | `net_bridge` / `net_vlan` | Null VLAN leaves the NIC untagged |
| `cores` / `sockets` | `default_cores` / `default_sockets` | Applied in place; needs a reboot to take effect |
| `memory_mb` | `default_memory_mb` | Applied in place |
| `disk_size_gb` | `default_disk_size_gb` | Grows in place. Shrinking is not supported |
| `vm_id` | auto | Pin if you care about it |
| `pool_id` | none | Proxmox resource pool |
| `description` | `"Managed by Terraform"` | Shown in the Proxmox UI |
| `tags` | `[]` | Merged with `default_tags` |
| `on_boot` | `on_boot` | Start with the node |
| `packages` | `[]` | Installed on top of the shared `packages` list |
| `groups` | `[]` | Ansible groups in the **generated** inventory. No effect on the VM |

Four things are rejected before any plan runs: a duplicate `name`, a name that isn't a
lowercase DNS label, two servers sharing one static `ip`, and an empty `ssh_public_keys`.
A static `ip` with no derivable gateway is caught by a precondition on the VM itself.

## Editing an existing server

**Most edits apply in place:** `cores`, `memory_mb`, `disk_size_gb` (upward), `tags`,
`description`, `on_boot`.

**Cloud-init is the exception.** It only runs on first boot, so a guest's SSH keys, package
list, hostname and **IP address** cannot be changed on a running VM — only by destroying and
recreating it. This module therefore pins the cloud-init surface:

```hcl
lifecycle {
  ignore_changes = [initialization]
}
```

which means editing an entry's `ip` will *not* silently destroy a host Ansible is managing.
To apply such a change deliberately, recreate that one guest:

```bash
terraform apply -replace='proxmox_virtual_environment_vm.this["web01"]'
```

> The upstream module this mirrors exposes a `recreate_on_cloud_init_change` toggle for the
> same purpose. Terraform's `lifecycle` blocks must be static — they can't read a variable —
> so a real toggle means duplicating the whole resource, and flipping it would change every
> resource address and destroy the fleet. This example takes the safe behaviour as fixed and
> gives you the `-replace` escape hatch instead.

## The generated inventory

Every apply writes `ansible_inventory_path` (default `inventory.yml`) from the `servers`
list. Each host joins `ansible_group` plus whatever is in its own `groups`:

```yaml
"all":
  "children":
    "databases":
      "hosts":
        "db01":
          "ansible_host": "192.168.100.11"
          "ansible_user": "ansible"
    "ubuntu_servers":
      "hosts":
        "db01": {...}
        "web01":
          "ansible_user": "ansible"     # DHCP host: no ansible_host pinned
```

Set `ansible_inventory_path = ""` to disable the file.

**If you also keep a static inventory by hand, two files now describe the same host.** That
is workable but it is the thing that most often goes wrong: a guest built here has a
key-only `username` account (default `ansible`) with root and password login disabled, so
dropping it into a hand-written group whose `ansible_ssh_user` is something else fails at
connection, before a single task runs. Either give the host a per-host
`ansible_ssh_user=<username>` override, or put it in a group whose vars already match.

## What was verified, and what wasn't

Run against Terraform v1.9.8:

- `terraform fmt -check -recursive` — clean; all HCL parses
- `terraform validate` — passes, against the real `variables.tf` and the real `locals` from
  `main.tf`
- The shipped `terraform.tfvars.example` type-checks as valid input, and its three entries
  resolve to the expected settings — a minimal entry correctly inherits every default, and
  overrides, tag merging and a pinned MAC/VMID all behave. Every host here is in one
  subnet, so the per-entry `gateway` override is documented but not exercised
- The generated inventory parses as YAML with the right group membership, and a DHCP host
  correctly omits `ansible_host`
- All five input validations reject what they should and accept valid input
- `templates/user-data.yaml.tftpl` renders to valid YAML with keys and packages each on
  their own line, and omits the `packages` key entirely when the list is empty

**Not verified: anything requiring the provider schema or a real Proxmox.** The environment
this was written in blocks `registry.terraform.io`, so `terraform init` could not download
bpg/proxmox and `terraform validate` could not check the resource blocks against it. The
resource arguments are written against bpg/proxmox ~> 0.66 but have not been schema-checked,
and nothing has been applied against a real node. **Run `terraform init && terraform validate`
yourself before your first apply**, and treat the first `plan` as the real review.
