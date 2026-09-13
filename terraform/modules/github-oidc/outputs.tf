output "infra_role_arn" {
  value = aws_iam_role.infra.arn
}

output "provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
