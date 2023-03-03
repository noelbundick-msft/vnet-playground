param location string = 'westus3'

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
    publicNetworkAccess: 'disabled'
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

resource aks 'Microsoft.ContainerService/managedClusters@2022-11-01' = {
  name: 'aks${suffix}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Paid'
  }
  properties: {
    kubernetesVersion: '1.25.5'
    enableRBAC: true
    dnsPrefix: 'aks${suffix}'
    agentPoolProfiles: [
      {
        name: 'default'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        vmSize: 'Standard_D2as_v5'
        osType: 'Linux'
        enableAutoScaling: true
        count: 1
        minCount: 1
        maxCount: 5
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        maxPods: 110
        vnetSubnetID: defaultSubnet.id
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
      dockerBridgeCidr: '172.17.0.1/16'
    }
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    addonProfiles: {
      httpApplicationRouting: {
        enabled: true
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'false'
          rotationPollInterval: '2m'
        }
      }
    }
  }
}

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'app${suffix}'
  location: location
}

resource appIdentityCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2022-01-31-preview' = {
  parent: appIdentity
  name: 'aks${suffix}'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:default:myserviceaccount'
  }
}

// from https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
resource acrPull 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acr.id, acrPull.id)
  scope: acr
  properties: {
    roleDefinitionId: acrPull.id
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsUser 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource webappKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appIdentity.name, keyvault.id, keyVaultSecretsUser.id)
  scope: keyvault
  properties: {
    roleDefinitionId: keyVaultSecretsUser.id
    principalId: appIdentity.properties.principalId
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
// Automating AAD auth to grant a limited role on the web app would be difficult. A SP/identity can be granted access, but deploymentScripts don't support VNET integration
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
    authConfig: {
      passwordAuth: 'Enabled'
      activeDirectoryAuth: 'Enabled'
      tenantId: subscription().tenantId
    }
  }
}

// Must be done separately because `name` must be known at deployment time
module postgresAADAdmin './postgresAdmin.bicep' = {
  name: 'postgresAADAdmin'
  params: {
    postgresServer: postgres.name
    principalId: appIdentity.properties.principalId
    principalName: 'app'
  }
}

// postgres read replica deployments are not idempotent as of 2023-03-03, so I'm invoking an old ARM hack to get around it
// The basic idea is:
// * check for a tag on the resource group that indicates the read replica has been created
// A) if the tag doesn't exist, create the replica
//    write the tag only after the replica is created
// B) if the tag exists, skip replica creation
var postgresReadReplicaTag = 'readReplicaExists'
var postgresReadReplicaExists = contains(resourceGroup().tags, postgresReadReplicaTag) && resourceGroup().tags[postgresReadReplicaTag] == 'true'

module postgresReadReplica './postgresReplica.bicep' = if (!postgresReadReplicaExists) {
  dependsOn: [
    postgresDNSVnetLink

    // force the AAD config on the primary to be created before creating the replica
    postgresAADAdmin
  ]

  name: 'postgresReadReplica'
  params: {
    location: location
    suffix: suffix
    sourceServerResourceId: postgres.id
    subnetId: postgresSubnet.id
    privateDnsZoneId: postgresDNS.id
    tagName: postgresReadReplicaTag
  }
}
