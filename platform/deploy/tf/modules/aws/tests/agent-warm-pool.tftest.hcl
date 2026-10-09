# Plan-only tests of the agent warm pool wiring (Roko CR-379), with every provider mocked. Run from
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

run "defaults" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.agent_node_pool.values[0]) == { name = "agents", idleTimeout = "30s", cpuLimit = 64, nodeClassRef = { group = "eks.amazonaws.com", kind = "NodeClass", name = "default" } }
    error_message = "The agents NodePool must consolidate after 30s, cap at 64 CPU and reference the EKS default NodeClass."
  }

  assert {
    condition     = helm_release.agent_node_pool.chart == "${path.module}/../agent-node-pool" && helm_release.agent_node_pool.namespace == "kube-system"
    error_message = "The agents NodePool must come from the local agent-node-pool chart."
  }

  assert {
    condition     = helm_release.keda.chart == "keda" && helm_release.keda.version == "2.20.2" && helm_release.keda.namespace == "keda"
    error_message = "KEDA must be installed from the kedacore chart at 2.20.2 into the keda namespace."
  }

  assert {
    condition     = local.platform_values.api.agents.nodePool == "agents"
    error_message = "api.agents.nodePool must select the agents NodePool."
  }

  assert {
    condition     = local.platform_values.api.agents.warmPool.enabled == true
    error_message = "api.agents.warmPool.enabled must be true where KEDA is installed."
  }
}

run "tunables" {
  command = plan

  variables {
    agent_node_idle_timeout   = "5m"
    agent_node_pool_cpu_limit = 32
    keda_chart_version        = "2.21.0"
  }

  assert {
    condition     = yamldecode(helm_release.agent_node_pool.values[0]).idleTimeout == "5m" && yamldecode(helm_release.agent_node_pool.values[0]).cpuLimit == 32
    error_message = "The idle timeout and the CPU limit must come from the variables."
  }

  assert {
    condition     = helm_release.keda.version == "2.21.0"
    error_message = "The KEDA chart version must come from the variable."
  }
}

run "no_builtin_node_pool_fails_the_plan" {
  command = plan

  variables {
    node_pools = []
  }

  expect_failures = [helm_release.agent_node_pool]
}
