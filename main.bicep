param location string = 'westus3'

var suffix = take(toLower(uniqueString(resourceGroup().id, location)), 5)

resource defaultNsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: 'default'
  location: location
  properties: {
    securityRules: [
    ]
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
            id: webappNsg.id
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
    ]
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

resource webappSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  name: 'webapp'
  parent: vnet
}

resource webapp 'Microsoft.Web/sites@2022-03-01' = {
  name: 'webapp${suffix}'
  location: location
  properties: {
    httpsOnly: true
    serverFarmId: appSvcPlan.id

    virtualNetworkSubnetId: webappSubnet.id
    vnetRouteAllEnabled: true
    vnetImagePullEnabled: true
    vnetContentShareEnabled: true
  }
}
