param location string = 'westus3'
param image string = 'fastapi:latest'

@secure()
param postgresPassword string = 'Password#1234'

var suffix = take(toLower(uniqueString(resourceGroup().id, location)), 5)

resource defaultNsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: 'default'
  location: location
  properties: {
    securityRules: [
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: 'vnet${suffix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: defaultNsg.id
          }
        }
      }
      {
        name: 'webapp'
        properties: {
          // minimum /28 (16 IPs), recommended /26 (64 IPs)
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: defaultNsg.id
          }
          delegations: [
            {
              name: 'webapp'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'postgres'
        properties: {
          // can't be resized after creation
          // minimum /28. A single HA flexible server uses 4 IPs
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: {
            // note: NSG's with ASG + postgres don't work yet
            // needs outbound rules for storage
            id: defaultNsg.id
          }
          delegations: [
            {
              name: 'postgres'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

resource defaultSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  name: 'default'
  parent: vnet
}

resource webappSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  name: 'webapp'
  parent: vnet
}

resource postgresSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  name: 'postgres'
  parent: vnet
}

resource acr 'Microsoft.ContainerRegistry/registries@2022-12-01' = {
  name: 'acr${suffix}'
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
  }
}

// attach the ACR to an ASG so that NSG rules can apply to "registries" instead of IP addresses
resource registriesASG 'Microsoft.Network/applicationSecurityGroups@2022-07-01' = {
  name: 'registries'
  location: location
}

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-07-01' = {
  name: 'acr${suffix}PrivateEndpoint'
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'default'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
    subnet: {
      id: defaultSubnet.id
    }
    applicationSecurityGroups: [
      {
        id: registriesASG.id
      }
    ]
  }
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
}

resource acrPrivateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZone
  name: vnet.name
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource acrPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-07-01' = {
  parent: acrPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'default'
        properties: {
          privateDnsZoneId: acrPrivateDnsZone.id
        }
      }
    ]
  }
}

resource keyvault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: 'kv${suffix}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

resource kvASG 'Microsoft.Network/applicationSecurityGroups@2022-07-01' = {
  name: 'keyvault'
  location: location
}

resource kvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-07-01' = {
  name: 'kv${suffix}PrivateEndpoint'
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'default'
        properties: {
          privateLinkServiceId: keyvault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
    subnet: {
      id: defaultSubnet.id
    }
    applicationSecurityGroups: [
      {
        id: kvASG.id
      }
    ]
  }
}

resource kvPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource kvPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-07-01' = {
  parent: kvPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'default'
        properties: {
          privateDnsZoneId: kvPrivateDnsZone.id
        }
      }
    ]
  }
}

resource kvPrivateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: kvPrivateDnsZone
  name: vnet.name
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource postgresPasswordKVSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyvault
  name: 'postgresPassword'
  properties: {
    value: postgresPassword
  }
}

resource appSvcPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'appSvcPlan${suffix}'
  location: location
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

resource webapp 'Microsoft.Web/sites@2022-03-01' = {
  name: 'webapp${suffix}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    httpsOnly: true
    serverFarmId: appSvcPlan.id

    virtualNetworkSubnetId: webappSubnet.id
    vnetRouteAllEnabled: true
    vnetImagePullEnabled: true
    vnetContentShareEnabled: true

    siteConfig: {
      linuxFxVersion: 'DOCKER|${acr.properties.loginServer}/${image}'
      acrUseManagedIdentityCreds: true
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8000'
        }
        {
          name: 'PGHOST'
          value: postgres.properties.fullyQualifiedDomainName
        }
        {
          name: 'PGPORT'
          value: '5432'
        }
        {
          name: 'PGSSLMODE'
          value: 'require'
        }
        {
          name: 'PGDATABASE'
          value: 'postgres'
        }
        {
          name: 'PGUSER'
          value: postgres.properties.administratorLogin
        }
        {
          // https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references?tabs=azure-cli
          // docs are wrong. If you include a trailing slash w/o specifying the version, it will fail
          name: 'PGPASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyvault.name}.vault.azure.net/secrets/${postgresPasswordKVSecret.name})'
        }
      ]
    }
  }
}

// from https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
resource acrPull 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
}

resource webappACRRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(webapp.id, acr.id, acrPull.id)
  scope: acr
  properties: {
    roleDefinitionId: acrPull.id
    principalId: webapp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsUser 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource webappKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(webapp.id, keyvault.id, keyVaultSecretsUser.id)
  scope: keyvault
  properties: {
    roleDefinitionId: keyVaultSecretsUser.id
    principalId: webapp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource postgresDNS 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'private.postgres.database.azure.com'
  location: 'global'
}

resource postgresDNSVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresDNS
  name: vnet.name
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// Flexible server:
// can't change network mode after creation - it's either VNet Integration or public IP
// Vnet needs subnet delegation and private dns zone
// can't be moved. doesn't support private link
// Single server, CosmosDB for PostgreSQL have a more typical network setup
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  // the DNS/VNET link must exist before provisioning
  dependsOn: [
    postgresDNSVnetLink
  ]

  name: 'postgres${suffix}'
  location: location
  sku: {
    tier: 'GeneralPurpose'
    name: 'Standard_D2s_v3'
  }
  properties: {
    version: '14'
    administratorLogin: 'azureuser'
    administratorLoginPassword: postgresPassword
    storage: {
      storageSizeGB: 32
    }
    network: {
      delegatedSubnetResourceId: postgresSubnet.id
      privateDnsZoneArmResourceId: postgresDNS.id
    }
  }
}

resource postgresReadReplica 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  dependsOn: [
    postgresDNSVnetLink
  ]

  name: 'postgres${suffix}-read'
  location: location
  sku: {
    tier: 'GeneralPurpose'
    name: 'Standard_D2s_v3'
  }
  properties: {
    createMode: 'Replica'
    sourceServerResourceId: postgres.id

    storage: {
      storageSizeGB: 32
    }
    network: {
      delegatedSubnetResourceId: postgresSubnet.id
      privateDnsZoneArmResourceId: postgresDNS.id
    }
  }
}
