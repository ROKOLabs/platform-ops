module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs
  endpoint_private_access      = true

  # Auto Mode: AWS manages nodes (Karpenter), the VPC CNI, CoreDNS,
  # kube-proxy, the EBS CSI driver, and the LB controller.
  compute_config = {
    enabled    = true
    node_pools = var.node_pools
  }

  # metrics-server is NOT part of Auto Mode's managed set — HPA, `kubectl top`,
  # and the scheduler's resource metrics all need it, so we add it explicitly.
  # most_recent picks the default add-on version compatible with the cluster's
  # Kubernetes version, so it tracks version bumps without a hand-maintained pin.
  addons = {
    metrics-server = {
      most_recent = true
    }
  }

  # Never enable creator-admin: it keys an access entry off whoever runs
  # terraform, captured at creation, and names it in a way this module cannot
  # address afterwards. Every principal is explicit, through
  # admin_principal_arns, which the composed module fills with the applying
  # identity as well as anyone the deployment names.
  enable_cluster_creator_admin_permissions = false

  # Keyed by the whole ARN rather than by basename: two principals whose ARNs end
  # in the same name would otherwise collapse into one entry, and the one that
  # lost would silently have no access. distinct() lets a caller list the same
  # principal twice, which happens when it merges in the identity applying it.
  access_entries = merge(
    {
      for arn in distinct(var.admin_principal_arns) : "admin-${arn}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      for arn in distinct(var.viewer_principal_arns) : "viewer-${arn}" => {
        principal_arn = arn
        policy_associations = {
          viewer = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
  )

  tags = var.tags
}
