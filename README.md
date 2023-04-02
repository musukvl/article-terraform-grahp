
This article shows you how to organize the order of making and updating Terraform resources by setting up the right connections between them.

During planning phase terraform evalutes depenencies between resources and builds a dependency graph. So terraform ensuring the proper order and parallelism for resource change operations.

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
Here is a work around for such problem: you can run `terraform apply` again and storage account will be created because resource group created before.
But right solution is to define relation between resource group and storage account. 

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
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "arygrexstacc"
  resource_group_name      = azurerm_resource_group.graph_example_rg.name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

```

 
![Resource group and storage account are dependent](https://raw.githubusercontent.com/musukvl/article-terraform-graph/master/002-output-depenency/graph.png)



Conclusion

Understanding the Terraform resource graph is essential for efficiently managing infrastructure with Terraform. By using built-in commands and third-party tools, you can visualize and analyze the resource graph to ensure optimal resource management. 
