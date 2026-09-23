resource "aws_s3_bucket" "media" {
  count = var.media ? 1 : 0

  bucket = "${var.name}-media-${var.account_id}"
}

resource "aws_s3_bucket_public_access_block" "media" {
  count = var.media ? 1 : 0

  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.media[0].id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "media" {
  count = var.media ? 1 : 0

  bucket = aws_s3_bucket.media[0].id

  cors_rule {
    allowed_headers = ["content-type"]
    allowed_methods = ["PUT"]
    allowed_origins = compact(["https://${aws_cloudfront_distribution.site.domain_name}", try("https://${var.domain.name}", null)])
    max_age_seconds = 3000
  }
}

data "aws_iam_policy_document" "media" {
  count = var.media ? 1 : 0

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.media[0].arn}/media/*"]

    condition {
      test     = "StringEquals"
      values   = [aws_cloudfront_distribution.site.arn]
      variable = "AWS:SourceArn"
    }

    principals {
      identifiers = ["cloudfront.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_s3_bucket_policy" "media" {
  count = var.media ? 1 : 0

  bucket = aws_s3_bucket.media[0].id
  policy = data.aws_iam_policy_document.media[0].json

  depends_on = [aws_s3_bucket_public_access_block.media]
}
