# OpenTelemetry Collector for one deployment, the same on every cloud. Two
# releases of the upstream chart:
#
#   otel-gateway  Deployment, one replica. Receives OTLP from the platform and
#                 from otel-node, reads cluster state (k8s_cluster) and Postgres
#                 statistics, adds pod metadata and `roko.deployment`, and exports
#                 everything to `endpoint`.
#   otel-node     DaemonSet. Reads pod and node CPU and memory from the local
#                 kubelet (kubeletstats) and forwards them to the gateway.
#
# The cloud module adds its database host metrics through the `gateway_extra_*`
# inputs and binds its workload identity to the gateway's ServiceAccount.
#
# Export header values never pass through Terraform. The operator writes them to
# the cloud secret store as JSON, and External Secrets Operator copies them into
# the `otel-headers` Secret, which the gateway loads as OTLP_HEADER_<i>. The
# gateway's Helm release renders the SecretStore and ExternalSecret.
# `kubernetes_manifest` cannot: it needs the ESO CRDs at plan time, and on a
# fresh install they do not exist yet.
#
# The node collector reads `nodes/stats` from its own kubelet. The alternative,
# one pod reading every kubelet through the API server proxy, needs `nodes/proxy`,
# which grants command execution on every node.

locals {
  gateway_name = "otel-gateway"
  node_name    = "otel-node"
  secret_name  = "otel-collector"
  files_volume = "gateway-files"

  # ESO resources in the collector namespace. A header value reaches the
  # collector only as OTLP_HEADER_<i>, where <i> is the name's index in
  # `header_names`.
  store_name          = "telemetry-secrets"
  headers_secret_name = "otel-headers"
  header_names        = var.header_names

  exporter_name = var.protocol == "grpc" ? "otlp" : "otlphttp"

  exporter = {
    endpoint    = var.endpoint
    compression = "gzip"
    headers     = { for i, name in local.header_names : name => "$${env:OTLP_HEADER_${i}}" }
  }

  image = {
    repository = "otel/opentelemetry-collector-contrib"
    tag        = var.collector_image_tag
  }

  # The chart opens Jaeger and Zipkin ports by default. Nothing here sends either.
  unused_ports = {
    jaeger-compact = { enabled = false }
    jaeger-thrift  = { enabled = false }
    jaeger-grpc    = { enabled = false }
    zipkin         = { enabled = false }
  }

  health_check = { endpoint = "$${env:MY_POD_IP}:13133" }

  memory_limiter = {
    check_interval         = "5s"
    limit_percentage       = 80
    spike_limit_percentage = 25
  }

  # Processor order matters: shed load first, then enrich, then batch.
  gateway_processors = ["memory_limiter", "k8sattributes", "resource", "batch"]

  # `alternateConfig` replaces the chart's default config (which carries Jaeger,
  # Zipkin and a debug exporter) instead of merging into it. The presets enabled
  # below still add their receivers and processor settings to it.
  gateway_config = {
    extensions = merge({ health_check = local.health_check }, var.gateway_extra_extensions)

    receivers = merge(
      {
        otlp = {
          protocols = {
            grpc = { endpoint = "$${env:MY_POD_IP}:4317" }
            http = { endpoint = "$${env:MY_POD_IP}:4318" }
          }
        }

        # The master user, read from the Secret. TLS stays on: both managed
        # servers require it.
        postgresql = {
          endpoint            = "${var.postgres.host}:${var.postgres.port}"
          transport           = "tcp"
          username            = "$${env:PG_USERNAME}"
          password            = "$${env:PG_PASSWORD}"
          databases           = [var.postgres.database]
          collection_interval = "60s"
          tls = {
            insecure             = false
            insecure_skip_verify = var.postgres.tls_insecure_skip_verify
          }
        }

        # The clusterMetrics preset defines k8s_cluster at 10 s. A minute is
        # enough for cluster state and a sixth of the data points.
        k8s_cluster = { collection_interval = "60s" }
      },
      var.gateway_extra_receivers,
    )

    processors = {
      memory_limiter = local.memory_limiter
      batch          = {}

      resource = {
        attributes = [
          { key = "roko.deployment", value = var.deployment_name, action = "upsert" },
        ]
      }

      # The rest of this processor comes from the kubernetesAttributes preset.
      # Node metrics arrive from otel-node pods, and without this exclusion the
      # connection-based association would stamp otel-node's own pod metadata
      # onto node-level series.
      k8sattributes = {
        exclude = { pods = [{ name = "^${local.node_name}-" }] }
      }
    }

    exporters = { (local.exporter_name) = local.exporter }

    service = {
      extensions = concat(["health_check"], keys(var.gateway_extra_extensions))

      pipelines = {
        metrics = {
          receivers  = concat(["otlp", "postgresql", "k8s_cluster"], keys(var.gateway_extra_receivers))
          processors = local.gateway_processors
          exporters  = [local.exporter_name]
        }
        traces = {
          receivers  = ["otlp"]
          processors = local.gateway_processors
          exporters  = [local.exporter_name]
        }
        logs = {
          receivers  = ["otlp"]
          processors = local.gateway_processors
          exporters  = [local.exporter_name]
        }
      }
    }
  }

  node_config = {
    extensions = { health_check = local.health_check }

    receivers = {
      # Kubelet serving certificates are not signed by a CA the pod trusts on
      # either managed service, so the connection to the node's own IP is not
      # verified.
      kubeletstats = {
        collection_interval  = "60s"
        auth_type            = "serviceAccount"
        endpoint             = "$${env:K8S_NODE_IP}:10250"
        insecure_skip_verify = true
      }
    }

    processors = {
      memory_limiter = local.memory_limiter
      batch          = {}
    }

    exporters = {
      otlp = {
        endpoint = "${local.gateway_name}.${var.namespace}.svc.cluster.local:4317"
        tls      = { insecure = true }
      }
    }

    service = {
      extensions = ["health_check"]

      pipelines = {
        metrics = {
          receivers  = ["kubeletstats"]
          processors = ["memory_limiter", "batch"]
          exporters  = ["otlp"]
        }
      }
    }
  }
}

