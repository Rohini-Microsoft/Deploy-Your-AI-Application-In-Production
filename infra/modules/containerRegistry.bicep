@minLength(5)
@description('Name of the Container Registry.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Resource ID of the virtual network to link the private DNS zones.')
param virtualNetworkResourceId string

@description('Resource ID of the subnet for the private endpoint.')
param virtualNetworkSubnetResourceId string

@description('Resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Specifies whether network isolation is enabled. This will create a private endpoint for the Container Registry and link the private DNS zone.')
param networkIsolation bool = true

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation) {
  name: 'private-dns-acr-deployment'
  params: {
    name: 'privatelink.${toLower(environment().name) == 'azureusgovernment' ? 'azurecr.us' : 'azurecr.io'}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

var nameFormatted = take(toLower(name), 50)

module containerRegistry 'br/public:avm/res/container-registry/registry:0.8.4' = {
  name: take('${nameFormatted}-container-registry-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [privateDnsZone]  // required due to optional flags that could change dependency
  params: {
    name: nameFormatted
    location: location
    tags: tags
    acrSku: 'Premium'
    acrAdminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    networkRuleSetDefaultAction: networkIsolation ? 'Deny' : 'Allow'
    exportPolicyStatus: networkIsolation ? 'disabled' : 'enabled'
    publicNetworkAccess: networkIsolation ? 'Disabled' : 'Enabled' 
    zoneRedundancy: 'Disabled'
    managedIdentities: {
      systemAssigned: true
    }
    diagnosticSettings:[
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
      } 
    ]
    privateEndpoints: networkIsolation ? [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
            }
          ]
        }
        subnetResourceId: virtualNetworkSubnetResourceId
      }
    ] : []
  }
}

output resourceId string = containerRegistry.outputs.resourceId
output loginServer string = containerRegistry.outputs.loginServer
output name string = containerRegistry.outputs.name
