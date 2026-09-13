resource "aws_iam_openid_connect_provider" "github" {
  client_id_list = ["sts.amazonaws.com"]
  url            = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "infra_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }

    condition {
      test     = "StringLike"
      values   = ["${var.infra_subject}:*"]
      variable = "token.actions.githubusercontent.com:sub"
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.github.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "infra" {
  assume_role_policy = data.aws_iam_policy_document.infra_trust.json
  name               = "${var.prefix}-terraform"
}

resource "aws_iam_role_policy_attachment" "infra_admin" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.infra.name
}
