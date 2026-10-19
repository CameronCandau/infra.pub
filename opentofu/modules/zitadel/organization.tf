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

locals {
  organization_ids = data.zitadel_organizations.organization.ids
  organization_id  = one(local.organization_ids)
}

check "organization" {
  assert {
    condition     = length(local.organization_ids) == 1
    error_message = "Expected exactly one active ZITADEL organization named ${var.organization_name}."
  }
}

output "organization_id" {
  value = local.organization_id
}
