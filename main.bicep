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
