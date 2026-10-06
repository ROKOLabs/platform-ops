# Plan-only tests of the telemetry wiring, with every provider mocked. Run from
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

run "disabled_creates_no_telemetry" {
  command = plan

  variables {
    telemetry = { enabled = false }
  }

  assert {
    condition     = length(module.telemetry) == 0
    error_message = "telemetry.enabled = false must not create the telemetry module."
  }

  assert {
    condition     = length(aws_iam_role.otel_gateway) == 0 && length(aws_eks_pod_identity_association.otel_gateway) == 0
    error_message = "telemetry.enabled = false must not create the otel-gateway IAM role or its Pod Identity association."
  }

  assert {
    condition     = !contains(keys(local.platform_values.api), "otel")
    error_message = "telemetry.enabled = false must not set api.otel."
  }

  assert {
    condition     = output.telemetry_otlp_endpoint == null
    error_message = "telemetry_otlp_endpoint must be null when telemetry is disabled."
  }
}

run "enabled_without_endpoint_fails" {
  command = plan

  variables {
    telemetry = {}
  }

  expect_failures = [var.telemetry]
}

run "grpc_with_two_headers" {
  command = plan

  variables {
    telemetry = {
      endpoint = "https://otlp.example.com:4317"
      protocol = "grpc"
    }
    telemetry_headers = {
      "api-key"  = "key"
      "x-tenant" = "acme"
    }
  }

  assert {
    condition     = keys(module.telemetry[0].gateway_config.exporters) == ["otlp"]
    error_message = "protocol = grpc must use the otlp exporter."
  }

  assert {
    condition = module.telemetry[0].gateway_config.exporters.otlp.headers == {
      "api-key"  = "$${env:OTLP_HEADER_0}"
      "x-tenant" = "$${env:OTLP_HEADER_1}"
    }
    error_message = "Each header must be bound to its own OTLP_HEADER_<i> environment variable."
  }

  assert {
    condition     = local.platform_values.api.otel.endpoint == "http://otel-gateway.telemetry.svc.cluster.local:4318"
    error_message = "api.otel.endpoint must point at the gateway when telemetry is enabled."
  }

  assert {
    condition     = length(aws_iam_role.otel_gateway) == 1 && aws_eks_pod_identity_association.otel_gateway[0].service_account == "otel-gateway"
    error_message = "The gateway must get its IAM role through Pod Identity."
  }
}
