# EKS Auto Mode does NOT create a default StorageClass. Without this, every
# PersistentVolumeClaim sits in Pending indefinitely with no obvious error.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  # Auto Mode's built-in driver. NOT ebs.csi.aws.com — that is the standalone
  # add-on's provisioner and will silently never bind.
  storage_provisioner    = "ebs.csi.eks.amazonaws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}
