locals {
  cloudfront_log_prefix  = "AWSLogs/${var.account_id}/CloudFront"
  database               = replace(var.prefix, "-", "_")
  log_retention_days     = 90
  projected_years        = "2025,2035"
  results_retention_days = 7
  scan_cutoff_bytes      = 1073741824

  log_columns = [
    { name = "date", type = "date" },
    { name = "time", type = "string" },
    { name = "x_edge_location", type = "string" },
    { name = "sc_bytes", type = "bigint" },
    { name = "c_ip", type = "string" },
    { name = "cs_method", type = "string" },
    { name = "cs_host", type = "string" },
    { name = "cs_uri_stem", type = "string" },
    { name = "sc_status", type = "int" },
    { name = "cs_referer", type = "string" },
    { name = "cs_user_agent", type = "string" },
    { name = "cs_uri_query", type = "string" },
    { name = "cs_cookie", type = "string" },
    { name = "x_edge_result_type", type = "string" },
    { name = "x_edge_request_id", type = "string" },
    { name = "x_host_header", type = "string" },
    { name = "cs_protocol", type = "string" },
    { name = "cs_bytes", type = "bigint" },
    { name = "time_taken", type = "float" },
    { name = "x_forwarded_for", type = "string" },
    { name = "ssl_protocol", type = "string" },
    { name = "ssl_cipher", type = "string" },
    { name = "x_edge_response_result_type", type = "string" },
    { name = "cs_protocol_version", type = "string" },
    { name = "fle_status", type = "string" },
    { name = "fle_encrypted_fields", type = "int" },
    { name = "c_port", type = "int" },
    { name = "time_to_first_byte", type = "float" },
    { name = "x_edge_detailed_result_type", type = "string" },
    { name = "sc_content_type", type = "string" },
    { name = "sc_content_len", type = "bigint" },
    { name = "sc_range_start", type = "bigint" },
    { name = "sc_range_end", type = "bigint" },
  ]

  log_partitions = ["year", "month", "day"]
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.prefix}-logs-${var.account_id}"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.logs.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    expiration {
      days = local.log_retention_days
    }

    filter {}
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]

    condition {
      test     = "StringEquals"
      values   = [var.account_id]
      variable = "aws:SourceAccount"
    }

    principals {
      identifiers = ["delivery.logs.amazonaws.com"]
      type        = "Service"
    }
  }

  statement {
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.logs.arn]

    condition {
      test     = "StringEquals"
      values   = [var.account_id]
      variable = "aws:SourceAccount"
    }

    principals {
      identifiers = ["delivery.logs.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront" {
  provider = aws.us_east_1

  name          = "${var.prefix}-cloudfront-logs"
  output_format = "w3c"

  delivery_destination_configuration {
    destination_resource_arn = aws_s3_bucket.logs.arn
  }
}

resource "aws_s3_bucket" "results" {
  bucket = "${var.prefix}-athena-${var.account_id}"
}

resource "aws_s3_bucket_public_access_block" "results" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.results.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    expiration {
      days = local.results_retention_days
    }

    filter {}
  }
}

resource "aws_athena_workgroup" "analytics" {
  force_destroy = true
  name          = "${var.prefix}-analytics"

  configuration {
    bytes_scanned_cutoff_per_query     = local.scan_cutoff_bytes
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.bucket}/"
    }
  }
}

resource "aws_glue_catalog_database" "analytics" {
  name = local.database
}

resource "aws_glue_catalog_table" "cloudfront_logs" {
  database_name = aws_glue_catalog_database.analytics.name
  name          = "cloudfront_logs"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                  = "TRUE"
    "has_encrypted_data"        = "false"
    "projection.day.digits"     = "2"
    "projection.day.range"      = "1,31"
    "projection.day.type"       = "integer"
    "projection.enabled"        = "true"
    "projection.month.digits"   = "2"
    "projection.month.range"    = "1,12"
    "projection.month.type"     = "integer"
    "projection.year.digits"    = "4"
    "projection.year.range"     = local.projected_years
    "projection.year.type"      = "integer"
    "skip.header.line.count"    = "2"
    "storage.location.template" = "s3://${aws_s3_bucket.logs.bucket}/${local.cloudfront_log_prefix}/$${year}/$${month}/$${day}"
  }

  dynamic "partition_keys" {
    for_each = local.log_partitions

    content {
      name = partition_keys.value
      type = "string"
    }
  }

  storage_descriptor {
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    location      = "s3://${aws_s3_bucket.logs.bucket}/${local.cloudfront_log_prefix}/"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    dynamic "columns" {
      for_each = local.log_columns

      content {
        name = columns.value.name
        type = columns.value.type
      }
    }

    ser_de_info {
      parameters            = { "field.delim" = "\t", "serialization.format" = "\t" }
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }
  }
}
