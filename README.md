
This article demonstrates how to manage the creation and updating of Terraform resources by properly configuring their dependencies, using practical examples. 
The code examples, available in this [GitHub repository](https://github.com/musukvl/article-terraform-graph) utilize Azure provider resources, but the concepts discussed apply to any provider.

# TL;DR

During planning phase terraform evaluates dependencies between resources and builds a dependency graph. So terraform ensuring the proper order and parallelism for resource change operations.

* Use resource and module outputs to define dependencies between resources.
* Use `for_each` for collecting outputs from created resources.
* Use `depends_on` with caution, as it can lead to resource recreation due to minor changes in related resources.
* Use the `terraform graph` command to review resource dependencies and refactor them.
* Assign proper resource identifiers wisely to be able using it for lookup.

# Using resource output to make dependency

The following example defines Azure resource group and storage account in it:

```hcl
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

```
(Check code in [001-local-for-name]())

The `terraform plan` command for this example does not return any errors. 
But if you run `terraform apply` you might see "Resource group 'ary-graph-example-rg' could not be found" error.

```
│ Error: creating Azure Storage Account "arygrexstacc": storage.AccountsClient#Create: Failure sending request: StatusCode=404 -- Original Error: Code="ResourceGroupNotFound" Message="Resource group 'ary-graph-example-rg' could not be found."    
│
│   with azurerm_storage_account.storage_account,
│   on main.tf line 11, in resource "azurerm_storage_account" "storage_account":
│   11: resource "azurerm_storage_account" "storage_account" {
```

The apply error happends because terraform creating resource group and storage account in parallel. (Default parallelism for `terraform apply` is 10). 
Here is a work around for such problem: you can run `terraform apply` again and storage account will be created because resource group created before. It would work, but you might have problems with day zero provisioning when you need to recreate everything from scratch.

The right solution is to define relation between resource group and storage account. 

It is possible to generate depenency graph with `terraform graph` command and draw image with Graphviz (DOT):
```sh
terraform graph | dot -Tpng > graph.png
```

use the following command to install Graphviz on Ubuntu:
```sh
#!/bin/bash
sudo apt-get update
sudo apt-get install graphviz -y
```


The graph shows, that there is no dependency between resource group and storage account, but they both dependend on `local.location` variable. 


![Resource group and storage account are not dependent](https://raw.githubusercontent.com/musukvl/article-terraform-graph/master/001-local-for-name/graph.png)

The fix is use resource group output `azurerm_resource_group.graph_example_rg.name` instead of local variable:

```hcl
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

resource "azurerm_storage_account" "storage_account" {
  name                     = "arygrexstacc"
  resource_group_name      = azurerm_resource_group.graph_example_rg.name # <- resource output used for dependency
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

```
 (Check code in [002-output-dependency](https://github.com/musukvl/article-terraform-graph/tree/master/002-output-dependency))


![Resource group and storage account are dependent](https://raw.githubusercontent.com/musukvl/article-terraform-graph/master/002-output-dependency/graph.png)

Now the graph shows that resource group and storage account are dependent on each other. 

# Using depends_on to make dependency

Using 'depends_on' is way to enforce dependency between resources. It is not recommended to use it, because it can lead to resource recreation because of minor change in related resource.

In the following example, resource group tag change, causes recreation of storage account:

```hcl
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
  depends_on               = [azurerm_resource_group.graph_example_rg]
  name = local.resource_group_name
}

resource "azurerm_storage_account" "storage_account" {
  depends_on               = [data.azurerm_resource_group.graph_example_rg]
  name                     = "arygrexstacc"
  resource_group_name      = data.azurerm_resource_group.graph_example_rg.name
  location                 = data.azurerm_resource_group.graph_example_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
```
(Check code in [003-depends_on](https://github.com/musukvl/article-terraform-graph/tree/master/003-depends_on))

For example in case of changing tag value from "Mark" to "Mark1" terraform will generate the following plan:

```hcl
 # azurerm_resource_group.graph_example_rg will be updated in-place
  ~ resource "azurerm_resource_group" "graph_example_rg" {
        id       = "/subscriptions/5293af6a-eac6-493f-8d6f-e6358448a2ff/resourceGroups/ary-graph-example-rg"
        name     = "ary-graph-example-rg"
      ~ tags     = {
          ~ "asset-owner" = "Mark" -> "Mark1"
        }
        # (1 unchanged attribute hidden)
    }

  # azurerm_storage_account.storage_account must be replaced
-/+ resource "azurerm_storage_account" "storage_account" {
      ~ access_tier                       = "Hot" -> (known after apply)
      ~ id                                = "/subscriptions/5293af6a-eac6-493f-8d6f-e6358448a2ff/resourceGroups/ary-graph-example-rg/providers/Microsoft.Storage/storageAccounts/arygrexstacc" -> (known after apply)
      + large_file_share_enabled          = (known after apply)
      ~ location                          = "northeurope" # forces replacement -> (known after apply)
        name                              = "arygrexstacc"

Plan: 1 to add, 1 to change, 1 to destroy.

```
(Check code in [003-data-resource/update-plan.txt](https://github.com/musukvl/article-terraform-graph/tree/master/003-depends_on/update-plan.txt))

# Terraform graph refactoring

Using `terraform graph > graph.dot` command is a good way to do dependency refactoring. You can generate graph file before refactoring and after and compare them. No changes in the graph means that you did not break anything.
You can visualize graph with Graphviz (DOT) tool: `terraform graph > graph.dot`

The previous example can be refactored to not use `depends_on` and having the same dependency graph by using resource output for dependency:

```hcl
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
  name = azurerm_resource_group.graph_example_rg.name   # <- resource output used for dependency
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "arygrexstacc"
  resource_group_name      = data.azurerm_resource_group.graph_example_rg.name
  location                 = data.azurerm_resource_group.graph_example_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

```
(Check code in [004-data-resource](https://github.com/musukvl/article-terraform-graph/tree/master/004-refactoring))

# One to may relation example

In the following example, the resource group and storage account defined in the local.config variable. 

```hcl
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
        resource_group = rg
        storage_account_name = sa.name
      }
    }
  ]...)
}

resource "azurerm_storage_account" "storage_account" {
  for_each = local.storage_accounts_to_create
  name                     = each.value.storage_account_name
  resource_group_name      = each.value.resource_group.name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

```
(Check code in [005-one-to-many-relation](https://github.com/musukvl/article-terraform-graph/tree/master/005-one-to-many-relation))

The essential of the example is using local variable to make dependency between created resources and local variable. 
So local variable evaluated only when resource groups are created, and then storage accounts are created only when variable evaluated.

![one-to-many relation](https://raw.githubusercontent.com/musukvl/article-terraform-graph/master/005-one-to-many-relation/graph-key.png)

It is possible to use multiple local variables for different created resources and make join operations between them.
Using local variables for iterating created resources is also a good way to make code more readable and maintainable. 

This example also demonstrates importance of resource identifiers management, in this case local.config map keys used as resource group resource identifiers, and concatenation of resource group key and storage account key used as storage account resource identifiers.

```shell
azurerm_resource_group.graph_example_rg["sample-rg1"]: Creating...
azurerm_storage_account.storage_account["sample-rg1_sa11"]: Still creating... [10s elapsed]
azurerm_storage_account.storage_account["sample-rg1_sa12"]: Still creating... [10s elapsed]
```

Using the same keys (`rg_key`) in the local.config map and as identifier of created resources allows to join created resource with the corresponding configuration in the local.config map.
```hcl
for rg_key, rg in azurerm_resource_group.graph_example_rg : {
      for sa_key, sa in local.config[rg_key].storage_accounts
```


 
# Conclusion

The article provides various examples to illustrate these concepts, such as using resource output to make dependencies, avoiding depends_on when possible, refactoring the Terraform graph, and managing one-to-many relationships between resources. These examples demonstrate the importance of managing resource identifiers and using local variables to make dependencies between created resources, making the code more readable and maintainable.
