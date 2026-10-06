variable "namespace" {
  description = "Namespace the collectors run in."
  type        = string
  default     = "telemetry"
}

variable "deployment_name" {
  description = "Value of the `roko.deployment` resource attribute stamped on every signal, so one backend can tell deployments apart."
  type        = string
}

# ── Export ───────────────────────────────────────────────────────────────────

variable "endpoint" {
  description = "OTLP endpoint the gateway exports to, for example `https://otlp.nr-data.net`."
  type        = string
}

variable "protocol" {
  description = "`http/protobuf` exports with the `otlphttp` exporter. `grpc` exports with the `otlp` exporter."
  type        = string
  default     = "http/protobuf"

  validation {
    condition     = contains(["http/protobuf", "grpc"], var.protocol)
    error_message = "protocol must be \"http/protobuf\" or \"grpc\"."
  }
}

variable "headers" {
  description = "Headers sent with every export, for example `{ \"api-key\" = \"...\" }`. The values go into a Kubernetes Secret and reach the collector as environment variables, never as plain config."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ── Postgres ─────────────────────────────────────────────────────────────────

variable "postgres" {
  description = "The platform database the `postgresql` receiver reads statistics from. `tls_insecure_skip_verify` keeps TLS on but skips verifying the server certificate, for a server whose CA the collector image does not trust (RDS)."
  type = object({
    host                     = string
    port                     = optional(number, 5432)
    database                 = string
    username                 = string
    password                 = string
    tls_insecure_skip_verify = optional(bool, false)
  })
}

# ── Cloud-specific additions ─────────────────────────────────────────────────
#
# The cloud module adds its database host metrics through these: a receiver, an
# extension it needs, a sidecar and the files the sidecar reads, and the
# workload identity of the gateway's service account.

variable "gateway_extra_receivers" {
  description = "Receivers added to the gateway's metrics pipeline, as `{ name = config }`."
  type        = any
  default     = {}
}

variable "gateway_extra_extensions" {
  description = "Extensions added to the gateway, as `{ name = config }`."
  type        = any
  default     = {}
}

variable "gateway_extra_containers" {
  description = "Sidecar containers added to the gateway pod. They mount `gateway_extra_files` from the volume named by the `gateway_files_volume` output."
  type        = any
  default     = []
}

variable "gateway_extra_files" {
  description = "Files written to a ConfigMap and mounted into the gateway pod as the `gateway-files` volume, as `{ file name = content }`."
  type        = map(string)
  default     = {}
}

variable "gateway_service_account_annotations" {
  description = "Annotations on the gateway's ServiceAccount, for example the Azure workload identity client id."
  type        = map(string)
  default     = {}
}

variable "gateway_pod_labels" {
  description = "Labels on the gateway pod, for example `azure.workload.identity/use`."
  type        = map(string)
  default     = {}
}

# ── Versions and sizing ──────────────────────────────────────────────────────

variable "chart_version" {
  description = "open-telemetry/opentelemetry-collector chart version."
  type        = string
  default     = "0.175.1"
}

variable "collector_image_tag" {
  description = "otel/opentelemetry-collector-contrib image tag. The default is the chart's appVersion."
  type        = string
  default     = "0.161.0"
}

variable "node_tolerations" {
  description = "Tolerations of the node DaemonSet. The default tolerates every taint, so node metrics cover tainted pools such as the AKS agent pool."
  type        = any
  default     = [{ operator = "Exists" }]
}
