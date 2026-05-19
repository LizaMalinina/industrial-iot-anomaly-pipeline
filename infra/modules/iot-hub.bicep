var iotHubApiVersion = '2021-07-02'

@description('Azure region for the IoT Hub.')
param location string

@description('Globally unique IoT Hub name.')
@minLength(3)
@maxLength(50)
param iotHubName string = 'iiot-anomaly-s1-dev'

@description('IoT Hub SKU. Use S1 for standard tier or F1 for free tier.')
@allowed([
  'F1'
  'S1'
])
param skuName string = 'S1'

@description('Number of IoT Hub units. F1 only supports 1.')
@minValue(1)
param skuCapacity int = 1

@description('Consumer group for downstream readers of the built-in events endpoint.')
param consumerGroupName string

@description('Dedicated consumer group for the Stream Analytics job.')
param asaConsumerGroupName string = 'asa-consumers'

@description('Device identity to register in the hub.')
param deviceId string

@description('Optional tags applied to the IoT Hub resource.')
param tags object = {}

resource iotHub 'Microsoft.Devices/IotHubs@2021-07-02' = {
  name: iotHubName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
    minTlsVersion: '1.2'
    features: 'None'
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: skuName == 'F1' ? 2 : 4
      }
    }
    cloudToDevice: {
      defaultTtlAsIso8601: 'PT1H'
      maxDeliveryCount: 10
      feedback: {
        ttlAsIso8601: 'PT1H'
        lockDurationAsIso8601: 'PT1M'
        maxDeliveryCount: 10
      }
    }
    messagingEndpoints: {
      fileNotifications: {
        ttlAsIso8601: 'PT1H'
        lockDurationAsIso8601: 'PT1M'
        maxDeliveryCount: 10
      }
    }
  }
}

resource consumerGroup 'Microsoft.Devices/IotHubs/eventHubEndpoints/ConsumerGroups@2021-07-02' = {
  name: '${iotHub.name}/events/${consumerGroupName}'
  properties: {
    name: consumerGroupName
  }
}

resource asaConsumerGroup 'Microsoft.Devices/IotHubs/eventHubEndpoints/ConsumerGroups@2021-07-02' = {
  name: '${iotHub.name}/events/${asaConsumerGroupName}'
  properties: {
    name: asaConsumerGroupName
  }
}

// Device identities cannot be created via ARM/Bicep.
// Use the Azure CLI after deployment:
//   az iot hub device-identity create --hub-name <hub> --device-id <id>

output iotHubName string = iotHub.name
output resourceId string = iotHub.id
output hostName string = reference(iotHub.id, iotHubApiVersion).hostName
output builtInEventHubEndpoint string = reference(iotHub.id, iotHubApiVersion).eventHubEndpoints.events.endpoint
output builtInEventHubPath string = reference(iotHub.id, iotHubApiVersion).eventHubEndpoints.events.path
output consumerGroupName string = consumerGroupName
output asaConsumerGroupName string = asaConsumerGroupName
output deviceId string = deviceId
output serviceConnectionStringCommand string = 'az iot hub connection-string show --hub-name ${iotHub.name} --policy-name iothubowner --output tsv'
output deviceConnectionStringCommand string = 'az iot hub device-identity connection-string show --hub-name ${iotHub.name} --device-id ${deviceId} --output tsv'
