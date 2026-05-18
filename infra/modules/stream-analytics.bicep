@description('Azure region for the Stream Analytics job.')
param location string

@description('Name of the Stream Analytics job.')
param streamAnalyticsJobName string

@description('IoT Hub name used as the streaming input namespace.')
param iotHubName string

@description('Dedicated consumer group for the Stream Analytics input.')
param consumerGroupName string

@description('Storage account name used for the raw telemetry archive.')
param storageAccountName string

@description('Blob container name used for the raw telemetry archive.')
param blobContainerName string

@description('Azure Data Explorer cluster name.')
param adxClusterName string

@description('Azure Data Explorer cluster URI.')
param adxClusterUri string

@description('Azure Data Explorer database name.')
param adxDatabaseName string

@description('Azure Data Explorer table name for anomaly results.')
param adxAnomalyTableName string = 'SensorAnomalies'

@description('Optional tags applied to the Stream Analytics job.')
param tags object = {}

var asaQuery = loadTextContent('../../stream-jobs/anomaly-detection.asaql')
var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var iotHubServicePolicyKeys = listKeys('${iotHub.id}/IotHubKeys/service', '2021-07-02')

resource iotHub 'Microsoft.Devices/IotHubs@2021-07-02' existing = {
  name: iotHubName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource adxCluster 'Microsoft.Kusto/clusters@2023-05-02' existing = {
  name: adxClusterName
}

resource adxDatabase 'Microsoft.Kusto/clusters/databases@2023-05-02' existing = {
  parent: adxCluster
  name: adxDatabaseName
}

resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Standard'
  }
  tags: tags
  properties: {
    compatibilityLevel: '1.2'
    dataLocale: 'en-US'
    eventsLateArrivalMaxDelayInSeconds: 15
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsOutOfOrderPolicy: 'Adjust'
    jobType: 'Cloud'
    outputErrorPolicy: 'Stop'
  }
}

resource rawTelemetryArchiveAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, streamAnalyticsJob.name, 'raw-telemetry-archive')
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource adxIngestorAccess 'Microsoft.Kusto/clusters/databases/principalAssignments@2023-05-02' = {
  parent: adxDatabase
  name: 'asa-ingestor'
  properties: {
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'App'
    role: 'Ingestor'
    tenantId: subscription().tenantId
  }
}

resource iotHubTelemetryInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'iotHubTelemetry'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.Devices/IotHubs'
      properties: {
        consumerGroupName: consumerGroupName
        endpoint: 'messages/events'
        iotHubNamespace: iotHub.name
        sharedAccessPolicyKey: iotHubServicePolicyKeys.primaryKey
        sharedAccessPolicyName: 'service'
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
        format: 'LineSeparated'
      }
    }
  }
}

resource adxAnomalyOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'adxAnomalyOutput'
  properties: {
    datasource: {
      type: 'Microsoft.Kusto/clusters/databases'
      properties: {
        authenticationMode: 'Msi'
        cluster: adxClusterUri
        database: adxDatabaseName
        table: adxAnomalyTableName
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
        format: 'LineSeparated'
      }
    }
  }
  dependsOn: [
    adxIngestorAccess
  ]
}

resource rawArchiveOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'rawArchiveOutput'
  properties: {
    datasource: {
      type: 'Microsoft.Storage/Blob'
      properties: {
        authenticationMode: 'Msi'
        blobPathPrefix: 'raw/{date}/{time}'
        blobWriteMode: 'Append'
        container: blobContainerName
        dateFormat: 'yyyy/MM/dd'
        pathPattern: '{date}/{time}'
        storageAccounts: [
          {
            accountName: storageAccount.name
            authenticationMode: 'Msi'
          }
        ]
        timeFormat: 'HH'
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
        format: 'LineSeparated'
      }
    }
  }
  dependsOn: [
    rawTelemetryArchiveAccess
  ]
}

resource transformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'anomalyDetection'
  properties: {
    query: asaQuery
    streamingUnits: 1
  }
}

output jobName string = streamAnalyticsJob.name
