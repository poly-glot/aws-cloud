output "wiring" {
  value = {
    athena_workgroup     = aws_athena_workgroup.analytics.name
    athena_workgroup_arn = aws_athena_workgroup.analytics.arn
    glue_arns = [
      "arn:aws:glue:${var.aws_region}:${var.account_id}:catalog",
      aws_glue_catalog_database.analytics.arn,
      aws_glue_catalog_table.cloudfront_logs.arn,
    ]
    glue_database       = aws_glue_catalog_database.analytics.name
    glue_table          = aws_glue_catalog_table.cloudfront_logs.name
    log_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront.arn
    log_record_fields   = local.log_record_fields
    logs_bucket         = aws_s3_bucket.logs.bucket
    logs_bucket_arn     = aws_s3_bucket.logs.arn
    results_bucket      = aws_s3_bucket.results.bucket
    results_bucket_arn  = aws_s3_bucket.results.arn
  }
}
