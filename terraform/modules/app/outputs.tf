output "wiring" {
  value = {
    cognito_client_id   = one(concat(aws_cognito_user_pool_client.console[*].id, aws_cognito_user_pool_client.users[*].id))
    cognito_domain      = one([for domain in concat(aws_cognito_user_pool_domain.admins, aws_cognito_user_pool_domain.users) : "https://${domain.domain}.auth.${var.aws_region}.amazoncognito.com"])
    deploy_role_arn     = aws_iam_role.deploy.arn
    distribution_domain = aws_cloudfront_distribution.site.domain_name
    distribution_id     = aws_cloudfront_distribution.site.id
    domain_validation = var.domain == null ? null : {
      name  = one(aws_acm_certificate.site[0].domain_validation_options).resource_record_name
      type  = one(aws_acm_certificate.site[0].domain_validation_options).resource_record_type
      value = one(aws_acm_certificate.site[0].domain_validation_options).resource_record_value
    }
    function_urls = { for key, url in aws_lambda_function_url.this : key => url.function_url }
    functions     = concat([for function in aws_lambda_function.this : function.function_name], aws_lambda_function.canary[*].function_name)
    site_url      = "https://${local.site_domain}"
    sites_bucket  = var.sites.bucket
    sites_prefix  = var.name
  }
}
