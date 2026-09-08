module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  # /20 each — sized for pods, not nodes: the VPC CNI gives every pod a VPC IP.
  private_subnets = [for i, az in var.azs : cidrsubnet(var.cidr, 4, i)]

  # /24 each — load balancers and the NAT gateway only.
  public_subnets = [for i, az in var.azs : cidrsubnet(var.cidr, 8, i + 200)]

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
