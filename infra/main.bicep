targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = 'westeurope'

@description('Deployment environment name used in resource naming.')
param environmentName string = 'dev'

@description('Base name used to derive globally unique resource names.')
param baseName string = 'iiot-anomaly'

@description('IoT Hub name.')
param iotHubName string = 'iiot-anomaly-s1-dev'

@description('IoT Hub SKU. S1 is the default for the shared dev environment.')
@allowed([
  'F1'
  'S1'
])
param iotHubSkuName string = 'S1'

@description('Number of IoT Hub units. F1 only supports 1.')
@minValue(1)
param iotHubSkuCapacity int = 1

@description('Device identity to register in IoT Hub.')
param deviceId string = 'sensor-dev-001'

@description('Consumer group used by downstream telemetry processors.')
param iotHubConsumerGroupName string = 'telemetry-consumers'

@description('Dedicated consumer group used by Stream Analytics.')
param iotHubAsaConsumerGroupName string = 'asa-consumers'

@description('Blob container for the bronze/raw telemetry landing zone.')
param telemetryContainerName string = 'raw-telemetry'

var normalizedBaseName = toLower(replace(baseName, '-', ''))
var normalizedEnvironmentName = toLower(environmentName)
var uniqueSuffix = uniqueString(subscription().subscriptionId, resourceGroup().id)
var storageAccountName = take(toLower('st${normalizedBaseName}${normalizedEnvironmentName}${uniqueSuffix}'), 24)
var adxClusterName = take(toLower('adx${normalizedEnvironmentName}${uniqueSuffix}'), 22)
var adxDatabaseName = 'telemetry'
var adxAnomalyTableName = 'SensorAnomalies'
var streamAnalyticsJobName = take(toLower('${baseName}-${normalizedEnvironmentName}-asa-${uniqueSuffix}'), 63)
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
    asaConsumerGroupName: iotHubAsaConsumerGroupName
    deviceId: deviceId
    tags: tags
  }
}

module adx './modules/adx.bicep' = {
  name: 'adxDeployment'
  params: {
    location: location
    clusterName: adxClusterName
    databaseName: adxDatabaseName
    anomalyResultsTableName: adxAnomalyTableName
    iotHubResourceId: iotHub.outputs.resourceId
    consumerGroupName: iotHub.outputs.consumerGroupName
    tags: tags
  }
}

module streamAnalytics './modules/stream-analytics.bicep' = {
  name: 'streamAnalyticsDeployment'
  params: {
    location: location
    streamAnalyticsJobName: streamAnalyticsJobName
    iotHubName: iotHub.outputs.iotHubName
    consumerGroupName: iotHub.outputs.asaConsumerGroupName
    storageAccountName: storage.outputs.storageAccountName
    blobContainerName: storage.outputs.containerName
    adxClusterName: adx.outputs.clusterName
    adxClusterUri: adx.outputs.clusterUri
    adxDatabaseName: adx.outputs.databaseName
    adxAnomalyTableName: adx.outputs.anomalyTableName
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
  asaConsumerGroupName: iotHub.outputs.asaConsumerGroupName
  deviceId: iotHub.outputs.deviceId
  serviceConnectionStringCommand: iotHub.outputs.serviceConnectionStringCommand
  deviceConnectionStringCommand: iotHub.outputs.deviceConnectionStringCommand
}
output adxClusterUri string = adx.outputs.clusterUri
output adxDatabaseName string = adx.outputs.databaseName
output streamAnalyticsJobName string = streamAnalytics.outputs.jobName
output storageAccountName string = storage.outputs.storageAccountName
output rawTelemetryContainerName string = storage.outputs.containerName
output rawTelemetryContainerUrl string = storage.outputs.containerUrl
