# External Secrets Operator: syncs Secrets Manager secrets into k8s Secrets,
# following rotation — a one-time stamped Secret would go stale.
resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "this" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "read" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.secret_arn_patterns
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "this" {
  name   = "read-secrets"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.read.json
}

# Auto Mode ships the Pod Identity agent; the controller's SA gets the role,
# and SecretStores with no auth block use the controller's credentials.
resource "aws_eks_pod_identity_association" "this" {
  cluster_name    = var.cluster_name
  namespace       = kubernetes_namespace_v1.this.metadata[0].name
  service_account = "external-secrets"
  role_arn        = aws_iam_role.this.arn
}
