# Plan-only tests of production availability and plan access (Chorus CR-694), with every provider mocked. Run from
# modules/aws:
#
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  # The AWS provider validates ARNs even under a mock, so the data sources that
  # ARNs are built from return real-looking values.
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
      arn        = "arn:aws:sts::111122223333:assumed-role/terraform/session"
    }
  }

  # The cluster access preflight compares this ARN against the admin list.
  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::111122223333:role/terraform"
    }
  }

  # IAM validates policy documents as JSON even under a mock.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "http" {}

variables {
  name                          = "acme-test"
  region                        = "us-east-1"
  azs                           = ["us-east-1a", "us-east-1b", "us-east-1c"]
  ingress_host                  = "acme.example.com"
  api_allowed_cidrs             = ["203.0.113.0/24"]
  restrict_origin_to_cloudflare = false
}

run "production_availability_and_plan_access" {
  command = plan
  variables {
    high_availability               = true
    grant_terraform_principal_admin = false
    admin_principal_arns            = ["arn:aws:iam::111122223333:role/deploy"]
    plan_principal_arns             = ["arn:aws:iam::111122223333:role/terraform"]
  }
  assert {
    condition     = aws_db_instance.platform.multi_az && length(module.network.nat_public_ips) == 3
    error_message = "HA must enable the RDS standby and a NAT gateway in each AZ."
  }
  assert {
    condition     = local.platform_values.api.highAvailability && local.platform_values.web.highAvailability
    error_message = "Both application services must enable chart availability constraints."
  }
  assert {
    condition     = toset(one(kubernetes_cluster_role_v1.terraform_plan[0].rule).verbs) == toset(["get", "list", "watch"])
    error_message = "The plan role must have read verbs only."
  }
  assert {
    condition     = alltrue([for resource in one(kubernetes_cluster_role_v1.terraform_plan[0].rule).resources : resource != "*" && !strcontains(resource, "/")])
    error_message = "The plan role must not grant exec, proxy, or other subresource access."
  }
  assert {
    condition     = toset(local.admin_principal_arns) == toset(["arn:aws:iam::111122223333:role/deploy"])
    error_message = "A PR plan must not add the plan principal to the administrators."
  }
}

run "trusted_proxy_hops_ingress_only" {
  command = plan

  variables {
    restrict_origin_to_cloudflare = false
  }

  assert {
    condition     = local.platform_values.api.trustedProxyHops == 1
    error_message = "Without Cloudflare the API must trust the ingress alone."
  }
}

run "trusted_proxy_hops_behind_cloudflare" {
  command = plan

  variables {
    restrict_origin_to_cloudflare = true
  }

  override_data {
    target = data.http.cloudflare_ips[0]
    values = {
      response_body = "{\"result\":{\"ipv4_cidrs\":[\"173.245.48.0/20\"],\"ipv6_cidrs\":[\"2400:cb00::/32\"]}}"
    }
  }

  assert {
    condition     = local.platform_values.api.trustedProxyHops == 2
    error_message = "Behind Cloudflare the API must trust Cloudflare and the ingress."
  }
}
