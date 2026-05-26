resource "azurerm_resource_group" "res-0" {
  location = "westeurope"
  name     = "rg-sample"
}
resource "azurerm_storage_account" "res-1" {
  name                     = "stsample0001"
  resource_group_name      = azurerm_resource_group.res-0.name
  location                 = "westeurope"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # Hardcoded ARM id reference (aztfexport leaves these in for cross-RG
  # references it cannot resolve to a Terraform resource address).
  network_rules {
    virtual_network_subnet_ids = [
      "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sample/providers/Microsoft.Network/virtualNetworks/vnet-x/subnets/snet-x",
    ]
  }
}
