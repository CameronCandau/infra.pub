resource "zitadel_human_user" "users" {
  # Resource addresses expose for_each keys, so only opaque IDs belong here.
  for_each = nonsensitive(toset(keys(var.users)))

  depends_on = [zitadel_instance_features.instance]

  org_id       = local.organization_id
  user_name    = var.users[each.key].user_name
  email        = var.users[each.key].email
  first_name   = var.users[each.key].first_name
  last_name    = var.users[each.key].last_name
  display_name = var.users[each.key].display_name
}
