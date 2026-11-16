terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Azure Migrate adds its own resources (vault, key vault, migrated VMs)
      # to this resource group. Allow terraform destroy to remove them too.
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
}

# Landing zone network for the migrated VMs. 10.0.0.0/16 doesn't overlap
# the AWS VPC (172.31.0.0/16).
resource "azurerm_virtual_network" "migration" {
  name                = "migration-lab-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.migration.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Storage account selected in the Replicate wizard
resource "azurerm_storage_account" "replication" {
  name                     = "stmigromy01"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
}