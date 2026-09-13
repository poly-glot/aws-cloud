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
