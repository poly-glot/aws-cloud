output "wiring" {
  value = {
    api_cache_policy_id = aws_cloudfront_cache_policy.api.id
    bucket              = aws_s3_bucket.sites.bucket
    bucket_arn          = aws_s3_bucket.sites.arn
    bucket_domain       = aws_s3_bucket.sites.bucket_regional_domain_name
    router_function_arn = aws_cloudfront_function.router.arn
    s3_oac_id           = aws_cloudfront_origin_access_control.s3.id
  }
}
