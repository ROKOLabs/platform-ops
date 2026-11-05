# Blob storage — the Azure analog of the S3 object-storage buckets. The uploads
# container serves artifacts and prototypes. The private checkpoints container
# stores agent run archives. The browser talks directly only to uploads via SAS
# URLs (see AzureBlobArtifactStorage), so CORS must allow the frontend origins,
# and ETag must be readable to confirm an upload.
resource "azurerm_storage_account" "this" {
  name                = var.account_name
  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    cors_rule {
      allowed_methods    = ["PUT", "GET", "HEAD"]
      allowed_origins    = var.cors_origins
      allowed_headers    = ["*"]
      exposed_headers    = ["ETag"]
      max_age_in_seconds = 3000
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "uploads" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "checkpoints" {
  name                  = var.checkpoints_container_name
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}
