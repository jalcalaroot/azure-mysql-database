# ============================================================================
# Azure Database for MySQL Flexible Server (Public Access + Private Endpoint mode)
#
# This mode was chosen specifically to AVOID requiring a delegated subnet
# (the "VNet Integration" mode would require a subnet delegated to
# Microsoft.DBforMySQL/flexibleServers, which cannot share space with other
# resources). Since no delegated_subnet_id is set below, the azurerm
# provider automatically disables public network access on this server -
# it's reachable ONLY through its Private Endpoint inside the existing
# VNet, the same pattern used for Key Vault and the Storage Account in the
# network project.
#
# Defense in depth: even though this server technically supports a public
# endpoint at the platform level, two independent layers (owned by the
# network project) block any real exposure:
#   1. public network access automatically disabled by not configuring
#      delegated_subnet_id (this project)
#   2. rt-data (0.0.0.0/0 -> None) already blocks all Internet egress from
#      the data subnet, regardless of the server's own configuration
#      (see azure-virtual-network/route_tables.tf)
#
# This project does not create or modify the data subnet's NSG - the
# existing NSG-Data in the network project already allows port 3306 from
# the App subnet CIDRs (see azure-virtual-network/nsg.tf).
# ============================================================================

resource "random_password" "mysql_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_mysql_flexible_server" "this" {
  name                    = var.mysql_server_name
  location                = var.location
  resource_group_name     = data.azurerm_resource_group.existing.name
  administrator_login     = var.mysql_admin_username
  administrator_password  = random_password.mysql_admin.result
  sku_name                = var.mysql_sku_name
  version                 = var.mysql_version
  zone                    = "1" # primary zone; standby (if HA enabled) lands in a different zone automatically

  storage {
    size_gb = var.mysql_storage_size_gb
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "mysql" {
  name                = "pe-mysql"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.existing.name
  subnet_id           = var.data_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-mysql"
    private_connection_resource_id = azurerm_mysql_flexible_server.this.id
    subresource_names              = ["mysqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.mysql.id]
  }
}

resource "azurerm_private_dns_zone" "mysql" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = data.azurerm_resource_group.existing.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "link-mysql"
  resource_group_name   = data.azurerm_resource_group.existing.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}
