terraform {
  # optional() with defaults in object type constraints needs >= 1.3.
  required_version = ">= 1.3"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # >= 0.61 for `content_type = "import"` on downloaded disk images.
      # Older versions only accept "iso", which produces the
      # "has wrong type 'iso' - needs to be 'images' or 'import'" error at apply.
      version = "~> 0.66"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}
