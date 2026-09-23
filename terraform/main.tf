terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "poly-glot-aws-cloud-state"
    key          = "terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  prefix     = "aws-cloud"
}

module "github_oidc" {
  source = "./modules/github-oidc"

  infra_subject = var.infra_subject
  prefix        = local.prefix
}

module "alerts" {
  source = "./modules/alerts"

  alert_email = var.alert_email
  prefix      = local.prefix
}

module "table" {
  source = "./modules/table"

  alerts_topic_arn = module.alerts.topic_arn
  prefix           = local.prefix
}

module "analytics" {
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  source    = "./modules/analytics"

  account_id = local.account_id
  aws_region = var.aws_region
  prefix     = local.prefix
}

module "sites" {
  source = "./modules/sites"

  account_id = local.account_id
  prefix     = local.prefix
}

module "apps" {
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  source    = "./apps"

  account_id        = local.account_id
  alerts_topic_arn  = module.alerts.topic_arn
  analytics         = module.analytics.wiring
  aws_region        = var.aws_region
  oidc_provider_arn = module.github_oidc.provider_arn
  sites             = module.sites.wiring
  table             = module.table.wiring

  donation_admin_emails          = var.donation_admin_emails
  donation_console_url           = var.donation_console_url
  donation_domain_live           = var.donation_domain_live
  donation_stripe_secret_key     = var.donation_stripe_secret_key
  donation_stripe_webhook_secret = var.donation_stripe_webhook_secret

  shorten_domain_live     = var.shorten_domain_live
  shorten_origin_verify   = var.shorten_origin_verify
  shorten_public_base_url = var.shorten_public_base_url
}
