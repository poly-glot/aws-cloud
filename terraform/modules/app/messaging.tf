resource "aws_sqs_queue" "dead_letter" {
  for_each = var.queues

  message_retention_seconds = 1209600
  name                      = "${var.name}-${each.key}-dlq"
}

resource "aws_sqs_queue" "this" {
  for_each = var.queues

  name = "${var.name}-${each.key}"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  })
  visibility_timeout_seconds = 6 * var.functions[each.value.consumer].timeout
}

resource "aws_lambda_event_source_mapping" "queues" {
  for_each = var.queues

  batch_size              = each.value.batch_size
  event_source_arn        = aws_sqs_queue.this[each.key].arn
  function_name           = aws_lambda_function.this[each.value.consumer].arn
  function_response_types = ["ReportBatchItemFailures"]

  dynamic "scaling_config" {
    for_each = each.value.max_concurrency == null ? [] : [each.value.max_concurrency]

    content {
      maximum_concurrency = scaling_config.value
    }
  }

  depends_on = [aws_iam_role_policy.runtime]
}

resource "aws_sns_topic" "this" {
  for_each = var.topics

  name = "${var.name}-${each.key}"
}

resource "aws_sns_topic_subscription" "this" {
  for_each = var.topics

  endpoint  = aws_lambda_function.this[each.value.subscriber].arn
  protocol  = "lambda"
  topic_arn = aws_sns_topic.this[each.key].arn
}

resource "aws_lambda_permission" "topics" {
  for_each = var.topics

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.value.subscriber].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.this[each.key].arn
}
