# Plan-only tests of the render Job wiring (Roko CR-475), with every provider
# mocked. Run from modules/aws:
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

run "defaults" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.render_node_pool.values[0]) == { name = "renders", idleTimeout = "30s", nodeClassRef = { group = "eks.amazonaws.com", kind = "NodeClass", name = "default" } }
    error_message = "The renders NodePool must come from the agent-node-pool chart, named renders, on the EKS default NodeClass."
  }

  assert {
    condition     = helm_release.render_node_pool.chart == "${path.module}/../agent-node-pool" && helm_release.render_node_pool.namespace == "kube-system"
    error_message = "The renders NodePool must come from the local agent-node-pool chart."
  }

  assert {
    condition     = kubernetes_namespace_v1.renders.metadata[0].name == "renders"
    error_message = "The renders namespace must exist for the chart's Role and the API's Jobs."
  }

  assert {
    condition     = aws_secretsmanager_secret.render.name == "acme-test/api-render"
    error_message = "The signing secret must sit under the deployment's name prefix, which ESO already reads."
  }

  assert {
    condition     = local.platform_values.api.renders == { enabled = true, namespace = "renders", secretName = "acme-test/api-render", nodePool = "renders", warmPool = { enabled = true, spares = 1 } }
    error_message = "api.renders must turn render Jobs on, on the renders pool, with one spare and the api-render secret."
  }
}

run "no_spares" {
  command = plan

  variables {
    render_warm_spares = 0
  }

  assert {
    condition     = local.platform_values.api.renders.warmPool == { enabled = false, spares = 0 }
    error_message = "render_warm_spares = 0 must turn the placeholders off."
  }
}

run "no_builtin_node_pool_fails_the_plan" {
  command = plan

  variables {
    node_pools = []
  }

  expect_failures = [helm_release.agent_node_pool, helm_release.render_node_pool]
}
