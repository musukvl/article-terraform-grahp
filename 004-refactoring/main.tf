locals {
  location = "northeurope"
  resource_group_name = "ary-graph-example-rg"   
}

resource "azurerm_resource_group" "graph_example_rg" {
  name     = local.resource_group_name
  location = local.location
  tags     = {
    "asset-owner" = "Mark"
  }
}

data "azurerm_resource_group" "graph_example_rg" {  
  name = azurerm_resource_group.graph_example_rg.name
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "arygrexstacc"
  resource_group_name      = data.azurerm_resource_group.graph_example_rg.name
  location                 = data.azurerm_resource_group.graph_example_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
