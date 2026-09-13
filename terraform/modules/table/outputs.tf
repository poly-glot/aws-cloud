output "wiring" {
  value = {
    arn  = aws_dynamodb_table.shared.arn
    name = aws_dynamodb_table.shared.name
  }
}
