variable "account_id" {
  type = string
}

variable "alerts_topic_arn" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "donation_admin_emails" {
  default = []
  type    = list(string)
}

variable "donation_console_url" {
  type = string
}

variable "donation_domain_live" {
  default = false
  type    = bool
}

variable "donation_stripe_secret_key" {
  sensitive = true
  type      = string
}

variable "donation_stripe_webhook_secret" {
  sensitive = true
  type      = string
}

variable "sites" {
  type = object({
    api_cache_policy_id = string
    bucket              = string
    bucket_arn          = string
    bucket_domain       = string
    router_function_arn = string
    s3_oac_id           = string
  })
}

variable "table" {
  type = object({
    arn  = string
    name = string
  })
}
