locals {
  budget_alerts = [
    { threshold = 80, type = "ACTUAL" },
    { threshold = 100, type = "ACTUAL" },
    { threshold = 100, type = "FORECASTED" },
  ]
}

resource "aws_sns_topic" "alerts" {
  name = "${var.prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  endpoint  = var.alert_email
  protocol  = "email"
  topic_arn = aws_sns_topic.alerts.arn
}

resource "aws_budgets_budget" "monthly" {
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  name         = "${var.prefix}-monthly"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.alert_email == "" ? [] : local.budget_alerts

    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = notification.value.type
      subscriber_email_addresses = [var.alert_email]
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
    }
  }
}
