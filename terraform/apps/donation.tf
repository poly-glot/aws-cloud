module "donation" {
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  source    = "../modules/app"

  account_id        = var.account_id
  alerts_topic_arn  = var.alerts_topic_arn
  aws_region        = var.aws_region
  github_subject    = "repo:poly-glot@2133299/donation@1368321996"
  name              = "donation"
  oidc_provider_arn = var.oidc_provider_arn
  sites             = var.sites
  table             = var.table

  domain     = { live = var.donation_domain_live, name = "donation.junaid.guru" }
  key_prefix = "donation#"

  secrets = {
    STRIPE_SECRET_KEY     = var.donation_stripe_secret_key
    STRIPE_WEBHOOK_SECRET = var.donation_stripe_webhook_secret
  }

  admins = {
    console_url = var.donation_console_url
    emails      = var.donation_admin_emails
  }

  functions = {
    admin               = { console = true, timeout = 30, url = "api/admin" }
    api                 = { errors_alarm = true, throttles_alarm = true, timeout = 10, url = "api" }
    draw-run            = { concurrency = 1, console = true, timeout = 900, url = "api/draw" }
    reconcile           = { concurrency = 1, schedule = "cron(0 6 * * ? *)", timeout = 900 }
    stripe-webhook      = { errors_alarm = true, url = "public" }
    subscription-charge = { concurrency = 1, errors_alarm = true, schedule = "rate(1 hour)", timeout = 900 }
  }

  canary         = { interval_minutes = 5, path = "/api/raffles/current" }
  http_5xx_alarm = true

  custom_alarms = {
    integrity-violations = {
      description        = "The daily reconciliation found a broken invariant, or did not run"
      metric_name        = "IntegrityViolations"
      period             = 86400
      statistic          = "Maximum"
      threshold          = 0
      treat_missing_data = "breaching"
    }
    subscription-charge-lag = {
      description = "A raffle has been open for more than 3 hours without a completed subscription charge run"
      metric_name = "SubscriptionChargeLagHours"
      period      = 3600
      statistic   = "Maximum"
      threshold   = 3
    }
  }
}
