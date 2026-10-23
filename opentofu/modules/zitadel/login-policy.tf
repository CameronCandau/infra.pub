resource "zitadel_login_policy" "organization" {
  org_id                        = local.organization_id
  user_login                    = true
  allow_register                = false
  allow_external_idp            = false
  force_mfa                     = false
  force_mfa_local_only          = false
  disable_login_with_email      = false
  passwordless_type             = "PASSWORDLESS_TYPE_ALLOWED"
  hide_password_reset           = true
  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  multi_factor_check_lifetime   = "24h0m0s"
  mfa_init_skip_lifetime        = "720h0m0s"
  second_factor_check_lifetime  = "24h0m0s"
  ignore_unknown_usernames      = true
  default_redirect_uri          = "https://auth.${var.domain}/ui/console/"

  multi_factors = [
    "MULTI_FACTOR_TYPE_U2F_WITH_VERIFICATION",
  ]
}
