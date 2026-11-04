resource "zitadel_project" "netbird" {
  org_id = local.organization_id
  name   = "NetBird"
}

resource "zitadel_application_oidc" "netbird" {
  org_id     = local.organization_id
  project_id = zitadel_project.netbird.id
  name       = "NetBird"

  redirect_uris = [
    "https://netbird.${var.domain}/oauth2/callback",
  ]
  post_logout_redirect_uris = [
    "https://netbird.${var.domain}/oauth2/logout/callback",
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

output "netbird_oidc_client_id" {
  value     = zitadel_application_oidc.netbird.client_id
  sensitive = true
}

output "netbird_oidc_client_secret" {
  value     = zitadel_application_oidc.netbird.client_secret
  sensitive = true
}
