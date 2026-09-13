locals {
  free_capacity = {
    table = { read = 15, write = 15 }
    GSI1  = { read = 5, write = 5 }
    GSI2  = { read = 5, write = 5 }
  }
  throttle_metrics = toset(["ReadThrottleEvents", "WriteThrottleEvents"])
}

resource "aws_dynamodb_table" "shared" {
  billing_mode                = "PROVISIONED"
  deletion_protection_enabled = true
  hash_key                    = "PK"
  name                        = var.prefix
  range_key                   = "SK"
  read_capacity               = local.free_capacity.table.read
  stream_enabled              = true
  stream_view_type            = "NEW_AND_OLD_IMAGES"
  write_capacity              = local.free_capacity.table.write

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  attribute {
    name = "GSI2PK"
    type = "S"
  }

  global_secondary_index {
    hash_key        = "GSI1PK"
    name            = "GSI1"
    projection_type = "ALL"
    range_key       = "GSI1SK"
    read_capacity   = local.free_capacity.GSI1.read
    write_capacity  = local.free_capacity.GSI1.write
  }

  global_secondary_index {
    hash_key        = "GSI2PK"
    name            = "GSI2"
    projection_type = "ALL"
    read_capacity   = local.free_capacity.GSI2.read
    write_capacity  = local.free_capacity.GSI2.write
  }

  point_in_time_recovery {
    enabled = false
  }
}

resource "aws_cloudwatch_metric_alarm" "throttles" {
  for_each = local.throttle_metrics

  alarm_actions       = [var.alerts_topic_arn]
  alarm_description   = "The shared table throttled requests (${each.key}); raise its provisioned capacity"
  alarm_name          = "${var.prefix}-table-${lower(each.key)}"
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { TableName = aws_dynamodb_table.shared.name }
  evaluation_periods  = 1
  metric_name         = each.key
  namespace           = "AWS/DynamoDB"
  ok_actions          = [var.alerts_topic_arn]
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
}
