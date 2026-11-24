resource "zitadel_project" "vaultwarden" {
  org_id             = local.organization_id
  name               = "Vaultwarden"
  has_project_check  = true
  project_role_check = true
}

resource "zitadel_project_role" "vaultwarden_user" {
  org_id       = local.organization_id
  project_id   = zitadel_project.vaultwarden.id
  role_key     = "vaultwarden-user"
  display_name = "Vaultwarden User"
}

resource "zitadel_application_oidc" "vaultwarden" {
  org_id     = local.organization_id
  project_id = zitadel_project.vaultwarden.id
  name       = "Vaultwarden"

  redirect_uris = [
    "https://vaultwarden.${var.domain}/identity/connect/oidc-signin",
  ]

  response_types    = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types       = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type          = "OIDC_APP_TYPE_WEB"
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
  version           = "OIDC_VERSION_1_0"
  dev_mode          = false
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"

  login_version {
    login_v1 = true
  }
}

resource "zitadel_user_grant" "vaultwarden_users" {
  for_each = var.vaultwarden_user_keys

  org_id     = local.organization_id
  project_id = zitadel_project.vaultwarden.id
  user_id    = zitadel_human_user.users[each.value].id
  role_keys  = [zitadel_project_role.vaultwarden_user.role_key]
}

resource "zitadel_user_grant" "vaultwarden_administrator" {
  org_id     = local.organization_id
  project_id = zitadel_project.vaultwarden.id
  user_id    = local.administrator_user_id
  role_keys  = [zitadel_project_role.vaultwarden_user.role_key]
}

output "vaultwarden_oidc_client_id" {
  value     = zitadel_application_oidc.vaultwarden.client_id
  sensitive = true
}

output "vaultwarden_oidc_client_secret" {
  value     = zitadel_application_oidc.vaultwarden.client_secret
  sensitive = true
}

output "vaultwarden_oidc_project_id" {
  value = zitadel_project.vaultwarden.id
}
