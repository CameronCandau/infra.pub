resource "zitadel_email_provider_smtp" "smtp" {
  host             = var.smtp.host
  user             = var.smtp.user
  password         = var.smtp.password
  sender_address   = var.smtp.sender_address
  sender_name      = var.smtp.sender_name
  reply_to_address = var.smtp.reply_to_address
  description      = nonsensitive(var.smtp.description)
  tls              = true
  set_active       = true
}
