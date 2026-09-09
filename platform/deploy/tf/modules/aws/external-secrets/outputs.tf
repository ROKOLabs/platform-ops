output "role_arn" { value = aws_iam_role.this.arn }
output "namespace" { value = kubernetes_namespace_v1.this.metadata[0].name }
