targetScope = 'subscription'

@minLength(3)
@maxLength(9)
@description('Used as the prefix to name provisioned resources where a custom name is not provided. Should be alphanumeric, at least 3 characters and no more than 9 characters.')
param serviceName string

@description('Location where the resources are deployed.')
@allowed([
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'canadaeast'
  'centralindia'
  'centralus'
  'chinanorth3'
  'eastasia'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'northcentralus'
  'northeurope'
  'norwayeast'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus'
  'westus2'
  'westus3'
])
param location string

@description('The UTC timestamp in the format yyyyMMddHHmmss to append to each of the deployment names to ensure each deployment is uniquely named. Default value is the current time.')
param timestamp string = utcNow('yyyyMMddHHmmss')

@description('Name of the resource group to deploy the resources to. If the resource group does not already exist, a new resource group will be provisioned with the given name or, if a name is not provided, with an autogenerated name based on serviceName.')
param resourceGroupName string = '${serviceName}-rg'

@description('Set to true to deploy a storage account for storing custom templates.')
param deployTemplateStore bool = false

@description('Set to true to enable usage of custom templates stored in specified template store. If false, only default templates can be used.')
param useCustomTemplates bool = false

@description('Name of storage account containing custom templates. If a name is not provided and deployTemplateStore is true, an autogenerated name based on serviceName will be used.')
param templateStorageAccountName string = '${serviceName}storageaccount'

@description('Name of storage account container containing custom templates. If a name is not provided and deployTemplateStore is true, an autogenerated name based on serviceName will be used.')
param templateStorageAccountContainerName string = '${serviceName}storagecontainer'

@description('If set to true, a key vault and user assigned managed identity will be deployed. A key vault is required to allow logs and metrics to flow to application insights.')
param deployKeyVault bool = true

@description('Name of the key vault to be deployed. If a name is not provided and deployTemplateStore is true, an autogenerated name based on serviceName will be used.')
param keyVaultName string = deployKeyVault ? '${serviceName}-kv' : ''

@description('Name of the user-assigned managed identity to be deployed for accessing the key vault. If a name is not provided and deployTemplateStore is true, an autogenerated name based on serviceName will be used.')
param keyVaultUserAssignedIdentityName string = deployKeyVault ? '${serviceName}-kv-identity' : ''

@description('Name of the container app environment. If a name is not provided, an autogenerated name based on serviceName will be used.')
param containerAppEnvName string = '${serviceName}-app-env'

@description('Name of the container app to run the FHIR Converter service. If a name is not provided, an autogenerated name based on serviceName will be used.')
param containerAppName string = '${serviceName}-app'

@description('Minimum number of replicas for the container app.')
param minReplicas int = 0

@description('Maximum number of replicas for the container app.')
param maxReplicas int = 30

@description('CPU limit for the container app.')
param cpuLimit string = '1.0'

@description('Memory limit for the container app.')
param memoryLimit string = '2Gi'

@description('If set to true, security requirements will be enabled on the API endpoint.')
param securityEnabled bool = false

@description('Audiences for the api authentication.')
param securityAuthenticationAudiences array = []

@description('Authority for the api authentication.')
param securityAuthenticationAuthority string = ''

@description('If set to true, a new application insights instance will be deployed.')
param deployApplicationInsights bool = true

@description('If set to true, application logs and metrics will be sent to the specified application insights instance.')
param useApplicationInsights bool = true

@description('Name of the application insights instance to send application logs and metrics to.')
param applicationInsightsName string = deployApplicationInsights ? '${serviceName}-app-insights' : ''

@description('The name of the secret in the key vault containing the app insights connection string.')
param applicationInsightsConnStringSecretName string = deployApplicationInsights ? '${serviceName}-app-insights-conn-string' : ''

@description('The tag of the image to pull from MCR. To see available image tags, visit the [FHIR Converter MCR page](https://mcr.microsoft.com/en-us/product/healthcareapis/fhir-converter/tags)')
param containerAppImageTag string

var deploymentTemplateVersion = '1'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: resourceGroupName
  location: location
  tags: {
    fhirConverterDeploymentTemplateVersion: deploymentTemplateVersion
  }
}

module dependentResourcesDeploy 'Deploy-DependentResources.bicep' = if (deployTemplateStore || deployKeyVault) {
  name: 'dependentResourcesDeploy_${timestamp}'
  scope: resourceGroup
  params: {
    location: location
    deployTemplateStore: deployTemplateStore
    templateStorageAccountName: templateStorageAccountName
    templateStorageAccountContainerName: templateStorageAccountContainerName
    deployKeyVault: deployKeyVault
    keyVaultName: keyVaultName
    keyVaultUserAssignedIdentityName: keyVaultUserAssignedIdentityName
  }
}

module convertInfrastructureDeploy 'Deploy-Infrastructure.bicep' = {
  name: 'convertInfrastructureDeploy_${timestamp}'
  scope: resourceGroup
  params: {
    location: location
    envName: containerAppEnvName
    deployApplicationInsights: deployApplicationInsights
    applicationInsightsName: applicationInsightsName
    keyVaultName: keyVaultName
  }
}

module fhirConverterDeploy 'Deploy-FhirConverterService.bicep' = {
  name: 'fhirConverterDeploy_${timestamp}'
  scope: resourceGroup
  params: {
    location: location
    appName: containerAppName
    imageTag: containerAppImageTag
    envName: convertInfrastructureDeploy.outputs.containerAppEnvironmentName
    containerAppEnvironmentId: convertInfrastructureDeploy.outputs.containerAppEnvironmentId
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    cpuLimit: cpuLimit
    memoryLimit: memoryLimit
    securityEnabled: securityEnabled
    securityAuthenticationAudiences: securityAuthenticationAudiences
    securityAuthenticationAuthority: securityAuthenticationAuthority
    useCustomTemplates: useCustomTemplates
    templateStorageAccountName: deployTemplateStore ? dependentResourcesDeploy.outputs.templateStorageAccountName : ''
    templateStorageAccountContainerName: deployTemplateStore ? dependentResourcesDeploy.outputs.templateStorageAccountContainerName : templateStorageAccountContainerName
    keyVaultName: deployKeyVault ? dependentResourcesDeploy.outputs.keyVaultName : keyVaultName
    keyVaultUAMIName: deployKeyVault ? dependentResourcesDeploy.outputs.keyVaultUAMIName : keyVaultUserAssignedIdentityName
    useApplicationInsights: useApplicationInsights
    applicationInsightsUAMIName: deployApplicationInsights ? convertInfrastructureDeploy.outputs.applicationInsightsUAMIName : applicationInsightsName
    applicationInsightsConnStringSecretName: deployApplicationInsights ? convertInfrastructureDeploy.outputs.appInsightsConnStringSecretName : applicationInsightsConnStringSecretName
  }
  dependsOn: [
    dependentResourcesDeploy
    convertInfrastructureDeploy
  ]
}

output fhirConverterApiEndpoint string = fhirConverterDeploy.outputs.containerAppFQDN
output resourceGroupName string = resourceGroup.name
