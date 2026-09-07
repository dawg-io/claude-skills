# The `terraform-create` skill's next-steps block ends with these two commands,
# so both output names are part of the contract with it:
#
#   terraform output -json servers
#   terraform output -raw ansible_inventory_yaml

output "servers" {
  description = "Every managed guest, with its resolved settings and the address Proxmox reports."

  value = {
    for name, s in local.servers : name => {
      vm_id     = proxmox_virtual_environment_vm.this[name].vm_id
      node_name = s.node_name

      # Configured address, or "dhcp". What the guest actually got is in ipv4_addresses.
      configured_ip = s.ip != null ? "${s.ip}/${s.cidr}" : "dhcp"

      # Reported by the guest agent; empty until the agent is up.
      ipv4_addresses = proxmox_virtual_environment_vm.this[name].ipv4_addresses

      cores        = s.cores
      memory_mb    = s.memory_mb
      disk_size_gb = s.disk_size_gb
      tags         = s.tags
      groups       = s.groups
    }
  }
}

output "ansible_inventory_yaml" {
  description = "The generated inventory, as written to ansible_inventory_path."
  value       = local.ansible_inventory_yaml
}

output "ansible_groups" {
  description = "Every group appearing in the generated inventory."
  value       = local.ansible_groups
}
