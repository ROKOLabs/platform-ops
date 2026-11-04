# PR plans use a separate AWS read-only role. Helm stores release state in
# Secrets, which AmazonEKSViewPolicy excludes. This role reads all resource
# kinds managed by Terraform, and grants no create/update/delete or exec verbs.
resource "aws_eks_access_entry" "terraform_plan" {
  for_each          = toset(var.plan_principal_arns)
  cluster_name      = module.cluster.cluster_name
  principal_arn     = each.value
  kubernetes_groups = ["terraform-plan"]
  type              = "STANDARD"
}

resource "kubernetes_cluster_role_v1" "terraform_plan" {
  count = length(var.plan_principal_arns) > 0 ? 1 : 0
  metadata {
    name = "terraform-plan"
  }
  rule {
    api_groups = ["*"]
    # Do not wildcard resources: GET on pods/exec or service proxy
    # subresources can execute code even without write verbs.
    resources = [
      "namespaces", "secrets", "configmaps", "services", "serviceaccounts",
      "endpoints", "nodes", "pods", "persistentvolumes", "persistentvolumeclaims",
      "deployments", "replicasets", "daemonsets", "statefulsets", "jobs", "cronjobs",
      "roles", "rolebindings", "clusterroles", "clusterrolebindings",
      "networkpolicies", "ingresses", "ingressclasses", "ingressclassparams", "storageclasses",
      "customresourcedefinitions", "horizontalpodautoscalers", "poddisruptionbudgets",
      "externalsecrets", "secretstores", "clustersecretstores", "nodepools", "nodeclasses",
      "scaledobjects", "scaledjobs", "triggerauthentications", "clustertriggerauthentications",
    ]
    verbs = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "terraform_plan" {
  count = length(var.plan_principal_arns) > 0 ? 1 : 0
  metadata {
    name = "terraform-plan"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.terraform_plan[0].metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "terraform-plan"
    api_group = "rbac.authorization.k8s.io"
  }
}
