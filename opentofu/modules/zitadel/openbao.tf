resource "zitadel_project" "openbao" {
  org_id                 = local.organization_id
  name                   = "OpenBao"
  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "openbao_admin" {
  org_id       = local.organization_id
  project_id   = zitadel_project.openbao.id
  role_key     = "openbao-admin"
  display_name = "OpenBao Administrator"
}

resource "zitadel_application_oidc" "openbao" {
  org_id     = local.organization_id
  project_id = zitadel_project.openbao.id
  name       = "OpenBao"

  redirect_uris = [
    "https://bao.${var.domain}/ui/vault/auth/oidc/oidc/callback",
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

resource "zitadel_user_grant" "openbao_administrator" {
  org_id     = local.organization_id
  project_id = zitadel_project.openbao.id
  user_id    = local.administrator_user_id
  role_keys  = [zitadel_project_role.openbao_admin.role_key]
}

output "openbao_oidc_client_id" {
  value     = zitadel_application_oidc.openbao.client_id
  sensitive = true
}

output "openbao_oidc_client_secret" {
  value     = zitadel_application_oidc.openbao.client_secret
  sensitive = true
}
