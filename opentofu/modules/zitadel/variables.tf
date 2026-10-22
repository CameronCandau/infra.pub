variable "domain" {
  type = string

  validation {
    condition     = length(var.domain) <= 253 && can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.domain))
    error_message = "domain must be a lowercase FQDN without a scheme, path, port, wildcard, or trailing dot."
  }
}

variable "organization_name" {
  type = string
}

variable "administrator_user_name" {
  type = string
}

variable "users" {
  type = map(object({
    user_name    = string
    email        = string
    first_name   = string
    last_name    = string
    display_name = string
  }))
  sensitive = true
}

variable "smtp" {
  type = object({
    host             = string
    user             = string
    password         = string
    sender_address   = string
    sender_name      = string
    reply_to_address = string
    description      = string
  })
  sensitive = true
}

variable "immich_user_keys" {
  type = set(string)
}

