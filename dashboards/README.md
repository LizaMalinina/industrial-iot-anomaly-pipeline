# ADX Dashboard — KQL Queries Reference

Azure Data Explorer dashboard for the IoT Telemetry & Anomaly Detection pipeline.

- **Cluster:** `https://adxdevkllur2lxqqguo.westeurope.kusto.windows.net`
- **Database:** `telemetry`
- **Tables:** `SensorReadings`, `SensorAnomalies`

## How to Create the Dashboard

ADX Dashboards are created interactively via the web UI. Use the KQL queries below to build each tile.

### Setup

1. Open [Azure Data Explorer web UI](https://dataexplorer.azure.com/)
2. Add a connection to the cluster: `https://adxdevkllur2lxqqguo.westeurope.kusto.windows.net`
3. Select the `telemetry` database
4. Go to **Dashboards → New dashboard**, name it "IoT Telemetry & Anomaly Detection"

### Adding tiles

For each query below:
1. Run the query in the web UI query editor
2. Select **Pin to dashboard** in the toolbar
3. Choose the dashboard, set the tile name and visual type as noted
4. Adjust layout as needed

### Recommended settings
- **Auto-refresh:** 1 minute (Settings → Auto refresh)
- **Time range parameter:** Add a `TimeRange` parameter (default: Last 1 hour) and replace `ago(1h)` in queries with the parameter for interactive filtering

---

## Page 1: Live Telemetry Overview

### Temperature (°C) — Last 1 Hour

Line chart showing temperature readings over time, broken out by device.

```kql
SensorReadings
| where timestamp > ago(1h)
| project timestamp, temperature_c, device_id
| order by timestamp asc
```

### Vibration (Raw) — Last 1 Hour

Line chart showing raw vibration sensor values over time, broken out by device.

```kql
SensorReadings
| where timestamp > ago(1h)
| project timestamp, vibration_raw, device_id
| order by timestamp asc
```

### Latest Temperature (°C)

Stat card showing the most recent temperature reading per device.

```kql
SensorReadings
| summarize arg_max(timestamp, temperature_c) by device_id
| project device_id, temperature_c, timestamp
```

### Latest Vibration (Raw)

Stat card showing the most recent vibration reading per device.

```kql
SensorReadings
| summarize arg_max(timestamp, vibration_raw) by device_id
| project device_id, vibration_raw, timestamp
```

### Messages — Last 1 Hour

Stat card with total message count in the last hour.

```kql
SensorReadings
| where timestamp > ago(1h)
| summarize MessageCount = count()
```

### Messages — Last 24 Hours

Stat card with total message count in the last 24 hours.

```kql
SensorReadings
| where timestamp > ago(24h)
| summarize MessageCount = count()
```

---

## Page 2: Anomaly Detection

### Temperature Anomalies on Readings — Last 6 Hours

Scatter chart overlaying detected temperature anomalies onto normal temperature readings. Normal readings appear as one series; anomaly points appear as a separate series so spikes are visually obvious.

```kql
let timeRange = ago(6h);
let readings = SensorReadings
| where timestamp > timeRange
| project timestamp, value = temperature_c, series = "Normal Reading", device_id;
let anomalies = SensorAnomalies
| where event_timestamp > timeRange and temperature_is_anomaly == 1
| project timestamp = event_timestamp, value = temperature_c, series = "Anomaly", device_id;
union readings, anomalies
| order by timestamp asc
```

### Vibration Anomalies on Readings — Last 6 Hours

Same overlay approach for vibration data.

```kql
let timeRange = ago(6h);
let readings = SensorReadings
| where timestamp > timeRange
| project timestamp, value = toreal(vibration_raw), series = "Normal Reading", device_id;
let anomalies = SensorAnomalies
| where event_timestamp > timeRange and vibration_is_anomaly == 1
| project timestamp = event_timestamp, value = toreal(vibration_raw), series = "Anomaly", device_id;
union readings, anomalies
| order by timestamp asc
```

### Anomaly Count by Type — Last 24 Hours

Pie chart showing the split between temperature and vibration anomalies. Uses `evaluate narrow()` to pivot the two counts into rows for the pie chart.

```kql
SensorAnomalies
| where event_timestamp > ago(24h)
| summarize
    TemperatureAnomalies = countif(temperature_is_anomaly == 1),
    VibrationAnomalies = countif(vibration_is_anomaly == 1)
| project-rename ['Temperature'] = TemperatureAnomalies, ['Vibration'] = VibrationAnomalies
| evaluate narrow()
| project-rename AnomalyType = Column, Count = Value
```

### Recent Anomalies (Last 20)

Table showing the 20 most recent anomaly records with derived `SensorType`, `MeasureValue`, and `AnomalyScore` columns for readability. A single `SensorAnomalies` row can flag both temperature and vibration — the `SensorType` column shows "Both" in that case.

```kql
SensorAnomalies
| extend SensorType = case(
    temperature_is_anomaly == 1 and vibration_is_anomaly == 1, "Both",
    temperature_is_anomaly == 1, "Temperature",
    vibration_is_anomaly == 1, "Vibration",
    "Unknown")
| extend AnomalyScore = iff(temperature_is_anomaly == 1, temperature_anomaly_score, vibration_anomaly_score)
| extend MeasureValue = iff(temperature_is_anomaly == 1, temperature_c, toreal(vibration_raw))
| project event_timestamp, device_id, SensorType, MeasureValue, AnomalyScore, temperature_anomaly_score, vibration_anomaly_score
| top 20 by event_timestamp desc
```

### Anomaly Rate — Per Hour (Last 24 Hours)

Stacked bar chart showing how many temperature and vibration anomalies occurred in each hour, making it easy to spot periods of elevated anomaly activity.

```kql
SensorAnomalies
| where event_timestamp > ago(24h)
| summarize
    TemperatureAnomalies = countif(temperature_is_anomaly == 1),
    VibrationAnomalies = countif(vibration_is_anomaly == 1)
    by bin(event_timestamp, 1h)
| order by event_timestamp asc
```

---

## Page 3: Device Health

### Device Last Seen

Table showing each device's last-seen timestamp, time since last seen, total message count, and a status indicator:
- 🟢 Online — last seen within 5 minutes
- 🟡 Stale — last seen 5–30 minutes ago
- 🔴 Offline — last seen over 30 minutes ago

```kql
SensorReadings
| summarize
    LastSeen = max(timestamp),
    TotalMessages = count(),
    LastTemperature = arg_max(timestamp, temperature_c),
    LastVibration = arg_max(timestamp, vibration_raw)
    by device_id
| extend TimeSinceLastSeen = now() - LastSeen
| extend Status = iff(TimeSinceLastSeen < 5m, '🟢 Online', iff(TimeSinceLastSeen < 30m, '🟡 Stale', '🔴 Offline'))
| project device_id, Status, LastSeen, TimeSinceLastSeen, TotalMessages
| order by LastSeen desc
```

### Messages per Minute — Last 1 Hour

Line chart showing message throughput per minute, broken out by device. Useful for verifying expected send rates and spotting intermittent connectivity.

```kql
SensorReadings
| where timestamp > ago(1h)
| summarize MessageCount = count() by bin(timestamp, 1m), device_id
| order by timestamp asc
```

### Data Gaps (> 5 Minutes) — Last 24 Hours

Table detecting periods where a device stopped sending data for more than 5 minutes. Uses `serialize` + `prev()` to compute the time delta between consecutive messages per device.

```kql
SensorReadings
| where timestamp > ago(24h)
| order by device_id asc, timestamp asc
| serialize
| extend PrevTimestamp = prev(timestamp), PrevDevice = prev(device_id)
| where device_id == PrevDevice
| extend GapDuration = timestamp - PrevTimestamp
| where GapDuration > 5m
| project device_id, GapStart = PrevTimestamp, GapEnd = timestamp, GapDuration
| order by GapStart desc
```

### Ingestion Latency (ingestion_time − timestamp) — Last 1 Hour

Line chart showing P50/P90/P99 ingestion latency in seconds — the delay between the device-side `timestamp` and the ADX `ingestion_time`. Helps detect IoT Hub or data connection bottlenecks.

```kql
SensorReadings
| where timestamp > ago(1h) and isnotempty(ingestion_time)
| extend LatencySeconds = datetime_diff('second', ingestion_time, timestamp)
| summarize
    P50_Latency = percentile(LatencySeconds, 50),
    P90_Latency = percentile(LatencySeconds, 90),
    P99_Latency = percentile(LatencySeconds, 99)
    by bin(timestamp, 1m)
| order by timestamp asc
```

---

## Table Schemas

These are the actual ADX table schemas (from `infra/modules/adx.bicep`):

### SensorReadings

| Column | Type | Description |
|--------|------|-------------|
| `device_id` | string | IoT Hub device identifier |
| `seq` | long | Monotonic sequence number from the device |
| `temperature_c` | real | Temperature in Celsius (TMP36 sensor) |
| `vibration_raw` | int | Raw vibration reading (Piezo sensor) |
| `timestamp` | datetime | Device-side UTC timestamp |
| `bridge_version` | string | Python bridge version that forwarded the message |
| `ingestion_time` | datetime | ADX ingestion timestamp |

### SensorAnomalies

| Column | Type | Description |
|--------|------|-------------|
| `device_id` | string | IoT Hub device identifier |
| `seq` | long | Sequence number from the device |
| `temperature_c` | real | Temperature at time of anomaly |
| `vibration_raw` | int | Vibration at time of anomaly |
| `event_timestamp` | datetime | Event timestamp from Stream Analytics |
| `bridge_version` | string | Bridge version |
| `temperature_anomaly_score` | real | Spike/dip anomaly score for temperature |
| `temperature_is_anomaly` | long | 1 if temperature triggered anomaly, 0 otherwise |
| `vibration_anomaly_score` | real | Spike/dip anomaly score for vibration |
| `vibration_is_anomaly` | long | 1 if vibration triggered anomaly, 0 otherwise |
| `ingestion_time` | datetime | ADX ingestion timestamp |
