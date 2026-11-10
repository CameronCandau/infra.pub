resource "zitadel_project" "timetracker" {
  org_id             = local.organization_id
  name               = "TimeTracker"
  has_project_check  = true
  project_role_check = true
}

resource "zitadel_project_role" "timetracker_user" {
  org_id       = local.organization_id
  project_id   = zitadel_project.timetracker.id
  role_key     = "timetracker-user"
  display_name = "TimeTracker User"
}

resource "zitadel_application_oidc" "timetracker" {
  org_id     = local.organization_id
  project_id = zitadel_project.timetracker.id
  name       = "TimeTracker"

  redirect_uris = [
    "https://time.${var.domain}/auth/oidc/callback",
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

resource "zitadel_user_grant" "timetracker_users" {
  for_each = var.timetracker_user_keys

  org_id     = local.organization_id
  project_id = zitadel_project.timetracker.id
  user_id    = zitadel_human_user.users[each.value].id
  role_keys  = [zitadel_project_role.timetracker_user.role_key]
}

resource "zitadel_user_grant" "timetracker_administrator" {
  org_id     = local.organization_id
  project_id = zitadel_project.timetracker.id
  user_id    = local.administrator_user_id
  role_keys  = [zitadel_project_role.timetracker_user.role_key]
}

output "timetracker_oidc_client_id" {
  value     = zitadel_application_oidc.timetracker.client_id
  sensitive = true
}

output "timetracker_oidc_client_secret" {
  value     = zitadel_application_oidc.timetracker.client_secret
  sensitive = true
}
