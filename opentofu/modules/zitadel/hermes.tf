resource "zitadel_project" "hermes" {
  org_id                 = local.organization_id
  name                   = "Hermes"
  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "hermes_administrator" {
  org_id       = local.organization_id
  project_id   = zitadel_project.hermes.id
  role_key     = "hermes-administrator"
  display_name = "Hermes Administrator"
}

resource "zitadel_application_oidc" "hermes" {
  org_id     = local.organization_id
  project_id = zitadel_project.hermes.id
  name       = "Hermes"

  redirect_uris = [
    "https://hermes.${var.domain}/auth/callback",
  ]

  response_types    = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types       = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]
  app_type          = "OIDC_APP_TYPE_WEB"
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_NONE"
  version           = "OIDC_VERSION_1_0"
  dev_mode          = false
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"

  login_version {
    login_v1 = true
  }
}

resource "zitadel_user_grant" "hermes_administrator" {
  org_id     = local.organization_id
  project_id = zitadel_project.hermes.id
  user_id    = local.administrator_user_id
  role_keys  = [zitadel_project_role.hermes_administrator.role_key]
}

output "hermes_oidc_client_id" {
  value     = zitadel_application_oidc.hermes.client_id
  sensitive = true
}
