targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = 'westeurope'

@description('Deployment environment name used in resource naming.')
param environmentName string = 'dev'

@description('Base name used to derive globally unique resource names.')
param baseName string = 'iiot-anomaly'

@description('IoT Hub SKU. F1 is suitable for dev/test, S1 for paid workloads.')
@allowed([
  'F1'
  'S1'
])
param iotHubSkuName string = 'F1'

@description('Number of IoT Hub units. F1 only supports 1.')
@minValue(1)
param iotHubSkuCapacity int = 1

@description('Device identity to register in IoT Hub.')
param deviceId string = 'sensor-dev-001'

@description('Consumer group used by downstream telemetry processors.')
param iotHubConsumerGroupName string = 'telemetry-consumers'

@description('Blob container for the bronze/raw telemetry landing zone.')
param telemetryContainerName string = 'raw-telemetry'

var normalizedBaseName = toLower(replace(baseName, '-', ''))
var normalizedEnvironmentName = toLower(environmentName)
var iotHubName = take(toLower('${baseName}-${normalizedEnvironmentName}-${uniqueString(subscription().subscriptionId, resourceGroup().id)}'), 50)
var storageAccountName = take(toLower('st${normalizedBaseName}${normalizedEnvironmentName}${uniqueString(subscription().subscriptionId, resourceGroup().id)}'), 24)
var tags = {
  environment: environmentName
  workload: 'industrial-iot-anomaly-pipeline'
  managedBy: 'bicep'
}

module storage './modules/storage.bicep' = {
  name: 'storageDeployment'
  params: {
    location: location
    storageAccountName: storageAccountName
    blobContainerName: telemetryContainerName
    tags: tags
  }
}

module iotHub './modules/iot-hub.bicep' = {
  name: 'iotHubDeployment'
  params: {
    location: location
    iotHubName: iotHubName
    skuName: iotHubSkuName
    skuCapacity: iotHubSkuCapacity
    consumerGroupName: iotHubConsumerGroupName
    deviceId: deviceId
    tags: tags
  }
}

output iotHubName string = iotHub.outputs.iotHubName
output iotHubHostname string = iotHub.outputs.hostName
output iotHubConnectionInfo object = {
  hostName: iotHub.outputs.hostName
  eventHubCompatibleEndpoint: iotHub.outputs.builtInEventHubEndpoint
  eventHubCompatiblePath: iotHub.outputs.builtInEventHubPath
  consumerGroupName: iotHub.outputs.consumerGroupName
  deviceId: iotHub.outputs.deviceId
  serviceConnectionStringCommand: iotHub.outputs.serviceConnectionStringCommand
  deviceConnectionStringCommand: iotHub.outputs.deviceConnectionStringCommand
}
output storageAccountName string = storage.outputs.storageAccountName
output rawTelemetryContainerName string = storage.outputs.containerName
output rawTelemetryContainerUrl string = storage.outputs.containerUrl
