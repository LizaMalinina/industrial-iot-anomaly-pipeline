# Infrastructure

Azure Bicep infrastructure for the Industrial IoT Anomaly Detection Pipeline.

## What gets deployed

- Azure IoT Hub (`F1` or `S1`, parameterized) with consumer groups
- Storage Account with the `raw-telemetry` blob container (bronze layer)
- Azure Data Explorer cluster (Dev/Test SKU) with `telemetry` database, `SensorReadings` and `SensorAnomalies` tables, and IoT Hub data connection
- Azure Stream Analytics job with anomaly detection (spike/dip on temperature and vibration)
- Device identity created via Azure CLI post-deployment

## Files

- `main.bicep` - resource-group level orchestration
- `modules\iot-hub.bicep` - IoT Hub and consumer groups
- `modules\storage.bicep` - Storage account and blob container
- `modules\adx.bicep` - ADX cluster, database, tables, JSON mapping, data connection
- `modules\stream-analytics.bicep` - Stream Analytics job with anomaly detection query
- `parameters.dev.json` - dev environment defaults
- `deploy.ps1` - one-command deployment helper

## Prerequisites

- Azure CLI with Bicep support (`az`)
- An authenticated Azure session (`az login`)
- Permission to create resource groups and resources in the target subscription

## Deploy

From PowerShell:

```powershell
cd infra
.\deploy.ps1 -ResourceGroupName rg-iiot-anomaly-dev
```

Optional overrides:

```powershell
.\deploy.ps1 -ResourceGroupName rg-iiot-anomaly-dev -Location westeurope -ParameterFile .\parameters.dev.json
```

The script creates the resource group if it does not exist and then runs a group deployment for `main.bicep`.

## Key parameters

- `location` - defaults to `westeurope`
- `environmentName` - defaults to `dev`
- `iotHubName` - defaults to `iiot-anomaly-s1-dev`
- `iotHubSkuName` - `S1` (default) or `F1`
- `iotHubSkuCapacity` - keep `1` for `F1`
- `telemetryContainerName` - raw telemetry landing container, defaults to `raw-telemetry`

Note: Device identities cannot be created via ARM/Bicep. After deployment, create the device manually:

```powershell
az iot hub device-identity create --hub-name <iotHubName> --device-id sensor-dev-001
az iot hub device-identity connection-string show --hub-name <iotHubName> --device-id sensor-dev-001 -o tsv
```

## Outputs

Deployment outputs include:

- IoT Hub name and hostname
- Built-in Event Hub-compatible endpoint and path
- Consumer group name
- Device identity name
- Storage account name and raw telemetry container URL
- Azure CLI commands to retrieve service and device connection strings after deployment

Example commands after deployment:

```powershell
az iot hub connection-string show --hub-name <iotHubName> --policy-name iothubowner --output tsv
az iot hub device-identity connection-string show --hub-name <iotHubName> --device-id <deviceId> --output tsv
```

## Notes

- The IoT Hub name defaults to `iiot-anomaly-s1-dev` (S1 tier). Override via `iotHubName` and `iotHubSkuName` parameters.
- Storage account names are generated in lowercase and trimmed to Azure naming limits.
- The `F1` IoT Hub tier has a daily quota of 8,000 messages — use `S1` for sustained workloads.
