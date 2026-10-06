# ── Telemetry ────────────────────────────────────────────────────────────────
#
# The shared `../telemetry` collector, plus what only AWS has: RDS host metrics
# from CloudWatch, read by a YACE sidecar on the gateway under its own Pod
# Identity role. `telemetry.enabled = false` removes every resource in this file
# and the API's OTLP endpoint with them.

locals {
  telemetry_enabled         = var.telemetry.enabled
  telemetry_deployment_name = coalesce(var.telemetry.deployment_name, var.name)
  telemetry_namespace       = "telemetry"

  # Merged into the API's chart values in main.tf.
  telemetry_api_values = {
    for k, v in { otel = { endpoint = one(module.telemetry[*].otlp_http_endpoint) } } : k => v
    if local.telemetry_enabled
  }

  # The CloudWatch metrics YACE reads for the platform database, every five
  # minutes, which is the resolution RDS publishes basic monitoring at.
  rds_metrics = [
    "CPUUtilization",
    "FreeableMemory",
    "FreeStorageSpace",
    "DatabaseConnections",
    "ReadLatency",
    "WriteLatency",
    "ReadIOPS",
    "WriteIOPS",
  ]

  yace_config = yamlencode({
    apiVersion   = "v1alpha1"
    "sts-region" = var.region
    static = [{
      name       = "rds"
      namespace  = "AWS/RDS"
      regions    = [var.region]
      dimensions = [{ name = "DBInstanceIdentifier", value = aws_db_instance.platform.identifier }]
      metrics = [for metric in local.rds_metrics : {
        name       = metric
        statistics = ["Average"]
        period     = 300
        length     = 300
      }]
    }]
  })
}

data "aws_iam_policy_document" "otel_gateway" {
  count = local.telemetry_enabled ? 1 : 0

  # GetMetricStatistics is what a YACE static job calls; GetMetricData and
  # ListMetrics are what its other job types call. None of the three supports
  # resource-level permissions.
  statement {
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "otel_gateway" {
  count = local.telemetry_enabled ? 1 : 0

  name               = "${var.name}-otel-gateway"
  assume_role_policy = data.aws_iam_policy_document.pods_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "otel_gateway" {
  count = local.telemetry_enabled ? 1 : 0

  name   = "cloudwatch-read"
  role   = aws_iam_role.otel_gateway[0].id
  policy = data.aws_iam_policy_document.otel_gateway[0].json
}

resource "aws_eks_pod_identity_association" "otel_gateway" {
  count = local.telemetry_enabled ? 1 : 0

  cluster_name    = module.cluster.cluster_name
  namespace       = local.telemetry_namespace
  service_account = "otel-gateway"
  role_arn        = aws_iam_role.otel_gateway[0].arn
}

module "telemetry" {
  source = "../telemetry"
  count  = local.telemetry_enabled ? 1 : 0

  namespace       = local.telemetry_namespace
  deployment_name = local.telemetry_deployment_name
  endpoint        = var.telemetry.endpoint
  protocol        = var.telemetry.protocol
  headers         = var.telemetry_headers

  # RDS presents a certificate signed by the Amazon RDS CA, which the collector
  # image does not carry. The connection stays encrypted inside the VPC.
  postgres = {
    host                     = aws_db_instance.platform.address
    port                     = aws_db_instance.platform.port
    database                 = aws_db_instance.platform.db_name
    username                 = aws_db_instance.platform.username
    password                 = random_password.db_master.result
    tls_insecure_skip_verify = true
  }

  gateway_extra_files = { "yace.yml" = local.yace_config }

  gateway_extra_containers = [{
    name  = "yace"
    image = "quay.io/prometheuscommunity/yet-another-cloudwatch-exporter:v0.68.0"
    args = [
      "--config.file=/etc/yace/yace.yml",
      "--listen-address=127.0.0.1:5000",
      "--scraping-interval=300",
    ]
    volumeMounts = [{ name = "gateway-files", mountPath = "/etc/yace", readOnly = true }]
    resources = {
      requests = { cpu = "10m", memory = "32Mi" }
      limits   = { memory = "128Mi" }
    }
  }]

  gateway_extra_receivers = {
    "prometheus/rds" = {
      config = {
        scrape_configs = [{
          job_name        = "rds"
          scrape_interval = "300s"
          static_configs  = [{ targets = ["127.0.0.1:5000"] }]
        }]
      }
    }
  }

  # A pod admitted before its Pod Identity association exists gets no AWS
  # credentials until it restarts.
  depends_on = [aws_eks_pod_identity_association.otel_gateway]
}
