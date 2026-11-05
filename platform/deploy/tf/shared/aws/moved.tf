moved {
  from = helm_release.agent_node_pool
  to   = helm_release.agent_node_pool[0]
}
moved {
  from = random_bytes.secret_encryption_key
  to   = random_bytes.secret_encryption_key[0]
}
moved {
  from = aws_secretsmanager_secret.secret_encryption
  to   = aws_secretsmanager_secret.secret_encryption[0]
}
moved {
  from = aws_secretsmanager_secret_version.secret_encryption
  to   = aws_secretsmanager_secret_version.secret_encryption[0]
}
