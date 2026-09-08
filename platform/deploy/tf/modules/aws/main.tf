# One composed module per cloud: a deployment sets one `source` and this module
# owns the whole thing — network, cluster, database, object storage, registries,
# budget, secrets, and the Helm releases that run the platform.
#
# `main.tf` sits beside the child directories, so `…//modules/aws` roots here and
# each child resolves as `./network`, `./eks-cluster` and so on. Every child is
# still a valid module on its own; nothing here depends on that.

locals {
  tags = merge(
    {
      Project   = var.name
      ManagedBy = "terraform"
    },
    var.tags,
  )

  # Empty `image_tag` means the release this module is. Only a lane that builds
  # its own images sets it (Roko's dev deployment, at a `sha-` tag).
  image_tag = var.image_tag != "" ? var.image_tag : local.platform_version

  uploads_bucket     = var.uploads_bucket_name != "" ? var.uploads_bucket_name : "${var.name}-uploads"
  checkpoints_bucket = var.checkpoints_bucket_name != "" ? var.checkpoints_bucket_name : "${var.name}-agent-checkpoints"

  ecr_repositories = {
    for image in ["api", "web", "agent"] :
    image => coalesce(lookup(var.ecr_repository_names, image, null), "${var.name}-${image}")
  }
}

data "aws_caller_identity" "current" {}

# ── Network and cluster ──────────────────────────────────────────────────────

module "network" {
  source = "./network"

  name                 = var.name
  cidr                 = var.vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.tags
}

module "cluster" {
  source = "./eks-cluster"

  name               = var.name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  api_allowed_cidrs  = var.api_allowed_cidrs
  admin_role_arns    = var.admin_role_arns
  viewer_role_arns   = var.viewer_role_arns
  tags               = local.tags
}

module "baseline" {
  source = "./cluster-baseline"
}

# ── Database ─────────────────────────────────────────────────────────────────

# Auto Mode nodes attach the cluster's primary security group, so allowing that
# one group covers every pod without tracking node groups.
resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres access from the EKS cluster"
  vpc_id      = module.network.vpc_id

  tags = merge(local.tags, { Name = "${var.name}-db" })
}

resource "aws_vpc_security_group_ingress_rule" "db_from_cluster" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = module.cluster.cluster_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.name}-db"
  subnet_ids = module.network.private_subnet_ids
  tags       = local.tags
}

# Static, self-managed master password — deliberately NOT the RDS-managed one.
# The API reads DATABASE_URL from its pod env once at startup and never re-reads
# it, so RDS's automatic 7-day rotation silently breaks every query between
# deploys. Holding the password here means it never changes underneath a running
# pod. The trade-off is that the value lives in the (encrypted, remote) state.
resource "random_password" "db_master" {
  length = 32
  # The password lands unencoded in DATABASE_URL's userinfo
  # (postgres://user:PASSWORD@host), which the app parses with the WHATWG URL
  # parser. On top of RDS Postgres forbidding '/', '@', '"' and space, that rules
  # out three more: '#' and '?' make new URL() throw, and '%' is mis-read as a
  # percent-escape on decode.
  override_special = "!$^&*()-_=+[]{}:."
}

resource "aws_db_instance" "platform" {
  identifier     = "${var.name}-platform"
  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name           = "platform"
  username          = "roko"
  password          = random_password.db_master.result
  apply_immediately = true

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_days
  copy_tags_to_snapshot   = true

  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-platform-final"

  tags = local.tags
}

# ── Secrets ──────────────────────────────────────────────────────────────────
#
# Terraform generates every secret this deployment needs. The module takes no
# secret as an input, so there is no value for a deployment to paste in and none
# for a public repository to leak. External Secrets Operator projects them into
# the namespace; the grant below is one name prefix, so a new secret is a change
# here alone.

# Written in the same JSON shape ({username, password}) the RDS-managed secret
# used, so the roko-api chart's ExternalSecret and its DATABASE_URL template need
# no change.
resource "aws_secretsmanager_secret" "db_master" {
  name = "${var.name}/db-master"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = aws_db_instance.platform.username
    password = random_password.db_master.result
  })
}

# AES-256-GCM key the API encrypts stored model-provider and code-host
# credentials with. It used to be created by hand, and a deployment that forgot
# it lost the feature with no error at deploy time.
resource "random_bytes" "secret_encryption_key" {
  length = 32
}

