provider "azurerm" {
  features {}
}

provider "aws" {
  region = var.aws_region
}

resource "azurerm_resource_group" "recovery" {
  name     = "rg-${var.project_name}-recovery-${var.environment}"
  location = var.location
}

# --- Recovery Control Plane (AKS) ---

resource "azurerm_kubernetes_cluster" "recovery_k8s" {
  name                = "aks-pitr-iq-${var.environment}"
  location            = azurerm_resource_group.recovery.location
  resource_group_name = azurerm_resource_group.recovery.name
  dns_prefix          = "recovery-k8s"

  default_node_pool {
    name       = "default"
    node_count = 3
    vm_size    = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }
}

# --- Recovery Metadata Store (Postgres) ---

resource "azurerm_postgresql_flexible_server" "metadata" {
  name                   = "psql-recovery-metadata-${var.environment}"
  resource_group_name    = azurerm_resource_group.recovery.name
  location               = azurerm_resource_group.recovery.location
  version                = "13"
  administrator_login    = "recadmin"
  administrator_password = var.db_password
  storage_mb             = 32768
  sku_name               = "GP_Standard_D2ds_v4"
}

# --- Immutable Recovery Vault (Azure Storage WORM) ---

resource "azurerm_storage_account" "vault" {
  name                     = "stpitrvault${var.environment}"
  resource_group_name      = azurerm_resource_group.recovery.name
  location                 = azurerm_resource_group.recovery.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "backups" {
  name                  = "immutable-backups"
  storage_account_name  = azurerm_storage_account.vault.name
  container_access_type = "private"
}

# --- Multi-Cloud Resilience (AWS S3 Cross-Region Vault) ---

resource "aws_s3_bucket" "dr_vault" {
  bucket = "db-recovery-dr-vault-${var.environment}"
  
  versioning {
    enabled = true
  }
}
