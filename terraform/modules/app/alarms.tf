locals {
  errors_alarms    = { for key, function in var.functions : key => function if function.errors_alarm }
  throttles_alarms = { for key, function in var.functions : key => function if function.throttles_alarm }
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  for_each = local.errors_alarms

  alarm_actions       = [var.alerts_topic_arn]
  alarm_description   = "${var.name}-${each.key} crashed or timed out in the last 15 minutes"
  alarm_name          = "${var.name}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { FunctionName = aws_lambda_function.this[each.key].function_name }
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  ok_actions          = [var.alerts_topic_arn]
  period              = 900
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "throttles" {
  for_each = local.throttles_alarms

  alarm_actions       = [var.alerts_topic_arn]
  alarm_description   = "${var.name}-${each.key} invocations were throttled"
  alarm_name          = "${var.name}-${each.key}-throttles"
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { FunctionName = aws_lambda_function.this[each.key].function_name }
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  ok_actions          = [var.alerts_topic_arn]
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "canary" {
  count = var.canary == null ? 0 : 1

  alarm_actions       = [var.alerts_topic_arn]
  alarm_description   = "${var.name} canary failed twice in a row, or stopped running"
  alarm_name          = "${var.name}-canary"
  comparison_operator = "GreaterThanThreshold"
  datapoints_to_alarm = 2
  dimensions          = { FunctionName = aws_lambda_function.canary[0].function_name }
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  ok_actions          = [var.alerts_topic_arn]
  period              = var.canary.interval_minutes * 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  for_each = var.http_5xx_alarm ? local.with_url : {}

  log_group_name = aws_cloudwatch_log_group.functions[each.key].name
  name           = "${var.name}-${each.key}-http-5xx"
  pattern        = "{ $.status >= 500 }"

  metric_transformation {
    default_value = 0
    name          = "Http5xx"
    namespace     = var.name
    value         = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  count = var.http_5xx_alarm ? 1 : 0

  alarm_actions       = [var.alerts_topic_arn]
  alarm_description   = "${var.name} answered 5xx five or more times in 5 minutes"
  alarm_name          = "${var.name}-http-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Http5xx"
  namespace           = var.name
  ok_actions          = [var.alerts_topic_arn]
  period              = 300
  statistic           = "Sum"
  threshold           = 4
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "custom" {
  for_each = var.custom_alarms

  alarm_actions       = [var.alerts_topic_arn]
  alarm_description   = each.value.description
  alarm_name          = "${var.name}-${each.key}"
  comparison_operator = each.value.comparison_operator
  dimensions          = each.value.dimensions
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = coalesce(each.value.namespace, var.name)
  ok_actions          = [var.alerts_topic_arn]
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data
}
