# ============================================================================
# This project is fully independent from the VNet project
# (azure-virtual-network). It does NOT read that project's state - instead,
# the network details it needs (resource group, location, data subnet) are
# passed in explicitly as variables below.
#
# Get these values from the VNet project's outputs after a `terraform apply`
# there, e.g.:
#   terraform output -raw resource_group_name
#   terraform output -json data_subnet_ids
#
# Or look them up directly via az cli:
#   az network vnet subnet list \
#     --resource-group rg-ha-vnet --vnet-name vnet-ha --output table
#
# IMPORTANT: the NSG-Data rules and rt-data route table that protect this
# subnet already live in the VNet project (nsg.tf / route_tables.tf there).
# This project does not create, modify, or duplicate those - it only
# attaches a Private Endpoint into the existing subnet.
# ============================================================================

variable "resource_group_name" {
  description = "Name of the EXISTING resource group where the VNet lives (from the network project)"
  type        = string
  default     = "rg-ha-vnet"
}

variable "location" {
  description = "Azure region - must match the existing VNet's region"
  type        = string
  default     = "eastus"
}

variable "data_subnet_id" {
  description = "Full resource ID of the existing Data subnet (AZ1) to place the Private Endpoint into. Get this from the network project's `data_subnet_ids` output, index 0."
  type        = string
}

variable "vnet_id" {
  description = "Full resource ID of the existing VNet, needed to link the Private DNS Zone. Get this from the network project's `vnet_id` output."
  type        = string
}

variable "mysql_server_name" {
  description = "Name of the MySQL Flexible Server (must be globally unique)"
  type        = string
  default     = "mysql-ha-vnet-demo"
}

variable "mysql_admin_username" {
  description = "Administrator login name for the MySQL Flexible Server"
  type        = string
  default     = "mysqladmin"
}

variable "mysql_sku_name" {
  description = "Compute tier and size for the MySQL Flexible Server (e.g. B_Standard_B1ms for burstable, GP_Standard_D2ds_v4 for general purpose)"
  type        = string
  default     = "MO_Standard_E2ds_v4"
}

variable "mysql_storage_size_gb" {
  description = "Storage size in GB for the MySQL Flexible Server"
  type        = number
  default     = 32
}

variable "mysql_version" {
  description = "MySQL version"
  type        = string
  default     = "8.0.21"
}

variable "tags" {
  description = "Common tags applied to resources in this project"
  type        = map(string)
  default = {
    environment = "production"
    project     = "mysql-database"
    managed_by  = "terraform"
  }
}
