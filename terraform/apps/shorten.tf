locals {
  managed_caching_disabled = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  shorten_viewer_headers = [
    "CloudFront-Is-Android-Viewer",
    "CloudFront-Is-Desktop-Viewer",
    "CloudFront-Is-IOS-Viewer",
    "CloudFront-Is-Mobile-Viewer",
    "CloudFront-Is-SmartTV-Viewer",
    "CloudFront-Is-Tablet-Viewer",
    "CloudFront-Viewer-Country",
    "CloudFront-Viewer-Country-Region",
  ]
}

resource "aws_cloudfront_function" "shorten_segment" {
  code    = <<-JS
    function handler(event) {
        var request = event.request;
        request.querystring = { s: { value: 'XX%7CXX%7Cother%7Cother' } };
        return request;
    }
  JS
  comment = "Placeholder; the shorten repository publishes edge/segment.js over it"
  name    = "shorten-segment"
  publish = true
  runtime = "cloudfront-js-2.0"

  lifecycle {
    ignore_changes = [code]
  }
}

resource "aws_cloudfront_cache_policy" "shorten" {
  default_ttl = 300
  max_ttl     = 3600
  min_ttl     = 0
  name        = "shorten-code"

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "whitelist"

      query_strings {
        items = ["s"]
      }
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "shorten" {
  name = "shorten-viewer"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = local.shorten_viewer_headers
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

module "shorten" {
  providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }
  source    = "../modules/app"

  account_id        = var.account_id
  alerts_topic_arn  = var.alerts_topic_arn
  analytics         = var.analytics
  aws_region        = var.aws_region
  github_subject    = "repo:poly-glot@2133299/shorten@1370097581"
  name              = "shorten"
  oidc_provider_arn = var.oidc_provider_arn
  sites             = var.sites
  table             = var.table

  api_cache_policy_id                 = local.managed_caching_disabled
  default_cache_policy_id             = aws_cloudfront_cache_policy.shorten.id
  default_origin_function             = "redirect"
  default_origin_request_policy_id    = aws_cloudfront_origin_request_policy.shorten.id
  default_viewer_request_function_arn = aws_cloudfront_function.shorten_segment.arn
  domain                              = { live = var.shorten_domain_live, name = "shorten.junaid.guru" }
  key_prefix                          = "shorten#"

  origin_header       = "X-Origin-Verify"
  origin_header_value = var.shorten_origin_verify

  secrets = {
    ORIGIN_VERIFY = var.shorten_origin_verify
  }

  functions = {
    mgmt     = { env = { PUBLIC_BASE_URL = var.shorten_public_base_url }, errors_alarm = true, timeout = 10, url = "api" }
    redirect = { errors_alarm = true, timeout = 5, url = "public" }
    rollup   = { concurrency = 1, schedule = "cron(15 2 * * ? *)", timeout = 900 }
  }

  custom_alarms = {
    rollup-failed = {
      description        = "The nightly shorten rollup errored, or did not run"
      dimensions         = { FunctionName = "shorten-rollup" }
      metric_name        = "Errors"
      namespace          = "AWS/Lambda"
      period             = 86400
      statistic          = "Sum"
      threshold          = 0
      treat_missing_data = "breaching"
    }
  }
}
