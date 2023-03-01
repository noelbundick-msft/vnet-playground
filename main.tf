provider "azurerm" {
  features {}

  skip_provider_registration = true
}

variable "region" {
  type    = string
  default = "westus3"
}

variable "rg" {
  type    = string
  default = "test2"
}

// these have to be separate in Terraform even though they just get concatenated back into one string
variable "image" {
  type    = string
  default = "fastapi"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "postgres_password" {
  type      = string
  default   = "Password#1234"
  sensitive = true
}

resource "random_string" "suffix" {
  keepers = {
    resource_group = var.rg
  }

  length  = 5
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = var.rg
  location = var.region
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  address_space = ["10.0.0.0/16"]
}

resource "azurerm_network_security_group" "default" {
  name                = "default"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "default" {
  subnet_id                 = azurerm_subnet.default.id
  network_security_group_id = azurerm_network_security_group.default.id
}

resource "azurerm_subnet" "webapp" {
  name                 = "webapp"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "webapp"
    service_delegation {
      name = "Microsoft.Web/serverFarms"

      # hack: to get terraform not to detect state changes when there are none
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "webapp" {
  subnet_id                 = azurerm_subnet.webapp.id
  network_security_group_id = azurerm_network_security_group.default.id
}

resource "azurerm_subnet" "postgres" {
  name                 = "postgres"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  # hack: to get terraform not to detect state changes when there are none
  service_endpoints = [
    "Microsoft.Storage"
  ]

  delegation {
    name = "postgres"

    # hack: to get terraform not to detect state changes when there are none
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "postgres" {
  subnet_id                 = azurerm_subnet.postgres.id
  network_security_group_id = azurerm_network_security_group.default.id
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Premium"
  admin_enabled       = false
}

resource "azurerm_private_endpoint" "acr" {
  name                = "acr${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.default.id

  private_service_connection {
    name                           = "default"
    private_connection_resource_id = azurerm_container_registry.acr.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "acr${random_string.suffix.result}"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.acr.id
    ]
  }
}

resource "azurerm_application_security_group" "registries" {
  name                = "registries"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_endpoint_application_security_group_association" "acr_registries" {
  private_endpoint_id           = azurerm_private_endpoint.acr.id
  application_security_group_id = azurerm_application_security_group.registries.id
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = azurerm_virtual_network.vnet.name
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

data "azurerm_subscription" "current" {
}

resource "azurerm_key_vault" "keyvault" {
  name                      = "kv${random_string.suffix.result}"
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name
  tenant_id                 = data.azurerm_subscription.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
  
  # TODO: going to have to jump through hoops and make this work (run this step from inside the created VNET / etc).
  # NOTE: Azure DeploymentScripts don't support VNET: https://github.com/Azure/bicep/issues/6540
  # public_network_access_enabled = false
}

resource "azurerm_application_security_group" "keyvault" {
  name                = "keyvault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = azurerm_virtual_network.vnet.name
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "keyvault" {
  name                = "kv${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.default.id

  private_service_connection {
    name                           = "default"
    private_connection_resource_id = azurerm_key_vault.keyvault.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "kv${random_string.suffix.result}"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.keyvault.id
    ]
  }
}

// Terraform doesn't use ARM to set secrets, so you have to grant a role assignment to the current executing principal here
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "currentuserKeyVaultRoleAssignment" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

// note: this duplicates the secret value in plaintext in the state file, which is terrible
resource "azurerm_key_vault_secret" "postgresPassword" {
  name         = "postgresPassword"
  value        = var.postgres_password
  key_vault_id = azurerm_key_vault.keyvault.id

  depends_on = [
    azurerm_role_assignment.currentuserKeyVaultRoleAssignment
  ]
}

resource "azurerm_service_plan" "appSvcPlan" {
  name                = "appSvcPlan${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "webapp" {
  name                = "webapp${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.appSvcPlan.location
  service_plan_id     = azurerm_service_plan.appSvcPlan.id

  https_only = true
  identity {
    type = "SystemAssigned"
  }

  virtual_network_subnet_id = azurerm_subnet.webapp.id

  // https://learn.microsoft.com/en-us/azure/app-service/configure-vnet-integration-routing
  // uses different (not the recommended) properties. Some are missing.
  site_config {
    vnet_route_all_enabled                  = true
    container_registry_use_managed_identity = true
    application_stack {
      // 2023-02-24: this is NOT private, and will only work if the ACR frontend is public
      // https://github.com/hashicorp/terraform-provider-azurerm/issues/19096
      docker_image     = "${azurerm_container_registry.acr.login_server}/${var.image}"
      docker_image_tag = var.image_tag
    }
  }

  app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_PORT                       = "8000"
    PGHOST                              = azurerm_postgresql_flexible_server.postgres.fqdn
    PGPORT                              = "5432"
    PGSSLMODE                           = "require"
    PGDATABASE                          = "postgres"
    PGUSER                              = azurerm_postgresql_flexible_server.postgres.administrator_login
    PGPASSWORD                          = "@Microsoft.KeyVault(SecretUri=https://${azurerm_key_vault.keyvault.name}.vault.azure.net/secrets/${azurerm_key_vault_secret.postgresPassword.name})"
  }
}

data "azurerm_linux_web_app" "webapp" {
  name                = azurerm_linux_web_app.webapp.name
  resource_group_name = azurerm_linux_web_app.webapp.resource_group_name
}

// the terraform docs don't seem to match reality here, we seem to have to do an extra lookup
resource "azurerm_role_assignment" "webappACRRoleAssignment" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azurerm_linux_web_app.webapp.identity.0.principal_id
}

resource "azurerm_role_assignment" "webappKeyVaultRoleAssignment" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_linux_web_app.webapp.identity.0.principal_id
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = azurerm_virtual_network.vnet.name
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "postgres${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "14"
  delegated_subnet_id    = azurerm_subnet.postgres.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = "azureuser"
  administrator_password = var.postgres_password

  storage_mb = 32768

  sku_name   = "GP_Standard_D2s_v3"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  # hack: to get terraform not to detect state changes when there are none
  zone = "1"
}

resource "azurerm_postgresql_flexible_server" "readReplica" {
  name                = "postgres${random_string.suffix.result}-read"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  create_mode      = "Replica"
  source_server_id = azurerm_postgresql_flexible_server.postgres.id

  storage_mb = 32768

  sku_name   = "GP_Standard_D2s_v3"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  # hack: to get terraform not to detect state changes when there are none
  zone = "1"
}
