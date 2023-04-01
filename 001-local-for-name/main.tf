locals {
  location = "northeurope"
  resource_group_name = "ary-graph-example-rg"   
}

resource "azurerm_resource_group" "graph_example_rg" {
  name     = local.resource_group_name
  location = local.location
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "arygrexstacc"
  resource_group_name      = local.resource_group_name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
