# In-cluster baseline for Azure — the analog of dev/cluster-config + the
# external-secrets module. Two differences from AWS:
#
#   1. No default-StorageClass resource. AKS ships `managed-csi`
#      (disk.csi.azure.com) as the default class out of the box, so there is
#      nothing to create (cluster-baseline exists on AWS only because Auto Mode
#      ships none).
#   2. ESO authenticates by Workload Identity, not Pod Identity. The controller
#      SA is annotated with the external-secrets identity's client id and the
#      pod carries the use-label, so SecretStores with authType: WorkloadIdentity
#      and no serviceAccountRef use the controller's federated token.
resource "kubernetes_namespace_v1" "service" {
  metadata {
    name = var.service_namespace
  }
}

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = var.external_secrets_namespace
  }
}

# Agent runs execute in their own namespace, isolated from the API — the Azure
# analog of the AWS cluster-config stack's `agents` namespace. What runs inside
# (single-shot Jobs) is created at runtime by the API, not from here; the
# `agent` ServiceAccount is rendered by the roko-api chart. Its federated
# identity credential lives in the data stack.
resource "kubernetes_namespace_v1" "agents" {
  metadata {
    name = var.agents_namespace
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version

  set = [
    # Federate the controller's ServiceAccount to the Key Vault-reader identity.
    {
      name  = "serviceAccount.annotations.azure\\.workload\\.identity/client-id"
      value = var.external_secrets_client_id
    },
    # The webhook only projects a token into pods carrying this label. `true`
    # must stay a string — Helm's --set parsing coerces bare true/false to a
    # YAML bool, and Kubernetes label values must unmarshal as strings.
    {
      name  = "podLabels.azure\\.workload\\.identity/use"
      value = "true"
      type  = "string"
    },
  ]
}