resource "aws_secretsmanager_secret" "secret_encryption" {
  name = "${var.name}/api-secret-encryption"
  tags = local.tags
}

# The chart's ExternalSecret reads SECRET_ENCRYPTION_KEY out of this JSON, so
# the shape is part of the contract.
resource "aws_secretsmanager_secret_version" "secret_encryption" {
  secret_id     = aws_secretsmanager_secret.secret_encryption.id
  secret_string = jsonencode({ SECRET_ENCRYPTION_KEY = random_bytes.secret_encryption_key.base64 })
}

# ── Object storage ───────────────────────────────────────────────────────────

resource "aws_s3_bucket" "uploads" {
  bucket = local.uploads_bucket
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# The browser PUTs and GETs this bucket directly through presigned URLs, so it
# must allow the frontend origin cross-origin. ExposeHeaders lets the browser
# read the ETag the confirm step records.
resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_origins = length(var.artifact_cors_origins) > 0 ? var.artifact_cors_origins : ["https://${var.ingress_host}"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Agent run checkpoints: a working-tree archive plus the opencode session export,
# written by the pod's supervisor so a blocked or retried run resumes where it
# stopped. Kept apart from uploads because a session export carries tool output,
# which can echo a token — so this bucket is encrypted, never public, and its
# objects are short-lived by policy as well as by the backend deleting them.
resource "aws_s3_bucket" "checkpoints" {
  bucket = local.checkpoints_bucket
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "checkpoints" {
  bucket = aws_s3_bucket.checkpoints.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "checkpoints" {
  bucket = aws_s3_bucket.checkpoints.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# The backend deletes a run's archives when it reaches a terminal state and a
# daily sweep catches the rest; this expiry is the backstop for anything both
# miss. The bucket is unversioned, so an expiry is a real delete.
resource "aws_s3_bucket_lifecycle_configuration" "checkpoints" {
  bucket = aws_s3_bucket.checkpoints.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = var.agent_checkpoint_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ── Registries ───────────────────────────────────────────────────────────────

module "api_ecr" {
  source = "./ecr-repo"
  name   = local.ecr_repositories.api
}

module "web_ecr" {
  source = "./ecr-repo"
  name   = local.ecr_repositories.web
}

module "agent_ecr" {
  source = "./ecr-repo"
  name   = local.ecr_repositories.agent
}

# ── Workload identity ────────────────────────────────────────────────────────

data "aws_iam_policy_document" "pods_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# Least privilege: PutObject to sign uploads, GetObject to sign downloads and to
# HEAD-confirm. Soft delete means no s3:DeleteObject is ever needed.
data "aws_iam_policy_document" "api_uploads" {
  statement {
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.uploads.arn}/*"]
  }
}

# The API only ever removes checkpoints: it deletes a run's archives when the run
# reaches a terminal state, and the daily sweep clears the rest. Writing is the
# pod's job, so there is no PutObject here.
data "aws_iam_policy_document" "api_checkpoints" {
  statement {
    actions   = ["s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.checkpoints.arn}/${var.agent_checkpoint_prefix}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.checkpoints.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.agent_checkpoint_prefix}/*"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "${var.name}-api"
  assume_role_policy = data.aws_iam_policy_document.pods_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "api_uploads" {
  name   = "uploads-read-write"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api_uploads.json
}

resource "aws_iam_role_policy" "api_checkpoints" {
  name   = "checkpoints-cleanup"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api_checkpoints.json
}

resource "aws_eks_pod_identity_association" "api" {
  cluster_name    = module.cluster.cluster_name
  namespace       = kubernetes_namespace_v1.service.metadata[0].name
  service_account = "roko-api"
  role_arn        = aws_iam_role.api.arn
}

# The `agent` service account gets its own identity, deliberately separate from
# the API's. Invoking a model and writing its own checkpoints is all a run needs,
# so that is all this grants: no uploads bucket, no Secrets Manager, nothing the
# API can touch. The MCP token and the GitHub credential are injected as env at
# launch, never carried by this role.
data "aws_iam_policy_document" "agent_bedrock" {
  statement {
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = var.agent_bedrock_model_arns
  }

  # Bedrock serves OpenAI's models over a second endpoint that authenticates with
  # a bearer token instead of signing each request. The pod derives a short-term
  # one from this same role, but using it is its own action under a second
  # service prefix: a run with only the `bedrock` action fails with "not
  # authorized to perform: bedrock-mantle:CallWithBearerToken".
  statement {
    actions = [
      "bedrock:CallWithBearerToken",
      "bedrock-mantle:CallWithBearerToken",
    ]
    resources = ["*"]
  }

  # The bearer token only authenticates the request; the inference call itself is
  # authorized as bedrock-mantle:CreateInference against the mantle project.
  # Requests land on the account's `default` project, but the id is
  # service-managed, so the grant covers any project in the account.
  statement {
    actions   = ["bedrock-mantle:CreateInference"]
    resources = ["arn:aws:bedrock-mantle:*:${data.aws_caller_identity.current.account_id}:project/*"]
  }
}

# The supervisor writes each checkpoint, reads the newest one back on a restore,
# and prunes all but the newest two. ListBucket is what lets it discover the
# existing checkpoint numbers, conditioned on the same prefix so the role cannot
# enumerate the bucket at large.
data "aws_iam_policy_document" "agent_checkpoints" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.checkpoints.arn}/${var.agent_checkpoint_prefix}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.checkpoints.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.agent_checkpoint_prefix}/*"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "${var.name}-agent"
  assume_role_policy = data.aws_iam_policy_document.pods_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "agent_bedrock" {
  name   = "bedrock-invoke"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent_bedrock.json
}

resource "aws_iam_role_policy" "agent_checkpoints" {
  name   = "checkpoints-read-write"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent_checkpoints.json
}

resource "aws_eks_pod_identity_association" "agent" {
  cluster_name    = module.cluster.cluster_name
  namespace       = kubernetes_namespace_v1.agents.metadata[0].name
  service_account = "agent"
  role_arn        = aws_iam_role.agent.arn
}

# ── Namespaces ───────────────────────────────────────────────────────────────
#
# Namespaces are Terraform's job; what runs inside them is the chart's.
#
# ── Before adding a NetworkPolicy here, read this ────────────────────────────
#
# The API reaches third-party HTTPS from the `service` namespace, and a
# default-deny egress policy breaks each of these in a way that does not look
# like a network problem: a 5-second hang and then a 502 quoting the third party,
# so whoever hits it suspects the credential long before the policy.
#
#   api.github.com    change-request sync, pull-request reads, App token
#                     exchange, and Issues search for linked ticketing.
#   *.atlassian.net   Jira search and resolution. CANNOT be allowlisted
#                     exhaustively: the site is a per-project setting somebody
#                     types in Settings, so the reachable set is whatever
#                     projects have configured.
#   dev.azure.com     Azure DevOps work items. Fixed: support is cloud-only.
resource "kubernetes_namespace_v1" "service" {
  metadata {
    name = "service"
  }
}

# Agent runs execute in their own namespace, isolated from the API. What runs
# inside is created at runtime by the API, not from here.
resource "kubernetes_namespace_v1" "agents" {
  metadata {
    name = "agents"
  }
}

# ── External Secrets Operator ────────────────────────────────────────────────

module "external_secrets" {
  source = "./external-secrets"

  cluster_name  = module.cluster.cluster_name
  chart_version = var.external_secrets_chart_version
  role_name     = "${var.name}-external-secrets"

  # One name prefix rather than one entry per secret: adding a secret above is
  # then a change in this file alone. The trailing "*" also covers Secrets
  # Manager's random ARN suffix (".../db-master-rJ9Bd2").
  secret_arn_patterns = [
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name}/*",
  ]
}

# ── Origin TLS ───────────────────────────────────────────────────────────────
#
# Cloudflare proxies the hostname and presents the certificate a browser checks,
# so the origin's certificate only has to exist. Terraform self-signs one for the
# hostname in this same apply, imports it into ACM, and the ALB keeps exactly the
# ACM integration it has today. Ten-year validity with no early renewal, because
# an imported ACM certificate never auto-renews: AWS will not manage a key it did
# not generate.
#
# The private key is held in state, which is inherent to `tls_private_key`. That
# is not a new exposure — the Postgres master credential is already in state for
# the same reason — but it means the state bucket now protects a certificate too.
resource "tls_private_key" "origin" {
  count = var.tls_mode == "self_signed" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "origin" {
  count = var.tls_mode == "self_signed" ? 1 : 0

  private_key_pem = tls_private_key.origin[0].private_key_pem

  subject {
    common_name  = var.ingress_host
    organization = var.name
  }

  dns_names = [var.ingress_host]

  validity_period_hours = 87600
  early_renewal_hours   = 0

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "origin" {
  count = var.tls_mode == "self_signed" ? 1 : 0

  private_key      = tls_private_key.origin[0].private_key_pem
  certificate_body = tls_self_signed_cert.origin[0].cert_pem

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ── Origin access ────────────────────────────────────────────────────────────
#
# Read at apply time from Cloudflare's public endpoint, so this needs no
# credential and the list is never written down here. The origin then cannot be
# reached around Cloudflare, which is what makes the unvalidated hop acceptable.
# The list is only as fresh as the last apply: the ranges are published as an
# output so drift shows up in a plan rather than as a partial outage.
data "http" "cloudflare_ips" {
  count = var.restrict_origin_to_cloudflare ? 1 : 0

  url = "https://api.cloudflare.com/client/v4/ips"

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  cloudflare_ips = var.restrict_origin_to_cloudflare ? jsondecode(data.http.cloudflare_ips[0].response_body).result : null

  origin_ipv4_cidrs = var.restrict_origin_to_cloudflare ? concat(local.cloudflare_ips.ipv4_cidrs, var.extra_origin_cidrs) : []
  origin_ipv6_cidrs = var.restrict_origin_to_cloudflare ? local.cloudflare_ips.ipv6_cidrs : []

  origin_annotations = var.restrict_origin_to_cloudflare ? {
    "alb.ingress.kubernetes.io/inbound-cidrs"      = join(",", local.origin_ipv4_cidrs)
    "alb.ingress.kubernetes.io/inbound-ipv6-cidrs" = join(",", local.origin_ipv6_cidrs)
  } : {}
}

# ── The platform itself ──────────────────────────────────────────────────────
#
# The values are computed from the resources this same apply created, so nothing
# restates the database endpoint, the secret name or the bucket in a values file
# or a --set flag. `chart_values` is passed as a second values document rather
# than merged in HCL: Helm merges values documents deeply, so overriding one
# nested key leaves its siblings alone, which an HCL `merge()` would not.
locals {
  platform_values = {
    api = {
      image = {
        repository = "${var.image_registry}/${var.image_names.api}"
        tag        = local.image_tag
      }

      aws       = { region = var.region }
      publicUrl = "https://${var.ingress_host}"

      db = {
        host      = aws_db_instance.platform.address
        secretArn = aws_secretsmanager_secret.db_master.arn
      }

      artifacts = { bucket = aws_s3_bucket.uploads.bucket }

      secretEncryption = { secretName = aws_secretsmanager_secret.secret_encryption.name }

      agents = {
        image            = "${var.image_registry}/${var.image_names.agent}:${local.image_tag}"
        checkpointBucket = aws_s3_bucket.checkpoints.bucket
      }
    }

    web = {
      image = {
        repository = "${var.image_registry}/${var.image_names.web}"
        tag        = local.image_tag
      }

      aws = { region = var.region }
    }

    ingress = {
      host = var.ingress_host

      # EKS Auto Mode's built-in load balancer controller ships no default
      # IngressClass, so this chart creates one.
      ingressClassName       = "alb"
      ingressClassController = "eks.amazonaws.com/alb"
      createIngressClass     = true

      certificateArn = var.tls_mode == "self_signed" ? aws_acm_certificate.origin[0].arn : var.tls_certificate_arn

      # TLS 1.2 and 1.3 only, an AEAD-only cipher set, and post-quantum hybrid
      # key exchange.
      sslPolicy = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"

      ingressAnnotations = local.origin_annotations
    }
  }
}

resource "helm_release" "platform" {
  name       = "roko-platform"
  repository = "oci://registry-1.docker.io/rokoplatform"
  chart      = "roko-platform"
  version    = local.platform_version
  namespace  = kubernetes_namespace_v1.service.metadata[0].name

  values = [
    yamlencode(local.platform_values),
    yamlencode(var.chart_values),
  ]

  # The chart templates a SecretStore and two ExternalSecrets, so the operator's
  # CRDs have to be registered before Helm applies them. That edge is not
  # expressible through a value, so it is written here.
  depends_on = [module.external_secrets]
}

# ── Budget ───────────────────────────────────────────────────────────────────

module "budget" {
  source = "./budget"
  count  = var.monthly_budget_usd == null ? 0 : 1

  name                  = "${var.name}-monthly"
  limit_usd             = tostring(var.monthly_budget_usd)
  notify_emails         = var.budget_notify_emails
  actual_thresholds     = [25, 50, 75, 100]
  forecasted_thresholds = [100]
}
