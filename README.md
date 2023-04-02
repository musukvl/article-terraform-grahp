
This article shows you how to organize the order of making and updating Terraform resources by setting up the right connections between them.

During planning phase terraform evalutes depenencies between resources and builds a dependency graph. So terraform ensuring the proper order and parallelism for resource change operations.

# TL;DR

* Use resource and module outputs to define dependencies between resources.
* Use for_each for collecting outputs from created resources.
* Use `depends_on` very carefully, because it can lead to resource recreation because of minor change in related resource.
* Use `terraform graph` command to review resource dependencies and refactor it.


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
```
terraform graph | dot -Tpng > graph.png
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
 (Check code in [002-output-depenency]())




![Resource group and storage account are dependent](https://raw.githubusercontent.com/musukvl/article-terraform-graph/master/002-output-depenency/graph.png)

Now the graph shows that resource group and storage account are dependent on each other. 

# Using depends_on to make dependency

'depends_on' is way to enforce dependency between resources. It is not recommended to use it, because it can lead to resource recreation because of minor change in related resource.

In the following example, resource group tag change, causes recreation of storage account:

```hcl

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
(Check code in [003-depends_on]())

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
(Check code in [003-data-resource/update-plan.txt]())

# Terraform graph refactoring

Using `terrafor graph > graph.dot` command is a good way to do dependency refactoring. You can generate graph file before refactoring and after and compare them. No changes in the graph means that you did not break anything.
You can vizualize graph with Graphviz (DOT) tool: `terraform graph > graph.dot`

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
(Check code in [004-data-resource]())


#Conclusion

Understanding the Terraform resource graph is essential for efficiently managing infrastructure with Terraform. 
The graph shows the dependencies between resources and helps to avoid problems with resource creation order.
