resource "zitadel_project" "nextcloud" {
  org_id             = local.organization_id
  name               = "Nextcloud"
  has_project_check  = true
  project_role_check = true
}

resource "zitadel_project_role" "nextcloud_user" {
  org_id       = local.organization_id
  project_id   = zitadel_project.nextcloud.id
  role_key     = "nextcloud-user"
  display_name = "Nextcloud User"
}

resource "zitadel_application_oidc" "nextcloud" {
  org_id     = local.organization_id
  project_id = zitadel_project.nextcloud.id
  name       = "Nextcloud"

  redirect_uris = [
    "https://cloud.${var.domain}/apps/user_oidc/code",
  ]
  post_logout_redirect_uris = [
    "https://cloud.${var.domain}/",
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

resource "zitadel_user_grant" "nextcloud_users" {
  for_each = var.nextcloud_user_keys

  org_id     = local.organization_id
  project_id = zitadel_project.nextcloud.id
  user_id    = zitadel_human_user.users[each.value].id
  role_keys  = [zitadel_project_role.nextcloud_user.role_key]
}

resource "zitadel_user_grant" "nextcloud_administrator" {
  org_id     = local.organization_id
  project_id = zitadel_project.nextcloud.id
  user_id    = local.administrator_user_id
  role_keys  = [zitadel_project_role.nextcloud_user.role_key]
}

output "nextcloud_oidc_client_id" {
  value     = zitadel_application_oidc.nextcloud.client_id
  sensitive = true
}

output "nextcloud_oidc_client_secret" {
  value     = zitadel_application_oidc.nextcloud.client_secret
  sensitive = true
}
