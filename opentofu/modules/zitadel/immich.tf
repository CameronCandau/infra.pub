resource "zitadel_project" "immich" {
  org_id             = local.organization_id
  name               = "Immich"
  has_project_check  = true
  project_role_check = true
}

resource "zitadel_project_role" "immich_user" {
  org_id       = local.organization_id
  project_id   = zitadel_project.immich.id
  role_key     = "immich-user"
  display_name = "Immich User"
}

resource "zitadel_application_oidc" "immich" {
  org_id     = local.organization_id
  project_id = zitadel_project.immich.id
  name       = "Immich"

  redirect_uris = [
    "https://immich.${var.domain}/auth/login",
    "https://immich.${var.domain}/user-settings",
    "app.immich:///oauth-callback",
  ]

  response_types    = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types       = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type          = "OIDC_APP_TYPE_WEB"
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
  version           = "OIDC_VERSION_1_0"
  dev_mode          = false
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"

  login_version {
    login_v1 = true
  }
}

resource "zitadel_user_grant" "immich_users" {
  for_each = var.immich_user_keys

  org_id     = local.organization_id
  project_id = zitadel_project.immich.id
  user_id    = zitadel_human_user.users[each.value].id
  role_keys  = [zitadel_project_role.immich_user.role_key]
}

resource "zitadel_user_grant" "immich_administrator" {
  org_id     = local.organization_id
  project_id = zitadel_project.immich.id
  user_id    = local.administrator_user_id
  role_keys  = [zitadel_project_role.immich_user.role_key]
}

output "immich_oidc_client_id" {
  value     = zitadel_application_oidc.immich.client_id
  sensitive = true
}

output "immich_oidc_client_secret" {
  value     = zitadel_application_oidc.immich.client_secret
  sensitive = true
}
