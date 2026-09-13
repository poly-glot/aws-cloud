resource "aws_s3_bucket" "sites" {
  bucket = "${var.prefix}-sites-${var.account_id}"
}

resource "aws_s3_bucket_public_access_block" "sites" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.sites.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "sites" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.sites.arn}/*"]

    condition {
      test     = "StringEquals"
      values   = [var.account_id]
      variable = "AWS:SourceAccount"
    }

    principals {
      identifiers = ["cloudfront.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_s3_bucket_policy" "sites" {
  bucket = aws_s3_bucket.sites.id
  policy = data.aws_iam_policy_document.sites.json
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.prefix}-s3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "router" {
  code    = file("${path.module}/router.js")
  name    = "${var.prefix}-router"
  publish = true
  runtime = "cloudfront-js-2.0"
}

resource "aws_cloudfront_cache_policy" "api" {
  default_ttl = 30
  max_ttl     = 60
  min_ttl     = 0
  name        = "${var.prefix}-api"

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
      query_string_behavior = "all"
    }
  }
}
