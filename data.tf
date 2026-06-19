# ============================================================================
# Reference to the EXISTING resource group (created by the network project).
# This project never creates or destroys the resource group, the VNet, its
# subnets, NSGs, or route tables - it only reads the resource group as a
# data source and attaches new resources (MySQL server, Private Endpoint,
# Private DNS Zone) using the subnet/VNet IDs passed in via variables.
# ============================================================================

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}
