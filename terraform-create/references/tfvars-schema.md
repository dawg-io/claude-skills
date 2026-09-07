# `servers` entry schema and module defaults

The `servers` object type and module-level defaults this skill assumes, matching the layout
in [`example/`](../example/). Used as a **fallback**: when your Terraform repo is present,
the values in your own `terraform.tfvars` win over anything here.

The names, addresses and sizes below are illustrative — one plausible set of numbers, not
universal defaults and not a description of any particular network.
`/terraform-create init` records yours in `.claude/terraform-create.yml` — tfvars path, servers variable, VLAN, addressing,
sizing, nodes — and the run prefers that config over this file. Nothing here needs editing
to reuse the skill elsewhere.

## Per-entry attributes

Only `name`, `node_name` and `disk_datastore_id` are required. Everything else falls back
to a module-level default of a similar name.

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `name` | string | — | **Required.** Lowercase DNS label; also the guest hostname and the terraform map key |
| `node_name` | string | — | **Required.** Proxmox node, e.g. `pve01` |
| `disk_datastore_id` | string | — | **Required.** Must be images-capable |
| `ip` | string | DHCP | Bare IPv4, no prefix. Omit the field entirely for DHCP |
| `cidr` | number | `network_cidr` (24) | Prefix length for `ip` |
| `gateway` | string | `network_gateway` | Required when `ip` is set and the global gateway is null or in another subnet |
| `net_mac` | string | auto | Pin it and a DHCP reservation survives a rebuild |
| `net_bridge` | string | `net_bridge` (`vmbr0`) | |
| `net_vlan` | number | `net_vlan` | Omit for an untagged NIC |
| `cores` | number | `default_cores` (2) | Applied in place; needs a reboot to take effect |
| `sockets` | number | `default_sockets` (1) | |
| `memory_mb` | number | `default_memory_mb` (2048) | Applied in place |
| `disk_size_gb` | number | `default_disk_size_gb` (20) | Root fs grows to fill it. Growing is in-place; shrinking is not supported |
| `vm_id` | number | auto | Pin the VMID if you care about it |
| `pool_id` | string | none | Proxmox resource pool |
| `description` | string | generic | Shown in the Proxmox UI |
| `tags` | list(string) | `[]` | Merged with `default_tags` (`["terraform","ubuntu"]`) |
| `on_boot` | bool | `on_boot` (true) | Start with the node |
| `packages` | list(string) | `[]` | On top of the shared package list |
| `groups` | list(string) | `[]` | Ansible groups in the **generated** `inventory.yml`. No effect on the VM |

There is no field for anything else. If the node needs something not in this table, it is
a module change, not a tfvars entry.

## Module-level defaults worth reading out of the real file

`net_vlan`, `net_bridge`, `network_cidr`, `network_gateway`, `dns_servers`,
`search_domain`, `default_cores`, `default_sockets`, `default_memory_mb`,
`default_disk_size_gb`, `default_tags`, `on_boot`, `username`, `ansible_group`,
`ansible_inventory_path`, `recreate_on_cloud_init_change`.

Values in the committed `terraform.tfvars.example` (not necessarily the live file):

```hcl
default_cores        = 2
default_memory_mb    = 2048
default_disk_size_gb = 20

net_bridge      = "vmbr0"
net_vlan        = 100
network_cidr    = 24
network_gateway = "192.168.100.1"
dns_servers     = ["192.168.100.1"]
search_domain   = "example.lan"

username = "ansible"

ansible_inventory_path = "inventory.yml"
ansible_group          = "ubuntu_servers"

recreate_on_cloud_init_change = false
```

## Things that make a change destructive

Most edits apply in place: `cores`, `memory_mb`, `disk_size_gb` (up), `tags`,
`description`, `on_boot`. Adding an entry creates just that VM.

Cloud-init is the exception — it only runs on first boot, so the user-data template, the
SSH keys, the package list and **a server's IP** can only change by destroying and
recreating the VM. `recreate_on_cloud_init_change` defaults to `false` precisely so that
does not happen by surprise on an Ansible-managed host.

Relevant here: adding a *new* entry is safe. Editing an existing entry's addressing is
not, and is out of scope for this skill.

## Secrets in this file

`terraform.tfvars` contains `pm_api_token` (marked sensitive in `variables.tf`) and
`ssh_public_keys`, and may reference `pm_ssh_private_key_path`. It is gitignored. Read it
for the collision checks; never quote the API/SSH sections back, in the report or
anywhere else.

## Known troubleshooting signals

Worth mentioning in **Risks / follow-up** when the chosen values invite them:

- `has wrong type 'iso' - needs to be 'images' or 'import'` — the cloud image is in the
  datastore's `iso/` content type. It must be in `import/`.
- VM boots but never gets an IP and never appears in Ansible — installer media was used
  instead of a cloud image.
- `datastore does not support content type snippets` — `Snippets` is not enabled on
  `snippets_datastore_id`.
