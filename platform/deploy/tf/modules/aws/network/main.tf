locals {
  zone_bits = ceil(log(length(var.azs), 2))

  # Private subnets are sized for pods, not nodes: the VPC CNI gives every pod a
  # VPC IP, so they take half the range, one per zone. Public subnets hold only
  # load balancers and the NAT gateway, so they take an eighth and sit at the top
  # of the range, leaving the middle free to grow into.
  #
  # On the default /22 with two zones that is a /24 per zone for pods and a /26
  # per zone for load balancers. Three zones on a /22 still works, at a /25 and a
  # /27; a deployment wanting three large zones should widen the CIDR instead.
  derived_private_subnets = [for i, az in var.azs : cidrsubnet(var.cidr, local.zone_bits + 1, i)]
  derived_public_subnets  = [for i, az in var.azs : cidrsubnet(var.cidr, local.zone_bits + 3, pow(2, local.zone_bits + 3) - length(var.azs) + i)]

  private_subnets = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : local.derived_private_subnets
  public_subnets  = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : local.derived_public_subnets
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = var.tags
}

# Free S3 gateway endpoint — ECR image layers and Terraform state live in S3.
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  create_security_group = false

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
      tags            = { Name = "${var.name}-s3" }
    }
  }

  tags = var.tags
}
