# Azure MySQL Database - Standalone Project

Terraform project that deploys an Azure Database for MySQL Flexible Server, fully integrated into an existing private VNet via a Private Endpoint. This project is **independent** from the network project (`azure-virtual-network`) — it attaches into an existing data subnet by ID, but never creates, modifies, or destroys the VNet, subnets, NSGs, or any other networking resource.

## The story behind this design

This project started with a simple goal: deploy a MySQL database in Azure, fully private, no public exposure. What followed was a journey through some of the most important infrastructure decisions you'll face in Azure:

- We avoided the delegated subnet trap that MySQL VNet Integration requires — instead using Private Endpoint mode, which lets the database live alongside other resources in the existing `snet-data` subnet without any special reservation.
- We discovered that Azure East US (Virginia) has real capacity restrictions for new subscriptions in 2025-2026 (confirmed by Bloomberg and Microsoft's own CFO), and migrated the entire stack to Central US (Iowa) — where the subscription had full access.
- We confirmed end-to-end private connectivity: a management VM in the App subnet reaching the database at `10.0.21.4` through the Private Endpoint, without the database ever touching the public internet.

## Architecture

```
azure-virtual-network/  (separate project, deployed first)
└── snet-data-az1  (existing data subnet, referenced by ID)
        │
        │ var.data_subnet_id (passed explicitly, no remote state read)
        ▼
azure-mysql-database/  (this project)
├── azurerm_mysql_flexible_server    (MySQL 8.0, no public access)
├── azurerm_private_endpoint         (pe-mysql, IP: 10.0.21.4)
├── azurerm_private_dns_zone         (privatelink.mysql.database.azure.com)
└── azurerm_private_dns_zone_virtual_network_link  (linked to the VNet)
```

## What this deploys

| Resource | Notes |
|---|---|
| MySQL Flexible Server | MySQL 8.0.21, public network access automatically disabled by not setting `delegated_subnet_id` |
| Admin password | Generated automatically by Terraform (`random_password`), stored as a sensitive output — never written to any `.tf` file |
| Private Endpoint | `pe-mysql`, placed in the existing data subnet — same pattern as Key Vault and Storage Account in the network project |
| Private DNS Zone | `privatelink.mysql.database.azure.com`, linked to the VNet — the server's FQDN resolves to its private IP automatically |

## Why Private Endpoint mode and not VNet Integration?

Azure Database for MySQL Flexible Server supports two connectivity modes:

- **VNet Integration**: the server is injected directly into a dedicated subnet, which must be delegated exclusively to `Microsoft.DBforMySQL/flexibleServers` — it cannot share space with any other resource.
- **Private Endpoint** (what we use): the server is a regional PaaS resource, and a Private Endpoint NIC is placed inside the existing subnet. No delegation required, no new subnet needed.

We chose Private Endpoint to keep `snet-data` as a generic data tier — consistent with Key Vault and Storage Account, which also connect via Private Endpoint. The same subnet hosts all three, with no special reservation or delegation for any of them.

## Defense in depth

Even without `public_network_access_enabled = false` being explicitly configurable in newer provider versions, the database is protected by two independent layers:

1. **No `delegated_subnet_id` configured**: the azurerm provider automatically prevents public network access when the server is connected exclusively via Private Endpoint.
2. **`rt-data` route table** (`0.0.0.0/0 → None`): blocks all Internet egress from the data subnet at the routing layer, regardless of the server's own network configuration. Even if someone misconfigured the server, traffic cannot leave the subnet toward the public internet.

## NSG-Data port coverage

The network project's `NSG-Data` was updated to allow traffic from the App subnet on all common data service ports:

| Port | Service |
|---|---|
| 3306 | MySQL |
| 5432 | PostgreSQL |
| 1433 | Microsoft SQL Server |
| 6379 | Redis |
| 27017 | MongoDB |
| 9092 | Kafka |
| 9093 | Kafka (SSL) |
| 9200 | Elasticsearch |
| 9042 | Cassandra |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), logged in via `az login`
- The network project (`azure-virtual-network`) already deployed — you need its `resource_group_name`, `data_subnet_ids`, and `vnet_id` outputs

