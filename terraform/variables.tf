variable "alert_email" {
  default     = ""
  description = "Email that receives the alarms and the budget notices; empty subscribes nothing"
  type        = string
}

variable "aws_region" {
  default = "eu-west-2"
  type    = string
}

variable "infra_subject" {
  default     = "repo:poly-glot@2133299/aws-cloud@1368316662"
  description = "This repository's OIDC subject prefix; its GitHub Actions may assume the infrastructure role"
  type        = string
}

variable "donation_admin_emails" {
  default     = []
  description = "Administrators invited to the donation admin console"
  type        = list(string)
}

variable "donation_console_url" {
  default     = "http://localhost:3000/admin.html"
  description = "Where Cognito sends the browser back after signing in to the donation console; the local console until the site has an address"
  type        = string
}

variable "donation_domain_live" {
  default     = false
  description = "Serve the donation site on its custom domain; set once its certificate is issued"
  type        = bool
}

variable "donation_stripe_secret_key" {
  default   = ""
  sensitive = true
  type      = string
}

variable "donation_stripe_webhook_secret" {
  default   = ""
  sensitive = true
  type      = string
}

variable "shorten_domain_live" {
  default     = false
  description = "Serve the shorten site on its custom domain; set once its certificate is issued"
  type        = bool
}

variable "shorten_public_base_url" {
  default     = ""
  description = "Origin of the short links the shorten mgmt function hands out, https://<distribution_domain> or the custom domain; set after the first apply, once the distribution has a name. Empty makes the function fall back to the request host, which behind CloudFront is the raw function URL"
  type        = string
}

variable "shorten_origin_verify" {
  default     = ""
  description = "Shared secret CloudFront sends as X-Origin-Verify to the shorten functions, which refuse any request without it"
  sensitive   = true
  type        = string
}

variable "txtlocal_domain_live" {
  default     = false
  description = "Serve the txtlocal site on its custom domain; set once its certificate is issued"
  type        = bool
}

variable "txtlocal_operator_secret" {
  default     = ""
  description = "The header value that authorises txtlocal's operator routes, such as approving a website registration"
  sensitive   = true
  type        = string

  validation {
    condition     = length(var.txtlocal_operator_secret) >= 32
    error_message = "Set TXTLOCAL_OPERATOR_SECRET to at least 32 random characters; an empty one would open the operator routes."
  }
}

variable "txtlocal_stripe_secret_key" {
  default     = ""
  description = "Stripe secret key for txtlocal; empty runs the deployed site on the scripted fake payment gateway"
  sensitive   = true
  type        = string
}

variable "txtlocal_stripe_webhook_secret" {
  default   = ""
  sensitive = true
  type      = string
}

variable "txtlocal_unsubscribe_secret" {
  default     = ""
  description = "HMAC key that signs txtlocal's per-recipient unsubscribe links"
  sensitive   = true
  type        = string

  validation {
    condition     = length(var.txtlocal_unsubscribe_secret) >= 32
    error_message = "Set TXTLOCAL_UNSUBSCRIBE_SECRET to at least 32 random characters; an empty key would let anyone forge unsubscribe links."
  }
}
