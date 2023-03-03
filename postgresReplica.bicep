param suffix string
param location string

param sourceServerResourceId string
param subnetId string
param privateDnsZoneId string

param tagName string

// bug? This can't be redeployed if the replica already exists
// so I'm invoking RG tag hacks to work around this
resource postgresReadReplica 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  name: 'postgres${suffix}-read'
  location: location
  sku: {
    tier: 'GeneralPurpose'
    name: 'Standard_D2s_v3'
  }
  properties: {
    createMode: 'Replica'
    sourceServerResourceId: sourceServerResourceId

    storage: {
      storageSizeGB: 32
    }
    network: {
      delegatedSubnetResourceId: subnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
  }
}

resource tags 'Microsoft.Resources/tags@2021-04-01' = {
  dependsOn: [
    postgresReadReplica
  ]

  name: 'default'
  properties: {
    tags: {
      '${tagName}': 'true'
    }
  }
}
