data "aws_iam_policy_document" "runtime_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "runtime" {
  statement {
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:TransactWriteItems",
      "dynamodb:UpdateItem",
    ]
    resources = [var.table.arn, "${var.table.arn}/index/*"]

    dynamic "condition" {
      for_each = var.key_prefix == null ? [] : [var.key_prefix]

      content {
        test     = "ForAllValues:StringLike"
        values   = ["${condition.value}*"]
        variable = "dynamodb:LeadingKeys"
      }
    }
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${var.name}-*"]
  }
}

resource "aws_iam_role" "runtime" {
  assume_role_policy = data.aws_iam_policy_document.runtime_trust.json
  name               = "${var.name}-runtime"
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${var.name}-runtime"
  policy = data.aws_iam_policy_document.runtime.json
  role   = aws_iam_role.runtime.id
}

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }

    condition {
      test     = "StringLike"
      values   = ["${var.github_subject}:*"]
      variable = "token.actions.githubusercontent.com:sub"
    }

    principals {
      identifiers = [var.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["lambda:GetFunction", "lambda:UpdateFunctionCode"]
    resources = concat([for function in aws_lambda_function.this : function.arn], aws_lambda_function.canary[*].arn)
  }

  statement {
    actions   = ["s3:DeleteObject", "s3:PutObject"]
    resources = ["${var.sites.bucket_arn}/${var.name}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.sites.bucket_arn]

    condition {
      test     = "StringLike"
      values   = ["${var.name}/*"]
      variable = "s3:prefix"
    }
  }

  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role" "deploy" {
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
  name               = "${var.name}-deploy"
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.name}-deploy"
  policy = data.aws_iam_policy_document.deploy.json
  role   = aws_iam_role.deploy.id
}
