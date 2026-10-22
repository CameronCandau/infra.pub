terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 3.8.0"
    }
  }
}

data "zitadel_organizations" "organization" {
  name        = var.organization_name
  name_method = "TEXT_QUERY_METHOD_EQUALS"
  state       = "ORGANIZATION_STATE_ACTIVE"
}

data "zitadel_human_users" "administrator" {
  org_id           = local.organization_id
  user_name        = var.administrator_user_name
  user_name_method = "TEXT_QUERY_METHOD_EQUALS"
}

locals {
  organization_ids       = data.zitadel_organizations.organization.ids
  organization_id        = one(local.organization_ids)
  administrator_user_ids = data.zitadel_human_users.administrator.user_ids
  administrator_user_id  = one(local.administrator_user_ids)
}

check "organization" {
  assert {
    condition     = length(local.organization_ids) == 1
    error_message = "Expected exactly one active ZITADEL organization named ${var.organization_name}."
  }
}

check "administrator" {
  assert {
    condition     = length(local.administrator_user_ids) == 1
    error_message = "Expected exactly one human user named ${var.administrator_user_name} in ${var.organization_name}."
  }
}

output "organization_id" {
  value = local.organization_id
}
