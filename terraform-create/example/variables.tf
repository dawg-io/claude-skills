# ---------------------------------------------------------------------------
# Proxmox connection
# ---------------------------------------------------------------------------

variable "pm_endpoint" {
  description = "Proxmox API endpoint, e.g. https://pve01.example.lan:8006/"
  type        = string
}

variable "pm_api_token" {
  description = <<-EOT
    Proxmox API token, in the form USER@REALM!TOKENID=UUID.
    Keep this in terraform.tfvars (gitignored) or TF_VAR_pm_api_token — never commit it.
  EOT
  type        = string
  sensitive   = true
}

variable "pm_insecure" {
  description = "Skip TLS verification against the Proxmox API. Only for a self-signed lab cert."
  type        = bool
  default     = false
}

variable "pm_ssh_username" {
  description = <<-EOT
    SSH user the provider uses on the Proxmox node itself. The provider needs SSH for a
    few operations the API cannot do alone, notably uploading snippets.
  EOT
  type        = string
  default     = "root"
}

variable "pm_ssh_private_key_path" {
  description = "Path to the private key for pm_ssh_username. Null uses the SSH agent."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Cloud image
# ---------------------------------------------------------------------------

variable "cloud_image_url" {
  description = <<-EOT
    URL of a cloud image — NOT an installer ISO. An installer image boots to a prompt,
    never runs cloud-init, and so never gets an address or appears in Ansible.
  EOT
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "cloud_image_file_name" {
  description = "File name to store the cloud image under. Must end in .img or .qcow2."
  type        = string
  default     = "noble-server-cloudimg-amd64.qcow2"
}

variable "image_datastore_id" {
  description = "Datastore holding the downloaded cloud image. Needs the 'Import' content type enabled."
  type        = string
  default     = "local"
}

variable "image_node_name" {
  description = "Proxmox node to download the cloud image onto."
  type        = string
}

variable "snippets_datastore_id" {
  description = <<-EOT
    Datastore for cloud-init user-data snippets. Needs the 'Snippets' content type enabled
    in Datacenter > Storage, or apply fails with
    "datastore does not support content type snippets".
  EOT
  type        = string
  default     = "local"
}

# ---------------------------------------------------------------------------
# Guest access
# ---------------------------------------------------------------------------

variable "username" {
  description = <<-EOT
    Login created inside each guest. Key-only: password auth and root login are disabled.
    This must match the ansible_ssh_user of whatever inventory group the host lands in,
    or every play fails at connection before a single task runs.
  EOT
  type        = string
  default     = "ansible"
}

variable "ssh_public_keys" {
  description = "Public keys authorised for `username`. At least one, or the guest is unreachable."
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "ssh_public_keys must contain at least one key; password login is disabled in the guests."
  }
}

variable "packages" {
  description = "Packages installed on every guest, on top of each server's own `packages`."
  type        = list(string)
  default     = ["qemu-guest-agent"]
}

# ---------------------------------------------------------------------------
# Networking defaults
# ---------------------------------------------------------------------------

variable "net_bridge" {
  description = "Default Proxmox bridge for guest NICs."
  type        = string
  default     = "vmbr0"
}

variable "net_vlan" {
  description = "Default VLAN tag. Null leaves the NIC untagged."
  type        = number
  default     = null
}

variable "network_cidr" {
  description = "Default prefix length for a server's static `ip`."
  type        = number
  default     = 24
}

variable "network_gateway" {
  description = <<-EOT
    Default gateway for statically addressed guests. Null is allowed only if every server
    with an `ip` sets its own `gateway`; see the validation in main.tf.
  EOT
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "Resolvers written into each guest's cloud-init."
  type        = list(string)
  default     = []
}

variable "search_domain" {
  description = "DNS search domain for the guests."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Sizing defaults
# ---------------------------------------------------------------------------

variable "default_cores" {
  description = "Default vCPU cores per server."
  type        = number
  default     = 2
}

variable "default_sockets" {
  description = "Default CPU sockets per server."
  type        = number
  default     = 1
}

variable "default_memory_mb" {
  description = "Default RAM in MB per server."
  type        = number
  default     = 2048
}

variable "default_disk_size_gb" {
  description = <<-EOT
    Default root disk in GB. The root filesystem grows to fill it on first boot.
    Growing later is in place; shrinking is not supported by Proxmox.
  EOT
  type        = number
  default     = 20
}

variable "default_tags" {
  description = "Tags applied to every VM, merged with each server's own `tags`."
  type        = list(string)
  default     = ["terraform", "ubuntu"]
}

variable "on_boot" {
  description = "Default for whether a guest starts with the Proxmox node."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Generated Ansible inventory
# ---------------------------------------------------------------------------

variable "ansible_group" {
  description = "Group every server joins in the generated inventory, on top of its own `groups`."
  type        = string
  default     = "ubuntu_servers"
}

variable "ansible_inventory_path" {
  description = "Where to write the generated inventory. Empty string disables the file."
  type        = string
  default     = "inventory.yml"
}

# ---------------------------------------------------------------------------
# The servers themselves
# ---------------------------------------------------------------------------

variable "servers" {
  description = <<-EOT
    One object per VM. Only name, node_name and disk_datastore_id are required; every
    other attribute falls back to the module-level default of a similar name.

    This is the list the `terraform-create` skill emits entries for — paste them here.
  EOT

  type = list(object({
    # Required.
    name              = string # lowercase DNS label; also the guest hostname and the map key
    node_name         = string # Proxmox node to build on
    disk_datastore_id = string # must be images-capable

    # Addressing. Omit `ip` entirely for DHCP.
    ip      = optional(string) # bare IPv4, no prefix
    cidr    = optional(number) # defaults to network_cidr
    gateway = optional(string) # defaults to network_gateway
    net_mac = optional(string) # pin it and a DHCP reservation survives a rebuild

    net_bridge = optional(string)
    net_vlan   = optional(number)

    # Sizing.
    cores        = optional(number)
    sockets      = optional(number)
    memory_mb    = optional(number)
    disk_size_gb = optional(number)

    # Proxmox bookkeeping.
    vm_id       = optional(number)
    pool_id     = optional(string)
    description = optional(string)
    tags        = optional(list(string), [])
    on_boot     = optional(bool)

    # Guest content.
    packages = optional(list(string), [])

    # Ansible groups in the GENERATED inventory. No effect on the VM itself.
    groups = optional(list(string), [])
  }))

  default = []

  validation {
    condition     = length(var.servers) == length(distinct([for s in var.servers : s.name]))
    error_message = "Every server name must be unique; it is the Terraform map key."
  }

  validation {
    condition = alltrue([
      for s in var.servers : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", s.name))
    ])
    error_message = "Server names must be lowercase DNS labels: [a-z0-9-], no underscores, dots, or leading/trailing hyphen."
  }

  validation {
    condition = length([for s in var.servers : s.ip if s.ip != null]) == length(distinct([
      for s in var.servers : s.ip if s.ip != null
    ]))
    error_message = "Two servers cannot share the same static ip."
  }
}
