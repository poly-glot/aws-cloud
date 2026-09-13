locals {
  live_domain                           = try(var.domain.live, false) ? var.domain.name : null
  managed_all_viewer_except_host_header = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  managed_cache_optimized               = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  site_domain                           = coalesce(local.live_domain, aws_cloudfront_distribution.site.domain_name)
}

resource "aws_acm_certificate" "site" {
  count    = var.domain == null ? 0 : 1
  provider = aws.us_east_1

  domain_name       = var.domain.name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "site" {
  count    = local.live_domain == null ? 0 : 1
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.site[0].arn
}

resource "aws_cloudfront_distribution" "site" {
  aliases             = local.live_domain == null ? [] : [local.live_domain]
  comment             = var.name
  default_root_object = "index.html"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"

  origin {
    domain_name              = var.sites.bucket_domain
    origin_access_control_id = var.sites.s3_oac_id
    origin_id                = "site"
    origin_path              = "/${var.name}"
  }

  dynamic "origin" {
    for_each = local.routed

    content {
      domain_name = trimsuffix(trimprefix(aws_lambda_function_url.this[origin.value].function_url, "https://"), "/")
      origin_id   = origin.key

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cache_policy_id        = local.managed_cache_optimized
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    target_origin_id       = "site"
    viewer_protocol_policy = "redirect-to-https"

    function_association {
      event_type   = "viewer-request"
      function_arn = var.sites.router_function_arn
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = reverse(sort(keys(local.routed)))

    content {
      allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cache_policy_id          = var.sites.api_cache_policy_id
      cached_methods           = ["GET", "HEAD"]
      compress                 = true
      origin_request_policy_id = local.managed_all_viewer_except_host_header
      path_pattern             = "/${ordered_cache_behavior.value}*"
      target_origin_id         = ordered_cache_behavior.value
      viewer_protocol_policy   = "https-only"

      function_association {
        event_type   = "viewer-request"
        function_arn = var.sites.router_function_arn
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = one(aws_acm_certificate_validation.site[*].certificate_arn)
    cloudfront_default_certificate = local.live_domain == null
    minimum_protocol_version       = local.live_domain == null ? "TLSv1" : "TLSv1.2_2021"
    ssl_support_method             = local.live_domain == null ? null : "sni-only"
  }
}
