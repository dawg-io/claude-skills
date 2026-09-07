provider "proxmox" {
  endpoint  = var.pm_endpoint
  api_token = var.pm_api_token
  insecure  = var.pm_insecure

  # The provider needs SSH to the node itself for a handful of operations the
  # API cannot do alone — uploading cloud-init snippets among them. Without a
  # working ssh block, `proxmox_virtual_environment_file` fails at apply.
  ssh {
    agent       = var.pm_ssh_private_key_path == null
    username    = var.pm_ssh_username
    private_key = var.pm_ssh_private_key_path != null ? file(var.pm_ssh_private_key_path) : null
  }
}
