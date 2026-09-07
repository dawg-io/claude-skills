# ---------------------------------------------------------------------------
# Resolve each server against the module-level defaults.
#
# Keyed by name, so `for_each` gives every VM a stable address and adding a new
# entry to `servers` plans exactly one create — it does not disturb the others.
# ---------------------------------------------------------------------------

locals {
  servers = {
    for s in var.servers : s.name => {
      name              = s.name
      node_name         = s.node_name
      disk_datastore_id = s.disk_datastore_id

      # Addressing. A null ip means DHCP, and then cidr/gateway are unused.
      ip      = s.ip
      cidr    = s.cidr != null ? s.cidr : var.network_cidr
      gateway = s.gateway != null ? s.gateway : var.network_gateway
      net_mac = s.net_mac

      net_bridge = s.net_bridge != null ? s.net_bridge : var.net_bridge
      net_vlan   = s.net_vlan != null ? s.net_vlan : var.net_vlan

      cores        = s.cores != null ? s.cores : var.default_cores
      sockets      = s.sockets != null ? s.sockets : var.default_sockets
      memory_mb    = s.memory_mb != null ? s.memory_mb : var.default_memory_mb
      disk_size_gb = s.disk_size_gb != null ? s.disk_size_gb : var.default_disk_size_gb

      vm_id       = s.vm_id
      pool_id     = s.pool_id
      description = s.description != null ? s.description : "Managed by Terraform"
      tags        = sort(distinct(concat(var.default_tags, s.tags)))
      on_boot     = s.on_boot != null ? s.on_boot : var.on_boot

      packages = distinct(concat(var.packages, s.packages))

      # Every host joins the shared group as well as its own.
      groups = distinct(concat([var.ansible_group], s.groups))
    }
  }
}

# ---------------------------------------------------------------------------
# Generated Ansible inventory
#
# This is a SECOND inventory, separate from any static one you maintain by hand.
# Both can describe the same host, so keep track of which is which.
# ---------------------------------------------------------------------------

locals {
  ansible_groups = sort(distinct(flatten([for s in local.servers : s.groups])))

  ansible_inventory = {
    all = {
      children = {
        for g in local.ansible_groups : g => {
          hosts = {
            for name, s in local.servers : name => merge(
              { ansible_user = var.username },
              s.ip != null ? { ansible_host = s.ip } : {},
            ) if contains(s.groups, g)
          }
        }
      }
    }
  }

  ansible_inventory_yaml = yamlencode(local.ansible_inventory)
}

resource "local_file" "ansible_inventory" {
  count = var.ansible_inventory_path != "" ? 1 : 0

  filename        = var.ansible_inventory_path
  content         = local.ansible_inventory_yaml
  file_permission = "0644"
}

# ---------------------------------------------------------------------------
# Cloud image
#
# Must be a cloud image, and must land in the datastore's `import` content type.
# An installer ISO boots to a prompt, never runs cloud-init, and so never picks
# up an address or appears in the inventory.
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_download_file" "cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore_id
  node_name    = var.image_node_name
  url          = var.cloud_image_url
  file_name    = var.cloud_image_file_name
  overwrite    = false
}

# ---------------------------------------------------------------------------
# Per-guest cloud-init user data
#
# Needs the `Snippets` content type enabled on snippets_datastore_id, or apply
# fails with "datastore does not support content type snippets".
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_file" "user_data" {
  for_each = local.servers

  content_type = "snippets"
  datastore_id = var.snippets_datastore_id
  node_name    = each.value.node_name

  source_raw {
    file_name = "${each.value.name}-user-data.yaml"

    data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
      hostname        = each.value.name
      username        = var.username
      ssh_public_keys = var.ssh_public_keys
      packages        = each.value.packages
    })
  }
}

# ---------------------------------------------------------------------------
# The guests
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "this" {
  for_each = local.servers

  name        = each.value.name
  node_name   = each.value.node_name
  vm_id       = each.value.vm_id
  pool_id     = each.value.pool_id
  description = each.value.description
  tags        = each.value.tags
  on_boot     = each.value.on_boot

  # The guest agent is what makes `terraform` and the Proxmox UI able to report
  # the guest's real address. `packages` installs qemu-guest-agent by default.
  agent {
    enabled = true
  }

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = each.value.disk_datastore_id
    import_from  = proxmox_virtual_environment_download_file.cloud_image.id
    interface    = "virtio0"
    size         = each.value.disk_size_gb
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge      = each.value.net_bridge
    vlan_id     = each.value.net_vlan
    mac_address = each.value.net_mac
  }

  initialization {
    datastore_id      = each.value.disk_datastore_id
    interface         = "ide2"
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id

    dynamic "dns" {
      for_each = length(var.dns_servers) > 0 || var.search_domain != null ? [1] : []

      content {
        servers = var.dns_servers
        domain  = var.search_domain
      }
    }

    ip_config {
      ipv4 {
        address = each.value.ip != null ? "${each.value.ip}/${each.value.cidr}" : "dhcp"
        gateway = each.value.ip != null ? each.value.gateway : null
      }
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    precondition {
      condition     = each.value.ip == null || each.value.gateway != null
      error_message = "Server '${each.key}' sets a static ip but no gateway is derivable: set network_gateway, or give the entry its own gateway."
    }

    # Cloud-init only runs on FIRST boot. Pinning it here means editing a
    # server's ip, keys, or packages can never silently destroy a running host.
    # To apply such a change deliberately, recreate that one VM:
    #   terraform apply -replace='proxmox_virtual_environment_vm.this["<name>"]'
    ignore_changes = [initialization]
  }
}
