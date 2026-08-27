output "mysql_server_id" {
  description = "ID of the MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.this.id
}

output "mysql_server_fqdn" {
  description = "Fully qualified domain name of the MySQL server (resolves to its private IP via the linked Private DNS Zone)"
  value       = azurerm_mysql_flexible_server.this.fqdn
}

output "mysql_private_endpoint_ip" {
  description = "Private IP address assigned to the MySQL Private Endpoint"
  value       = azurerm_private_endpoint.mysql.private_service_connection[0].private_ip_address
}

output "mysql_admin_username" {
  description = "Administrator username for the MySQL server"
  value       = var.mysql_admin_username
}

output "mysql_admin_password" {
  description = "Generated administrator password for the MySQL server (sensitive - retrieve with: terraform output -raw mysql_admin_password)"
  value       = random_password.mysql_admin.result
  sensitive   = true
}
