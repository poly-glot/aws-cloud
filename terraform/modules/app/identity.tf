locals {
  analytics_statements = var.analytics == null ? [] : [
    {
      actions = [
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:GetWorkGroup",
        "athena:StartQueryExecution",
      ]
      resources = [var.analytics.athena_workgroup_arn]
    },
    {
      actions = [
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:GetPartition",
        "glue:GetPartitions",
        "glue:GetTable",
        "glue:GetTables",
      ]
      resources = var.analytics.glue_arns
    },
    {
      actions   = ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"]
      resources = [var.analytics.logs_bucket_arn, "${var.analytics.logs_bucket_arn}/*"]
    },
    {
      actions = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
      ]
      resources = [var.analytics.results_bucket_arn, "${var.analytics.results_bucket_arn}/*"]
    },
  ]
  queryable_log_groups = [for key in local.queryable : "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${var.name}-${key}"]
  resource_statements = concat(
    length(var.queues) == 0 ? [] : [{
      actions   = ["sqs:ChangeMessageVisibility", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ReceiveMessage", "sqs:SendMessage"]
      resources = [for queue in aws_sqs_queue.this : queue.arn]
    }],
    length(var.topics) == 0 ? [] : [{
      actions   = ["sns:Publish"]
      resources = [for topic in aws_sns_topic.this : topic.arn]
    }],
    var.users == null ? [] : [{
      actions   = ["cognito-idp:AdminCreateUser"]
      resources = aws_cognito_user_pool.users[*].arn
    }],
    var.media ? [{
      actions   = ["s3:PutObject"]
      resources = [for bucket in aws_s3_bucket.media : "${bucket.arn}/media/*"]
    }] : [],
    length(local.queryable) == 0 ? [] : [
      {
        actions   = ["logs:StartQuery"]
        resources = concat(local.queryable_log_groups, [for group in local.queryable_log_groups : "${group}:*"])
      },
      {
        actions   = ["logs:GetQueryResults", "logs:StopQuery"]
        resources = ["*"]
      },
    ],
  )
}

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
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
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

  dynamic "statement" {
    for_each = local.resource_statements

    content {
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }

  dynamic "statement" {
    for_each = local.analytics_statements

    content {
      actions   = statement.value.actions
      resources = statement.value.resources
    }
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

  dynamic "statement" {
    for_each = var.seed_partition == null ? [] : [var.seed_partition]

    content {
      actions   = ["dynamodb:PutItem"]
      resources = [var.table.arn]

      condition {
        test     = "ForAllValues:StringEquals"
        values   = [statement.value]
        variable = "dynamodb:LeadingKeys"
      }
    }
  }

  dynamic "statement" {
    for_each = var.default_viewer_request_function_arn == null ? [] : [var.default_viewer_request_function_arn]

    content {
      actions = [
        "cloudfront:DescribeFunction",
        "cloudfront:GetFunction",
        "cloudfront:PublishFunction",
        "cloudfront:UpdateFunction",
      ]
      resources = [statement.value]
    }
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
