@description('Azure region for the ADX cluster and database.')
param location string

@description('Globally unique Azure Data Explorer cluster name.')
param clusterName string

@description('ADX database name.')
param databaseName string = 'telemetry'

@description('Telemetry table name for direct IoT Hub ingestion.')
param sensorReadingsTableName string = 'SensorReadings'

@description('JSON ingestion mapping name for the telemetry table.')
param sensorReadingsMappingName string = 'SensorReadingsJsonMapping'

@description('ADX table used for Stream Analytics anomaly results.')
param anomalyResultsTableName string = 'SensorAnomalies'

@description('Resource ID of the IoT Hub wired into the ingestion data connection.')
param iotHubResourceId string

@description('Consumer group used by the ADX IoT Hub data connection.')
param consumerGroupName string

@description('Optional tags applied to ADX resources.')
param tags object = {}

var tableSetupScript = '''.create-merge table SensorReadings (
    device_id:string,
    seq:long,
    temperature_c:real,
    vibration_raw:int,
    timestamp:datetime,
    bridge_version:string,
    ingestion_time:datetime
)

.create-or-alter table SensorReadings ingestion json mapping 'SensorReadingsJsonMapping'
'[{"column":"device_id","path":"$.device_id"},{"column":"seq","path":"$.seq"},{"column":"temperature_c","path":"$.temperature_c"},{"column":"vibration_raw","path":"$.vibration_raw"},{"column":"timestamp","path":"$.timestamp"},{"column":"bridge_version","path":"$.bridge_version"}]'

.create-merge table SensorAnomalies (
    device_id:string,
    seq:long,
    temperature_c:real,
    vibration_raw:int,
    event_timestamp:datetime,
    bridge_version:string,
    temperature_anomaly_score:real,
    temperature_is_anomaly:long,
    vibration_anomaly_score:real,
    vibration_is_anomaly:long,
    ingestion_time:datetime
)
'''

resource cluster 'Microsoft.Kusto/clusters@2023-05-02' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Dev(No SLA)_Standard_E2a_v4'
    capacity: 1
    tier: 'Basic'
  }
  properties: {
    enableAutoStop: true
    enableDiskEncryption: false
    enableDoubleEncryption: false
    enablePurge: false
    enableStreamingIngest: true
    engineType: 'V2'
    publicIPType: 'IPv4'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
    trustedExternalTenants: []
  }
}

resource database 'Microsoft.Kusto/clusters/databases@2023-05-02' = {
  parent: cluster
  name: databaseName
  location: location
  kind: 'ReadWrite'
  properties: {
    hotCachePeriod: 'P1D'
    softDeletePeriod: 'P30D'
  }
}

resource databaseScript 'Microsoft.Kusto/clusters/databases/scripts@2023-05-02' = {
  parent: database
  name: 'telemetry-schema'
  properties: {
    continueOnErrors: false
    forceUpdateTag: guid(tableSetupScript)
    scriptContent: tableSetupScript
  }
}

resource telemetryConnection 'Microsoft.Kusto/clusters/databases/dataConnections@2023-05-02' = {
  parent: database
  name: 'sensorreadings-iothub'
  location: location
  kind: 'IotHub'
  properties: {
    consumerGroup: consumerGroupName
    dataFormat: 'JSON'
    databaseRouting: 'Single'
    eventSystemProperties: [
      'iothub-connection-device-id'
      'iothub-enqueuedtime'
    ]
    iotHubResourceId: iotHubResourceId
    mappingRuleName: sensorReadingsMappingName
    sharedAccessPolicyName: 'iothubowner'
    tableName: sensorReadingsTableName
  }
  dependsOn: [
    databaseScript
  ]
}

output clusterName string = cluster.name
output clusterUri string = 'https://${cluster.name}.${location}.kusto.windows.net'
output databaseName string = database.name
output anomalyTableName string = anomalyResultsTableName
