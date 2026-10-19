terraform {
  required_version = "~> 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114.0"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 3.8.0"
    }
  }
}

locals {
  inventory = jsondecode(file("${path.module}/../inventory.json"))
}

module "machines" {
  source = "../../opentofu/modules/proxmox"

  machines       = local.inventory.machines
  network_bridge = local.inventory.network.bridge
  template       = local.inventory.template
}

module "zitadel" {
  source = "../../opentofu/modules/zitadel"

  domain            = "example.test"
  organization_name = "Example Lab"
  users = {
    example = {
      user_name    = "person@example.test"
      email        = "person@example.test"
      first_name   = "Example"
      last_name    = "Person"
      display_name = "Example Person"
    }
  }
  smtp = {
    host             = "smtp.example.test:465"
    user             = "example"
    password         = "not-a-secret"
    sender_address   = "noreply@example.test"
    sender_name      = "Example Lab"
    reply_to_address = "admin@example.test"
    description      = "Example SMTP"
  }
  immich_user_keys    = ["example"]
  immich_admin_users  = { owner = "000000000000000001" }
  openbao_admin_users = { owner = "000000000000000001" }
}
