output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "oidc_provider_arn" {
  value = local.oidc_arn
}
