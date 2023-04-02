locals {
  location = "northeurope"

  config = {
    "sample-rg1" = {
      name = "ary-graph-example-1-rg"
      storage_accounts = {
        "sa11" = {
          "name" = "arysa11grexstacc"
        },
        "sa12" = {
          "name" = "arysa12grexstacc"
        }
      }
    },
    "sample-rg2" = {
      name = "ary-graph-example-2-rg"
      storage_accounts = {
        "sa21" = {
          "name" = "arysa21grexstacc"
        },
        "sa22" = {
          "name" = "arysa22grexstacc"
        }
      }
    }
  }
}

resource "azurerm_resource_group" "graph_example_rg" {
  for_each = local.config
  name     = each.value.name
  location = local.location
}

locals {
  storage_accounts_to_create = merge([
    for rg_key, rg in azurerm_resource_group.graph_example_rg : {
      for sa_key, sa in local.config[rg_key].storage_accounts : "${rg_key}_${sa_key}" => {
        resource_group       = rg
        storage_account_name = sa.name
      }
    }
  ]...)
}

resource "azurerm_storage_account" "storage_account" {
  for_each                 = local.storage_accounts_to_create
  name                     = each.value.storage_account_name
  resource_group_name      = each.value.resource_group.name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
