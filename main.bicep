param location string = 'westus3'

var suffix = take(toLower(uniqueString(resourceGroup().id, location)), 5)

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: 'vnet${suffix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource defaultNsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: 'default'
  location: location
  properties: {
    securityRules: [
    ]
  }
}

resource defaultSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' = {
  name: 'default'
  parent: vnet
  properties: {
    addressPrefix: '10.0.0.0/24'
  }
}

resource webappNsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: 'webapp'
  location: location
  properties: {
    securityRules: [
    ]
  }
}

resource webappSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' = {
  name: 'webapp'
  parent: vnet
  properties: {
    // minimum /28 (16 IPs), recommended /26 (64 IPs)
    addressPrefix: '10.0.1.0/24'
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
