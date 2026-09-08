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
  # terraform, so the entry flip-flops between the SSO role (local) and the
  # CI role and collides with cicd's entry. Admins are explicit, via
  # admin_role_arns, only.
  enable_cluster_creator_admin_permissions = false

  access_entries = merge(
    {
      for arn in var.admin_role_arns : "admin-${basename(arn)}" => {
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
      for arn in var.viewer_role_arns : "viewer-${basename(arn)}" => {
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
