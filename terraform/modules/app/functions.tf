data "aws_servicequotas_service_quota" "lambda_concurrency" {
  quota_code   = "L-B99A9384"
  service_code = "lambda"
}

locals {
  analytics_env = var.analytics == null ? {} : {
    ATHENA_OUTPUT    = "s3://${var.analytics.results_bucket}/"
    ATHENA_WORKGROUP = var.analytics.athena_workgroup
    GLUE_DATABASE    = var.analytics.glue_database
    GLUE_TABLE       = var.analytics.glue_table
    LOGS_BUCKET      = var.analytics.logs_bucket
  }
  base_env = merge({ METRIC_NAMESPACE = var.name, TABLE_NAME = var.table.name }, local.analytics_env, var.env, var.secrets)
  console_env = var.admins == null ? {} : {
    COGNITO_CLIENT_ID = aws_cognito_user_pool_client.console[0].id
    COGNITO_ISSUER    = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.admins[0].id}"
  }
  canary_schedule = try(var.canary.interval_minutes, 1) == 1 ? "rate(1 minute)" : "rate(${try(var.canary.interval_minutes, 1)} minutes)"
  reservable      = data.aws_servicequotas_service_quota.lambda_concurrency.value > 100
  routed          = { for key, function in var.functions : function.url => key if function.url != null && function.url != "public" }
  scheduled       = { for key, function in var.functions : key => function.schedule if function.schedule != null }
  with_url        = { for key, function in var.functions : key => function.url if function.url != null }
}

resource "aws_cloudwatch_log_group" "functions" {
  for_each = var.functions

  name              = "/aws/lambda/${var.name}-${each.key}"
  retention_in_days = 90
}

resource "aws_lambda_function" "this" {
  for_each = var.functions

  architectures                  = ["arm64"]
  filename                       = "${path.module}/placeholder.zip"
  function_name                  = "${var.name}-${each.key}"
  handler                        = "bootstrap"
  memory_size                    = each.value.memory
  reserved_concurrent_executions = local.reservable ? each.value.concurrency : -1
  role                           = aws_iam_role.runtime.arn
  runtime                        = "provided.al2023"
  source_code_hash               = filebase64sha256("${path.module}/placeholder.zip")
  timeout                        = each.value.timeout

  environment {
    variables = merge(local.base_env, each.value.console ? local.console_env : {}, each.value.env)
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_cloudwatch_log_group.functions, aws_iam_role_policy.runtime]
}

resource "aws_lambda_function_url" "this" {
  for_each = local.with_url

  authorization_type = "NONE"
  function_name      = aws_lambda_function.this[each.key].function_name
}

resource "aws_lambda_permission" "url" {
  for_each = local.with_url

  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this[each.key].function_name
  function_url_auth_type = "NONE"
  principal              = "*"
  statement_id           = "AllowPublicFunctionUrl"
}

resource "aws_lambda_permission" "url_invoke" {
  for_each = local.with_url

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.key].function_name
  principal     = "*"
  statement_id  = "AllowPublicFunctionUrlInvoke"
}

resource "aws_cloudwatch_event_rule" "schedule" {
  for_each = local.scheduled

  name                = "${var.name}-${each.key}"
  schedule_expression = each.value
}

resource "aws_cloudwatch_event_target" "schedule" {
  for_each = local.scheduled

  arn       = aws_lambda_function.this[each.key].arn
  rule      = aws_cloudwatch_event_rule.schedule[each.key].name
  target_id = each.key
}

resource "aws_lambda_permission" "schedule" {
  for_each = local.scheduled

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[each.key].arn
}

resource "aws_cloudwatch_log_group" "canary" {
  count = var.canary == null ? 0 : 1

  name              = "/aws/lambda/${var.name}-canary"
  retention_in_days = 90
}

resource "aws_lambda_function" "canary" {
  count = var.canary == null ? 0 : 1

  architectures                  = ["arm64"]
  filename                       = "${path.module}/placeholder.zip"
  function_name                  = "${var.name}-canary"
  handler                        = "bootstrap"
  memory_size                    = 128
  reserved_concurrent_executions = local.reservable ? 1 : -1
  role                           = aws_iam_role.runtime.arn
  runtime                        = "provided.al2023"
  source_code_hash               = filebase64sha256("${path.module}/placeholder.zip")
  timeout                        = 10

  environment {
    variables = {
      BROWSE_URL       = "https://${local.site_domain}${var.canary.path}"
      METRIC_NAMESPACE = var.name
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_cloudwatch_log_group.canary, aws_iam_role_policy.runtime]
}

resource "aws_lambda_function_event_invoke_config" "canary" {
  count = var.canary == null ? 0 : 1

  function_name          = aws_lambda_function.canary[0].function_name
  maximum_retry_attempts = 0
}

resource "aws_cloudwatch_event_rule" "canary" {
  count = var.canary == null ? 0 : 1

  name                = "${var.name}-canary"
  schedule_expression = local.canary_schedule
}

resource "aws_cloudwatch_event_target" "canary" {
  count = var.canary == null ? 0 : 1

  arn       = aws_lambda_function.canary[0].arn
  rule      = aws_cloudwatch_event_rule.canary[0].name
  target_id = "canary"
}

resource "aws_lambda_permission" "canary" {
  count = var.canary == null ? 0 : 1

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.canary[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.canary[0].arn
}
