# Preserve all existing client state addresses when introducing the wrapper.
moved {
  from = aws_acm_certificate.origin
  to   = module.implementation.aws_acm_certificate.origin
}
moved {
  from = aws_db_instance.platform
  to   = module.implementation.aws_db_instance.platform
}
moved {
  from = aws_db_subnet_group.db
  to   = module.implementation.aws_db_subnet_group.db
}
moved {
  from = aws_eks_access_entry.terraform_plan
  to   = module.implementation.aws_eks_access_entry.terraform_plan
}
moved {
  from = aws_eks_pod_identity_association.agent
  to   = module.implementation.aws_eks_pod_identity_association.agent
}
moved {
  from = aws_eks_pod_identity_association.api
  to   = module.implementation.aws_eks_pod_identity_association.api
}
moved {
  from = aws_eks_pod_identity_association.otel_gateway
  to   = module.implementation.aws_eks_pod_identity_association.otel_gateway
}
moved {
  from = aws_iam_role.agent
  to   = module.implementation.aws_iam_role.agent
}
moved {
  from = aws_iam_role.api
  to   = module.implementation.aws_iam_role.api
}
moved {
  from = aws_iam_role.otel_gateway
  to   = module.implementation.aws_iam_role.otel_gateway
}
moved {
  from = aws_iam_role_policy.agent_bedrock
  to   = module.implementation.aws_iam_role_policy.agent_bedrock
}
moved {
  from = aws_iam_role_policy.agent_checkpoints
  to   = module.implementation.aws_iam_role_policy.agent_checkpoints
}
moved {
  from = aws_iam_role_policy.api_bedrock
  to   = module.implementation.aws_iam_role_policy.api_bedrock
}
moved {
  from = aws_iam_role_policy.api_checkpoints
  to   = module.implementation.aws_iam_role_policy.api_checkpoints
}
moved {
  from = aws_iam_role_policy.api_uploads
  to   = module.implementation.aws_iam_role_policy.api_uploads
}
moved {
  from = aws_iam_role_policy.otel_gateway
  to   = module.implementation.aws_iam_role_policy.otel_gateway
}
moved {
  from = aws_s3_bucket.checkpoints
  to   = module.implementation.aws_s3_bucket.checkpoints
}
moved {
  from = aws_s3_bucket.uploads
  to   = module.implementation.aws_s3_bucket.uploads
}
moved {
  from = aws_s3_bucket_cors_configuration.uploads
  to   = module.implementation.aws_s3_bucket_cors_configuration.uploads
}
moved {
  from = aws_s3_bucket_lifecycle_configuration.checkpoints
  to   = module.implementation.aws_s3_bucket_lifecycle_configuration.checkpoints
}
moved {
  from = aws_s3_bucket_lifecycle_configuration.uploads
  to   = module.implementation.aws_s3_bucket_lifecycle_configuration.uploads
}
moved {
  from = aws_s3_bucket_public_access_block.checkpoints
  to   = module.implementation.aws_s3_bucket_public_access_block.checkpoints
}
moved {
  from = aws_s3_bucket_public_access_block.uploads
  to   = module.implementation.aws_s3_bucket_public_access_block.uploads
}
moved {
  from = aws_s3_bucket_server_side_encryption_configuration.checkpoints
  to   = module.implementation.aws_s3_bucket_server_side_encryption_configuration.checkpoints
}
moved {
  from = aws_s3_bucket_versioning.uploads
  to   = module.implementation.aws_s3_bucket_versioning.uploads
}
moved {
  from = aws_secretsmanager_secret.db_master
  to   = module.implementation.aws_secretsmanager_secret.db_master
}
moved {
  from = aws_secretsmanager_secret.root_token
  to   = module.implementation.aws_secretsmanager_secret.root_token
}
moved {
  from = aws_secretsmanager_secret.secret_encryption
  to   = module.implementation.aws_secretsmanager_secret.secret_encryption
}
moved {
  from = aws_secretsmanager_secret.telemetry_headers
  to   = module.implementation.aws_secretsmanager_secret.telemetry_headers
}
moved {
  from = aws_secretsmanager_secret_version.db_master
  to   = module.implementation.aws_secretsmanager_secret_version.db_master
}
moved {
  from = aws_secretsmanager_secret_version.root_token
  to   = module.implementation.aws_secretsmanager_secret_version.root_token
}
moved {
  from = aws_secretsmanager_secret_version.secret_encryption
  to   = module.implementation.aws_secretsmanager_secret_version.secret_encryption
}
moved {
  from = aws_security_group.db
  to   = module.implementation.aws_security_group.db
}
moved {
  from = aws_vpc_security_group_ingress_rule.db_from_cluster
  to   = module.implementation.aws_vpc_security_group_ingress_rule.db_from_cluster
}
moved {
  from = helm_release.agent_node_pool
  to   = module.implementation.helm_release.agent_node_pool
}
moved {
  from = helm_release.keda
  to   = module.implementation.helm_release.keda
}
moved {
  from = helm_release.platform
  to   = module.implementation.helm_release.platform
}
moved {
  from = kubernetes_cluster_role_binding_v1.terraform_plan
  to   = module.implementation.kubernetes_cluster_role_binding_v1.terraform_plan
}
moved {
  from = kubernetes_cluster_role_v1.terraform_plan
  to   = module.implementation.kubernetes_cluster_role_v1.terraform_plan
}
moved {
  from = kubernetes_namespace_v1.agents
  to   = module.implementation.kubernetes_namespace_v1.agents
}
moved {
  from = kubernetes_namespace_v1.keda
  to   = module.implementation.kubernetes_namespace_v1.keda
}
moved {
  from = kubernetes_namespace_v1.service
  to   = module.implementation.kubernetes_namespace_v1.service
}
moved {
  from = module.agent_ecr
  to   = module.implementation.module.agent_ecr
}
moved {
  from = module.api_ecr
  to   = module.implementation.module.api_ecr
}
moved {
  from = module.baseline
  to   = module.implementation.module.baseline
}
moved {
  from = module.budget
  to   = module.implementation.module.budget
}
moved {
  from = module.cluster
  to   = module.implementation.module.cluster
}
moved {
  from = module.external_secrets
  to   = module.implementation.module.external_secrets
}
moved {
  from = module.network
  to   = module.implementation.module.network
}
moved {
  from = module.telemetry
  to   = module.implementation.module.telemetry
}
moved {
  from = module.web_ecr
  to   = module.implementation.module.web_ecr
}
moved {
  from = random_bytes.secret_encryption_key
  to   = module.implementation.random_bytes.secret_encryption_key
}
moved {
  from = random_password.db_master
  to   = module.implementation.random_password.db_master
}
moved {
  from = random_password.root_token
  to   = module.implementation.random_password.root_token
}
moved {
  from = terraform_data.cluster_access_preflight
  to   = module.implementation.terraform_data.cluster_access_preflight
}
moved {
  from = terraform_data.wait_for_load_balancer
  to   = module.implementation.terraform_data.wait_for_load_balancer
}
moved {
  from = time_static.db
  to   = module.implementation.time_static.db
}
moved {
  from = tls_private_key.origin
  to   = module.implementation.tls_private_key.origin
}
moved {
  from = tls_self_signed_cert.origin
  to   = module.implementation.tls_self_signed_cert.origin
}