locals {
  secret_store_manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata   = { name = local.store_name, namespace = var.namespace }
    spec       = { provider = var.secret_store_provider }
  }

  # One entry per header. ESO fails the sync while the store secret has no value
  # or lacks a property, and the Secret then does not exist. The gateway pod
  # waits in CreateContainerConfigError until it does; nothing else depends on
  # it. ESO retries a failed sync with backoff, and refreshInterval bounds how
  # long a changed value takes to reach the Secret.
  headers_external_secret_manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata   = { name = local.headers_secret_name, namespace = var.namespace }
    spec = {
      refreshInterval = "15m"
      secretStoreRef  = { kind = "SecretStore", name = local.store_name }
      target          = { name = local.headers_secret_name }
      data = [for i, name in local.header_names : {
        secretKey = "OTLP_HEADER_${i}"
        remoteRef = { key = var.headers_secret_key, property = name }
      }]
    }
  }

  gateway_manifests = [
    for m in [local.secret_store_manifest, local.headers_external_secret_manifest] : m
    if length(local.header_names) > 0
  ]

  gateway_values = {
    mode             = "deployment"
    replicaCount     = 1
    fullnameOverride = local.gateway_name
    image            = local.image

    presets = {
      clusterMetrics       = { enabled = true }
      kubernetesAttributes = { enabled = true }
    }

    alternateConfig = local.gateway_config

    ports = local.unused_ports

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "512Mi" }
    }

    serviceAccount = { annotations = var.gateway_service_account_annotations }
    podLabels      = var.gateway_pod_labels

    extraEnvsFrom = concat(
      [{ secretRef = { name = local.secret_name } }],
      length(local.header_names) > 0 ? [{ secretRef = { name = local.headers_secret_name } }] : [],
    )
    extraManifests  = local.gateway_manifests
    extraContainers = var.gateway_extra_containers
    extraVolumes = length(var.gateway_extra_files) > 0 ? [
      { name = local.files_volume, configMap = { name = "${local.gateway_name}-files" } },
    ] : []

    # Restart the pod when the Postgres Secret or the files change; neither is
    # part of the chart's own config checksum. A changed header value reaches
    # the collector only when the pod restarts.
    podAnnotations = {
      "checksum/secret" = nonsensitive(sha256(jsonencode([var.postgres.username, var.postgres.password])))
      "checksum/files"  = sha256(jsonencode(var.gateway_extra_files))
    }
  }

  node_values = {
    mode             = "daemonset"
    fullnameOverride = local.node_name
    image            = local.image

    # Not the kubeletMetrics preset: it grants get, list and watch on
    # `nodes/stats`, and reading the summary endpoint needs only get.
    clusterRole = {
      create = true
      rules = [
        { apiGroups = [""], resources = ["nodes/stats"], verbs = ["get"] },
      ]
    }

    extraEnvs = [
      { name = "K8S_NODE_IP", valueFrom = { fieldRef = { fieldPath = "status.hostIP" } } },
    ]

    alternateConfig = local.node_config

    # Nothing sends to the node collector, so it opens no ports and takes no
    # host ports.
    ports = merge(local.unused_ports, {
      otlp      = { enabled = false }
      otlp-http = { enabled = false }
      metrics   = { enabled = false }
    })

    tolerations = var.node_tolerations

    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { memory = "256Mi" }
    }
  }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "collector" {
  metadata {
    name      = local.secret_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    PG_USERNAME = var.postgres.username
    PG_PASSWORD = var.postgres.password
  }
}

resource "kubernetes_config_map_v1" "gateway_files" {
  count = length(var.gateway_extra_files) > 0 ? 1 : 0

  metadata {
    name      = "${local.gateway_name}-files"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = var.gateway_extra_files
}

resource "helm_release" "gateway" {
  name       = local.gateway_name
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.chart_version

  values = [yamlencode(local.gateway_values)]

  # No wait, and so no atomic: the gateway pod is not ready until the operator
  # writes the header values to the secret store, which happens after the first
  # apply. Waiting would fail that apply and roll the release back.
  timeout         = 600
  wait            = false
  atomic          = false
  cleanup_on_fail = true

  # The values name the Secret and the ConfigMap rather than reference them, so
  # that the values can be read in a console. This keeps the order.
  depends_on = [
    kubernetes_secret_v1.collector,
    kubernetes_config_map_v1.gateway_files,
  ]
}

resource "helm_release" "node" {
  name       = local.node_name
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.chart_version

  values = [yamlencode(local.node_values)]

  timeout         = 600
  wait            = true
  atomic          = true
  cleanup_on_fail = true

  # The node collector exports to the gateway's Service.
  depends_on = [helm_release.gateway]
}
