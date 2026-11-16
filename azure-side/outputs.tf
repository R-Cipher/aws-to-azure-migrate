output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "vnet_and_subnet" {
  value = "${azurerm_virtual_network.migration.name} / ${azurerm_subnet.default.name}"
}

output "replication_storage_account" {
  value = azurerm_storage_account.replication.name
}