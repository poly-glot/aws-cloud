module "txtlocal" {
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  source    = "../modules/app"

  account_id        = var.account_id
  alerts_topic_arn  = var.alerts_topic_arn
  analytics         = var.analytics
  aws_region        = var.aws_region
  github_subject    = "repo:poly-glot@2133299/txtlocal@1384238265"
  name              = "txtlocal"
  oidc_provider_arn = var.oidc_provider_arn
  sites             = var.sites
  table             = var.table

  domain           = { live = var.txtlocal_domain_live, name = "txtlocal.junaid.guru" }
  key_prefix       = "txtlocal#"
  media            = true
  runtime          = "python3.14"
  strip_api_prefix = false

  env = {
    API_BASE_URL    = "https://txtlocal.junaid.guru"
    API_LOG_GROUP   = "/aws/lambda/txtlocal-api"
    BUS             = "sqs"
    PUBLIC_BASE_URL = "https://txtlocal.junaid.guru"
    SEND_LOG_GROUP  = "/aws/lambda/txtlocal-send-worker"
    SMS_MODE        = "fake"
  }

  secrets = {
    OPERATOR_SECRET       = var.txtlocal_operator_secret
    STRIPE_SECRET_KEY     = var.txtlocal_stripe_secret_key
    STRIPE_WEBHOOK_SECRET = var.txtlocal_stripe_webhook_secret
    UNSUBSCRIBE_SECRET    = var.txtlocal_unsubscribe_secret
  }

  users = {
    callback_urls = ["https://txtlocal.junaid.guru/auth/callback"]
    logout_urls   = ["https://txtlocal.junaid.guru/"]
  }

  functions = {
    api              = { handler = "txtlocal.entrypoints.api.handler", log_retention_days = 7, queryable = true, timeout = 29, url = "api" }
    billing-charge   = { concurrency = 1, handler = "txtlocal.entrypoints.billing_charge.handler", timeout = 60 }
    billing-renewals = { concurrency = 1, handler = "txtlocal.entrypoints.billing_renewals.handler", schedule = "cron(30 6 * * ? *)", timeout = 900 }
    delivery-events  = { handler = "txtlocal.entrypoints.delivery_events.handler" }
    inbound          = { handler = "txtlocal.entrypoints.inbound.handler" }
    redirect         = { handler = "txtlocal.entrypoints.redirect.handler", timeout = 5, url = "l" }
    rollup           = { concurrency = 1, handler = "txtlocal.entrypoints.rollup.handler", schedule = "cron(30 2 * * ? *)", timeout = 900 }
    scheduler        = { concurrency = 1, handler = "txtlocal.entrypoints.scheduler.handler", schedule = "rate(1 minute)", timeout = 60 }
    send-worker      = { handler = "txtlocal.entrypoints.send_worker.handler", log_retention_days = 120, queryable = true, timeout = 60 }
    stripe-webhook   = { handler = "txtlocal.entrypoints.stripe_webhook.handler", timeout = 10, url = "public" }
    webhook-dispatch = { handler = "txtlocal.entrypoints.webhook_dispatch.handler" }
  }

  queues = {
    recharge  = { batch_size = 1, consumer = "billing-charge", env = "RECHARGE_QUEUE_URL" }
    send-jobs = { consumer = "send-worker", env = "SEND_QUEUE_URL", max_concurrency = 2 }
    webhooks  = { batch_size = 1, consumer = "webhook-dispatch", env = "WEBHOOK_QUEUE_URL", max_concurrency = 2 }
  }

  topics = {
    sms-events  = { env = "SMS_EVENTS_TOPIC_ARN", subscriber = "delivery-events" }
    sms-inbound = { env = "SMS_INBOUND_TOPIC_ARN", subscriber = "inbound" }
  }
}
