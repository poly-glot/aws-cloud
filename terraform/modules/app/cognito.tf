resource "aws_cognito_user_pool" "admins" {
  count = var.admins == null ? 0 : 1

  auto_verified_attributes = ["email"]
  deletion_protection      = "ACTIVE"
  mfa_configuration        = "OPTIONAL"
  name                     = "${var.name}-admins"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 3
  }

  software_token_mfa_configuration {
    enabled = true
  }
}

resource "aws_cognito_user_pool_client" "console" {
  count = var.admins == null ? 0 : 1

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid"]
  callback_urls                        = [var.admins.console_url]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret                      = false
  logout_urls                          = [var.admins.console_url]
  name                                 = "console"
  prevent_user_existence_errors        = "ENABLED"
  supported_identity_providers         = ["COGNITO"]
  user_pool_id                         = aws_cognito_user_pool.admins[0].id
}

resource "aws_cognito_user_pool_domain" "admins" {
  count = var.admins == null ? 0 : 1

  domain       = "${var.name}-admins"
  user_pool_id = aws_cognito_user_pool.admins[0].id
}

resource "aws_cognito_user" "admins" {
  for_each = var.admins == null ? toset([]) : toset(var.admins.emails)

  username     = each.value
  user_pool_id = aws_cognito_user_pool.admins[0].id

  attributes = {
    email          = each.value
    email_verified = true
  }
}