## Getting the required inputs from the network project

```bash
cd azure-virtual-network
terraform output -raw resource_group_name
terraform output -json data_subnet_ids   # use index 0 (AZ1)
terraform output -raw vnet_id
```

## Configuration

Create a `terraform.tfvars` file in this directory (already excluded by `.gitignore`):

```hcl
resource_group_name = "<your-resource-group>"
location             = "<your-region>"
data_subnet_id       = "/subscriptions/<your-subscription-id>/resourceGroups/<your-resource-group>/providers/Microsoft.Network/virtualNetworks/vnet-ha/subnets/snet-data-az1"
vnet_id              = "/subscriptions/<your-subscription-id>/resourceGroups/<your-resource-group>/providers/Microsoft.Network/virtualNetworks/vnet-ha"
mysql_server_name    = "<your-globally-unique-name>"
```

> **Important:** `mysql_server_name` must be globally unique across all of Azure. Choose something specific to your project.

| Variable | Default | Description |
|---|---|---|
| `resource_group_name` | `rg-ha-vnet` | Name of the EXISTING resource group from the network project |
| `location` | `eastus` | Must match the existing VNet's region |
| `data_subnet_id` | *(required)* | Full resource ID of the existing Data subnet (AZ1) |
| `vnet_id` | *(required)* | Full resource ID of the existing VNet |
| `mysql_server_name` | `mysql-ha-vnet-demo` | Globally unique server name |
| `mysql_admin_username` | `mysqladmin` | Administrator login |
| `mysql_sku_name` | `B_Standard_B1ms` | VM size for the MySQL server |
| `mysql_storage_size_gb` | `32` | Storage in GB |
| `mysql_version` | `8.0.21` | MySQL version |

## Region note

East US (Virginia) has capacity restrictions for new Azure subscriptions that are expected to continue through mid-2026. If you hit `ProvisionNotSupportedForRegion`, try `centralus` (Iowa) or `westus2` (Washington) — both confirmed working for new subscriptions. See the [Bloomberg report](https://www.bloomberg.com/news/articles/2025-10-09/microsoft-forecasts-show-data-center-crunch-persisting-into-2026) and [The Register](https://www.theregister.com/2025/08/08/sudden_spike_in_demand_azure_issues/) for context.

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Connecting to the database

The server is only reachable from within the VNet — there is no public path to it. To connect, use the management VM in the App subnet (see `azure-jumpbox-server` project):

**Install the MySQL client on the jumpbox:**
```bash
az vm run-command invoke \
  --resource-group <your-resource-group> \
  --name <your-jumpbox-vm-name> \
  --command-id RunShellScript \
  --scripts "apt-get update -y && apt-get install -y mysql-client"
```

**Retrieve the admin password:**
```bash
terraform output -raw mysql_admin_password
```

**Connect:**
```bash
az vm run-command invoke \
  --resource-group <your-resource-group> \
  --name <your-jumpbox-vm-name> \
  --command-id RunShellScript \
  --scripts "mysql -h <your-mysql-fqdn> -u <your-admin-username> -p'<your-password>' -e 'SHOW DATABASES;'"
```

Or via Serial Console for an interactive session:
```bash
az serial-console connect \
  --resource-group <your-resource-group> \
  --name <your-jumpbox-vm-name>
```

## Outputs

| Output | Description |
|---|---|
| `mysql_server_id` | Full resource ID of the MySQL server |
| `mysql_server_fqdn` | FQDN — resolves to private IP via the linked Private DNS Zone |
| `mysql_private_endpoint_ip` | Private IP of the MySQL Private Endpoint |
| `mysql_admin_username` | Administrator username |
| `mysql_admin_password` | Generated password (sensitive — use `terraform output -raw mysql_admin_password`) |

## Destroying

```bash
terraform destroy
```

This only removes the MySQL server, Private Endpoint, and DNS Zone created by this project. The VNet, subnets, NSGs, and all other network resources remain untouched.
