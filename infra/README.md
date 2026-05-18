# Infrastructure

Azure Bicep infrastructure for the Industrial IoT Anomaly Detection Pipeline.

## What gets deployed

- Azure IoT Hub (`F1` or `S1`, parameterized)
- IoT Hub device identity for a development sensor/device
- Storage Account with the `raw-telemetry` blob container for the bronze layer
- Outputs for IoT Hub hostname, built-in Event Hub-compatible endpoint details, and CLI commands to fetch connection strings

## Files

- `main.bicep` - resource-group level orchestration
- `modules\iot-hub.bicep` - IoT Hub, consumer group, and device identity
- `modules\storage.bicep` - Storage account and blob container
- `parameters.dev.json` - dev environment defaults
- `deploy.ps1` - one-command deployment helper

## Prerequisites

- Azure CLI with Bicep support (`az`)
- An authenticated Azure session (`az login`)
- Permission to create resource groups and resources in the target subscription

## Deploy

From PowerShell:

```powershell
cd C:\Users\lizamalinina\Repos\iot\infra
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
- `iotHubSkuName` - `F1` or `S1`
- `iotHubSkuCapacity` - keep `1` for `F1`
- `deviceId` - device identity to register in IoT Hub
- `telemetryContainerName` - raw telemetry landing container, defaults to `raw-telemetry`

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

- IoT Hub names are generated with the environment suffix plus a `uniqueString(...)` value to avoid global naming conflicts.
- Storage account names are generated in lowercase and trimmed to Azure naming limits.
- The `F1` IoT Hub tier is limited and intended for lightweight dev/test usage.
