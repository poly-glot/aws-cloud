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

resource "aws_cognito_user_pool" "users" {
  count = var.users == null ? 0 : 1

  auto_verified_attributes = ["email"]
  deletion_protection      = "ACTIVE"
  mfa_configuration        = "OFF"
  name                     = "${var.name}-users"
  username_attributes      = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
}

resource "aws_cognito_user_pool_client" "users" {
  count = var.users == null ? 0 : 1

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid"]
  callback_urls                        = var.users.callback_urls
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret                      = false
  logout_urls                          = var.users.logout_urls
  name                                 = "site"
  prevent_user_existence_errors        = "ENABLED"
  supported_identity_providers         = ["COGNITO"]
  user_pool_id                         = aws_cognito_user_pool.users[0].id
}

resource "aws_cognito_user_pool_domain" "users" {
  count = var.users == null ? 0 : 1

  domain       = "${var.name}-users"
  user_pool_id = aws_cognito_user_pool.users[0].id
}
