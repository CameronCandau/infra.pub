resource "zitadel_project" "kimai" {
  org_id             = local.organization_id
  name               = "Kimai"
  has_project_check  = true
  project_role_check = true
}

resource "zitadel_project_role" "kimai_admin" {
  org_id       = local.organization_id
  project_id   = zitadel_project.kimai.id
  role_key     = "kimai-admin"
  display_name = "Kimai Administrator"
}

resource "zitadel_application_saml" "kimai" {
  org_id       = local.organization_id
  project_id   = zitadel_project.kimai.id
  name         = "Kimai"
  metadata_url = "https://time.${var.domain}/auth/saml/metadata"

  login_version {
    login_v1 = true
  }
}

resource "zitadel_user_grant" "kimai_users" {
  for_each = var.kimai_user_keys

  org_id     = local.organization_id
  project_id = zitadel_project.kimai.id
  user_id    = zitadel_human_user.users[each.value].id
  role_keys  = [zitadel_project_role.kimai_admin.role_key]
}

resource "zitadel_user_grant" "kimai_administrator" {
  org_id     = local.organization_id
  project_id = zitadel_project.kimai.id
  user_id    = local.administrator_user_id
  role_keys  = [zitadel_project_role.kimai_admin.role_key]
}

resource "zitadel_action" "kimai_roles" {
  org_id          = local.organization_id
  name            = "kimaiRoles"
  timeout         = "10s"
  allowed_to_fail = false
  script          = <<-JS
    function kimaiRoles(ctx, api) {
      if (ctx.v1.user.grants == undefined || ctx.v1.user.grants.count == 0) {
        return;
      }
      let roles = [];
      ctx.v1.user.grants.grants.forEach(grant => {
        if (grant.projectId == '${zitadel_project.kimai.id}') {
          grant.roles.forEach(role => roles.push(role));
        }
      });
      if (roles.length > 0) {
        api.v1.attributes.setCustomAttribute('KimaiRoles', '', ...roles);
      }
    }
  JS
}

resource "zitadel_trigger_actions" "kimai_roles" {
  org_id       = local.organization_id
  flow_type    = "FLOW_TYPE_SAML_RESPONSE"
  trigger_type = "TRIGGER_TYPE_PRE_SAML_RESPONSE_CREATION"
  action_ids   = [zitadel_action.kimai_roles.id]
}
