param postgresServer string
param principalId string
param principalName string

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' existing = {
  name: postgresServer
}

resource postgresAADAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2022-12-01' = {
  parent: postgres
  name: principalId
  properties: {
    tenantId: subscription().tenantId
    principalName: principalName
    principalType: 'ServicePrincipal'
  }
}
